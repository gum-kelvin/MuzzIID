"""Export the pinned BVRA MegaDescriptor checkpoint to fixed-shape ONNX.
The FP32 reference is preserved locally; a separate process quantizes linear weights.
"""
import hashlib
import json
import pathlib
import time
import numpy as np
import torch
import timm
from timm.layers import set_fused_attn
from timm.models.swin_transformer import checkpoint_filter_fn
from huggingface_hub import hf_hub_download

ROOT = pathlib.Path(__file__).resolve().parent
REVISION = '33b3c6f4ee0c386a4126cc3dcd23843920613fa1'

def main():
    started = time.time()
    torch.set_num_threads(4)
    torch.set_num_interop_threads(1)
    set_fused_attn(False)
    weights = hf_hub_download('BVRA/MegaDescriptor-L-384','pytorch_model.bin',revision=REVISION)
    print('Loading pinned checkpoint',flush=True)
    state = torch.load(weights,map_location='cpu',weights_only=True,mmap=True)
    print('Checkpoint keys',list(state)[:5],flush=True)
    model = timm.create_model('swin_large_patch4_window12_384',pretrained=False,num_classes=0)
    state = checkpoint_filter_fn(state,model)
    # Normal load matches timm's dtype conversion into its FP32 model.
    model.load_state_dict(state,strict=True)
    del state
    model.eval().requires_grad_(False)
    sample = torch.zeros(1,3,384,384)
    with torch.inference_mode():
        start = time.time()
        reference = model(sample)
        print('Reference shape',tuple(reference.shape),'seconds',time.time()-start,flush=True)
    assert tuple(reference.shape)==(1,1536)
    np.save(ROOT/'zero_reference.npy',reference.numpy())
    print('Exporting ONNX',flush=True)
    with torch.no_grad():
        torch.onnx.export(model,sample,str(ROOT/'megadescriptor_fp32.onnx'),
            input_names=['images'],output_names=['embedding'],opset_version=17,
            dynamo=False,do_constant_folding=True)
    report=dict(source='BVRA/MegaDescriptor-L-384',revision=REVISION,
        architecture='swin_large_patch4_window12_384',parameters=sum(p.numel() for p in model.parameters()),
        input=[1,3,384,384],output=[1,1536],mean=[.5,.5,.5],std=[.5,.5,.5],
        preprocessing='RGB, bilinear resize 384x384, ToTensor /255, normalize .5/.5',
        license='CC-BY-NC-4.0 (Hugging Face model card)',export_seconds=round(time.time()-started),
        opset=17,source_checkpoint_sha256='ccfe757f50f7984a115ffe00921cd4c09e260e645215463b23814586040227a3')
    (ROOT/'export_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Export complete',report,flush=True)

if __name__=='__main__': main()
