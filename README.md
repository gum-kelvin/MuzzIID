# MuzzIID

Private Flutter Android cattle register with CameraX guided muzzle capture, encrypted offline records, structured vaccinations, English/Luganda, and a bundled ResNet50/ArcFace research embedding model.

The interface uses Material 3 with the existing cream-and-green design. Saved offline is in Settings. Enrolment captures five quality-approved frames and issues a local receipt; verification compares against the device's local register.

## Run

Install Flutter stable and the Android SDK, connect an Android handset with USB debugging enabled, then:

```sh
cd muzzlid
flutter pub get
flutter run
```

The validation script locates the configured Flutter/ADB installations and selects the sole connected device, or accepts an explicit device ID:

```sh
cd muzzlid
./tool/test_android.sh
# Or: ./tool/test_android.sh YOUR_DEVICE_ID
```

## Project layout

- `muzzlid/`: Android app, domain/data/presentation layers, tests and bundled ONNX model.
- `model_training/`: reproducible baseline training/export scripts, split manifest, attribution and measured results. Downloaded images, caches and checkpoints are excluded from Git.
- `docs/`: implementation, model handoff and Android validation.
- `files/`: UI references.
- `backend/`: experimental backend prototype, currently disconnected from the private Android client. Its local database and generated checkpoint are excluded.
- `literature review/links.txt`: research sources. Third-party repository copies and archives are not vendored.

The original Word specification is included. Later user-approved client changes are recorded in the current documentation.

## Model and validation

The bundled model was trained using 4,823 public muzzle images from 248 cattle, with separate training, calibration and test identities. It ranked the correct identity first on 95.06% of 627 held-out probes. This is a research baseline: field accuracy, the specification's false-match target, liveness and ownership verification are not certified. Research results require manual confirmation.

See [model integration](docs/MODEL_INTEGRATION.md), [training provenance](model_training/README.md), [measured results](model_training/report.json), and [Android validation](docs/ANDROID_VALIDATION.md).

The Nokia validation passed the full Android runner, including encrypted workflows, CameraX/GPS, actual ONNX inference, and isolated enrolment/matching/cache checks. Local device screenshots, records, exports, environments and build outputs are excluded from this repository.
