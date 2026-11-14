# MuzzlID implementation

## Authority and approved decisions
Source: `System Design & Implementation Specification Requ....docx`; searchable extraction beside this file preserves Office Math text. User approved Flutter + private local MVP instead of Kotlin/cloud on this session. Document spelling MuzzlID is used for display. Dart name is `muzzlid`; proposed Android application ID `com.example.muzzlid` normalizes the prompt's mixed case. Finance transactions/investments are template examples, superseded by animal records and scan receipts.

The current delivery is source scaffolding, not a production biometric system. No model weights, native camera pipeline, medical clearance, server, analytics, remote manifests or background upload are included. All animal records remain pending biometric enrolment. Owner name is collected; NIN and phone are deliberately unnecessary for this MVP. Locale currently lasts for the session.

## Step 0 — Plan
Small feature layers:

```
muzzlid/lib/
  main.dart                 Material 3, route table, locales
  domain/register.dart      Animal, repository contract, CRUD use cases, matching policy, model interface
  data/encrypted_register.dart  AES-256-GCM snapshots, platform key storage
  presentation/state.dart   Riverpod application state
  presentation/screens.dart Field desk, register, enrol/edit, guided demo, settings
```

Field desk makes verification the primary action, enrolment secondary, and local receipts visible. Register supports search, edit and confirmed deletion. Guided verification includes mandatory hygiene acknowledgement; all results state that they are simulated. Settings provides language selection and explicit file exports. Empty, loading, failure and busy states are included. Phone content is capped at 640 logical pixels and scrolls; device accessibility testing remains outstanding.

Visual direction: outdoor-readable warm white surfaces, forest-green actions, Material typography and icons, restrained spacing, no decorative imagery. Status must always carry text. Future real capture should keep the camera frame primary, with one actionable quality instruction. Respect system reduced-motion preferences when adding animation.

## Step 1 — Bootstrap
On a workstation with a writable Flutter installation and network access:

```sh
flutter channel stable
flutter upgrade
flutter doctor
cd muzzlid
flutter create --project-name muzzlid --org com.example --platforms android,ios --no-pub .
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

Run platform generation against this existing source directory; inspect its diff and retain the supplied application files. No successful generation/build occurred in this environment. The current stable version must be recorded from `flutter --version` and the resolved pubspec.lock committed after dependency resolution; the installed SDK was unable to report its version. Do not interpret dependency ranges as verified latest versions.

Dependencies declared in pubspec: flutter_riverpod (single state management system); go_router (navigation); flutter_localizations (Material widgets and Turkish/English); cryptography (authenticated AES-GCM); flutter_secure_storage (platform-protected encryption key); path_provider (private app directory); file_picker (user-directed local import/export); csv (quoted field handling). flutter_test and flutter_lints support verification. No analytics or HTTP SDK.

Android configuration after generation: applicationId com.example.muzzlid; display label MuzzlID; minimum SDK compatible with resolved plugins (start at 23); compile/target SDK matching installed stable Flutter requirements. Disable backups with android:allowBackup="false" and provide Android 12+ extraction rules excluding app files and shared preferences from cloud backup/device transfer. Do not add release INTERNET, camera or location permissions until actual functionality needs them. Explicitly inspect the merged release manifest. Android Keystore key loss must show recovery guidance, never reset data silently. Configure release signing outside source control.

iOS is future scaffolding only: generate Runner on macOS, configure unique bundle ID, signing team and the secure-storage plugin's required Keychain capabilities for its resolved version. Set deployment target to the plugin-supported minimum. Exclude sensitive app storage from iCloud backup. Camera/location purpose strings are needed only once these integrations exist. Android is the required platform; iOS cannot be validated here.

How to run: commands above. SDK bootstrap, platform hardening and actual device execution remain outstanding.

## Step 2 — Local data
Animal: local ID, owner name, breed, district, UTC creation time. The repository persists authenticated encrypted snapshots using a random platform-protected 256-bit key, random nonces and atomic replacement. Failed decryption does not overwrite existing data. This is lean small-register storage; move to encrypted SQLite with transactional migrations before large district manifests. Avoid simultaneous mutation entry points; add serialized repository writes before background workers are introduced.

JSON has version=1 and an animals array. CSV header is id,owner,breed,district,created. Imports validate required strings/date and reject duplicate IDs before writing; existing records are preserved. Import file cap is 2 MB, but picker allocation occurs before the cap is checked. Export is deliberate plaintext and warns the operator. Spreadsheet formula escaping, streaming validation and encrypted portable backups remain production hardening work.

How to run: enrol a record, reopen app, search/edit it, export JSON or CSV to a private location, delete it with confirmation, then reimport. Test invalid import without losing records. Confirm raw app files contain ciphertext. These are manual acceptance checks, not tests already performed.

## Steps 3–4 — Capture and field validation (next increment)
Implement actual camera permission/lifecycle handling and bounded frame processing off the UI isolate. Preserve 640×480 YUV input, YOLOv8-nano, Laplacian variance >120, luminance [45,215], >=40% reticle occupancy and all-corners containment. Offer manual reticle fallback without bypassing quality gates. Enrolment needs five valid frames over approximately 1.5 seconds, JPEG quality 85. Camera simulation does not satisfy these gates.

Keep ResNet50 + ArcFace, 512-D L2-normalized embeddings, model-version isolation and optional CLAHE as the document's technical direction. No supplied production model is assumed. Real inference must occur on-device under the approved privacy boundary; benchmark memory/latency before committing to that deployment. If not feasible, pause identity resolution and keep captures pending instead of sending personal data to a server.

Calibrate open-set thresholds on held-out cattle, devices and field conditions. 0.78 and 0.68 are illustrative specification thresholds, not validated production values. Unknown is below 0.68; the storyboard's broader '<0.78 means unregistered' conflicts with its ambiguous band, so the explicit three-way policy wins. Motion variance alone is insufficient proof of liveness; do not claim anti-spoofing or hardware-attested GPS without validation. Identity confidence is not health clearance.

## Step 5 — Model API and sync
ModelApi is injected through Riverpod. MockModelApi uses explicit scenario selection and deterministic receipt acknowledgements; no transport, credentials or upload. Running mock sync never converts local records into verified identities. A durable per-scan queue with pending/processing/acknowledged/conflict/failed state, retry count, model version, payload hash and idempotency key is a next increment, not implemented here. Real acknowledgements must be committed atomically; duplicates must enter conflict review rather than minting a second identity. WorkManager/native platform bridges are deferred until there is an approved on-device job to schedule.

How to run: Field → Verify demo → acknowledge hygiene → select a scenario → run. Unknown offers enrolment. Field → Run mock sync reports that nothing was uploaded. No backend setup required.

## Evidence and literature
- Swisscontact, 18 January 2023: https://www.swisscontact.org/en/news/bangladeshs-first-ever-muzzle-based-cattle-identification-system-for-insurance describes mPower/Surokkha cattle and farmer registration for health/life insurance. It motivates ownership linkage and simple registration flows; it does not publish architecture, operating thresholds or accuracy figures.
- Local Animal_Biometrics_System README/notebooks supply training/data split examples. Evaluate splits by individual animal and acquisition session to prevent leakage; no production model is assumed from notebooks.
- Local capsule README describes cropped muzzle → features → comparison, using LightGlue/LoFTR. These are alternative baselines, not reasons to silently replace the specification's model.
- Local engproc-92-00053.pdf reports YOLOv8, CLAHE, ORB and FLANN with 22/25 cattle correctly identified (88%). The small evaluation does not establish the document's <=0.1% false-match-rate target.

## Tools and validation status
Used local shell/Python ZIP+XML extraction, pdftotext, official Flutter documentation and Swisscontact web access, and the Impeccable design skill. Its context launcher failed because its engine/cache was unavailable. No external service received app data. No generated images or backend services.

Flutter execution failed first on its read-only SDK cache; a writable SDK copy then failed on unavailable GitHub DNS and a read-only telemetry directory. Dependencies, native platform projects, analyzer, widget tests, APK build and visual device review are therefore unverified. This source increment must not be described as production-ready.


## Implementation increment 2
Android and iOS platform source projects were successfully generated using the cached Flutter 3.44.8 stable tool snapshot with analytics and version checking disabled. This bypassed the previous bootstrap error. Android display name is now MuzzlID, minimum SDK is 23, and allowBackup/fullBackupContent are disabled. Android 12 extraction-rule review, signing and release manifest validation remain outstanding.

Added encrypted demo queue storage (`scans.v1`), a local queue screen linked from Field desk, immutable receipt IDs, model version tags, retry counts and persisted pending/processing/acknowledged/failed/conflict states. Operators explicitly add one demo receipt per animal. Interrupted processing is retried with the same idempotency key. Acknowledged entries are skipped on subsequent runs; simulated acknowledgements never verify animal identity. No real scan payloads, duplicate biometric detector, scheduled worker or remote transport is implemented. Queue receipts are separate from animal metadata and retained if its record is deleted.

Register UI writes are serialized to avoid overlapping edits losing records. Each encrypted snapshot uses a separate platform-protected key, with key initialization cached per store instance.

Validation performed: dependency-free queue check passed failure persistence, retry count, acknowledgement, idempotency, crash recovery and JSON round trip. All Dart sources were formatted. `flutter pub get` failed because pub.dev DNS/network was unavailable. Full analysis, package-based tests, APK compilation and visual device review remain blocked; no successful build is claimed.

Run the independent domain check from the project root:

```sh
dart test/queue_check.dart
```

Once dependencies are reachable, from muzzlid run `flutter pub get`, `flutter analyze`, `flutter test`, and `flutter run`. The original bootstrap notes above describe the initial delivery; this increment supersedes their platform-generation and durable-demo-queue status.

## Implementation increment 3 — capture policy
Added specification-derived capture gates, isolate-based cropped Y-plane statistics, timed five-frame burst rules, and an English/Turkish guided capture rehearsal. See [requirement-by-requirement validation](SPECIFICATION_VALIDATION.md) for implemented behaviour, deliberate decisions, tests and remaining native/model work. No new dependency was introduced. Real camera capture remains unavailable.

## Current Android capture increment
[Current behaviour and remaining gaps](ANDROID_CAPTURE_IMPLEMENTATION.md) supersede previous demo, Turkish-language, settings-layout and import-schema descriptions. Client acceptance must be rerun; the earlier emulator success applies to the previous revision.
