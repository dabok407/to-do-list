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
uri=$(python3 - "$database" <<'PY'
import sqlite3,sys,urllib.parse
db=sqlite3.connect(sys.argv[1])
row=db.execute("select id,state from occurrences where state='paused' limit 1").fetchone()
assert row, 'SQLite task state did not survive simulator app termination/reinstallation.'
print('hangeoreum://task?'+urllib.parse.urlencode({'id':row[0],'action':'start'}))
PY
)
set +e
maestro --device "$device" test -e TASK_URI="$uri" tool/ios_widget_link.yaml > "$results/ios-deep-link-ui.log" 2>&1
ui_status=$?
set -e
xcrun simctl io "$device" screenshot "$results/ios-native-launch.png"
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
cp "$database" "$results/ios-local-database.db"

