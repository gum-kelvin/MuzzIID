# Android validation and specification conformance

Current private Flutter client, with the user's latest UI removals and a bundled trained research embedding model. Original source: `System Design & Implementation Specification Requ....docx`; explicit user changes override its stack, account, field, privacy and feature decisions.

## Approved client changes

- Flutter/Material 3, Riverpod, Android, English/Luganda, existing cream/green shell and wordmark.
- No accounts, named officer identity, NIN, phone or new breed fields. Owner, automatic UTC time, GPS/place label and structured vaccination history remain.
- Saved offline moved from Home into Settings.
- Export/import, About, haptic feedback, outdoor contrast and district manifest removed completely from active app code. The Home manifest card, network controller, archive codec, file-picker and CSV dependencies were removed too. Existing dormant encrypted cache files are not purged or exposed.
- Release manifest no longer requests Internet. Debug/profile manifests retain Flutter tooling's network permission. No personal data upload or server sync is implemented.

## Model evidence

Actual model: `cattle-resnet50-arcface-research-v1`, ONNX SHA-256 `b0e1839cf367e18c53aa649d182274d336bedbaae87cd834db791c8ae44bbdb4`.

Source data: [Xiong, Li and Erickson's cattle muzzle dataset](https://zenodo.org/records/6324361), CC BY 4.0. Archive checksum verified. After requiring at least seven images per identity: 4,823 images / 248 cattle, split by dataset identity into 173 train / 37 calibration / 38 test (seed 42). No private device records were used.

Training: frozen ImageNet ResNet50 backbone, learned 512-D projection/BatchNorm/L2 normalization, ArcFace training for 60 epochs. This adapts the [reference project's](https://github.com/darasiemi/Animal_Biometrics_System) ResNet approach to open-set template matching. It does not reproduce the paper's closed-set classifier experiment or perform end-to-end backbone fine-tuning.

| Held-out test metric | Value |
| --- | ---: |
| Probe images / cattle | 627 / 38 |
| Correct top-ranked identity | 95.06% |
| Correct accepted match | 81.02% |
| Wrong accepted match | 0.319% (2/627) |
| Strongest wrong candidate exceeding threshold | 0.478% |
| PyTorch/ONNX output maximum absolute difference | 1.08e-7 |

These are exploratory public-dataset results, not independent field certification. The specification's ≤0.1% FMR is not established. Exact image duplicates were checked; near-duplicate physical identities under different labels may remain. US clean/cropped feedlot images do not establish performance on Uganda field scans. Model/status/result screens explicitly label research use and ask for manual identity confirmation.

See [full training report](../model_training/report.json), [split manifest](../model_training/split.json), [training provenance](../model_training/README.md) and [asset contracts/replacement](MODEL_INTEGRATION.md).

## Client implementation boundaries

| Specification item | Implementation | Acceptance boundary |
| --- | --- | --- |
| CameraX / YUV capture | Flutter CameraX plugin, measured luminance/focus, portrait ROI, quality-85 JPEG after raw burst collection | Nokia negotiates 720×480, not the exact requested 640×480 |
| YOLO localization / ≥40% occupancy | Optional single-class ONNX detector adapter and box/containment checks; guided fallback | No detector weights bundled; guided acknowledgement does not prove anatomical localization |
| Five-frame enrolment | Five quality-approved raw frames, gap/reset policy, encoding after collection, pause/resume-safe completion | Previous Nokia runs collected five in 1,834 and 1,740 ms; latest attached-model run is checked separately |
| 512-D embedding / version isolation | Bundled trained model, validated shapes/hash, normalized burst centroid, encrypted template cache keyed by artifact/source digest | Research model; no validated field FMR or recognition latency claim |
| Open-set matching | Calibrated local cosine scores, top-two ambiguity margin; local unknown explicitly scoped to device register | Missing source images/model errors return pending; national registry lookup is absent |
| Privacy/storage | AES-256-GCM snapshots, platform-protected keys, atomic writes, codecs off UI isolate, fail-closed missing keys, Android backup exclusions | Snapshot store is for small local field registers, not national-scale indexing |
| GPS | Fresh device fix, accuracy and UTC timestamp, visible refresh failures | GPS is ordinary device positioning, without hardware attestation |
| Vaccination | Structured chips/date, optional batch/validity/GPS, editable profile history, encrypted saving | Operator records do not certify trade clearance or medical validity |
| Offline queue | Local receipts/activity/pending inspection from Settings | No server uploader, WorkManager batch sync, acknowledgement or server duplicate guard |
| Safeguards | Hygiene prompts and strict measured quality gates | No automatic occlusion classifier, optical-flow liveness, Play Integrity or server identity/authentication |

## Current checks

The latest source analyzer and 12 unit/widget tests pass. Seven standalone checks cover quality/burst rules, YUV/rotations/RGB/JPEG, record persistence, queue behavior, lifecycle completion and AES-GCM round trips/tamper rejection. Tests for removed archive/manifest features were removed with those implementations; queued enrolment, vaccine and metadata regression coverage remains.

The required runner is `./tool/test_android.sh YOUR_DEVICE_ID`. Its attached-model Nokia tests passed: workflow/removal assertions, actual CameraX/GPS, native ONNX embeddings and a baseline-specific enrol/verify smoke test. The normal APK was built, installed and launched successfully; the full runner completed with exit 0. The smoke test uses selected public-image fixtures in an isolated encrypted template store and creates no production animal records. It is not the accuracy benchmark.

Production screenshots and device logs are under `muzzlid/test-results/`. Final acceptance still needs actual cattle field testing, first-run denial/retry UX, storage/key recovery across supported vendors, liveness/attestation work, and trained detector validation. Luganda remains draft copy for native-speaker review.

Attached-model device measurements: Nokia C32 / Android 13, 720×480 YUV, fresh GPS accuracy 24 m, five-frame raw collection 1,680 ms after pause/resume. Native embedding calls measured 8,656 ms cold and 1,196 ms warm in a debug integration run. These are individual call samples, not an AOT latency distribution. The baseline-specific enrol/verify/cache smoke test passed in 16 seconds.

Final visual check: current production Home and Settings and the integration Luganda Settings capture were inspected on the Nokia. Saved offline is absent from Home and present in Settings; removed features are absent; Research model ready is visible; labels wrap without overflow. Existing production records remained present after installation. The temporary USB keep-awake setting was restored to its original value (0).
