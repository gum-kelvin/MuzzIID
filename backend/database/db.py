"""
MuzzlID Relational Database & Encrypted PII Storage
SQLite implementation compatible with PostgreSQL & pgvector schema.
Enforces Uganda Data Protection and Privacy Act (2019) PII encryption.
"""

import os
import sqlite3
import json
import base64
import hashlib
from datetime import datetime
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import numpy as np

DB_FILE = os.environ.get("MUZZLID_DB_FILE", os.path.join(os.path.dirname(__file__), "muzzlid.db"))

# Key for AES-256-GCM encryption of Farmer PII (Uganda DPPA 2019 compliance)
PII_KEY = os.environ.get("MUZZLID_PII_KEY", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
if len(PII_KEY) == 64:
    PII_KEY_BYTES = bytes.fromhex(PII_KEY)
else:
    PII_KEY_BYTES = hashlib.sha256(PII_KEY.encode()).digest()

def encrypt_pii(cleartext: str) -> str:
    if not cleartext:
        return ""
    aesgcm = AESGCM(PII_KEY_BYTES)
    nonce = os.urandom(12)
    ct = aesgcm.encrypt(nonce, cleartext.encode("utf-8"), None)
    return base64.b64encode(nonce + ct).decode("ascii")

def decrypt_pii(ciphertext: str) -> str:
    if not ciphertext:
        return ""
    try:
        raw = base64.b64decode(ciphertext)
        nonce, ct = raw[:12], raw[12:]
        aesgcm = AESGCM(PII_KEY_BYTES)
        pt = aesgcm.decrypt(nonce, ct, None)
        return pt.decode("utf-8")
    except Exception:
        return "[ENCRYPTED_PII]"

class Database:
    def __init__(self, db_path: str = DB_FILE):
        self.db_path = db_path
        self._init_tables()

    def get_connection(self):
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_tables(self):
        with self.get_connection() as conn:
            c = conn.cursor()
            # Farmers table with encrypted PII
            c.execute("""
            CREATE TABLE IF NOT EXISTS farmers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                district TEXT NOT NULL,
                national_id_enc TEXT,
                phone_number_enc TEXT,
                created_at TEXT NOT NULL
            );
            """)

            # Animals table
            c.execute("""
            CREATE TABLE IF NOT EXISTS animals (
                id TEXT PRIMARY KEY,
                farmer_id TEXT,
                owner_name TEXT NOT NULL,
                district TEXT NOT NULL,
                place_label TEXT,
                breed TEXT,
                legacy_tag_id TEXT,
                created_at TEXT NOT NULL,
                sync_state TEXT NOT NULL DEFAULT 'acknowledged',
                FOREIGN KEY (farmer_id) REFERENCES farmers(id)
            );
            """)

            # Biometric templates table
            c.execute("""
            CREATE TABLE IF NOT EXISTS biometric_templates (
                id TEXT PRIMARY KEY,
                animal_id TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                model_version TEXT NOT NULL,
                frame_count INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                FOREIGN KEY (animal_id) REFERENCES animals(id)
            );
            """)

            # Vaccinations table
            c.execute("""
            CREATE TABLE IF NOT EXISTS vaccinations (
                id TEXT PRIMARY KEY,
                animal_id TEXT NOT NULL,
                vaccine TEXT NOT NULL,
                administered_at TEXT NOT NULL,
                recorded_at TEXT,
                valid_until TEXT,
                batch TEXT,
                latitude REAL,
                longitude REAL,
                accuracy_meters REAL,
                FOREIGN KEY (animal_id) REFERENCES animals(id)
            );
            """)

            # Audit scans log
            c.execute("""
            CREATE TABLE IF NOT EXISTS audit_scans (
                id TEXT PRIMARY KEY,
                device_id TEXT NOT NULL,
                operator_id TEXT,
                scan_mode TEXT NOT NULL,
                latitude REAL,
                longitude REAL,
                accuracy_meters REAL,
                top_match_animal_id TEXT,
                confidence_score REAL,
                decision TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """)
            conn.commit()

    def add_animal(self, animal_data: dict, template_embedding: np.ndarray, model_version: str = "resnet50_muzzle_v1.2"):
        with self.get_connection() as conn:
            c = conn.cursor()
            now = datetime.utcnow().isoformat() + "Z"
            aid = animal_data["id"]
            owner = animal_data.get("owner", animal_data.get("owner_name", "Unknown"))
            district = animal_data.get("district", "Mbarara")
            place = animal_data.get("location", animal_data.get("place_label", ""))
            breed = animal_data.get("breed", "Ankole-cross")
            tag = animal_data.get("legacy_tag_id", "")
            created = animal_data.get("created", now)

            # Insert farmer record
            farmer_id = f"FARMER-{aid}"
            nin_enc = encrypt_pii(animal_data.get("national_id", ""))
            phone_enc = encrypt_pii(animal_data.get("phone", ""))
            c.execute("""
                INSERT OR REPLACE INTO farmers (id, name, district, national_id_enc, phone_number_enc, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (farmer_id, owner, district, nin_enc, phone_enc, created))

            # Insert animal
            c.execute("""
                INSERT OR REPLACE INTO animals (id, farmer_id, owner_name, district, place_label, breed, legacy_tag_id, created_at, sync_state)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'acknowledged')
            """, (aid, farmer_id, owner, district, place, breed, tag, created))

            # Insert biometric template
            tid = f"TPL-{aid}"
            emb_json = json.dumps(template_embedding.tolist())
            c.execute("""
                INSERT OR REPLACE INTO biometric_templates (id, animal_id, embedding_json, model_version, frame_count, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (tid, aid, emb_json, model_version, animal_data.get("frame_count", 5), now))

            # Insert vaccinations
            for v in animal_data.get("vaccinations", []):
                vid = v.get("id", f"VAC-{aid}-{v.get('vaccine', 'V')}")
                gps = v.get("gps") or {}
                c.execute("""
                    INSERT OR REPLACE INTO vaccinations (id, animal_id, vaccine, administered_at, recorded_at, valid_until, batch, latitude, longitude, accuracy_meters)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    vid, aid, v["vaccine"],
                    v.get("administeredAt", v.get("administered_at", now)),
                    v.get("recordedAt", v.get("recorded_at", now)),
                    v.get("validUntil", v.get("valid_until")),
                    v.get("batch", ""),
                    gps.get("latitude") if isinstance(gps, dict) else getattr(gps, "latitude", None),
                    gps.get("longitude") if isinstance(gps, dict) else getattr(gps, "longitude", None),
                    gps.get("accuracyMeters") if isinstance(gps, dict) else getattr(gps, "accuracyMeters", None)
                ))
            conn.commit()

    def get_animal_with_vaccinations(self, animal_id: str) -> dict:
        with self.get_connection() as conn:
            c = conn.cursor()
            c.execute("SELECT * FROM animals WHERE id = ?", (animal_id,))
            row = c.fetchone()
            if not row:
                return None
            c.execute("SELECT * FROM vaccinations WHERE animal_id = ? ORDER BY administered_at DESC", (animal_id,))
            vax_rows = c.fetchall()
            vaccinations = []
            for vr in vax_rows:
                v = {
                    "id": vr["id"],
                    "vaccine": vr["vaccine"],
                    "administeredAt": vr["administered_at"],
                    "recordedAt": vr["recorded_at"],
                    "validUntil": vr["valid_until"],
                    "batch": vr["batch"]
                }
                if vr["latitude"] is not None and vr["longitude"] is not None:
                    v["gps"] = {
                        "latitude": vr["latitude"],
                        "longitude": vr["longitude"],
                        "accuracyMeters": vr["accuracy_meters"]
                    }
                vaccinations.append(v)

            return {
                "id": row["id"],
                "owner": row["owner_name"],
                "owner_name": row["owner_name"],
                "district": row["district"],
                "location": row["place_label"] or row["district"],
                "place_label": row["place_label"],
                "breed": row["breed"],
                "legacy_tag_id": row["legacy_tag_id"],
                "created": row["created_at"],
                "created_at": row["created_at"],
                "sync_state": row["sync_state"],
                "vaccinations": vaccinations
            }

    def get_all_templates(self) -> list:
        with self.get_connection() as conn:
            c = conn.cursor()
            c.execute("""
                SELECT bt.animal_id, bt.embedding_json, bt.model_version
                FROM biometric_templates bt
            """)
            rows = c.fetchall()
            results = []
            for r in rows:
                results.append({
                    "animal_id": r["animal_id"],
                    "embedding": np.array(json.loads(r["embedding_json"]), dtype=np.float32),
                    "model_version": r["model_version"]
                })
            return results

    def get_district_manifest(self, district: str) -> list:
        with self.get_connection() as conn:
            c = conn.cursor()
            c.execute("SELECT id FROM animals WHERE lower(district) = lower(?)", (district,))
            rows = c.fetchall()
            animals = []
            for r in rows:
                anim = self.get_animal_with_vaccinations(r["id"])
                if anim:
                    animals.append(anim)
            return animals

    def record_audit_scan(self, audit: dict):
        with self.get_connection() as conn:
            c = conn.cursor()
            now = datetime.utcnow().isoformat() + "Z"
            sid = audit.get("id", f"AUDIT-{datetime.utcnow().timestamp()}")
            c.execute("""
                INSERT OR REPLACE INTO audit_scans (
                    id, device_id, operator_id, scan_mode, latitude, longitude, accuracy_meters,
                    top_match_animal_id, confidence_score, decision, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                sid,
                audit.get("device_id", "DEV-UNKNOWN"),
                audit.get("operator_id", "OPERATOR-DEFAULT"),
                audit.get("scan_mode", "VERIFY"),
                audit.get("latitude"),
                audit.get("longitude"),
                audit.get("accuracy_meters"),
                audit.get("top_match_animal_id"),
                audit.get("confidence_score"),
                audit.get("decision", "PENDING"),
                now
            ))
            conn.commit()

db = Database()
