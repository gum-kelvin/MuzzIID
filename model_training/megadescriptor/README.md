# Active model: BVRA MegaDescriptor-L-384

Source: [Hugging Face model card](https://huggingface.co/BVRA/MegaDescriptor-L-384), revision `33b3c6f4ee0c386a4126cc3dcd23843920613fa1`. Model-card license: **CC BY-NC 4.0**, including its non-commercial restriction. The config file's embedded pretrained_cfg licence differs; this integration follows the explicit model-card licence. Citation and modification details are shipped in Android `assets/models/ATTRIBUTION.txt`.

The model is the pretrained animal re-identification Swin-L feature network, not a newly trained ResNet projection. The loaded feature backbone has 195,198,516 parameters and produces all **1,536 features**; no 512-D projection/truncation is applied.

## Input contract

The supplied user/model-card recipe wins over timm's repository-config defaults:

- Decode RGB, bilinear resize to **384×384** with no center crop.
- Float32 CHW, values `/255`, then mean `[.5,.5,.5]` and std `[.5,.5,.5]`.
- Raw network output `[1,1536]`; the Android matching adapter L2 normalizes it for cosine comparisons.

## Export and validation

1. `export_model.py`: load the pinned public checkpoint using timm's official Swin checkpoint conversion, FP32 eval mode, disable fused attention for export, and export a fixed-shape ONNX opset 17 graph.
2. `quantize_model.py`: dynamically quantize constant MatMul/Gemm weights per channel to INT8. Inputs and outputs remain float32. Attention operations with nonconstant operands remain float operations.
3. `validate_package.py`: compare FP32 ONNX with PyTorch, compare quantized directions on real images, run a small public-data calibration/pilot, generate semantic device fixtures, and only then replace active Android assets.

Run these scripts sequentially in the existing Python training environment. Required packages include torch, timm, huggingface_hub, numpy, Pillow, onnx and onnxruntime. Large checkpoints/reference exports are local ignored artifacts.

The FP32 export is 837,189,898 bytes; the mobile artifact is **254,701,330 bytes** (about 243 MiB). FP32 export maximum absolute error against PyTorch was `1.2279e-5`. Quantized/FP32 cosine on four checked images ranged **0.99047–0.99763**. The quantized derivative is numerically different from the original checkpoint and has its own version/hash.

The pilot uses 140 public images: 10 calibration cattle and 10 test cattle, five gallery images and two probes per identity. Calibration and pilot sample identities are selected before seeing scores from the earlier dataset split. MegaDescriptor may already have seen this public dataset during pretraining, so this is **not an independent generalization study**. Both small groups had all 20 known probes correctly accepted; on the test group, 15% of strongest wrong candidates exceeded the provisional threshold, even though the correct candidate still won. This does not establish reliable unknown-animal rejection or the project's target FMR. Research flags and manual confirmation remain enabled. See `validation_report.json` and `pilot_split.json` for exact results.

The previous ResNet thresholds/templates are not reused. New pilot thresholds are model-specific and provisional. Deployment requires representative field positives and unknown animals for recalibration.

## Android

`ModelRuntime.kt` streams the model asset into an app-private no-backup file, verifies its checksum, and opens it by path. It does not allocate the whole model as a Java byte array. Model loading and inference stay on the native worker executor. Tensor sizes and RGB normalization are read from validated metadata.

Template identities include model version, ONNX SHA-256, and a preprocessing fingerprint. Old 512-D templates are ignored and recomputed from encrypted source photos when verification next runs. No personal data is sent to Hugging Face or another server.

The existing full-screen camera, five separate registration captures, hidden GPS/audit metadata, vaccination records and English/Luganda UI remain in use. No muzzle detector/liveness weights are supplied by this embedding model.

Use `muzzlid/tool/test_android.sh YOUR_DEVICE_ID` for device validation. Native tests check 384-pixel inputs, 1,536-dimensional unit vectors, matching/rejection and encrypted template reuse. Device results are recorded in `docs/ANDROID_VALIDATION.md`. The runtime artifact exceeds GitHub's ordinary single-file limit; use an appropriate large-artifact distribution mechanism when publishing it.
