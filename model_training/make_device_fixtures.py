"""Generate baseline-specific handset smoke fixtures; not an accuracy benchmark."""
import base64
import io
import json
import pathlib
import numpy as np
from PIL import Image
import torch
from torch.nn import functional as F
from train_baseline import Projection

root = pathlib.Path(__file__).resolve().parent
assets = root.parent/'muzzlid/android/app/src/main/assets/models'
config = json.loads((assets/'model.json').read_text())
manifest = json.loads((root/'split.json').read_text())
features = torch.load(root/'features.pt', weights_only=True)
weights = torch.load(root/'baseline.pt', weights_only=True)
projection = Projection(weights['projection.mean'])
projection.load_state_dict({k.removeprefix('projection.'):v for k,v in weights.items() if k.startswith('projection.')})
projection.eval()
with torch.no_grad():
    vectors = projection(features)
labels = np.array([item['identity'] for item in manifest])
test_ids = sorted({item['identity'] for item in manifest if item['split'] == 'test'})
best = None
for label in test_ids:
    indices = np.flatnonzero(labels == label)
    gallery_size = min(5,len(indices)-2)
    gallery = indices[:gallery_size]
    centroid = F.normalize(vectors[gallery].mean(0),dim=0)
    probe_candidates = indices[gallery_size:]
    scores = vectors[probe_candidates] @ centroid
    candidate = (float(scores.max()),gallery,int(probe_candidates[int(scores.argmax())]),centroid)
    if best is None or candidate[0] > best[0]:
        best = candidate
score,gallery,probe,centroid = best
wrong_indices = np.array([i for i,lab in enumerate(labels) if lab != labels[probe] and manifest[i]['split']=='test'])
unknown_scores = vectors[wrong_indices] @ centroid
unknown = int(wrong_indices[int(unknown_scores.argmin())])

def encode(index):
    with Image.open(root/'dataset'/manifest[index]['file']) as image:
        image = image.convert('RGB').resize((224,224), Image.Resampling.BILINEAR)
        output = io.BytesIO()
        image.save(output,format='JPEG',quality=85)
    return base64.b64encode(output.getvalue()).decode()

full_version = config['version']+':'+config['sha256']
text = '// Generated baseline-specific smoke fixtures; CC BY 4.0 dataset attribution: model_training/README.md.\n'
text += '// Selected to test native enrol/verify integration, not to estimate model accuracy.\n'
text += 'const baselineFixtureVersion = '+json.dumps(full_version)+';\n'
text += 'const baselineGallery = <String>['+','.join(json.dumps(encode(int(i))) for i in gallery)+'];\n'
text += 'const baselineProbe = '+json.dumps(encode(probe))+';\n'
text += 'const baselineUnknown = '+json.dumps(encode(unknown))+';\n'
(root.parent/'muzzlid/integration_test/model_fixtures.dart').write_text(text)
(root/'fixture_selection.json').write_text(json.dumps({'positive_similarity_before_jpeg':score,
    'negative_similarity_before_jpeg':float(unknown_scores.min()),'model_version':full_version,
    'purpose':'Selected smoke examples, not accuracy benchmark'},indent=2))
print('Handset fixtures generated', score, float(unknown_scores.min()))
