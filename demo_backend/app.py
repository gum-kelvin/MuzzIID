"""CPU-only, local demonstration registry. Run one uvicorn worker."""
import base64
import binascii
import json
import os
import sqlite3
import threading
import uuid
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .model import MegaDescriptor, normalize

class Enrollment(BaseModel):
    record: dict
    images: list[str] = Field(min_length=5, max_length=5)

class Probe(BaseModel):
    image: str

class Policy:
    def __init__(self, accept=None, reject=None, margin=.04):
        if accept is not None and not (-1 <= reject < accept <= 1 and 0 < margin <= 2):
            raise ValueError('Invalid similarity policy')
        self.accept, self.reject, self.margin = accept, reject, margin

    def decide(self, scores):
        if not scores:
            return 'unknown'
        if self.accept is None:
            return 'uncertain'
        if scores[0][1] < self.reject:
            return 'unknown'
        if scores[0][1] < self.accept or (len(scores) > 1 and scores[0][1] - scores[1][1] < self.margin):
            return 'uncertain'
        return 'accepted'


def create_app(engine=None, database=None, policy=None):
    lock = threading.RLock()
    db_path = str(database or os.getenv('MUZZLID_DB', 'demo_backend/registry.sqlite3'))
    state = {}

    @asynccontextmanager
    async def lifespan(app):
        state['instance_id'] = str(uuid.uuid4())
        state['engine'] = engine or MegaDescriptor()
        state['policy'] = policy or Policy()
        policy_path = os.getenv('MUZZLID_POLICY')
        if policy is None and policy_path:
            calibration = json.loads(Path(policy_path).read_text())
            if calibration['model_version'] != state['engine'].version:
                raise ValueError('Calibration/model mismatch')
            if calibration.get('policy') is None:
                raise ValueError('Calibration did not support a policy; omit MUZZLID_POLICY')
            if calibration.get('calibration_protocol') != 'five-image-mean-l2-v1':
                raise ValueError('Calibration enrollment protocol mismatch; five-image templates required')
            state['policy'] = Policy(**calibration['policy'])
        with connect() as db:
            db.execute('CREATE TABLE IF NOT EXISTS cattle (id TEXT PRIMARY KEY, record TEXT NOT NULL, version TEXT NOT NULL, template BLOB NOT NULL, hashes TEXT NOT NULL)')
            db.execute('CREATE TABLE IF NOT EXISTS vaccinations (id TEXT PRIMARY KEY, animal TEXT NOT NULL REFERENCES cattle(id), record TEXT NOT NULL)')
            for version, template in db.execute('SELECT version, template FROM cattle'):
                if version != state['engine'].version:
                    raise ValueError('Registry contains incompatible model version')
                normalize(np.frombuffer(template, dtype=np.float32))
        yield

    app = FastAPI(title='MuzzlD MegaDescriptor CPU demonstration', lifespan=lifespan)

    @contextmanager
    def connect():
        db = sqlite3.connect(db_path)
        try:
            db.execute('PRAGMA foreign_keys=ON')
            with db:
                yield db
        finally:
            db.close()

    def embed(encoded):
        try:
            if len(encoded) > 16_000_000:
                raise ValueError('Image exceeds upload limit')
            data = base64.b64decode(encoded, validate=True)
            return normalize(state['engine'].embed(data)), __import__('hashlib').sha256(data).hexdigest()
        except (ValueError, binascii.Error) as exc:
            raise HTTPException(422, str(exc)) from exc

    def scores(db, vector):
        ranked = []
        for id_, version, blob in db.execute('SELECT id, version, template FROM cattle'):
            if version != state['engine'].version:
                raise HTTPException(503, 'Incompatible model version in registry')
            ranked.append((id_, float(normalize(np.frombuffer(blob, dtype=np.float32)) @ vector)))
        return sorted(ranked, key=lambda item: (-item[1], item[0]))

    def profile(db, id_):
        row = db.execute('SELECT record FROM cattle WHERE id=?', (id_,)).fetchone()
        if row is None:
            raise HTTPException(404, 'Animal not found')
        record = json.loads(row[0])
        record['vaccinations'] = [json.loads(row[0]) for row in db.execute('SELECT record FROM vaccinations WHERE animal=? ORDER BY id', (id_,))]
        return record

    def save_vaccination(db, id_, record):
        if not all(isinstance(record.get(k), str) and record[k].strip() for k in ('id', 'vaccine', 'administeredAt')):
            raise HTTPException(422, 'Vaccination needs id, vaccine and administeredAt')
        existing = db.execute('SELECT animal, record FROM vaccinations WHERE id=?', (record['id'],)).fetchone()
        if existing and (existing[0] != id_ or json.loads(existing[1]) != record):
            raise HTTPException(409, 'Vaccination ID already exists')
        db.execute('INSERT OR IGNORE INTO vaccinations VALUES (?,?,?)', (record['id'], id_, json.dumps(record)))

    @app.get('/health')
    def health():
        return dict(status='ready', instance_id=state['instance_id'], model_version=state['engine'].version, dimension=1536,
                    policy=vars(state['policy']), calibrated=state['policy'].accept is not None)

    @app.get('/animals')
    def animals():
        with lock, connect() as db:
            return [profile(db, row[0]) for row in db.execute('SELECT id FROM cattle ORDER BY id')]

    @app.post('/enroll', status_code=201)
    def enroll(request: Enrollment):
        record = dict(request.record)
        if not all(isinstance(record.get(k), str) and record[k].strip() for k in ('id', 'owner', 'created')):
            raise HTTPException(422, 'Animal needs id, owner and created')
        if len(record['id']) > 120 or len(record['owner']) > 120:
            raise HTTPException(422, 'Animal field too long')
        with lock:
            # Reject known identity retries and unassessable duplicates before
            # spending CPU time extracting five unnecessary embeddings.
            with connect() as db:
                if db.execute('SELECT 1 FROM cattle WHERE id=?', (record['id'],)).fetchone():
                    raise HTTPException(409, 'Animal ID already enrolled')
                if state['policy'].accept is None and db.execute('SELECT 1 FROM cattle LIMIT 1').fetchone():
                    raise HTTPException(409, 'Registry uncalibrated; cannot exclude a duplicate. Enrollment blocked, not evidence that these animals match.')
            vectors, hashes = zip(*(embed(image) for image in request.images))
            if len(set(hashes)) != 5:
                raise HTTPException(422, 'Five distinct photographs are required')
            template = normalize(np.mean(vectors, axis=0))
            with connect() as db:
                ranked = scores(db, template)
                repeated = any(set(hashes) & set(json.loads(row[0])) for row in db.execute('SELECT hashes FROM cattle'))
                # Any uncertain/accepted similarity is conservatively a possible duplicate.
                if repeated or db.execute('SELECT 1 FROM cattle WHERE id=?', (record['id'],)).fetchone() or (ranked and state['policy'].decide(ranked) != 'unknown'):
                    raise HTTPException(409, 'Possible duplicate; review registry before enrollment')
                record['muzzleFrames'] = []
                record['syncState'] = 'acknowledged'
                vaccinations = record.pop('vaccinations', [])
                db.execute('INSERT INTO cattle VALUES (?,?,?,?,?)', (record['id'], json.dumps(record), state['engine'].version, template.tobytes(), json.dumps(hashes)))
                for vaccination in vaccinations:
                    save_vaccination(db, record['id'], vaccination)
                return profile(db, record['id'])

    @app.post('/recognize')
    def recognize(request: Probe):
        with lock, connect() as db:
            vector, _ = embed(request.image)
            ranked = scores(db, vector)
            decision = state['policy'].decide(ranked)
            # Identity and veterinary data are returned only after acceptance.
            return dict(decision=decision, score=ranked[0][1] if ranked else None,
                        margin=ranked[0][1]-ranked[1][1] if len(ranked)>1 else None,
                        animal=profile(db, ranked[0][0]) if decision == 'accepted' else None)

    @app.get('/animals/{id_}')
    def animal(id_: str):
        with lock, connect() as db:
            return profile(db, id_)

    @app.patch('/animals/{id_}')
    def update(id_: str, changes: dict):
        with lock, connect() as db:
            record = profile(db, id_)
            for key in ('owner', 'location', 'gps'):
                if key in changes:
                    record[key] = changes[key]
            db.execute('UPDATE cattle SET record=? WHERE id=?', (json.dumps(record), id_))
            return profile(db, id_)

    @app.post('/animals/{id_}/vaccinations')
    def vaccination(id_: str, record: dict):
        with lock, connect() as db:
            profile(db, id_)
            save_vaccination(db, id_, record)
            return profile(db, id_)

    @app.delete('/animals/{id_}', status_code=204)
    def delete(id_: str):
        with lock, connect() as db:
            profile(db, id_)
            db.execute('DELETE FROM vaccinations WHERE animal=?', (id_,))
            db.execute('DELETE FROM cattle WHERE id=?', (id_,))

    return app

app = create_app()
