#!/usr/bin/env python3
"""Validate local signing inputs and set per-target manual signing for CI.

This helper creates no Apple credentials and makes no network requests. Decoded
provisioning profiles and the original Xcode project stay in the script's private
temporary directory. Only the signed IPA and public build metadata are exported.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import plistlib
import re
import zipfile

TEAM = "B2MTNFVL58"
APP = "com.dabok407.hangeoreum"
WIDGET = APP + ".TasksWidget"
GROUP = "group.com.dabok407.hangeoreum"


def validate_ipa_metadata(filename, version, build_number):
    """Validate the exported app and extension, rather than only the archive."""
    with zipfile.ZipFile(filename) as archive:
        names = archive.namelist()
        apps = [name for name in names if name.startswith("Payload/")
                and name.count("/") == 2 and name.endswith(".app/Info.plist")]
        if len(apps) != 1:
            raise ValueError("Expected exactly one application in the IPA")
        app_root = apps[0].removesuffix("Info.plist")
        widget_info = app_root + "PlugIns/HangeoreumWidget.appex/Info.plist"
        widget_infos = [name for name in names if name.startswith(app_root + "PlugIns/")
                        and name.endswith(".appex/Info.plist")]
        if widget_infos != [widget_info]:
            raise ValueError("Expected exactly the registered widget extension in the IPA")
        app_info = None
        for info_path, bundle in [(apps[0], APP), (widget_info, WIDGET)]:
            info = plistlib.loads(archive.read(info_path))
            if info.get("CFBundleIdentifier") != bundle:
                raise ValueError(f"Unexpected exported bundle ID for {bundle}")
            if (info.get("CFBundleShortVersionString") != version
                    or info.get("CFBundleVersion") != build_number):
                raise ValueError(f"Exported version/build mismatch for {bundle}")
            if not {"ko", "en"}.issubset(set(info.get("CFBundleLocalizations", []))):
                raise ValueError(f"Korean and English declarations missing for {bundle}")
            if info_path.removesuffix("Info.plist") + "embedded.mobileprovision" not in names:
                raise ValueError(f"Exported distribution profile missing for {bundle}")
            if info.get("CFBundleDisplayName") != "Todoniq":
                raise ValueError("Exported display name does not match the chosen brand")
            bundle_root = info_path.removesuffix("Info.plist")
            for language, brand in [("ko", "투두닉"), ("en", "Todoniq")]:
                strings_path = bundle_root + language + ".lproj/InfoPlist.strings"
                if strings_path not in names:
                    raise ValueError(f"Localized display name missing for {bundle}/{language}")
                raw_strings = archive.read(strings_path)
                try:
                    localized = plistlib.loads(raw_strings)
                    name = localized.get("CFBundleDisplayName")
                except (plistlib.InvalidFileException, UnicodeDecodeError, ValueError):
                    # Xcode generally compiles .strings as a binary plist.
                    # Accept source-style UTF-8/UTF-16 strings for inspection too.
                    encoding = "utf-16" if raw_strings.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
                    decoded = raw_strings.decode(encoding)
                    match = re.search(r'"?CFBundleDisplayName"?\s*=\s*"([^"]+)"\s*;', decoded)
                    name = match.group(1) if match else None
                if name != brand:
                    raise ValueError(f"Unexpected localized display name for {bundle}/{language}")
            if bundle == APP:
                app_info = info
        return app_info


def validate_profile(profile, bundle, identities, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        raise ValueError("Provisioning profile has no valid expiration date")
    if expiration.tzinfo is None:
        expiration = expiration.replace(tzinfo=dt.timezone.utc)
    if expiration <= now:
        raise ValueError("Provisioning profile has expired; regenerate it in Apple Developer")
    if TEAM not in profile.get("TeamIdentifier", []):
        raise ValueError("Provisioning profile belongs to a different Apple team")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != f"{TEAM}.{bundle}":
        raise ValueError(f"Provisioning profile must use the explicit App ID {bundle}")
    if entitlements.get("com.apple.developer.team-identifier") != TEAM:
        raise ValueError("Provisioning profile entitlement has an unexpected team")
    if GROUP not in entitlements.get("com.apple.security.application-groups", []):
        raise ValueError(f"Both app and widget profiles must include App Group {GROUP}")
    if entitlements.get("get-task-allow") or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
        raise ValueError("Use an App Store Connect distribution profile, not development/ad hoc/enterprise")
    uuid = profile.get("UUID", "")
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid):
        raise ValueError("Provisioning profile has an invalid UUID")
    certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    allowed = certificates & identities
    if not allowed:
        raise ValueError("The profile does not include the imported Apple Distribution certificate")
    return {"uuid": uuid, "signers": allowed}


def manual_signing_project(source, project, profile_by_bundle, signer):
    objects = project["objects"]
    configured = set()
    for target in objects.values():
        name = target.get("name")
        if target.get("isa") != "PBXNativeTarget" or name not in {"Runner", "HangeoreumWidget"}:
            continue
        expected = APP if name == "Runner" else WIDGET
        configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
        release_found = False
        for config_id in configurations:
            config = objects[config_id]
            if config.get("name") not in {"Release", "Profile"}:
                continue
            if config["buildSettings"].get("PRODUCT_BUNDLE_IDENTIFIER") != expected:
                raise ValueError(f"Unexpected bundle ID for Xcode target {name}")
            # Preserve OpenStep formatting and every unrelated build setting.
            pattern = re.compile(r"(^\t\t" + re.escape(config_id) + r" /\*[^\n]*\*/ = \{\n.*?^\t\t\tbuildSettings = \{\n)(.*?)(^\t\t\t\};)", re.M | re.S)
            signing_keys = r'(?:CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]"|DEVELOPMENT_TEAM|PROVISIONING_PROFILE_SPECIFIER|PROVISIONING_PROFILE)'
            def replace(match):
                body = re.sub(r"^[ \t]*" + signing_keys + r"[ \t]*=[^\n]*;[ \t]*\n", "", match[2], flags=re.M)
                settings = {
                    "CODE_SIGN_STYLE": "Manual", "DEVELOPMENT_TEAM": TEAM,
                    "CODE_SIGN_IDENTITY": signer, '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"': signer,
                    "PROVISIONING_PROFILE_SPECIFIER": profile_by_bundle[expected],
                }
                return match[1] + "".join(f'\t\t\t\t{key} = "{value}";\n' for key, value in settings.items()) + body + match[3]
            source, count = pattern.subn(replace, source)
            if count != 1:
                raise ValueError(f"Could not locate manual signing settings for target {name}")
            release_found |= config["name"] == "Release"
        if release_found:
            configured.add(name)
    if configured != {"Runner", "HangeoreumWidget"}:
        raise ValueError("Expected app and widget Release configurations were not found")
    return source


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-profile", required=True)
    parser.add_argument("--widget-profile", required=True)
    parser.add_argument("--identities", required=True)
    parser.add_argument("--project-json", required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--export-plist", required=True)
    parser.add_argument("--settings-json", required=True)
    args = parser.parse_args()
    identity_text = pathlib.Path(args.identities).read_text()
    identities = set(re.findall(r'\b([0-9A-F]{40})\b[^\n]*"Apple Distribution:', identity_text))
    profiles = {}
    for bundle, filename in [(APP, args.app_profile), (WIDGET, args.widget_profile)]:
        with open(filename, "rb") as stream:
            profiles[bundle] = validate_profile(plistlib.load(stream), bundle, identities)
    signers = profiles[APP]["signers"] & profiles[WIDGET]["signers"]
    if not signers:
        raise ValueError("App and widget profiles must permit the same imported distribution identity")
    signer = sorted(signers)[0]
    uuid_by_bundle = {bundle: data["uuid"] for bundle, data in profiles.items()}
    project_path = pathlib.Path(args.project)
    source = manual_signing_project(project_path.read_text(), json.loads(pathlib.Path(args.project_json).read_text()), uuid_by_bundle, signer)
    project_path.write_text(source)
    export = {
        "method": "app-store-connect", "destination": "export", "teamID": TEAM,
        "signingStyle": "manual", "signingCertificate": signer,
        "provisioningProfiles": uuid_by_bundle, "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False, "stripSwiftSymbols": True,
    }
    with open(args.export_plist, "wb") as stream:
        plistlib.dump(export, stream)
    pathlib.Path(args.settings_json).write_text(json.dumps({"profiles": uuid_by_bundle, "signer": signer}))
    print("App and widget signing profiles validated; per-target manual signing prepared.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Signing setup failed: {error}")
