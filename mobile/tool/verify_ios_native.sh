#!/usr/bin/env bash
# Normal app launch/deep-link test after the Flutter driver and native XCTest.
set -euo pipefail
device="$1"
package=com.dabok407.hangeoreum
results=build/integration_test
mkdir -p "$results"
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
xcrun simctl openurl "$device" "$uri"
sleep 5
python3 - "$database" <<'PY'
import sqlite3,sys
assert sqlite3.connect(sys.argv[1]).execute("select count(*) from occurrences where state='progressing'").fetchone()[0] == 1
print('IOS_COLD_WIDGET_DEEP_LINK_OK')
PY
xcrun simctl io "$device" screenshot "$results/ios-native-start.png"
cp "$database" "$results/ios-local-database.db"

