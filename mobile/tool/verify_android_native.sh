#!/usr/bin/env bash
# Run after app_test.dart, on an API 33+ emulator with exact alarm permission.
set -euo pipefail
package=com.dabok407.hangeoreum
results=build/integration_test
mkdir -p "$results"
adb install -r build/native-debug.apk
adb shell pm grant "$package" android.permission.POST_NOTIFICATIONS
adb shell appops set "$package" SCHEDULE_EXACT_ALARM allow
adb logcat -c
adb shell am start -W -n "$package/.NativeLifecycleTestActivity"
for ((attempt=0; attempt<60; attempt++)); do
  if adb logcat -d | grep -q 'NATIVE_LIFECYCLE_PROBES_READY'; then break; fi
  sleep 1
done
adb logcat -d > "$results/android-probe-bootstrap.log"
grep -q 'NATIVE_LIFECYCLE_PROBES_READY' "$results/android-probe-bootstrap.log"
adb shell dumpsys alarm > "$results/android-probes-scheduled.txt"
stop_app_process() {
  adb shell input keyevent KEYCODE_HOME
  sleep 2
  adb shell am kill "$package"
  # am kill may retain a recently visible process. SIGKILL under the debug app's
  # own UID models OS eviction and preserves alarms, unlike am force-stop.
  for pid in $(adb shell pidof "$package" | tr -d '\r'); do
    [[ "$pid" =~ ^[0-9]+$ ]] || exit 1
    adb shell run-as "$package" kill -9 "$pid"
  done
  sleep 1
  if adb shell pidof "$package" | grep -q '[0-9]'; then
    echo 'The app process survived eviction; background check is invalid.' >&2
    exit 1
  fi
}
stop_app_process
adb shell dumpsys alarm > "$results/android-probes-after-eviction.txt"

wait_for_notification() {
  local id="$1" attempts="$2"
  for ((attempt=0; attempt<attempts; attempt++)); do
    adb shell dumpsys notification --noredact > "$results/notifications-$id.txt"
    if grep -E "NotificationRecord.*$package.*id=$id([ ,)]|$)" "$results/notifications-$id.txt" >/dev/null; then
      echo "BACKGROUND_NOTIFICATION_OK:$id"
      return
    fi
    sleep 2
  done
  echo "Notification $id was not delivered by Android." >&2
  exit 1
}

# The debug entry point schedules +90/+240 second probes after driver cleanup.
wait_for_notification 100001 60
adb exec-out screencap -p > "$results/android-background-notification.png"
adb reboot
adb wait-for-device
for ((attempt=0; attempt<90; attempt++)); do
  if [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; then break; fi
  sleep 2
done
test "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
wait_for_notification 100002 90
echo 'REBOOT_NOTIFICATION_OK'
adb exec-out screencap -p > "$results/android-after-reboot.png"

read_database() {
  adb exec-out run-as "$package" cat databases/hangeoreum.db > "$results/hangeoreum.db"
  for extension in -wal -shm; do
    if adb shell run-as "$package" test -f "databases/hangeoreum.db$extension"; then
      adb exec-out run-as "$package" cat "databases/hangeoreum.db$extension" > "$results/hangeoreum.db$extension"
    fi
  done
}

# Native checks continue the Flutter fixture, whose app language must be explicit.
# Never infer the expected widget text from whichever OS locale the CI image has.
read_database
language=$(python3 - "$results/hangeoreum.db" <<'PY'
import sqlite3,sys
row=sqlite3.connect(sys.argv[1]).execute("select value from settings where key='display_language'").fetchone()
assert row and row[0] in ('ko','en'), f'Native fixture must persist an explicit app language: {row}'
print(row[0])
PY
)
if [[ "$language" == en ]]; then
  snooze_label='Snooze 10 min'
else
  snooze_label='10분 미루기'
fi
echo "ANDROID_NATIVE_UI_LANGUAGE:$language"

adb shell appwidget grantbind --package "$package" --user 0
adb shell wm size 420x840
adb shell wm density 160
for height in 130 220 330; do
  adb logcat -c
  adb shell am start -W -f 0x10008000 -n "$package/.WidgetTestActivity" --ei widgetHeight "$height" --ei widgetWidth 330 --es expectedTitle "'안방 대청소 통합 테스트'"
  for ((attempt=0; attempt<20; attempt++)); do
    adb logcat -d > "$results/widget-$height.log"
    if grep -q "WIDGET_RENDER_OK:330x$height" "$results/widget-$height.log"; then break; fi
    if grep -q 'FATAL EXCEPTION' "$results/widget-$height.log"; then break; fi
    sleep 1
  done
  adb exec-out screencap -p > "$results/android-widget-$height.png"
  grep -q "WIDGET_RENDER_OK:330x$height" "$results/widget-$height.log"
  # onCreate runs resolver cases with injected locales, without changing the OS
  # language or saved user preferences. Require its result on every fresh host.
  grep -q 'WIDGET_LANGUAGE_OK' "$results/widget-$height.log"
done

adb shell uiautomator dump /sdcard/hangeoreum-widget.xml
adb pull /sdcard/hangeoreum-widget.xml "$results/android-widget-ui.xml"
read -r tap_x tap_y < <(python3 - "$results/android-widget-ui.xml" "$snooze_label" <<'PY'
import re,sys,xml.etree.ElementTree as ET
button=next(n for n in ET.parse(sys.argv[1]).iter('node') if n.attrib.get('text')==sys.argv[2])
left,top,right,bottom=map(int,re.findall(r'\d+',button.attrib['bounds']))
assert right>left and bottom>top
print((left+right)//2,(top+bottom)//2)
PY
)
adb shell input tap "$tap_x" "$tap_y"
sleep 5
read_database
python3 - "$results/hangeoreum.db" <<'PY'
import sqlite3,sys
row=sqlite3.connect(sys.argv[1]).execute("select state,snoozes from occurrences limit 1").fetchone()
assert row and row[0]=='paused' and row[1]==2, row
print('WIDGET_SNOOZE_BUTTON_OK')
PY
adb exec-out screencap -p > "$results/android-widget-snooze.png"

read_database
uri=$(python3 - "$results/hangeoreum.db" <<'PY'
import sqlite3, sys, urllib.parse
db=sqlite3.connect(sys.argv[1])
row=db.execute("select id,state from occurrences where state='paused' limit 1").fetchone()
assert row, 'The saved paused occurrence did not survive process replacement/reboot.'
print('hangeoreum://task?'+urllib.parse.urlencode({'id':row[0],'action':'start'}))
PY
)
stop_app_process
adb shell am start -W -a android.intent.action.VIEW -d "'$uri'" "$package"
sleep 5
read_database
python3 - "$results/hangeoreum.db" <<'PY'
import sqlite3,sys
assert sqlite3.connect(sys.argv[1]).execute("select count(*) from occurrences where state='progressing'").fetchone()[0] == 1
print('COLD_WIDGET_DEEP_LINK_OK')
PY
adb exec-out screencap -p > "$results/android-widget-start.png"
adb shell dumpsys alarm > "$results/android-alarm-manager.txt"
adb shell dumpsys jobscheduler > "$results/android-background-jobs.txt"

# Exercise the real Workmanager headless engine without waiting six hours. This
# activity/entry point exists only in debug builds and schedules the same worker.
read_database
previous_refresh=$(python3 - "$results/hangeoreum.db" <<'PY'
import sqlite3,sys
row=sqlite3.connect(sys.argv[1]).execute("select value from settings where key='last_background_refresh'").fetchone()
print(row[0] if row else '')
PY
)
adb logcat -c
adb shell am start -W -n "$package/.NativeBackgroundTestActivity"
background_ok=0
for ((attempt=0; attempt<30; attempt++)); do
  read_database
  if python3 - "$results/hangeoreum.db" "$previous_refresh" <<'PY'
import sqlite3,sys
row=sqlite3.connect(sys.argv[1]).execute("select value from settings where key='last_background_refresh'").fetchone()
sys.exit(0 if row and row[0] != sys.argv[2] else 1)
PY
  then background_ok=1; break; fi
  sleep 2
done
adb logcat -d > "$results/android-headless-refresh.log"
test "$background_ok" = 1
echo 'ANDROID_HEADLESS_REFRESH_OK'

