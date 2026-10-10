#!/usr/bin/env bash
# Normal app launch/deep-link test after the Flutter driver and native XCTest.
set -euo pipefail
device="$1"
package=com.dabok407.hangeoreum
results=build/integration_test
mkdir -p "$results"
# XCTest can shut down the original device after using its own test clone.
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcrun simctl terminate "$device" "$package" || true
xcrun simctl install "$device" build/native/Runner.app
container=$(xcrun simctl get_app_container "$device" "$package" data)
database="$container/Documents/hangeoreum.db"
# The Flutter fixture must save an explicit language. Read it from the real DB
# rather than accepting either label, so incorrect localization still fails.
language=$(python3 - "$database" <<'PY'
import sqlite3,sys
row=sqlite3.connect(sys.argv[1]).execute("select value from settings where key='display_language'").fetchone()
assert row and row[0] in ('ko','en'), f'Native fixture must persist an explicit app language: {row}'
print(row[0])
PY
)
if [[ "$language" == en ]]; then
  progressing_label='In progress'
  settings_label='Settings'
  test_button='Test reminder in 10 seconds'
  test_title='첫칸 reminder test'
  test_body='Check that this reminder arrives while the app is closed.'
else
  progressing_label='진행 중'
  settings_label='설정'
  test_button='10초 뒤 테스트 알림'
  test_title='첫칸 테스트'
  test_body='앱 밖에서도 알림이 도착하는지 확인해주세요.'
fi
echo "IOS_NATIVE_UI_LANGUAGE:$language"
uri=$(python3 - "$database" <<'PY'
import sqlite3,sys,urllib.parse
db=sqlite3.connect(sys.argv[1])
row=db.execute("select id,state from occurrences where state='paused' limit 1").fetchone()
assert row, 'SQLite task state did not survive simulator app termination/reinstallation.'
print('hangeoreum://task?'+urllib.parse.urlencode({'id':row[0],'action':'start'}))
PY
)
set +e
export MAESTRO_CLI_NO_ANALYTICS=1
maestro --device "$device" test --debug-output="$results/maestro" --test-output-dir="$results/maestro" -e TASK_URI="$uri" tool/ios_widget_link.yaml > "$results/ios-deep-link-ui.log" 2>&1
ui_status=$?
set -e
xcrun simctl io "$device" screenshot "$results/ios-native-launch.png"
if [ "$ui_status" != 0 ]; then
  # A simulator AX snapshot can omit the visible system confirmation. Only
  # accept the coordinate fallback after independently checking its pixels.
  swift tool/verify_ios_screen.swift "$results/ios-native-launch.png" "Open in" "첫칸" "Cancel" "Open" \
    > "$results/ios-link-confirmation-ocr.log"
  maestro --device "$device" test --debug-output="$results/maestro-confirmation" \
    --test-output-dir="$results/maestro-confirmation" tool/ios_widget_link_confirm.yaml \
    > "$results/ios-link-confirmation-ui.log" 2>&1
  ui_status=0
fi
set +e
python3 - "$database" <<'PY'
import sqlite3,sys,time
for attempt in range(30):
    with sqlite3.connect(sys.argv[1]) as db:
        rows=db.execute("select id,state from occurrences").fetchall()
    if sum(state=='progressing' for _,state in rows)==1:
        print('IOS_COLD_WIDGET_DEEP_LINK_OK')
        sys.exit(0)
    time.sleep(1)
print('Cold widget link did not update SQLite:', rows, file=sys.stderr)
sys.exit(1)
PY
status=$?
set -e
xcrun simctl io "$device" screenshot "$results/ios-native-start.png"
xcrun simctl spawn "$device" log show --last 3m --style compact --predicate 'process == "Runner"' > "$results/ios-native-launch.log" || true
test "$status" = 0
test "$ui_status" = 0
# Require both the expected task title and its updated state in the rendered
# screenshot. UI automation selectors alone are flaky for cold Flutter scenes.
screen_ok=0
for ((attempt=0; attempt<10; attempt++)); do
  xcrun simctl io "$device" screenshot "$results/ios-native-start.png"
  if swift tool/verify_ios_screen.swift "$results/ios-native-start.png" "안방 대청소 통합 테스트" "$progressing_label" >> "$results/ios-screen-ocr.log" 2>&1; then
    screen_ok=1
    break
  fi
  sleep 1
done
test "$screen_ok" = 1
cp "$database" "$results/ios-local-database.db"

# A consumed pending request alone does not prove that a user saw an alert.
# Clear old deliveries, schedule via the real Settings button, terminate the
# app, and require a new visible notification in SpringBoard Notification Center.
xcrun simctl terminate "$device" "$package" || true
xcrun simctl launch "$device" "$package" --clear-delivered-notifications
notification_results="$results/maestro-notification-$(date +%s)"
set +e
maestro --device "$device" test --debug-output="$notification_results" \
  --test-output-dir="$notification_results" \
  -e SETTINGS_LABEL="$settings_label" -e TEST_BUTTON="$test_button" \
  -e TEST_TITLE="$test_title" -e TEST_BODY="$test_body" \
  tool/ios_background_notification.yaml \
  > "$results/ios-background-notification-ui.log" 2>&1
notification_status=$?
set -e
xcrun simctl io "$device" screenshot "$results/ios-after-notification-flow.png"
test "$notification_status" = 0
# The transient banner may disappear before the driver exits. OCR must inspect
# pixels captured inside the flow immediately after the visible-text assertions.
python3 - "$notification_results" "$results/ios-background-notification.png" <<'PY'
import pathlib, shutil, sys
images = list(pathlib.Path(sys.argv[1]).rglob('ios-background-notification.png'))
assert len(images) == 1, f'Expected one screenshot from this flow, found {images}'
shutil.copyfile(images[0], sys.argv[2])
PY
swift tool/verify_ios_screen.swift "$results/ios-background-notification.png" \
  "$test_title" "$test_body" > "$results/ios-background-notification-ocr.log"
echo 'IOS_TERMINATED_NOTIFICATION_OK'

