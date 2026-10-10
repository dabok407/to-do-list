#!/usr/bin/env python3
"""Upload preparation only: revalidate a successful main-branch signed artifact.

The workflow supplies an Actions read-only token for artifact retrieval. Apple
credentials are never read here. No downloaded code is executed, re-signed, or
rebuilt; only the verified original IPA path is passed to the upload action.
"""
import hashlib
import json
import os
import pathlib
import plistlib
import re
import stat
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from testflight_signing import APP, WIDGET, TEAM, GROUP, validate_ipa_metadata, validate_profile

REPOSITORY = "dabok407/to-do-list"
WORKFLOW_PATH = ".github/workflows/ios-testflight.yml"
API = f"https://api.github.com/repos/{REPOSITORY}"
APP_STORE_ID = "6821236391"
ARTIFACT_FILES = {"firstkan.ipa", "symbols.zip", "build-manifest.json"}
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_EXPANDED_BYTES = 1024 * 1024 * 1024


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        parsed = urllib.parse.urlsplit(new_url)
        require(parsed.scheme == "https" and parsed.hostname and not parsed.username
                and not parsed.password, "Artifact redirect must use an HTTPS URL")
        require(parsed.hostname.endswith((".blob.core.windows.net", ".actions.githubusercontent.com"))
                and parsed.port in (None, 443), "Artifact redirect must use GitHub Actions artifact storage")
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        # GitHub artifact downloads redirect to storage. Never send its token there.
        if redirected is not None:
            redirected.remove_header("Authorization")
        return redirected


def request_url(url, token):
    require(url.startswith(API + "/"), "Unexpected GitHub API request")
    request = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json", "Authorization": "Bearer " + token,
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Todoniq-TestFlight-reuse",
    })
    return urllib.request.build_opener(SafeRedirect()).open(request, timeout=90)


def api_json(path, token):
    with request_url(API + path, token) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    require(len(raw) <= 4 * 1024 * 1024, "GitHub metadata response is too large")
    return json.loads(raw)


def validate_run(run, workflow, run_id):
    require(workflow.get("path") == WORKFLOW_PATH and workflow.get("state") == "active",
            "Original signing workflow is not the expected active workflow")
    require(isinstance(workflow.get("id"), int) and workflow["id"] > 0,
            "Original signing workflow has no valid identifier")
    require(run.get("id") == run_id and run.get("workflow_id") == workflow["id"]
            and run.get("path") == WORKFLOW_PATH,
            "Source run is not from the registered signing workflow")
    require(run.get("event") == "workflow_dispatch" and run.get("head_branch") == "main",
            "Source run must be an explicit main-branch signing run")
    require(run.get("status") == "completed" and run.get("conclusion") == "success",
            "Source signing run has not completed successfully")
    for key in ("repository", "head_repository"):
        require(run.get(key, {}).get("full_name") == REPOSITORY,
                "Source run must belong to this repository, without a fork")
    require(isinstance(run.get("head_sha"), str)
            and re.fullmatch(r"[0-9a-f]{40}", run["head_sha"]) is not None,
            "Source run has no valid commit SHA")


def select_artifact(artifacts, run, version, build):
    name = f"firstkan-ios-{version}-{build}"
    matches = [artifact for artifact in artifacts if artifact.get("name") == name]
    require(len(matches) == 1, "Expected one exact signed IPA artifact in the source run")
    artifact = matches[0]
    require(artifact.get("expired") is False, "Source artifact has expired")
    require(isinstance(artifact.get("id"), int) and artifact["id"] > 0,
            "Source artifact has no valid identifier")
    provenance = artifact.get("workflow_run", {})
    require(provenance.get("id") == run["id"] and provenance.get("head_sha") == run["head_sha"]
            and provenance.get("head_branch") == "main", "Artifact source run/commit does not match")
    require(isinstance(artifact.get("digest"), str)
            and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"]) is not None,
            "Source artifact has no verifiable SHA256 digest")
    require(isinstance(artifact.get("size_in_bytes"), int)
            and 0 < artifact["size_in_bytes"] <= MAX_ARCHIVE_BYTES, "Source artifact size is invalid")
    return artifact


def check_zip_members(archive, *, exact_files=None):
    entries = archive.infolist()
    names = [entry.filename for entry in entries]
    require(len(names) == len(set(names)), "Archive contains duplicate paths")
    require(sum(entry.file_size for entry in entries) <= MAX_EXPANDED_BYTES,
            "Archive expands beyond the permitted size")
    for entry in entries:
        path = pathlib.PurePosixPath(entry.filename)
        require(not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename
                and not re.match(r"^[A-Za-z]:", entry.filename), "Archive contains an unsafe path")
        require(entry.filename == path.as_posix() + ("/" if entry.is_dir() else ""),
                "Archive contains a noncanonical path")
        require(not stat.S_ISLNK(entry.external_attr >> 16), "Archive contains an unexpected symlink")
        require(not entry.flag_bits & 1, "Archive contains encrypted entries")
    if exact_files is not None:
        require(set(names) == exact_files, "Signed artifact does not contain exactly IPA, symbols, and manifest")


def validate_manifest(manifest, ipa, run, version, build):
    expected = {
        "app_store_id": APP_STORE_ID, "bundle_id": APP, "widget_bundle_id": WIDGET,
        "localizations": ["ko", "en"], "version": version, "build_number": build,
        "commit": run["head_sha"], "uploaded": False,
    }
    require(isinstance(manifest, dict) and set(manifest) == set(expected) | {"sha256"},
            "Unexpected build manifest schema")
    for key, value in expected.items():
        require(manifest.get(key) == value, "Build manifest does not match the requested original build")
    require(manifest.get("uploaded") is False, "Manifest does not identify a build-only artifact")
    sha256 = hashlib.sha256(ipa.read_bytes()).hexdigest()
    require(manifest.get("sha256") == sha256, "Original IPA SHA256 differs from the signed build manifest")
    with zipfile.ZipFile(ipa) as archive:
        check_zip_members(archive)
    validate_ipa_metadata(ipa, version, build)
    return sha256


def native_command(arguments):
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    # codesign diagnostics and profiles contain legal names. Keep them out of CI output.
    require(result.returncode == 0, "macOS signed IPA verification command failed: " + arguments[0])
    return result.stdout, result.stderr


def verify_native_ipa(ipa, temporary):
    require(os.uname().sysname == "Darwin", "IPA signature verification requires macOS")
    extracted = temporary / "extracted"
    native_command(["ditto", "-x", "-k", str(ipa), str(extracted)])
    apps = list((extracted / "Payload").glob("*.app"))
    require(len(apps) == 1, "Expected one extracted application")
    profiles = []
    for index, (target, bundle) in enumerate([(apps[0], APP),
            (apps[0] / "PlugIns/HangeoreumWidget.appex", WIDGET)]):
        native_command(["codesign", "--verify", "--deep", "--strict", str(target)])
        _, detail = native_command(["codesign", "-d", "--verbose=4", str(target)])
        lines = detail.decode("utf-8", errors="replace").splitlines()
        require("TeamIdentifier=" + TEAM in lines and "Identifier=" + bundle in lines,
                "Actual code signature belongs to an unexpected team or bundle")
        require(any(line.startswith("Authority=Apple Distribution:") for line in lines),
                "Actual code signature is not an Apple Distribution signature")
        raw_entitlements, _ = native_command(["codesign", "-d", "--entitlements", ":-", str(target)])
        entitlements = plistlib.loads(raw_entitlements)
        require(entitlements.get("application-identifier") == TEAM + "." + bundle
                and entitlements.get("com.apple.developer.team-identifier") == TEAM
                and GROUP in entitlements.get("com.apple.security.application-groups", [])
                and entitlements.get("get-task-allow", False) is False,
                "Actual app/widget entitlements do not match the App Store setup")
        certificate_prefix = temporary / f"signer-{index}-"
        native_command(["codesign", "-d", "--extract-certificates=" + str(certificate_prefix), str(target)])
        identity = hashlib.sha1(pathlib.Path(str(certificate_prefix) + "0").read_bytes()).hexdigest().upper()
        raw_profile, _ = native_command(["security", "cms", "-D", "-i", str(target / "embedded.mobileprovision")])
        profile = validate_profile(plistlib.loads(raw_profile), bundle, {identity})
        profiles.append(profile)
    require(bool(profiles[0]["signers"] & profiles[1]["signers"]),
            "App and widget were signed with different distribution identities")


def main():
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY
            and os.environ.get("GITHUB_REF") == "refs/heads/main", "Upload-only workflow must run in this repository on main")
    source = os.environ.get("SOURCE_RUN_ID", "")
    version = os.environ.get("EXPECTED_VERSION", "")
    build = os.environ.get("EXPECTED_BUILD", "")
    require(re.fullmatch(r"[1-9][0-9]*", source) is not None, "Source run ID must be a positive integer")
    require(re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) is not None, "Expected version must be numeric major.minor.patch")
    require(re.fullmatch(r"[1-9][0-9]*", build) is not None, "Expected build number must be a positive integer")
    token = os.environ.get("GH_ARTIFACT_TOKEN", "")
    require(bool(token), "Read-only Actions artifact token is unavailable")
    run = api_json(f"/actions/runs/{source}", token)
    workflow = api_json("/actions/workflows/ios-testflight.yml", token)
    validate_run(run, workflow, int(source))
    native_command(["git", "merge-base", "--is-ancestor", run["head_sha"], "HEAD"])
    artifacts = api_json(f"/actions/runs/{source}/artifacts?per_page=100", token)
    require(artifacts.get("total_count", 0) <= 100, "Source run contains an unexpected number of artifacts")
    artifact = select_artifact(artifacts.get("artifacts", []), run, version, build)
    output = pathlib.Path("mobile/build/testflight-reuse")
    require(not output.exists(), "IPA reuse output already exists; refusing a stale output")
    with tempfile.TemporaryDirectory(prefix="todoniq-reuse-", dir=os.environ.get("RUNNER_TEMP")) as directory:
        temporary = pathlib.Path(directory)
        downloaded = temporary / "artifact.zip"
        digest = hashlib.sha256()
        count = 0
        with request_url(API + f"/actions/artifacts/{artifact['id']}/zip", token) as response, downloaded.open("wb") as stream:
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                require(count <= MAX_ARCHIVE_BYTES, "Downloaded artifact exceeds the permitted size")
                digest.update(chunk)
                stream.write(chunk)
        require(count == artifact["size_in_bytes"], "Downloaded artifact size does not match GitHub metadata")
        require("sha256:" + digest.hexdigest() == artifact["digest"], "Downloaded artifact digest differs from GitHub metadata")
        candidate = temporary / "candidate"
        with zipfile.ZipFile(downloaded) as archive:
            check_zip_members(archive, exact_files=ARTIFACT_FILES)
            archive.extractall(candidate)
        manifest_path = candidate / "build-manifest.json"
        require(manifest_path.stat().st_size <= 16 * 1024, "Build manifest is too large")
        manifest = json.loads(manifest_path.read_text())
        ipa = candidate / "firstkan.ipa"
        sha256 = validate_manifest(manifest, ipa, run, version, build)
        verify_native_ipa(ipa, temporary)
        output.mkdir(parents=True)
        # Preserve the original IPA byte-for-byte after every validation succeeds.
        destination = output / "firstkan.ipa"
        destination.write_bytes(ipa.read_bytes())
        require(hashlib.sha256(destination.read_bytes()).hexdigest() == sha256,
                "IPA changed while preparing the upload")
    values = {"ipa_path": str(destination), "source_url": f"https://github.com/{REPOSITORY}/actions/runs/{source}",
              "version": version, "build_number": build, "sha256": sha256}
    with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
        stream.write("".join(f"{key}={value}\n" for key, value in values.items()))
    print(f"Original signed artifact verified: Todoniq iOS {version} ({build}), SHA256 {sha256}")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"IPA reuse verification failed: GitHub API HTTP {error.code}") from None
    except (ValidationError, ValueError, KeyError, OSError, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        # Do not include raw responses, signing details, or unexpected credential data.
        message = str(error) if isinstance(error, ValidationError) else type(error).__name__
        raise SystemExit("IPA reuse verification failed: " + message) from None
