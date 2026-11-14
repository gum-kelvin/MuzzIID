# Field UI integration

This source extension follows `files/02_field_home` through the supplied `18` PNG references within the existing Flutter application. It retains the cream and green shell, Field/Register/Settings navigation, and the existing brand treatment. It adds no account, login or named-officer identity. Daily enrolment/verification counters and breed fields are absent from the current screens; dates remain visible as record timestamps. Legacy breed data remains readable for compatibility.

This document supersedes workflow, language, record-field, manifest and validation statements in `IMPLEMENTATION.md`, `ANDROID_CLIENT_TESTING.md`, `ANDROID_CAPTURE_IMPLEMENTATION.md` and `SPECIFICATION_VALIDATION.md` where those describe earlier revisions. Those files retain historical implementation evidence; prior emulator success does not establish acceptance of this revision.

## Screen and route map

Only `/`, `/enrol` and `/verify` are declared router paths in `lib/main.dart`. Other destinations use pushed Material routes; tab selection is application state, not a distinct URL.

| Entry | Destination and behavior |
| --- | --- |
| `/` → Field | Primary Verify animal and secondary Enrol animal actions; pending offline total; district-manifest summary; recent enrolment, vaccination and verification activity. Record activity opens its profile; verification activity opens sync status. |
| Field → Enrol, Register → Enrol, or `/enrol` | Three-step owner/location → guided muzzle capture → vaccination/review flow. Successful local save replaces the form with a receipt. |
| Receipt | Receipt ID, owner, optional place label, GPS, timestamp and administered vaccines; pending-sync status; Enrol another and Back to Field actions. |
| Register tab | Combined district-manifest and local records, with local records taking precedence for matching IDs; search by ID, owner or location; All/Vaccinated/Due soon/None filters; empty and no-match states. |
| Register or activity → profile | Captured image, owner, recording time, location and vaccine history; edit metadata, confirmed local deletion, and Add vaccination. Manifest-only records cannot be deleted as local records. |
| Profile → Add vaccination | One vaccine, administration date, optional validity date and batch number, fresh GPS, and explicit offline save. |
| Field → Verify or `/verify` | Three-item preparation checklist and GPS acquisition before Start scanning becomes available. |
| Checklist → scanner → result | Actual camera preview and quality instructions, capture, local activity persistence, then verification result. Result variants are verified, low confidence, unregistered and pending. |
| Field offline summary → sync status | Waiting enrolments and verification activities, failed/conflict states and any imported acknowledged records. Conflict items open their profile for inspection. |
| Settings tab | District manifest first, then sync/scanning controls, haptics, outdoor contrast and About; language and export/import follow. |

## Implemented behavior

Owner is required. The officer-entered place label is optional; it supplements device GPS. GPS is required for new enrolment, verification and new vaccination records, with permission/service/error guidance and retry. A fix records coordinates, accuracy and capture time; fixes older than five minutes are refreshed before the action. This is device location, not hardware-attested proof. Creation timestamps are automatic and retained during metadata edits.

New enrolment requires five captured JPEG crops before review/save. Vaccination during enrolment is optional; selecting it requires at least one vaccine chip. The choices are FMD, Lumpy skin, Brucellosis, Anthrax and Other, with an administration-date picker. Separate Add vaccination accepts one vaccine and checks that optional validity does not precede administration. Entries record their own recording time and GPS; vaccine history is officer-entered data, not medical clearance. The Due soon filter uses supplied validity dates within 30 days, including dates already passed; the UI does not display elapsed-day counters.

The scanner uses the rear Android camera and a portrait guide. Hygiene/framing acknowledgement, focus above 120 and luminance within [45,215] gate capture. Enrolment collects five valid samples over approximately 1.5 seconds; invalid input or a processing gap over 500 ms resets the burst. YUV conversion, rotation/cropping and JPEG processing run outside the UI isolate. Guidance covers steadiness, lighting and glare. Camera errors allow retry. Camera resources are released on pause, unfinished capture resets, and completed immutable payloads are delivered once after resume; disposed screens cannot navigate. These are source behaviors and command-line checks, not hardware acceptance.

Records, captured images, GPS, vaccinations, scanning preferences, manifests and verification activity use local encrypted snapshots; language selection uses platform secure storage. Snapshot cryptography runs outside the UI isolate. Saves finish before the receipt is shown. JSON v4 and the current CSV export include structured GPS, vaccinations and sync state; earlier JSON versions and CSV headers remain accepted. Register import rejects duplicate IDs before replacing the register. Explicit exports are plaintext. Manifest import is a separate operation and does not replace local edits.

English and Luganda are available with persisted selection. App strings and the custom Luganda Material date-picker labels/calendar formatting are bundled locally. Luganda copy still needs native-speaker review. Haptic feedback and high-contrast outdoor theme settings persist. No translation service is called.

## Manifest setup

From `muzzlid`, resolve packages and supply an HTTPS source at build/run time to enable downloads:

```sh
flutter pub get
flutter run --dart-define=MANIFEST_URL=https://example.org/manifest
```

The URL is deployment configuration, not an endpoint supplied by this project. Download appends the selected `district` query parameter while preserving existing query parameters. The endpoint must return HTTP 200 with UTF-8 JSON containing an `animals` array readable by `Animal.fromJson`; a JSON register export provides a compatible array. The selected district and local download/import timestamp are stored with the cache. No authentication or signed-manifest protocol is implemented.

Downloads have bounded size (10 MiB), timeouts, progress and cancellation before final persistence. Redirects are rejected. The final encrypted commit cannot be cancelled or overlapped. Validation or download failure preserves the previous cache. Without `MANIFEST_URL`, Settings reports that the source is not configured. Import manifest remains available through the JSON file picker without a network source; files over 10 MiB and duplicate animal IDs are rejected. File-picker allocation occurs before the size check.

Android is the implementation target. Location uses `geolocator_android` 5.0.3 directly; this avoids pulling desktop geolocator dependencies that conflict with the existing file-picker dependency. Existing iOS scaffolding is not validated by this increment.

## Service boundaries

No backend, trained detector/embedding model, calibrated biometric matcher, automatic uploader or background sync worker is connected. The verification interface defaults to `UnconnectedVerificationService`, which returns pending. A captured verification is saved locally before the service call; unavailable, timed-out or invalid service responses stay pending. Verified/low-confidence/unregistered layouts and their actions exist for a future service, but the default application never fabricates those outcomes. Illustrative score guards in the adapter are not field-validated accuracy thresholds.

Auto-sync is visibly disabled and off. Guided reticle is visibly enabled and locked until a detector exists. Sync now reports that the service is disconnected and does not upload or change pending records into acknowledgements. Conflict status offers inspection, not biometric duplicate resolution. Manifest download is a read-only cache fetch and does not constitute sync or identity verification.

Automatic muzzle detection/occupancy measurement, liveness, matching accuracy and physical-device camera/GPS performance remain outstanding. The manual reticle and quality statistics do not prove that a frame depicts a muzzle.

## Design continuity

`lib/main.dart` remains the theme source: Material 3, cream scaffold (`0xfff6f7f2`), green seed (`0xff245c40`), outlined inputs and primary buttons with a minimum height of 52 logical pixels. Existing shared page bodies constrain content to 640 logical pixels with 24-pixel padding and scrolling. The extension reuses Material typography, icons, cards, chips and textual status badges. No new visual identity or separate design-token authority is introduced. Startup requests portrait orientation; render behavior at large font sizes and on physical devices still needs review.

## Validation scope

Passed command-line checks cover:

- Field-record/GPS/vaccination round trips, freshness and invalid-data rejection, plus current and legacy record compatibility (`field_records_check.dart`, `record_check.dart`).
- Capture gates and burst timing, four-rotation YUV/quality/JPEG processing, and durable queue behavior (`capture_check.dart`, `camera_frame_check.dart`, `queue_check.dart`).
- Isolate AES-GCM round trip, ciphertext confidentiality and tamper rejection (`snapshot_check.dart`).
- Immutable completed payloads, delivery once after pause/resume, and prevention of navigation after disposal (`capture_lifecycle_check.dart`).

Final analyzer validation reports no issues. `client_workflow_test.dart` adds manifest commit/cancellation and Luganda calendar checks. The Android integration suite is authored, including injected capture/location fixtures; this revision's Android suite has not been executed successfully. Fixtures test workflow/storage boundaries and do not certify live camera or GPS.

The mandatory `./tool/test_android.sh` runner was attempted from `muzzlid`, but ADB could not create its listener in the sandbox (`Operation not permitted`). That failure occurs before device acceptance and does not establish a problem with the host emulator. Run the same command from a host terminal with a booted emulator; optionally pass its device ID. The runner includes analysis, domain/package checks, Android integration, APK build/install, process checking and a screenshot only if all preceding steps succeed.

No current emulator screenshots or render validation are available. Host/device acceptance still needs live camera permission and preview checks, blur/dark/glare rejection, five-frame enrolment, GPS permission/service failures, pause/resume, offline save/reopen, manifest failure/cancellation, file-picker returns, large text, English/Luganda navigation and visual comparison with the supplied references. Neither the documentation nor the authored tests claim a new Android integration pass.
