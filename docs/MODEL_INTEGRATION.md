# Android model integration

The current Android app bundles an actual research embedding model: `cattle-resnet50-arcface-research-v1`. It runs privately on the handset through ONNX Runtime Android. Personal records and source images stay on-device.

## Bundled baseline

The [training pipeline](../model_training/README.md) adapts the ResNet family approach in [Animal_Biometrics_System](https://github.com/darasiemi/Animal_Biometrics_System), using the original [public cattle muzzle dataset](https://zenodo.org/records/6324361). That repository supplied notebooks and CSV splits, not trained weights or image files. The model attached here was trained in this workspace; the unrelated local backend checkpoint was not reused.

Architecture: frozen ImageNet ResNet50 → training-set feature centering → learned 2048→512 projection → BatchNorm → L2 normalization. Projection training uses ArcFace angular margin 0.3, scale 32, for 60 epochs. It is an embedding model for enrolment of additional cattle, rather than a fixed classifier over training IDs.

Data selection: 4,823 images from 248 cattle with at least seven photos. Identity-level split: 173 train / 37 calibration / 38 test, seed 42. Calibration/test images are distinct from each animal's gallery images. Exact image duplicates were checked; near-duplicate physical identities under different labels remain a limitation.

Measured test results on 627 probes / 38 cattle:

| Metric | Result |
| --- | ---: |
| Correct identity ranked first | 95.06% |
| Correct accepted match at configured threshold/margin | 81.02% |
| Wrong accepted match | 0.319% (2/627) |
| Strongest impostor exceeding threshold | 0.478% |
| PyTorch vs ONNX maximum absolute output difference | 1.08e-7 |

These metrics are from public clean cropped feedlot images. They do not certify field accuracy, the specification's ≤0.1% FMR, liveness, owner identity, or trade clearance. The model is explicitly marked `research=true`; Settings and result screens show that status and require manual confirmation. The [full report](../model_training/report.json) includes thresholds and limitations. Handset smoke fixtures are selected integration examples, not the accuracy sample.

## Asset contract and replacement

Files live under `muzzlid/android/app/src/main/assets/models/`:

- `embedder.onnx`: float32 input `[1,3,224,224]`, single float32 output `[1,512]`, ONNX opset 17.
- `model.json`: schema/version/checksum, tensor dimensions, calibrated operating thresholds, top-two margin, research flag.
- `model_card.json` and `ATTRIBUTION.txt`: measured provenance and dataset credits.

Preprocessing: JPEG decode → bilinear 224×224 resize → RGB CHW `/255` → ImageNet mean `[.485,.456,.406]`, std `[.229,.224,.225]`. CLAHE is off. Export the embedding head, not classification logits. Tensor shapes, finite outputs, nonzero vector norm and SHA-256 are validated. Outputs are L2 normalized.

To use your own trained export, preserve the existing baseline artifacts elsewhere, replace the ONNX/config, recompute `sha256sum embedder.onnx`, and rebuild. Change the version when weights/preprocessing change. Use thresholds calibrated for your own model/data. Keep `research=true` while field validation is incomplete; `calibrated=false` deliberately leaves identification pending. Never reuse another model's thresholds blindly.

`muzzlid/tool/prepare_model.py` can validate and package an embedding export using CPU onnx/onnxruntime/numpy in a developer Python environment. It refuses to overwrite existing model assets and defaults to calibration disabled. Reproduce the bundled baseline with `model_training/train_baseline.py`; regenerate baseline smoke fixtures with `model_training/make_device_fixtures.py`.

Native model sessions/inference run on a worker executor with two intra-op threads, initialized lazily. Enrolment source images stay encrypted. Registration collects five individual quality-approved photos of the same muzzle, with an explicit shutter press for each. First verification creates and encrypts a normalized mean template from each animal's source images. Cached templates are isolated by artifact hash/version and source-image digest, and rebuilt when either changes. Empty records or missing reference photos return pending. A local unknown is explicitly labelled No local match and does not establish national registration status.

## Optional detector

No detector weights are bundled. A full-screen guided camera and measured focus/exposure gates remain available, without a pre-scan page or acknowledgement checkboxes. GPS and audit time are background metadata and never displayed. A compatible trained detector may be added as `detector.onnx` + `detector.json`: single-class YOLOv8 float32 RGB `[1,3,640,640]`, raw `[1,5,N]` output (cx, cy, width, height, confidence), no fused NMS, class 0=muzzle. JSON: `{"schema":1,"inputSize":640,"sha256":"YOUR_SHA256","confidenceThreshold":0.5}`.

The detector adapter uses letterboxing and RGB float scaling, reverses coordinates, draws a box within the guide, and requires ≥40% occupancy and containment. Frames reach native detection as RGB bytes without intermediate JPEG encoding. When a detector is ready, the guided preference can be disabled in Settings. Actual model FPS and detector accuracy require measurement with those weights.

## Current UI and service scope

Saved offline is in Settings. Export/import, About, haptic feedback, outdoor contrast, and district-manifest features were removed at the user's request, including the manifest network controller and unused file-picker/CSV dependencies. Home contains Verify, Enrol and actual recent activity. Language and the existing cream/green design remain.

Verification, enrolment and vaccination are local. Backend uploads/automatic sync, liveness/occlusion classification and hardware-backed attestation are absent. The main release manifest does not request Internet access; debug/profile builds retain Flutter tooling's network permission.

## Run

```sh
cd muzzlid
./tool/test_android.sh YOUR_DEVICE_ID
```

The runner covers encrypted workflows, UI removals, CameraX/GPS, actual native ONNX embeddings, and an isolated baseline enrol/verify smoke test. Baseline fixtures are specific to this artifact; regenerate semantic fixtures when replacing the model. Device validation results are recorded in [Android validation](ANDROID_VALIDATION.md).

External tools: CPU PyTorch 2.15.0, torchvision 0.29.2, ONNX export/opset 17, host ONNX Runtime 1.32.0 for parity, Android ONNX Runtime 1.24.3 for execution. The training environment is `backend_venv`; no backend source or checkpoint was modified. Dataset attribution is shipped with the model.
