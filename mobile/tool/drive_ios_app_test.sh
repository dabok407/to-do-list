#!/usr/bin/env bash
# Xcode can route Flutter's VM address to the unified log instead of stdout.
# Read both sources and verify the endpoint; never assume a printed port is live.
set -euo pipefail
device="$1"
target="${2:-integration_test/app_test.dart}"
package=com.dabok407.hangeoreum
results=build/integration_test
mkdir -p "$results"
name=$(basename "$target" .dart)
runtime="$results/ios-$name-runtime.log"
system_log="$results/ios-$name-vm.log"
: > "$system_log"
flutter build ios --simulator --debug --target "$target"
xcrun simctl terminate "$device" "$package" || true
xcrun simctl install "$device" build/ios/iphonesimulator/Runner.app
xcrun simctl launch --console "$device" "$package" \
  --enable-dart-profiling --disable-vm-service-publication --start-paused --enable-checked-mode \
  --verify-entry-points --verbose-logging --vm-service-port=8181 < /dev/null > "$runtime" 2>&1 &
launcher=$!
trap 'kill "$launcher" 2>/dev/null || true' EXIT
uri=''
for ((attempt=0; attempt<90; attempt++)); do
  if (( attempt % 5 == 0 )); then
    xcrun simctl spawn "$device" log show --last 2m --style compact \
      --predicate 'process == "Runner" AND eventMessage CONTAINS "Dart VM"' \
      > "$system_log" 2>&1 || true
  fi
  uri=$(python3 - "$runtime" "$system_log" <<'PY'
import json,re,sys,urllib.request
text='\n'.join(open(path, errors='replace').read() for path in sys.argv[1:])
matches=re.findall(r'(?:Dart VM service|Dart VM Service).*?(http://127\.0\.0\.1:8181/[^\s\x1b]*)', text)
for uri in reversed(matches):
    try:
        with urllib.request.urlopen(uri.rstrip('/')+'/getVM', timeout=1) as response:
            result=json.load(response)
        if result.get('result', {}).get('type') == 'VM':
            print(uri)
            break
    except (OSError, ValueError):
        pass
PY
)
  if [[ -n "$uri" ]]; then break; fi
  if ! kill -0 "$launcher" 2>/dev/null; then break; fi
  sleep 1
done
if [[ -z "$uri" ]]; then
  cat "$runtime"
  cat "$system_log"
  xcrun simctl spawn "$device" log show --last 3m --style compact \
    --predicate 'process == "Runner"' > "$results/ios-$name-system.log" 2>&1 || true
  for app_pid in $(pgrep -x Runner || true); do
    sample "$app_pid" 3 -file "$results/ios-$name-stack-$app_pid.txt" || true
  done
  xcrun simctl io "$device" screenshot "$results/ios-$name-startup-failed.png" || true
  echo 'Simulator did not expose a VM service within 90 seconds.' >&2
  exit 1
fi
flutter drive --no-dds --keep-app-running --use-existing-app="$uri" \
  -d "$device" --driver=test_driver/integration_test.dart --target="$target" \
  2>&1 | tee "$results/ios-$name-driver.log"
