"""Check export/quantization, calibrate a small research pilot and package Android assets.
This is not an independent evaluation: MegaDescriptor may have seen this public dataset.
"""
import base64
import gc
import hashlib
import io
import json
import pathlib
import shutil
import time
import numpy as np
from PIL import Image
import onnxruntime as ort

ROOT=pathlib.Path(__file__).resolve().parent
TRAINING=ROOT.parent
ASSETS=TRAINING.parent/'muzzlid/android/app/src/main/assets/models'

def unit(v):
    assert np.isfinite(v).all() and np.linalg.norm(v)>1e-12
    return v/np.linalg.norm(v)

def tensor(path):
    with Image.open(path) as image:
        image=image.convert('RGB').resize((384,384),Image.Resampling.BILINEAR)
        values=np.asarray(image).astype('float32')/255
    return ((values-.5)/.5).transpose(2,0,1)[None].copy()

def session(path):
    options=ort.SessionOptions()
    options.intra_op_num_threads=4
    options.inter_op_num_threads=1
    return ort.InferenceSession(str(path),sess_options=options,providers=['CPUExecutionProvider'])

def evaluate(vectors, labels, ids, high=None):
    galleries=[]; probes=[]; truth=[]; gallery_indices=[]; probe_indices=[]
    for label in ids:
        indices=np.flatnonzero(labels==label)
        gallery_indices.append(indices[:5])
        galleries.append(unit(vectors[indices[:5]].mean(0)))
        probes.extend(vectors[indices[5:]])
        probe_indices.extend(indices[5:])
        truth.extend([len(galleries)-1]*(len(indices)-5))
    scores=np.stack(probes)@np.stack(galleries).T
    truth=np.array(truth)
    wrong=scores.copy();wrong[np.arange(len(truth)),truth]=-2
    impostor=wrong.max(1)
    if high is None: high=min(.9999,float(impostor.max())+.02)
    ordered=np.sort(scores,axis=1)
    predicted=scores.argmax(1)
    accepted=(ordered[:,-1]>=high)&((ordered[:,-1]-ordered[:,-2])>=.02)
    return high,dict(identities=len(ids),probe_images=len(truth),rank1_accuracy=float((predicted==truth).mean()),
      correct_accept_rate=float((accepted&(predicted==truth)).mean()),wrong_accept_rate=float((accepted&(predicted!=truth)).mean()),
      impostor_search_exceedance=float((impostor>=high).mean())),(scores,truth,gallery_indices,probe_indices)

def main():
    started=time.time()
    manifest=json.loads((TRAINING/'split.json').read_text())
    # Fixed existing split, capped before seeing scores. Five galleries/two probes per cow.
    calibration_ids=sorted({x['identity'] for x in manifest if x['split']=='calibration'})[:10]
    test_ids=sorted({x['identity'] for x in manifest if x['split']=='test'})[:10]
    selected=[]
    for label in calibration_ids+test_ids:
        selected.extend([x for x in manifest if x['identity']==label][:7])
    paths=[TRAINING/'dataset'/x['file'] for x in selected]
    labels=np.array([x['identity'] for x in selected])
    (ROOT/'pilot_split.json').write_text(json.dumps(selected,indent=2)+'\n')
    reference=session(ROOT/'megadescriptor_fp32.onnx')
    actual=reference.run(None,{'images':np.zeros((1,3,384,384),dtype='float32')})[0]
    delta=float(np.max(np.abs(actual-np.load(ROOT/'zero_reference.npy'))))
    assert delta<.0005 and actual.shape==(1,1536)
    runtime=session(ROOT/'megadescriptor_int8.onnx')
    cosines=[]
    for path in paths[:4]:
        sample=tensor(path)
        expected=reference.run(None,{'images':sample})[0][0]
        output=runtime.run(None,{'images':sample})[0][0]
        cosines.append(float(unit(expected)@unit(output)))
        print('Quantized/FP32 cosine',cosines[-1],flush=True)
    assert min(cosines)>.98, 'Quantization changes identity embeddings too much'
    del reference;gc.collect()
    vectors=[];latencies=[]
    for i,path in enumerate(paths):
        start=time.time()
        vector=runtime.run(None,{'images':tensor(path)})[0][0]
        latencies.append(time.time()-start)
        assert vector.shape==(1536,)
        vectors.append(unit(vector))
        if i%14==0: print('Pilot',i,'/',len(paths),'elapsed',round(time.time()-started),flush=True)
    vectors=np.stack(vectors)
    high,calibration,_=evaluate(vectors,labels,calibration_ids)
    _,test,details=evaluate(vectors,labels,test_ids,high)
    low=max(-.99,high-.1)
    version='megadescriptor-l-384-int8-r1'
    source=ROOT/'megadescriptor_int8.onnx'
    sha=hashlib.file_digest(source.open('rb'),'sha256').hexdigest()
    config=dict(schema=1,version=version,displayName='MegaDescriptor-L-384',sha256=sha,
      inputSize=384,dimensions=1536,mean=[.5,.5,.5],std=[.5,.5,.5],calibrated=True,research=True,
      matchThreshold=high,uncertainThreshold=low,minimumMargin=.02,
      source='BVRA/MegaDescriptor-L-384',revision='33b3c6f4ee0c386a4126cc3dcd23843920613fa1',license='CC-BY-NC-4.0')
    contract='384:1536:0.5, 0.5, 0.5:0.5, 0.5, 0.5'
    full_version=version+':'+sha+':'+hashlib.sha256(contract.encode()).hexdigest()[:16]
    # Selected smoke examples test app plumbing; pilot metrics above use every probe.
    scores,truth,galleries,probes=details
    genuine=scores[np.arange(len(truth)),truth]
    best=int(genuine.argmax())
    gallery=galleries[int(truth[best])]
    probe=int(probes[best])
    centroid=unit(vectors[gallery].mean(0))
    wrong_indices=np.flatnonzero(labels!=labels[probe])
    unknown=int(wrong_indices[(vectors[wrong_indices]@centroid).argmin()])
    assert genuine[best]>high+.01
    def encode(index):
        with Image.open(paths[index]) as image:
            image=image.convert('RGB').resize((384,384),Image.Resampling.BILINEAR)
            output=io.BytesIO();image.save(output,format='JPEG',quality=85)
        return base64.b64encode(output.getvalue()).decode()
    text='// MegaDescriptor-specific public-data smoke fixtures; attribution: model_training/megadescriptor/README.md.\n'
    text+='// Selected integration examples, not an accuracy benchmark.\n'
    text+='const baselineFixtureVersion = '+json.dumps(full_version)+';\n'
    text+='const baselineGallery = <String>['+','.join(json.dumps(encode(int(i))) for i in gallery)+'];\n'
    text+='const baselineProbe = '+json.dumps(encode(probe))+';\n'
    text+='const baselineUnknown = '+json.dumps(encode(unknown))+';\n'
    report=dict(model=config,preprocessing=config['mean'],fp32_export_max_absolute_error=delta,
      int8_fp32_sample_cosines=cosines,calibration=calibration,test=test,
      host_int8_median_seconds=float(np.median(latencies)),runtime_bytes=source.stat().st_size,
      seconds=round(time.time()-started),limitations=[
        'Small public-data pilot only; no field FMR certificate',
        'MegaDescriptor may have seen this dataset during pretraining; results are not independent generalization estimates',
        'Quantized runtime differs numerically from the full-precision checkpoint',
        'No muzzle detector/liveness model is supplied'])
    (ROOT/'validation_report.json').write_text(json.dumps(report,indent=2)+'\n')
    # Do not replace the active model until all host checks above succeed.
    old=ASSETS/'embedder.onnx'
    if old.exists(): shutil.copyfile(old,ROOT/'previous/embedder.onnx')
    shutil.copyfile(source,old)
    (ASSETS/'model.json').write_text(json.dumps(config,indent=2)+'\n')
    (ASSETS/'model_card.json').write_text(json.dumps(report,indent=2)+'\n')
    (TRAINING.parent/'muzzlid/integration_test/model_fixtures.dart').write_text(text)
    print('Packaged MegaDescriptor',json.dumps(report,indent=2),flush=True)

if __name__=='__main__': main()
