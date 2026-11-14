# Android client acceptance

Current camera/enrolment acceptance is documented in [ANDROID_CAPTURE_IMPLEMENTATION.md](ANDROID_CAPTURE_IMPLEMENTATION.md). Earlier demo steps below are historical and superseded by that increment.

Scope: Android client only. Backend and literature-derived model integration wait for client acceptance. Current simulated screens remain explicitly labelled; they do not validate real camera or biometric inference.

## Run on the host

Start the existing Android Studio AVD and allow it to boot. In a host terminal:

```sh
cd /home/geto/Desktop/hack-a-thon
./muzzlid/tool/test_android.sh
```

To select among multiple devices, pass an ID such as `emulator-5554`. The runner requires Flutter and adb on PATH. It fetches packages, runs analysis/unit/domain/integration tests, builds/installs the debug APK, and opens MuzzlID. Output is saved in `muzzlid/test-results/android-client.log`. A failure stops subsequent steps; a completed runner is not a substitute for the manual checks below.

The integration test uses a uniquely named encrypted snapshot and platform key and cleans them up. It checks ciphertext does not expose the test owner, reads data with a fresh repository, exercises create/edit/delete through the UI, and changes language to Turkish. It does not reset the actual register. App reinstall/restart persistence still needs manual testing.

## Manual checks before client acceptance

- Enrol metadata; force-stop and reopen. Confirm records persist. Search by owner, ID and breed. Edit and delete; cancel deletion once.
- Export JSON and CSV via Android's file chooser to a private emulator folder. Delete a test record and import it back. Reject malformed and duplicate imports without changing existing records. Cancel both chooser flows.
- Open capture rehearsal, test hygiene requirement and each bad condition, then complete five valid fixture frames. Changing conditions resets progress. This is not a camera test.
- Add a demo queue receipt, process it, reopen, and confirm its acknowledgement persists. Reprocess and confirm the attempt count is unchanged. Animal identity remains unverified.
- Test English/Turkish at large system font size; rotate while editing and while capture rehearsal runs; check scrolling, keyboard visibility and navigation. Record any unsaved-input loss.
- Use airplane mode for all local CRUD flows. No server or model should be required.
- Check dark/background/resume behaviour, Android Back, and file picker return. Inspect app-scoped crash logs if any flow fails.

## Environment evidence

Agent sandbox ADB attempt failed before device discovery: `could not install *smartsocket* listener: Operation not permitted` and inability to open a netlink socket. The sandbox cannot reach Android Studio's host ADB socket. This is not evidence that the user's emulator is missing or broken. No emulator test has been completed from this session.

Independent queue and capture domain checks pass. The integration suite is authored and formatted but unexecuted. Flutter dependencies and device execution still require host access. Client acceptance is pending, and backend/model work has not commenced.

## Host run: dependency compatibility fix

The host runner discovered emulator-5554, resolved dependencies, passed analysis, passed all three register unit tests, and passed capture/queue domain checks. Emulator integration stopped before installation at `:file_picker:checkDebugAarMetadata`: file_picker 8.3.7 sets compileSdk 34, but flutter_plugin_android_lifecycle 2.0.35 requires 36.

A targeted project-level `finalizeDsl` configuration now sets the file_picker library's compileSdk floor to 36 after its own configuration. API 36 is installed locally. The shared pub cache is unchanged. This follows Android's module-specific compileSdk configuration model: https://developer.android.com/build . Gradle compilation of this fix and emulator tests still await the next host run. The later uninstall error occurred during test cleanup after the failed build and is not yet evidence of an app installation defect.
