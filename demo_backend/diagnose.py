"""Offline ranking diagnostics only. Never exports thresholds or changes the registry."""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from .model import MegaDescriptor, normalize
from .selection import ROOT


def rank_probes(templates, probes):
    """Closed-set rank-1 and pairwise scores, independent of acceptance policy."""
    results = []
    for animal, path, vector in probes:
        scores = sorted(((key, float(template @ vector)) for key, template in templates.items()), key=lambda x: (-x[1], x[0]))
        by_id = dict(scores)
        impostors = [score for key, score in scores if key != animal]
        genuine = by_id[animal]
        best_other = max(impostors) if impostors else None
        results.append(dict(animal=animal, path=path, rank1=scores[0][0], correct=scores[0][0] == animal,
                            genuine=genuine, max_impostor=best_other,
                            genuine_margin=genuine-best_other if best_other is not None else None,
                            scores=dict(scores)))
    return dict(probes=results, correct=sum(p['correct'] for p in results), count=len(results),
                rank1_accuracy=sum(p['correct'] for p in results)/len(results) if results else None,
                min_genuine=min((p['genuine'] for p in results), default=None),
                max_impostor=max((p['max_impostor'] for p in results if p['max_impostor'] is not None), default=None))


def diagnose(root, calibration, selection, output, cache):
    previous = json.loads(calibration.read_text())
    demo = json.loads(selection.read_text())
    dev_ids = sorted({item['animal'] for item in previous['development_manifest']})
    if set(dev_ids) & {item['animal'] for item in demo['samples']}:
        raise ValueError('Development/demo identity leakage')
    model = MegaDescriptor()
    if model.version != previous['model_version']:
        raise SystemExit('Checkpoint/preprocessing differs from completed calibration; use a separate experiment.')
    cache.mkdir(parents=True, exist_ok=True)
    metadata = []
    seen = {}

    def embed(relative, expected_hash=None):
        path = root / relative
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if expected_hash and digest != expected_hash:
            raise ValueError(f'Manifest file changed: {relative}')
        with Image.open(path) as image:
            rgb = ImageOps.exif_transpose(image).convert('RGB')
            pixels = hashlib.sha256(str(rgb.size).encode()+rgb.tobytes()).hexdigest()
            if pixels in seen and seen[pixels] != relative:
                raise ValueError(f'Duplicate oriented pixels: {relative} and {seen[pixels]}')
            seen[pixels] = relative
            metadata.append(dict(path=relative, sha256=digest, size=image.size, format=image.format, exif_orientation=image.getexif().get(274), oriented_size=rgb.size))
        key = hashlib.sha256((model.version+digest).encode()).hexdigest()
        target = cache / (key+'.npy')
        if target.exists():
            return normalize(np.load(target, allow_pickle=False))
        vector = model.embed(data)
        np.save(target, vector, allow_pickle=False)
        return vector

    original_groups, original_probes, three, five, heldout = {}, [], {}, {}, []
    for animal in dev_ids:
        items = [i for i in previous['development_manifest'] if i['animal'] == animal]
        original_enrollment = [i for i in items if i['role']=='development_enrollment']
        original_probe = [i for i in items if i['role']=='development_probe']
        original_groups[animal] = normalize(np.mean([embed(i['path'], i['sha256']) for i in original_enrollment], axis=0))
        original_probes.extend((animal, i['path'], embed(i['path'], i['sha256'])) for i in original_probe)
        files = sorted((root/animal).glob('*.jpg'))
        if len(files) < 7:
            raise ValueError(f'Need seven distinct images for five-image protocol: {animal}')
        relative = [str(p.relative_to(root)) for p in files[:7]]
        if sorted(i['path'] for i in items) != relative[:len(items)]:
            raise ValueError(f'Development file selection changed since calibration: {animal}')
        vectors = [embed(p) for p in relative]
        three[animal] = normalize(np.mean(vectors[:3], axis=0))
        five[animal] = normalize(np.mean(vectors[:5], axis=0))
        heldout.extend((animal, p, v) for p,v in zip(relative[5:], vectors[5:]))
        print('Diagnostic development identity', animal, flush=True)
    report = dict(model_version=model.version,
                  preprocessing='Publisher model-card pipeline: EXIF-transposed RGB; torchvision Resize((384,384)) bilinear; ToTensor; mean/std 0.5; per-image L2; L2-normalized mean of image embeddings.',
                  completed_protocol_reproduction=rank_probes(original_groups, original_probes),
                  controlled_three_image_templates=rank_probes(three, heldout),
                  controlled_five_image_templates=rank_probes(five, heldout),
                  limitations=['Diagnostic only: no policy exported and no threshold selection from demo scores.', 'Original three-image experiment probes can enter the five-image enrollment set; controlled comparison uses only separate sixth/seventh images for both template sizes.', 'Small same-dataset sample; capture-session dependence, near duplicates and pretraining overlap unresolved. Closed-set rank-1 does not establish unknown rejection.'])
    templates, probes = {}, []
    for animal in sorted({i['animal'] for i in demo['samples']}):
        items = [i for i in demo['samples'] if i['animal']==animal]
        enrollment = [embed(i['path'], i['sha256']) for i in items if i['role']=='enrollment']
        templates[animal] = normalize(np.mean(enrollment, axis=0))
        probes.extend((animal, i['path'], embed(i['path'], i['sha256'])) for i in items if i['role']=='probe')
        print('Diagnostic demo identity', animal, flush=True)
    registry = Path('demo_backend/http_evaluation.sqlite3')
    if registry.exists():
        with sqlite3.connect(registry.resolve().as_uri()+'?mode=ro', uri=True) as db:
            report['registry_template_check'] = []
            for animal, version, blob in db.execute('SELECT id, version, template FROM cattle'):
                if animal not in templates:
                    continue
                stored = np.frombuffer(blob, dtype=np.float32)
                rebuilt = templates[animal]
                compatible = version == model.version and stored.shape == rebuilt.shape
                residual = float(np.linalg.norm(stored-rebuilt)) if compatible else None
                report['registry_template_check'].append(dict(animal=animal, version_match=version==model.version, norm=float(np.linalg.norm(stored)), residual=residual, matches_five_image_formula=compatible and residual < 1e-6))
    evaluation = Path('demo_backend/evaluation.json')
    if evaluation.exists():
        checkpoint = json.loads(evaluation.read_text()).get('persistence_checkpoint', {})
        reference = checkpoint.get('reference_response')
        if reference and checkpoint['health']['model_version'] == model.version:
            vector = next((v for _,path,v in probes if path == checkpoint['reference_path']), None)
            if vector is not None and 'cattle_0100' in templates:
                score = float(templates['cattle_0100'] @ vector)
                report['http_A_probe_reproduction'] = dict(http_score=reference['score'], offline_score=score, matches=abs(score-reference['score']) < 1e-6)
    report['demo_closed_set_ABC'] = rank_probes(templates, probes)
    known = [p for p in probes if p[0] != 'cattle_0300']
    ab = {key:value for key,value in templates.items() if key != 'cattle_0300'}
    report['demo_known_AB'] = rank_probes(ab, known)
    report['demo_unknown_C_against_AB'] = [dict(path=path, scores={key:float(t@v) for key,t in ab.items()}, decision='NOT EVALUATED: no supported threshold') for animal,path,v in probes if animal=='cattle_0300']
    report['images'] = list({i['path']:i for i in metadata}.values())
    output.write_text(json.dumps(report, indent=2)+'\n')
    for name in ['completed_protocol_reproduction','controlled_three_image_templates','controlled_five_image_templates','demo_closed_set_ABC','demo_known_AB']:
        result=report[name]
        print(name, {key:value for key,value in result.items() if key!='probes'}, flush=True)
    print('Diagnostic report:',output)

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--dataset',type=Path,default=ROOT)
    parser.add_argument('--calibration',type=Path,default=Path('demo_backend/calibration.json'))
    parser.add_argument('--selection',type=Path,default=Path('demo_backend/selection.json'))
    parser.add_argument('--output',type=Path,default=Path('demo_backend/diagnostics.json'))
    parser.add_argument('--cache',type=Path,default=Path('demo_backend/.embedding_cache'))
    args=parser.parse_args()
    diagnose(args.dataset,args.calibration,args.selection,args.output,args.cache)
