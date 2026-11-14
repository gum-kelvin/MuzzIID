"""Train a research muzzle embedding baseline using the reference cattle dataset.
Frozen ImageNet ResNet50 -> learned 512-D ArcFace projection; never uploads data.
"""
import csv
import hashlib
import json
import math
import pathlib
import random
import time
import zipfile

import numpy as np
from PIL import Image
import torch
from torch import nn
from torch.nn import functional as F
from torchvision.models import resnet50, ResNet50_Weights
from torchvision.transforms import Compose, Resize, ToTensor, Normalize, InterpolationMode

ROOT = pathlib.Path(__file__).resolve().parent
ASSETS = ROOT.parent / 'muzzlid/android/app/src/main/assets/models'
SEED = 42


class Projection(nn.Module):
    def __init__(self, mean):
        super().__init__()
        self.register_buffer('mean', mean.clone())
        self.fc = nn.Linear(2048, 512, bias=False)
        self.bn = nn.BatchNorm1d(512)

    def forward(self, features):
        return F.normalize(self.bn(self.fc(F.normalize(features - self.mean, dim=1))), dim=1)


class Embedder(nn.Module):
    def __init__(self, backbone, projection):
        super().__init__()
        self.backbone = backbone
        self.projection = projection

    def forward(self, images):
        return self.projection(self.backbone(images))


def evaluate(vectors, labels, identities, high=None, low=None):
    galleries, probes, truth = [], [], []
    for label in identities:
        indices = np.flatnonzero(labels == label)
        # Disjoint actual images; gallery of up to five, at least two probes.
        gallery_size = min(5, len(indices) - 2)
        galleries.append(F.normalize(vectors[indices[:gallery_size]].mean(0), dim=0))
        probes.append(vectors[indices[gallery_size:]])
        truth.extend([len(galleries)-1] * (len(indices)-gallery_size))
    gallery = torch.stack(galleries)
    scores = torch.cat(probes) @ gallery.T
    truth = torch.tensor(truth)
    genuine = scores[torch.arange(len(truth)), truth]
    wrong = scores.clone()
    wrong[torch.arange(len(truth)), truth] = -2
    impostor = wrong.max(1).values
    if high is None:
        high = min(.999999, float(torch.quantile(impostor, .999)) + .000001)
        low = max(-.99, high - .10)
    top, predicted = scores.max(1)
    ordered = scores.topk(2, dim=1).values
    accepted = (top >= high) & ((ordered[:,0] - ordered[:,1]) >= .02)
    return high, low, {
        'identities': len(identities), 'probe_images': len(truth),
        'rank1_accuracy': float((predicted == truth).float().mean()),
        'correct_accept_rate': float((accepted & (predicted == truth)).float().mean()),
        'wrong_accept_rate': float((accepted & (predicted != truth)).float().mean()),
        'impostor_search_exceedance': float((impostor >= high).float().mean()),
        'genuine_similarity_median': float(genuine.median()),
        'impostor_max_similarity_median': float(impostor.median()),
    }


def main():
    started = time.time()
    torch.manual_seed(SEED)
    random.seed(SEED)
    np.random.seed(SEED)
    torch.set_num_threads(4)
    torch.set_num_interop_threads(1)
    source = ROOT / 'dataset'
    if not source.exists():
        with zipfile.ZipFile(ROOT / 'cattle.zip') as archive:
            for entry in archive.infolist():
                if '..' in pathlib.PurePosixPath(entry.filename).parts or entry.filename.startswith('/'):
                    raise ValueError('Unsafe archive member')
            archive.extractall(source)
    paths = sorted(source.rglob('*.jpg')) + sorted(source.rglob('*.JPG'))
    unique, hashes, duplicate_count = [], set(), 0
    for path in paths:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest in hashes:
            duplicate_count += 1
            continue
        hashes.add(digest)
        label = next(part for part in path.parts if part.startswith('cattle_'))
        unique.append((path, label))
    counts = {}
    for _, label in unique:
        counts[label] = counts.get(label, 0) + 1
    records = [(p, lab) for p, lab in unique if counts[lab] >= 7]
    identities = sorted({lab for _, lab in records})
    random.shuffle(identities)
    n = len(identities)
    train_ids = identities[:int(n*.70)]
    calibration_ids = identities[int(n*.70):int(n*.85)]
    test_ids = identities[int(n*.85):]
    assert not set(train_ids) & set(calibration_ids) and not set(train_ids) & set(test_ids)
    labels = np.array([lab for _, lab in records])
    manifest = [{'file': str(p.relative_to(source)), 'identity': lab,
                 'split': 'train' if lab in train_ids else 'calibration' if lab in calibration_ids else 'test'} for p, lab in records]
    (ROOT / 'split.json').write_text(json.dumps(manifest, indent=2))
    print(f'Dataset: {len(records)} images, {n} identities; splits {len(train_ids)}/{len(calibration_ids)}/{len(test_ids)}; duplicates removed {duplicate_count}', flush=True)
    backbone = resnet50(weights=ResNet50_Weights.IMAGENET1K_V2)
    backbone.fc = nn.Identity()
    backbone.eval().to(memory_format=torch.channels_last)
    for parameter in backbone.parameters():
        parameter.requires_grad = False
    preprocess = Compose([Resize((224,224), interpolation=InterpolationMode.BILINEAR), ToTensor(),
                          Normalize([.485,.456,.406],[.229,.224,.225])])
    cache = ROOT / 'features.pt'
    if cache.exists():
        features = torch.load(cache, weights_only=True)
        assert features.shape == (len(records),2048)
    else:
        batches = []
        with torch.inference_mode():
            for start in range(0,len(records),16):
                batch = []
                for path, _ in records[start:start+16]:
                    with Image.open(path) as image:
                        batch.append(preprocess(image.convert('RGB')))
                batches.append(backbone(torch.stack(batch).to(memory_format=torch.channels_last)).clone())
                if start % 256 == 0:
                    print(f'Features {start}/{len(records)} · {time.time()-started:.0f}s', flush=True)
        features = torch.cat(batches)
        torch.save(features, cache)
    train_indices = torch.tensor([i for i, lab in enumerate(labels) if lab in train_ids])
    train_features = features[train_indices]
    class_ids = {lab:i for i,lab in enumerate(train_ids)}
    train_targets = torch.tensor([class_ids[labels[i]] for i in train_indices.tolist()])
    projection = Projection(train_features.mean(0,keepdim=True))
    class_weights = nn.Parameter(torch.randn(len(train_ids),512))
    optimizer = torch.optim.AdamW(list(projection.parameters())+[class_weights], lr=.001, weight_decay=.0001)
    history = []
    for epoch in range(60):
        projection.train()
        order = torch.randperm(len(train_indices))
        losses = []
        for chunk in order.split(256):
            if len(chunk) < 2:
                continue
            inputs = train_features[chunk]
            # Feature dropout regularizes the head; no false claim of image-level dust augmentation.
            embedded = projection(F.dropout(inputs,p=.03,training=True))
            cosine = F.linear(embedded,F.normalize(class_weights,dim=1)).clamp(-.999999,.999999)
            targets = train_targets[chunk]
            true_cos = cosine[torch.arange(len(chunk)),targets]
            # Additive angular margin ArcFace (m=0.3, s=32).
            margin_cos = true_cos * math.cos(.3) - torch.sqrt(1-true_cos.square()) * math.sin(.3)
            logits = cosine.clone()
            logits[torch.arange(len(chunk)),targets] = margin_cos
            loss = F.cross_entropy(logits*32,targets)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            losses.append(float(loss.detach()))
        history.append(float(np.mean(losses)))
        if epoch % 10 == 0 or epoch == 59:
            print(f'Epoch {epoch+1}/60 loss={history[-1]:.4f} · {time.time()-started:.0f}s',flush=True)
    projection.eval()
    with torch.inference_mode():
        vectors = projection(features)
    high, low, calibration = evaluate(vectors, labels, calibration_ids)
    _, _, test = evaluate(vectors, labels, test_ids, high, low)
    model = Embedder(backbone,projection).eval()
    torch.save(model.state_dict(),ROOT/'baseline.pt')
    target = ASSETS/'embedder.onnx'
    torch.onnx.export(model,torch.zeros(1,3,224,224),str(target),opset_version=17,
                      input_names=['images'],output_names=['embedding'],dynamo=False)
    import onnxruntime as ort
    session = ort.InferenceSession(str(target), providers=['CPUExecutionProvider'])
    sample = np.random.default_rng(SEED).normal(size=(1,3,224,224)).astype('float32')
    with torch.inference_mode():
        expected = model(torch.from_numpy(sample)).numpy()
    actual = session.run(None,{'images':sample})[0]
    difference = float(np.max(np.abs(actual-expected)))
    assert actual.shape == (1,512) and np.isfinite(actual).all() and difference < .0001
    config = dict(schema=1, version='cattle-resnet50-arcface-research-v1',
                  sha256=hashlib.sha256(target.read_bytes()).hexdigest(),inputSize=224,dimensions=512,
                  calibrated=True,research=True,matchThreshold=high,uncertainThreshold=low,minimumMargin=.02)
    (ASSETS/'model.json').write_text(json.dumps(config,indent=2)+'\n')
    report = dict(seed=SEED, images=len(records),identities=n,removed_exact_duplicate_images=duplicate_count,
                  train_identities=len(train_ids),calibration=calibration,test=test,epochs=60,
                  loss=history,match_threshold=high,uncertain_threshold=low,onnx_max_absolute_error=difference,
                  training_seconds=round(time.time()-started),model_sha256=config['sha256'],
                  backbone='ImageNet ResNet50 frozen',head='512-D projection + BatchNorm + ArcFace training',
                  limitations=['Research baseline, not field-certified','Near-duplicate physical identities may remain under different dataset IDs',
                               'Public feedlot dataset does not establish Ugandan field accuracy','Threshold calibrated on public dataset only'])
    (ROOT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)


if __name__ == '__main__':
    main()
