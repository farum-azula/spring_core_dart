#!/usr/bin/env bash
# The reinstall test on an iOS simulator (integration_test/reinstall_test.dart):
# write; clear the app's preferences (as SharedPreferences.clear() does)
# and install again over the app (an update): kept; uninstall and install
# (a reinstall): gone.
#
#   example/flutter_guide/integration_test/reinstall_test.sh <simulator udid>
set -euo pipefail
cd "$(dirname "$0")/.."
device="$1"
bundle="dev.farumazula.neonBooksApp"
# `flutter test` uninstalls the app after the tests unless told not to.
run() {
  flutter test integration_test/reinstall_test.dart -d "$device" \
    --dart-define=SPRING_TEST_PHASE="$1" "${@:2}"
}
xcrun simctl uninstall "$device" "$bundle" || true
run write --no-uninstall
# Every key of the app's UserDefaults removed, through cfprefsd (the
# domain by its path in the container): the install marker must not
# read that as a reinstall.
preferences="$(xcrun simctl get_app_container "$device" "$bundle" data)/Library/Preferences/$bundle"
xcrun simctl spawn "$device" defaults write "$preferences" spring.test.cleared -bool true
xcrun simctl spawn "$device" defaults delete "$preferences"
run kept --no-uninstall
xcrun simctl uninstall "$device" "$bundle"
run gone
