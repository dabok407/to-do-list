"""Reject untrusted provenance, tampering and credential-leaking redirects."""
import copy
import hashlib
import io
import pathlib
import stat
import tempfile
import unittest
import urllib.request
from unittest.mock import patch
import zipfile

import reuse_testflight as reuse


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.workflow = {"id": 123, "path": reuse.WORKFLOW_PATH, "state": "active"}
        self.run = {"id": 456, "workflow_id": 123, "path": reuse.WORKFLOW_PATH,
                    "event": "workflow_dispatch", "head_branch": "main", "status": "completed",
                    "conclusion": "success", "head_sha": "a" * 40,
                    "repository": {"full_name": reuse.REPOSITORY},
                    "head_repository": {"full_name": reuse.REPOSITORY}}
        self.artifact = {"id": 789, "name": "firstkan-ios-1.0.0-101", "expired": False,
                         "digest": "sha256:" + "b" * 64, "size_in_bytes": 1234,
                         "workflow_run": {"id": 456, "head_sha": "a" * 40, "head_branch": "main"}}

    def test_original_successful_main_run_is_accepted(self):
        reuse.validate_run(self.run, self.workflow, 456)
        self.assertEqual(reuse.select_artifact([self.artifact], self.run, "1.0.0", "101"), self.artifact)

    def test_wrong_workflow_branch_event_incomplete_failure_or_commit_is_rejected(self):
        changes = {"id": 999, "workflow_id": 999, "path": ".github/workflows/other.yml",
                   "event": "pull_request", "head_branch": "feature", "status": "in_progress",
                   "conclusion": "failure", "head_sha": "missing"}
        for key, value in changes.items():
            with self.subTest(key=key):
                invalid = copy.deepcopy(self.run)
                invalid[key] = value
                with self.assertRaises(reuse.ValidationError):
                    reuse.validate_run(invalid, self.workflow, 456)

    def test_fork_or_other_repository_is_rejected(self):
        for key in ("head_repository", "repository"):
            with self.subTest(key=key):
                invalid = copy.deepcopy(self.run)
                invalid[key]["full_name"] = "someone/to-do-list"
                with self.assertRaises(reuse.ValidationError):
                    reuse.validate_run(invalid, self.workflow, 456)

    def test_different_or_disabled_workflow_is_rejected(self):
        for key, value in [("path", "other.yml"), ("state", "disabled_manually"), ("id", None)]:
            with self.subTest(key=key), self.assertRaises(reuse.ValidationError):
                invalid = dict(self.workflow, **{key: value})
                reuse.validate_run(self.run, invalid, 456)

    def test_missing_duplicate_wrong_version_or_wrong_build_artifact_is_rejected(self):
        for artifacts, version, build in [([], "1.0.0", "101"),
                ([self.artifact, self.artifact], "1.0.0", "101"),
                ([self.artifact], "1.0.1", "101"), ([self.artifact], "1.0.0", "102")]:
            with self.subTest(version=version, build=build, count=len(artifacts)), self.assertRaises(reuse.ValidationError):
                reuse.select_artifact(artifacts, self.run, version, build)

    def test_expired_invalid_digest_or_oversized_artifact_is_rejected(self):
        for key, value in [("expired", True), ("id", 0), ("digest", None),
                           ("digest", "sha256:" + "x" * 64), ("size_in_bytes", 0),
                           ("size_in_bytes", reuse.MAX_ARCHIVE_BYTES + 1)]:
            with self.subTest(key=key, value=value), self.assertRaises(reuse.ValidationError):
                invalid = dict(self.artifact, **{key: value})
                reuse.select_artifact([invalid], self.run, "1.0.0", "101")

    def test_artifact_from_another_run_commit_or_branch_is_rejected(self):
        for key, value in [("id", 999), ("head_sha", "c" * 40), ("head_branch", "feature")]:
            with self.subTest(key=key), self.assertRaises(reuse.ValidationError):
                invalid = copy.deepcopy(self.artifact)
                invalid["workflow_run"][key] = value
                reuse.select_artifact([invalid], self.run, "1.0.0", "101")


class ArchiveTests(unittest.TestCase):
    def check(self, entries, exact_files=None):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            for entry, content in entries:
                archive.writestr(entry, content)
        data.seek(0)
        with zipfile.ZipFile(data) as archive:
            reuse.check_zip_members(archive, exact_files=exact_files)

    def test_exact_build_artifact_is_accepted(self):
        self.check([(name, b"bytes") for name in reuse.ARTIFACT_FILES], reuse.ARTIFACT_FILES)

    def test_missing_and_extra_files_are_rejected(self):
        for files in ({"firstkan.ipa"}, reuse.ARTIFACT_FILES | {"payload.sh"}):
            with self.subTest(files=files), self.assertRaises(reuse.ValidationError):
                self.check([(name, b"bytes") for name in files], reuse.ARTIFACT_FILES)

    def test_path_traversal_absolute_windows_and_symlink_paths_are_rejected(self):
        for path in ("../key", "Payload/../../key", "/tmp/key", "C:/key", "Payload\\..\\key",
                     "Payload/./key", "Payload//key"):
            with self.subTest(path=path), self.assertRaises(reuse.ValidationError):
                self.check([(path, b"bytes")])
        symlink = zipfile.ZipInfo("Payload/link")
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(reuse.ValidationError):
            self.check([(symlink, b"../../key")])

    def test_oversized_expansion_is_rejected(self):
        with patch.object(reuse, "MAX_EXPANDED_BYTES", 2), self.assertRaises(reuse.ValidationError):
            self.check([("file", b"123")])


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.ipa = pathlib.Path(self.directory.name) / "firstkan.ipa"
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Payload/Runner.app/example", b"fixture")
        self.run = {"head_sha": "a" * 40}
        self.manifest = {"app_store_id": reuse.APP_STORE_ID, "bundle_id": reuse.APP,
                         "widget_bundle_id": reuse.WIDGET, "localizations": ["ko", "en"],
                         "version": "1.0.0", "build_number": "101", "commit": "a" * 40,
                         "sha256": hashlib.sha256(self.ipa.read_bytes()).hexdigest(), "uploaded": False}

    def validate(self, manifest):
        with patch.object(reuse, "validate_ipa_metadata") as metadata:
            result = reuse.validate_manifest(manifest, self.ipa, self.run, "1.0.0", "101")
            metadata.assert_called_once_with(self.ipa, "1.0.0", "101")
        return result

    def test_original_manifest_and_ipa_digest_are_accepted(self):
        self.assertEqual(self.validate(self.manifest), self.manifest["sha256"])

    def test_wrong_store_bundle_locale_version_build_commit_or_uploaded_is_rejected(self):
        for key, value in [("app_store_id", "1"), ("bundle_id", "com.other.app"),
                ("widget_bundle_id", "com.other.widget"), ("localizations", ["en"]),
                ("version", "1.0.1"), ("build_number", "102"), ("commit", "c" * 40),
                ("uploaded", True), ("uploaded", 0), ("sha256", "b" * 64)]:
            with self.subTest(key=key), self.assertRaises(reuse.ValidationError):
                self.validate(dict(self.manifest, **{key: value}))

    def test_missing_or_extra_manifest_fields_are_rejected(self):
        invalid = dict(self.manifest)
        del invalid["sha256"]
        for manifest in (invalid, dict(self.manifest, injection="anything")):
            with self.assertRaises(reuse.ValidationError):
                self.validate(manifest)

    def test_tampered_ipa_is_rejected_before_metadata_inspection(self):
        with zipfile.ZipFile(self.ipa, "a") as archive:
            archive.writestr("Payload/Runner.app/tampered", b"new code")
        with patch.object(reuse, "validate_ipa_metadata") as metadata, self.assertRaises(reuse.ValidationError):
            reuse.validate_manifest(self.manifest, self.ipa, self.run, "1.0.0", "101")
        metadata.assert_not_called()

    def test_actual_metadata_error_blocks_upload(self):
        with patch.object(reuse, "validate_ipa_metadata", side_effect=ValueError("Bundle mismatch")), self.assertRaises(ValueError):
            reuse.validate_manifest(self.manifest, self.ipa, self.run, "1.0.0", "101")


class RedirectAndDiagnosticsTests(unittest.TestCase):
    def test_artifact_storage_redirect_drops_github_credentials(self):
        request = urllib.request.Request(reuse.API + "/actions/artifacts/789/zip",
                                         headers={"Authorization": "Bearer test-only-placeholder"})
        redirected = reuse.SafeRedirect().redirect_request(request, None, 302, "", {}, "https://example.blob.core.windows.net/artifact.zip")
        self.assertIsNone(redirected.get_header("Authorization"))

    def test_http_or_embedded_credentials_redirect_is_rejected(self):
        request = urllib.request.Request(reuse.API + "/actions/artifacts/789/zip")
        for url in ("http://example.blob.core.windows.net/file", "https://user:password@example.blob.core.windows.net/file",
                    "https://storage.example.test/file", "https://example.blob.core.windows.net.evil.test/file",
                    "https://example.blob.core.windows.net:444/file"):
            with self.subTest(url=url), self.assertRaises(reuse.ValidationError):
                reuse.SafeRedirect().redirect_request(request, None, 302, "", {}, url)

    def test_failed_signature_diagnostics_are_sanitized(self):
        response = reuse.subprocess.CompletedProcess(["codesign"], 1, b"sensitive output", b"private legal name")
        with patch.object(reuse.subprocess, "run", return_value=response), self.assertRaises(reuse.ValidationError) as caught:
            reuse.native_command(["codesign", "--verify", "app"])
        self.assertNotIn("sensitive", str(caught.exception))
        self.assertNotIn("private", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
