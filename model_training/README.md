> Historical ResNet experiment. The active Android model is now [MegaDescriptor-L-384](megadescriptor/README.md). Results below describe the previous model and must not be attributed to MegaDescriptor.

# Cattle muzzle research baseline

Training pipeline for the Android client. This adapts the ResNet family approach in [Animal_Biometrics_System](https://github.com/darasiemi/Animal_Biometrics_System) into a versioned 512-dimensional embedding model compatible with MuzzlID's ONNX runtime. It is not a reproduction of that project's classifier results.

Data: [Beef Cattle Muzzle/Noseprint database](https://zenodo.org/records/6324361), Xiong, Yijie; Li, Guoming; Erickson, Galen (2022), DOI 10.5281/zenodo.6324361, CC BY 4.0. The original archive contains 4,923 images of 268 cattle. This experiment retains 4,823 images from 248 identities with at least seven images, allowing five distinct gallery images and at least two probes. No private app records are used for training.

Archive checksum: `md5:f2b19d9bab2fc668460a796259944204`. Creator/license metadata and verified acquisition details are retained alongside this file.

Architecture: ImageNet pretrained ResNet50 (torchvision IMAGENET1K_V2, frozen backbone), training-set feature centering, learned 2048→512 linear projection, BatchNorm, L2 normalization. The projection is trained for 60 epochs using ArcFace angular margin 0.3/scale 32 and feature dropout 0.03. Source notebook classifiers are replaced by an embedding head to permit enrolment of new identities.

Split seed 42: 173 training identities, 37 calibration identities, 38 test identities. `split.json` records every image's assignment. Exact content duplicates are removed before splitting. Dataset identity labels are used as supplied; undetected near-duplicate physical identities remain a limitation. Held-out identities are distinct by dataset label, which is not proof of physical identity independence.

Calibration uses disjoint gallery/probe images on calibration cattle, selecting a high threshold from the 99.9th percentile of each query's strongest wrong candidate. The lower threshold is high−0.10; top-two margin is 0.02. The test split is evaluated only after the thresholds are selected. `impostor_search_exceedance` is a dataset-specific estimate, not a certified field FMR or national registry accuracy guarantee.

Run using an environment with CPU torch, torchvision, numpy, Pillow, onnx, onnxruntime and onnxscript:

```sh
python train_baseline.py
```

Place the verified original archive at `cattle.zip` first. The script extracts it locally, caches backbone features, trains the projection, exports ONNX opset 17, compares PyTorch/ONNX outputs numerically and packages model assets for Android. `features.pt` and dataset files are local caches, not APK assets. A fresh experiment should use a clean cache directory if data/preprocessing changes.

Outputs: `report.json`, `split.json`, `baseline.pt`, and Android `assets/models/embedder.onnx` plus `model.json`. The packaged config marks the model `research=true`; the app displays that status and asks for manual identity confirmation on research results. Model replacement invalidates old cached templates through the artifact hash.

Limitations: clean cropped US feedlot data; no Uganda field evaluation; no detector training, occlusion classifier, liveness or ownership verification. No claim of the original papers' reported accuracy is made for this baseline.
