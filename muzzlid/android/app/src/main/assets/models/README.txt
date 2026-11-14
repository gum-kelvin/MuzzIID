Active embedding model: BVRA/MegaDescriptor-L-384, INT8 ONNX mobile runtime.
Input: float32 RGB [1,3,384,384], /255 then mean=.5/std=.5.
Output: 1536 features, L2-normalized by the private native adapter.
See model_card.json, ATTRIBUTION.txt and model_training/megadescriptor/.
The previous 512-D ResNet templates are incompatible and are rebuilt from
locally encrypted source images. No detector weights are bundled.
