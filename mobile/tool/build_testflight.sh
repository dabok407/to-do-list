#!/usr/bin/env bash
# macOS only. Build an App Store-signed IPA without creating credentials,
# uploading a build, or submitting anything for App Review.
set +x
set -euo pipefail
umask 077

fail() { printf '%s\n' "$1" >&2; exit 1; }
[[ "$(uname -s)" == Darwin ]] || fail 'TestFlight signing requires a macOS runner. Use the manual GitHub workflow from Windows.'
for command in flutter xcodebuild security plutil python3 ditto; do
  command -v "$command" >/dev/null || fail "Required macOS build tool is missing: $command"
done
for variable in IOS_DISTRIBUTION_P12_BASE64 IOS_DISTRIBUTION_P12_PASSWORD IOS_APP_PROFILE_BASE64 IOS_WIDGET_PROFILE_BASE64 BUILD_NAME BUILD_NUMBER; do
  [[ -n "${!variable:-}" ]] || fail "Required environment value is missing: $variable"
done
[[ "$BUILD_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'BUILD_NAME must be a numeric version such as 1.0.0.'
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || fail 'BUILD_NUMBER must be a positive integer not previously uploaded for this version.'

mobile_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$mobile_dir"
project="$mobile_dir/ios/Runner.xcodeproj/project.pbxproj"
[[ -f "$project" ]] || fail 'The iOS Xcode project was not found.'
temporary="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/firstkan-signing.XXXXXX")"
keychain="$temporary/signing.keychain-db"
keychain_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
# Xcode 26 and this Flutter toolchain discover profiles in this directory.
profile_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
installed_profiles=()
prior_keychains=()
project_backed_up=false

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  # macOS Bash 3.2 treats empty arrays as unset under nounset. Cleanup must
  # continue even when profile installation failed before filling the arrays.
  set +eu
  if [[ "$project_backed_up" == true ]] && ! cp "$temporary/project.pbxproj" "$project"; then
    printf 'Failed to restore the original Xcode project.\n' >&2
    status=1
  fi
  for profile in "${installed_profiles[@]}"; do
    if [[ -f "$temporary/previous-$(basename "$profile")" ]]; then
      cp "$temporary/previous-$(basename "$profile")" "$profile"
    else
      rm -f "$profile"
    fi
  done
  if [[ ${#prior_keychains[@]} -gt 0 ]]; then security list-keychains -d user -s "${prior_keychains[@]}" >/dev/null 2>&1; fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  # This path is created by mktemp above; never remove a caller-selected path.
  [[ "$temporary" == */firstkan-signing.* ]] && rm -rf "$temporary"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

security list-keychains -d user > "$temporary/keychains.txt"
while IFS= read -r line; do
  [[ "$line" == *\"* ]] || continue
  line="${line#*\"}"
  line="${line%\"*}"
  prior_keychains+=("$line")
done < "$temporary/keychains.txt"
python3 - "$temporary" <<'PY'
import base64, os, pathlib, sys
directory = pathlib.Path(sys.argv[1])
for variable, name in [('IOS_DISTRIBUTION_P12_BASE64', 'distribution.p12'), ('IOS_APP_PROFILE_BASE64', 'app.mobileprovision'), ('IOS_WIDGET_PROFILE_BASE64', 'widget.mobileprovision')]:
    try:
        data = base64.b64decode(''.join(os.environ[variable].split()), validate=True)
        if not data:
            raise ValueError('empty')
    except ValueError:
        raise SystemExit(f'{variable} is not a valid base64 file')
    (directory / name).write_bytes(data)
PY
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$temporary/distribution.p12" -P "$IOS_DISTRIBUTION_P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -f pkcs12 -k "$keychain" >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
if [[ ${#prior_keychains[@]} -gt 0 ]]; then
  security list-keychains -d user -s "$keychain" "${prior_keychains[@]}"
else
  security list-keychains -d user -s "$keychain"
fi
security find-identity -v -p codesigning "$keychain" > "$temporary/identities.txt"
security cms -D -i "$temporary/app.mobileprovision" > "$temporary/app.plist"
security cms -D -i "$temporary/widget.mobileprovision" > "$temporary/widget.plist"

cp "$project" "$temporary/project.pbxproj"
project_backed_up=true
# Config-only may migrate the project, so preserve the source before invoking it.
flutter build ios --release --config-only --no-codesign --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
plutil -convert json -o "$temporary/project.json" "$project"
python3 tool/testflight_signing.py \
  --app-profile "$temporary/app.plist" --widget-profile "$temporary/widget.plist" \
  --identities "$temporary/identities.txt" --project-json "$temporary/project.json" \
  --project "$project" --export-plist "$temporary/ExportOptions.plist" --settings-json "$temporary/settings.json"
mkdir -p "$profile_directory"
for item in app widget; do
  bundle=com.dabok407.hangeoreum
  [[ "$item" == widget ]] && bundle="$bundle.TasksWidget"
  uuid="$(python3 - "$temporary/settings.json" "$bundle" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['profiles'][sys.argv[2]])
PY
)"
  destination="$profile_directory/$uuid.mobileprovision"
  if [[ -f "$destination" ]]; then cp "$destination" "$temporary/previous-$uuid.mobileprovision"; fi
  installed_profiles+=("$destination")
  cp "$temporary/$item.mobileprovision" "$destination"
done

# Flutter can return success after archiving even if IPA export fails. Remove
# earlier outputs in this known build directory so a stale IPA cannot pass.
python3 - <<'PY'
import pathlib
for directory, pattern in [('build/ios/ipa', '*.ipa'), ('build/testflight', '*')]:
    for output in pathlib.Path(directory).glob(pattern):
        if output.is_file():
            output.unlink()
PY
flutter build ipa --release --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER" --export-options-plist "$temporary/ExportOptions.plist"
archive=build/ios/archive/Runner.xcarchive
app="$archive/Products/Applications/Runner.app"
[[ -d "$app/PlugIns/HangeoreumWidget.appex" ]] || fail 'The signed archive does not contain the required widget extension.'
codesign --verify --deep --strict "$app"
mkdir -p build/testflight
python3 - "$temporary" <<'PY'
import hashlib, json, os, pathlib, plistlib, shutil, subprocess, sys
sys.path.insert(0, 'tool')
from testflight_signing import APP, WIDGET, TEAM, GROUP, validate_ipa_metadata
ipas = list(pathlib.Path('build/ios/ipa').glob('*.ipa'))
if len(ipas) != 1:
    raise SystemExit('Expected exactly one newly exported IPA')
ipa = ipas[0]
try:
    info = validate_ipa_metadata(ipa, os.environ['BUILD_NAME'], os.environ['BUILD_NUMBER'])
except ValueError as error:
    raise SystemExit(f'Exported IPA validation failed: {error}')
# Export re-signs the archive. Verify the actual file sent to App Store Connect.
extracted = pathlib.Path(sys.argv[1]) / 'exported'
subprocess.run(['ditto', '-x', '-k', str(ipa), str(extracted)], check=True)
apps = list((extracted / 'Payload').glob('*.app'))
if len(apps) != 1:
    raise SystemExit('Expected one extracted application')
for target, bundle in [(apps[0], APP), (apps[0] / 'PlugIns/HangeoreumWidget.appex', WIDGET)]:
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)], check=True)
    details = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(target)],
                             check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    entitlements = plistlib.loads(details.stdout)
    if (entitlements.get('application-identifier') != TEAM + '.' + bundle
            or entitlements.get('com.apple.developer.team-identifier') != TEAM
            or GROUP not in entitlements.get('com.apple.security.application-groups', [])
            or entitlements.get('get-task-allow', False) is not False):
        raise SystemExit('Exported app/widget signing entitlements do not match the registered distribution setup')
destination = pathlib.Path('build/testflight/firstkan.ipa')
shutil.copyfile(ipa, destination)
metadata = {'app_store_id': '6821236391', 'bundle_id': info['CFBundleIdentifier'], 'widget_bundle_id': 'com.dabok407.hangeoreum.TasksWidget', 'localizations': ['ko', 'en'], 'version': os.environ['BUILD_NAME'], 'build_number': os.environ['BUILD_NUMBER'], 'commit': os.environ.get('GITHUB_SHA'), 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest(), 'uploaded': False}
pathlib.Path('build/testflight/build-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('Signed Korean/English IPA exported with widget extension. No upload has been performed by this script.')
PY
if [[ -d "$archive/dSYMs" ]]; then ditto -c -k --keepParent "$archive/dSYMs" build/testflight/symbols.zip; fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then printf 'ipa_path=mobile/build/testflight/firstkan.ipa\n' >> "$GITHUB_OUTPUT"; fi
