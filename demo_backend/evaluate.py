"""Reproducible development calibration and real HTTP demo evaluation. No training."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from .model import MegaDescriptor, normalize
from .selection import ROOT


def calibrate(root, output):
    model = MegaDescriptor()
    excluded = {'cattle_0100', 'cattle_0200', 'cattle_0300'}
    folders = [p for p in sorted(root.glob('cattle_*')) if p.name not in excluded and len(list(p.glob('*.jpg'))) >= 7][:8]
    if len(folders) != 8:
        raise ValueError('Need eight separate development identities with seven images each')
    templates, probes, manifest = [], [], []
    demo = json.loads(Path('demo_backend/selection.json').read_text())
    seen = {item['pixel_sha256'] for item in demo['samples']}
    for folder in folders:
        vectors = []
        for i, path in enumerate(sorted(folder.glob('*.jpg'))[:7]):
            data = path.read_bytes()
            with Image.open(path) as image:
                rgb = ImageOps.exif_transpose(image).convert('RGB')
                digest = hashlib.sha256(str(rgb.size).encode() + rgb.tobytes()).hexdigest()
            if digest in seen:
                raise ValueError('Duplicate development image')
            seen.add(digest)
            vectors.append(model.embed(data))
            manifest.append(dict(animal=folder.name, path=str(path.relative_to(root)), role='development_enrollment' if i<5 else 'development_probe', sha256=hashlib.sha256(data).hexdigest()))
        templates.append(normalize(np.mean(vectors[:5], axis=0)))
        probes.append(vectors[5:])
        print(f'Embedded development identity {folder.name}', flush=True)
    genuine, impostor, margins = [], [], []
    for i, group in enumerate(probes):
        for probe in group:
            scores = [float(t @ probe) for t in templates]
            genuine.append(scores[i])
            other = [s for j,s in enumerate(scores) if j != i]
            impostor.extend(other)
            margins.append(scores[i] - max(other))
    # Fixed rule chosen before scoring demonstration identities. Do not tune to demo results.
    reject, accept, margin = max(impostor)+.005, max(impostor)+.02, .04
    supported = accept <= min(genuine) and min(margins) >= margin and accept <= 1
    report = dict(model_version=model.version, calibration_protocol='five-image-mean-l2-v1', development_manifest=manifest,
                  min_genuine=min(genuine), max_impostor=max(impostor), min_margin=min(margins),
                  policy=dict(accept=accept, reject=reject, margin=margin) if supported else None,
                  status='development-only' if supported else 'overlap: no supported policy',
                  limitations='Eight development identities are insufficient for reliable field unknown rejection. No printed-photo calibration. Potential model pretraining overlap with dataset is not ruled out.')
    output.write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='development_manifest'}, indent=2))
    if not supported:
        raise SystemExit('No policy exported: overlap or insufficient margin. Keep uncalibrated uncertain mode.')


def evaluate(root, url, output):
    import httpx
    selection = json.loads(Path('demo_backend/selection.json').read_text())
    report = dict(health=None, observations=[])
    with httpx.Client(base_url=url, timeout=180, trust_env=False) as client:
        report['health'] = client.get('/health').raise_for_status().json()
        if client.get('/animals').raise_for_status().json():
            raise SystemExit('Evaluation requires an empty dedicated database; do not erase your demonstration registry.')
        def samples(animal, role):
            result = []
            for item in selection['samples']:
                if item['animal']==animal and item['role']==role:
                    data = (root/item['path']).read_bytes()
                    if hashlib.sha256(data).hexdigest() != item['sha256']:
                        raise ValueError('Manifest image changed')
                    result.append(base64.b64encode(data).decode())
            return result
        def observe(name, response, expected=None, decision=None, status=200):
            data=response.json()
            actual = (data.get('animal') or {}).get('id')
            passed = response.status_code == status and (decision is None or data.get('decision') == decision) and (expected is None or actual == expected or (status == 201 and data.get('id') == expected))
            report['observations'].append(dict(test=name, result='PASS' if passed else 'FAIL', http=response.status_code, decision=data.get('decision'), expected_decision=decision, score=data.get('score'), actual_identity=actual, expected_identity=expected, detail=data.get('detail')))
            report['counts'] = {outcome: sum(item['result'] == outcome for item in report['observations']) for outcome in ['PASS', 'FAIL']}
            output.write_text(json.dumps(report, indent=2)+'\n')
            print(report['observations'][-1], flush=True)
            return data
        def enroll(animal):
            return client.post('/enroll', json=dict(record=dict(id=animal, owner=f'FICTIONAL DEMO OWNER {animal}', location='FICTIONAL DEMO FARM', created='2026-11-14T00:00:00Z', vaccinations=[dict(id=f'fictional-{animal}', vaccine='FICTIONAL DEMO VACCINE, not veterinary history', administeredAt='2026-11-14T00:00:00Z')]), images=samples(animal,'enrollment')))
        reference_response = None
        observe('empty registry',client.post('/recognize',json={'image':samples('cattle_0100','probe')[0]}),decision='unknown')
        for animal in ['cattle_0100','cattle_0200']:
            response=enroll(animal)
            observe('enroll '+animal,response,animal,status=201)
            if response.status_code!=201:
                continue
            for probe in samples(animal,'probe'):
                response = client.post('/recognize',json={'image':probe})
                result = observe('unseen probe '+animal,response,animal,decision='accepted')
                if animal == 'cattle_0100' and reference_response is None and response.status_code == 200:
                    reference_response = result
            profile=client.get('/animals/'+animal).raise_for_status().json()
            assert profile['id']==animal and profile['vaccinations'][0]['id']==f'fictional-{animal}'
        c=samples('cattle_0300','probe')
        observe('unknown C before enrollment',client.post('/recognize',json={'image':c[0]}),decision='unknown')
        observe('duplicate A',enroll('cattle_0100'),status=409)
        response=enroll('cattle_0300')
        observe('enroll C',response,'cattle_0300',status=201)
        if response.status_code==201:
            observe('C second unseen probe',client.post('/recognize',json={'image':c[1]}),'cattle_0300',decision='accepted')
        observe('corrupt photograph',client.post('/recognize',json={'image':base64.b64encode(b'not a photograph').decode()}),status=422)
        report['persistence_checkpoint'] = dict(
            health=report['health'],
            profiles=client.get('/animals').raise_for_status().json(),
            reference_path=next(item['path'] for item in selection['samples'] if item['animal']=='cattle_0100' and item['role']=='probe'),
            reference_response=reference_response,
        )
        report['limitations'] = ['No supported calibration: accepted known matches and reliable unknown rejection are unavailable; uncertainty must not be reported as successful recognition.', 'Later enrollments may be blocked by conservative duplicate handling; blocked C enrollment means C-after-enrollment recognition is NOT TESTED.'] if not report['health']['calibrated'] else []
        output.write_text(json.dumps(report, indent=2)+'\n')
    print('Recorded actual outcomes in',output)
    if report['counts']['FAIL']:
        raise SystemExit('Biometric evaluation has unsuccessful outcomes. See report; do not tune thresholds to these demo animals.')


def verify_restart(root, url, output):
    """Run only after restarting Uvicorn with the same database and model."""
    import httpx
    report = json.loads(output.read_text())
    checkpoint = report['persistence_checkpoint']
    with httpx.Client(base_url=url, timeout=180, trust_env=False) as client:
        try:
            health = client.get('/health').raise_for_status().json()
        except httpx.RequestError as exc:
            report['restart_verification'] = dict(result='NOT TESTED', reason='Backend unavailable; start it with the same database in a separate terminal and wait for Application startup complete.', error=type(exc).__name__)
            output.write_text(json.dumps(report, indent=2)+'\n')
            raise SystemExit(report['restart_verification']['reason']) from None
        before = checkpoint['health']
        if not health.get('instance_id') or health['instance_id'] == before.get('instance_id'):
            raise SystemExit('Restart not demonstrated: stop and restart backend with the same database first.')
        profiles = client.get('/animals').raise_for_status().json()
        data = (root / checkpoint['reference_path']).read_bytes()
        response = client.post('/recognize', json={'image': base64.b64encode(data).decode()})
        current = response.raise_for_status().json()
        reference = checkpoint['reference_response']
        checks = dict(
            server_restarted=True,
            same_model=health['model_version'] == before['model_version'],
            same_policy=health['policy'] == before['policy'],
            profiles_and_vaccinations_persisted=bool(profiles) and profiles == checkpoint['profiles'],
            templates_persisted=reference is not None and current['decision'] == reference['decision'] and current['animal'] == reference['animal'] and abs(current['score']-reference['score']) < 1e-6,
        )
        report['restart_verification'] = dict(result='PASS' if all(checks.values()) else 'FAIL', checks=checks, actual_response=current)
        output.write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report['restart_verification'], indent=2))
        if not all(checks.values()):
            raise SystemExit('Persistence verification failed; inspect evaluation report.')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('mode',choices=['calibrate','http','http-restart'])
    parser.add_argument('--dataset',type=Path,default=ROOT)
    parser.add_argument('--url',default='http://127.0.0.1:8000')
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    if args.mode=='calibrate': calibrate(args.dataset,args.output or Path('demo_backend/calibration.json'))
    elif args.mode=='http': evaluate(args.dataset,args.url,args.output or Path('demo_backend/evaluation.json'))
    else: verify_restart(args.dataset,args.url,args.output or Path('demo_backend/evaluation.json'))
