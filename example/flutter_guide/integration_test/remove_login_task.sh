#!/usr/bin/env bash
# Runs the Android login window test that needs the host: when the test
# prints its marker, removes the task of the login window
# (AuthorizationManagementActivity and its Custom Tab), as the system
# does when a singleTask main activity or a CLEAR_TOP intent clears it.
#
#   example/flutter_guide/integration_test/remove_login_task.sh [device id]
set -euo pipefail
cd "$(dirname "$0")/.."
device="${1:-emulator-5554}"
adb="${ADB:-adb}"
output="$(mktemp)"
flutter test integration_test/authorization_window_test.dart -d "$device" \
  --dart-define=SPRING_TEST_REMOVE_TASK=true > "$output" 2>&1 &
test_pid=$!
until grep -q SPRING_TEST_LOGIN_WINDOW_OPEN "$output"; do
  if ! kill -0 "$test_pid" 2>/dev/null; then
    cat "$output"
    wait "$test_pid"
    exit $?
  fi
  sleep 1
done
sleep 3 # the Custom Tab is up
task=$("$adb" -s "$device" shell am stack list |
  grep -B2 'AuthorizationManagementActivity' |
  grep -oE 'RootTask id=[0-9]+' | grep -oE '[0-9]+' | head -1)
echo "Removing the login window's task $task"
"$adb" -s "$device" shell am stack remove "$task"
status=0
wait "$test_pid" || status=$?
cat "$output"
exit "$status"
