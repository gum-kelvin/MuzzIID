"""W8 dynamic quantization of linear layers; preserve float inputs/outputs."""
import json
import pathlib
import time
from onnxruntime.quantization import quantize_dynamic, QuantType
root=pathlib.Path(__file__).resolve().parent
started=time.time()
quantize_dynamic(str(root/'megadescriptor_fp32.onnx'),str(root/'megadescriptor_int8.onnx'),
    op_types_to_quantize=['MatMul','Gemm'],weight_type=QuantType.QInt8,
    per_channel=True,reduce_range=False, use_external_data_format=False)
(root/'quantization_report.json').write_text(json.dumps(dict(
    method='ONNX Runtime dynamic W8 per-channel MatMul/Gemm, float activations between operators',
    seconds=round(time.time()-started),fp32_bytes=(root/'megadescriptor_fp32.onnx').stat().st_size,
    runtime_bytes=(root/'megadescriptor_int8.onnx').stat().st_size),indent=2)+'\n')
print('Quantization complete',flush=True)
