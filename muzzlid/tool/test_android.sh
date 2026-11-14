#!/usr/bin/env bash
# Run on the host terminal with the selected Android device connected.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
mkdir -p test-results
exec > >(tee test-results/android-client.log) 2>&1
if ! command -v flutter >/dev/null 2>&1; then
  for android_flutter_bin in "${FLUTTER_ROOT:-}/bin" /home/geto/develop/flutter/bin; do
    if [[ -x "$android_flutter_bin/flutter" ]]; then
      export PATH="$android_flutter_bin:$PATH"
      break
    fi
  done
fi
if ! command -v adb >/dev/null 2>&1; then
  for android_adb_bin in "${ANDROID_SDK_ROOT:-}/platform-tools" "${ANDROID_HOME:-}/platform-tools" /opt/android-sdk/platform-tools; do
    if [[ -x "$android_adb_bin/adb" ]]; then
      export PATH="$android_adb_bin:$PATH"
      break
    fi
  done
fi
if ! command -v flutter >/dev/null 2>&1 || ! command -v adb >/dev/null 2>&1; then
  echo 'Flutter or adb was not found. Set FLUTTER_ROOT and ANDROID_SDK_ROOT to their installation directories.'
  exit 1
fi
command -v flutter
command -v adb
adb devices -l
android_test_device="${1:-}"
if [[ -z "$android_test_device" ]]; then
  mapfile -t android_test_devices < <(adb devices | awk '$2 == "device" {print $1}')
  if [[ "${#android_test_devices[@]}" != 1 ]]; then
    echo 'Connect exactly one Android device, or pass its adb device ID as the first argument.'
    exit 1
  fi
  android_test_device="${android_test_devices[0]}"
fi
if [[ "$(adb -s "$android_test_device" shell getprop sys.boot_completed | tr -d '\r')" != '1' ]]; then
  echo 'Android device has not finished booting.'
  exit 1
fi
flutter --version
flutter pub get
flutter analyze --no-fatal-infos
flutter test test
dart test/capture_check.dart
dart test/queue_check.dart
dart test/camera_frame_check.dart
dart test/record_check.dart
dart test/field_records_check.dart
dart test/capture_lifecycle_check.dart
dart test/snapshot_check.dart
flutter test integration_test/android_client_test.dart -d "$android_test_device" --no-uninstall
adb -s "$android_test_device" shell pm grant com.example.muzzlid android.permission.CAMERA
adb -s "$android_test_device" shell pm grant com.example.muzzlid android.permission.ACCESS_FINE_LOCATION
adb -s "$android_test_device" shell pm grant com.example.muzzlid android.permission.ACCESS_COARSE_LOCATION
flutter test integration_test/camera_device_test.dart -d "$android_test_device" --no-uninstall
flutter test integration_test/model_device_test.dart -d "$android_test_device" --no-uninstall
flutter build apk --debug
adb -s "$android_test_device" install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s "$android_test_device" shell am start -n com.example.muzzlid/.MainActivity
sleep 3
if ! adb -s "$android_test_device" shell pidof com.example.muzzlid; then
  echo 'App process did not remain running. Inspect Android logcat before accepting the launch.'
  exit 1
fi
adb -s "$android_test_device" exec-out screencap -p > test-results/android-launch.png
mkdir -p "test-results/screens/$android_test_device"
for android_ui_shot in field registration-review receipt register profile settings-luganda camera-device; do
  adb -s "$android_test_device" exec-out run-as com.example.muzzlid cat "files/ui-test-screenshots/$android_ui_shot.png" > "test-results/screens/$android_test_device/$android_ui_shot.png"
done
echo 'Automated checks completed. See docs/ANDROID_CLIENT_TESTING.md for remaining manual checks.'
