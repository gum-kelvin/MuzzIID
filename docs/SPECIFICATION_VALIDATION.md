# Specification validation — capture increment

Authority: `System Design & Implementation Specification Requ....docx`, including Office Math expressions preserved in `specification-extracted.txt`. The user-approved Flutter/private local MVP exception continues to govern native UI and cloud transport choices.

| Specification requirement | Current evidence | Status / remaining work |
|---|---|---|
| Flutter Material 3 / English + Turkish | Routing, field/register/settings, new capture rehearsal | Source implemented; device rendering unverified |
| 640×480 YUV CameraX acquisition | Luma analyser accepts cropped Y-plane bytes and strides | Actual camera adapter, permissions, lifecycle and rotation absent |
| YOLOv8-nano INT8/FP16 localisation | No model weights present in supplied files | Unavailable; no fabricated model-ready status |
| Laplacian variance >120 | CapturePolicy rejects 120 and below; isolated luma analysis | Domain tested; OpenCV kernel/border parity and calibration pending |
| Luminance [45,215] | Inclusive limits; padding excluded from image statistics | Domain tested |
| Bounding box ≥40% reticle area | Geometric occupancy check | Domain tested |
| Four corners inside frame margins | safeFrame containment plus reticle containment | Domain tested; stricter reticle containment is a conservative implementation decision |
| Mandatory wipe-muzzle prompt | Hygiene acknowledgement blocks capture rehearsal | Source implemented; domain tested |
| Occluded muzzle rejection | Explicit occluded input blocks quality policy | Policy tested; no detector supplies this signal yet |
| Five consecutive valid frames over ~1.5 seconds | EnrolmentBurst samples at ≥375 ms; invalid intermediate frames reset | Domain tested; actual frame/image retention absent |
| Manual guided reticle fallback | Capture rehearsal uses fixture geometry | Rehearsal only; live manual ROI selection absent |
| JPEG quality 85%, 35–60 KB target | No image encoder integrated | Pending; size target must be measured, not guaranteed |
| ResNet50/ArcFace, 512-D normalised embeddings | Existing model interface only | Training, weights and on-device inference absent |
| Three-way open-set decision | Existing version-isolated matching policy | Thresholds illustrative; no field FMR validation |
| Offline encrypted scans / receipts | Encrypted demo receipt queue, retry/crash recovery | No real image payloads stored; biometric enrolment unavailable |
| Automatic WorkManager jobs | None | Deferred; no network transmission permitted under approved MVP |
| Duplicate enrolment conflict | Queue supports conflict state | No embedding deduplication or conflict resolution yet |
| Farmer ownership and health | Local owner/breed/district register | No verified ownership, vaccination evidence or trade clearance |
| Regional manifest | None | Private local import/export only |
| Anti-replay / attestation | None | Never inferred from hygiene, quality checks or simulated frames |
| Backend API / JWT / pgvector | Mock model and receipt processing only | Cloud behaviour excluded by approved privacy decision |

Burst cadence is an explicit interpretation of “5 consecutive valid frames over ~1.5 seconds”: all analysed frames must pass, and five samples are spaced over that window. The 500 ms maximum inter-frame gap is an engineering safeguard rather than a document-provided threshold. A camera adapter must submit every analysed frame with monotonic timestamps; real frame-rate/backpressure tests remain necessary.

The analyser uses a four-neighbour discrete Laplacian over interior ROI pixels and calculates population variance. It is a pure Dart implementation running in Isolate.run, not an assertion of OpenCV equivalence. The camera adapter must crop the ROI before calling it. Input copying is on the caller isolate; image computation is on the worker. Frame-stream allocation and scheduling must be benchmarked and replaced with a persistent worker or native implementation if needed.

## Validation performed

`dart --disable-dart-dev muzzlid/test/capture_check.dart` passed checks for exact threshold boundaries, hygiene, occlusion, invalid metrics, frame containment, scale, timed five-frame completion, invalid-frame resets, stalled/out-of-order timestamps and flat/textured ROI statistics computed in an isolate. Existing queue regression checks also pass.

Dart formatting completed. Dependency resolution was retried and failed reaching pub.dev (flutter_riverpod). Flutter analyzer, widget tests, Android APK and visual device review remain blocked by missing dependencies. No claims of real camera capture, validated biometric recognition, liveness or production readiness are made.

## How to run this increment

With dependencies available, run `flutter pub get` and `flutter run` from `muzzlid`. Open Field → Rehearse guided capture. Confirm hygiene, choose a good fixture, and start the burst; expect five samples in about 1.5 seconds. Change conditions to exercise blur, glare, darkness, distance, framing and occlusion feedback. These fixtures do not use the camera or save images.

Without Flutter dependencies, from the workspace root:

```sh
/path/to/dart --disable-dart-dev muzzlid/test/capture_check.dart
/path/to/dart --disable-dart-dev muzzlid/test/queue_check.dart
```

Next executable integration is an Android CameraX Y-plane adapter with rotation-aware ROI mapping, camera lifecycle handling and a validated localisation model. Native capture must not bypass quality gates when model readiness fails.
