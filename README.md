# MuzzIID

Private Flutter Android cattle register with CameraX guided muzzle capture, encrypted offline records, structured vaccinations, English/Luganda, and a bundled MegaDescriptor-L-384 research embedding model.

The interface uses Material 3 with the existing cream-and-green design. Saved offline is in Settings. Registration collects five separate quality-approved photos and issues a local receipt; verification opens directly into a full-screen camera and compares against the device's local register. GPS and audit timestamps are collected automatically and not displayed.

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

The active model is [BVRA/MegaDescriptor-L-384](https://huggingface.co/BVRA/MegaDescriptor-L-384), converted to INT8 ONNX for private mobile inference. It uses 384×384 RGB inputs normalized with mean/std 0.5 and returns all 1,536 embedding features. Its model-card licence is CC BY-NC 4.0. Matching thresholds are from a small public-data pilot and require field calibration; research results require manual confirmation. The previous ResNet experiment is retained as historical training provenance.

See [model integration](docs/MODEL_INTEGRATION.md), [active-model provenance](model_training/megadescriptor/README.md), [measured results](model_training/megadescriptor/validation_report.json), and [Android validation](docs/ANDROID_VALIDATION.md).

The Nokia validation passed the full Android runner, including encrypted workflows, CameraX/GPS, actual ONNX inference, and isolated enrolment/matching/cache checks. Local device screenshots, records, exports, environments and build outputs are excluded from this repository.
