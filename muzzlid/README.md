# MuzzIID — Android client

Flutter Material 3 cattle register with encrypted local enrolment, CameraX guided capture, five individual registration photos, structured vaccination records, English/Luganda, and a bundled MegaDescriptor-L-384 research embedding model.

Saved offline is in Settings. Export/import, About, haptics, outdoor contrast and district-manifest features have been removed. Identification stays on-device. Research results require manual confirmation and field validation.

With the Nokia connected, unlocked and pointed at a well-lit textured surface:

```sh
./tool/test_android.sh YOUR_DEVICE_ID
```

See [model integration and replacement](../docs/MODEL_INTEGRATION.md), [active-model provenance](../model_training/megadescriptor/README.md), and [Android validation](../docs/ANDROID_VALIDATION.md).

Verification opens directly into the full-screen camera. Each registration photo requires its own shutter press; accepted photos survive camera pauses, exact duplicates are rejected, and retakes are available. GPS and audit times remain encrypted metadata and are hidden throughout the interface. Clinical vaccination dates remain visible.
