#!/usr/bin/env bash
# Run the real app test with a fresh fixture and stable VM-service forwarding.
set -euo pipefail
package=com.dabok407.hangeoreum
results=build/integration_test
mkdir -p "$results"
logger_pid=''
trap 'if [[ -n "$logger_pid" ]]; then kill "$logger_pid" 2>/dev/null || true; fi' EXIT
for attempt in 1 2; do
  adb shell am force-stop "$package"
  adb shell pm clear "$package"
  adb shell pm grant "$package" android.permission.POST_NOTIFICATIONS
  adb shell appops set "$package" SCHEDULE_EXACT_ALARM allow
  adb forward --remove-all
  adb logcat -c
  adb logcat -v threadtime > "$results/android-runtime-$attempt.log" &
  logger_pid=$!
  set +e
  timeout 600 flutter drive --keep-app-running --verbose \
    --host-vmservice-port=8181 --device-vmservice-port=8182 \
    --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart \
    2>&1 | tee "$results/android-driver-$attempt.log"
  status=${PIPESTATUS[0]}
  set -e
  kill "$logger_pid" 2>/dev/null || true
  logger_pid=''
  adb exec-out screencap -p > "$results/android-driver-$attempt.png" || true
  if [[ "$status" = 0 ]]; then exit 0; fi
  # Retry only a startup bridge timeout, never a failed app assertion. Preserve
  # both attempts so infrastructure failures remain visible in CI artifacts.
  if [[ "$status" != 124 ]] || ! grep -q 'Exception attempting to connect to the VM Service' "$results/android-driver-$attempt.log"; then
    exit "$status"
  fi
  echo "ANDROID_VM_STARTUP_TIMEOUT:$attempt"
done
exit 124
