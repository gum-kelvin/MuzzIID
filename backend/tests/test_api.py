"""
Backend API Unit and Integration Tests
Tests:
- Authentication
- Healthcheck
- Biometric verification with thresholds (Verified, Uncertain, Unregistered)
- Burst enrolment with de-duplication guard
- Batch sync with duplicate conflict detection
- District manifest retrieval
"""

import io
import base64
import pytest
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw
import numpy as np

from backend.app import app
from backend.database.db import db
from backend.database.seed import create_synthetic_muzzle_image

client = TestClient(app)

def test_healthcheck():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "resnet50_muzzle_v1.2" in data["model_version"]
    assert data["thresholds"]["match_confirmed"] == 0.78
    assert data["thresholds"]["uncertain_lower_bound"] == 0.68

def test_login():
    response = client.post("/api/v1/auth/login", json={"username": "kato", "password": "password123"})
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["role"] == "VET_OFFICER"

def test_verification_registered_match():
    # Muzzle image matching pattern 4192 (UG-MBR-2026-04192)
    img_bytes = create_synthetic_muzzle_image(pattern_id=4192)
    b64 = base64.b64encode(img_bytes).decode("ascii")

    response = client.post("/api/v1/biometrics/verify", json={
        "image": b64,
        "gps_coords": {"latitude": -0.6072, "longitude": 30.6545, "accuracyMeters": 3.0},
        "device_id": "TEST-DEV-01",
        "operator_id": "DR-KATO"
    })
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "verified"
    assert data["confidence"] >= 0.78
    assert data["animal"] is not None
    assert data["animal"]["id"] == "UG-MBR-2026-04192"
    assert data["animal"]["owner"] == "Katusiime Samuel"
    # Ensure health & vaccination records are returned
    vax = data["animal"]["vaccinations"]
    assert len(vax) > 0
    assert any(v["vaccine"] == "FMD" for v in vax)

def test_verification_unregistered():
    # Muzzle image with pattern that doesn't match any registered cow
    img_bytes = create_synthetic_muzzle_image(pattern_id=999999)
    b64 = base64.b64encode(img_bytes).decode("ascii")

    response = client.post("/api/v1/biometrics/verify", json={
        "image": b64,
        "gps_coords": {"latitude": -0.6072, "longitude": 30.6545}
    })
    assert response.status_code == 200
    data = response.json()
    assert data["status"] in ("unregistered", "uncertain")
    if data["status"] == "unregistered":
        assert data["confidence"] < 0.68

def test_enrolment_duplicate_guard():
    # Attempting to enrol the already-registered pattern 4192 must be rejected!
    img_bytes = create_synthetic_muzzle_image(pattern_id=4192)
    b64 = base64.b64encode(img_bytes).decode("ascii")
    burst = [b64] * 5

    response = client.post("/api/v1/biometrics/enrol", json={
        "frames": burst,
        "owner": "Duplicate Tester",
        "district": "Mbarara"
    })
    # Must trigger 409 Conflict duplicate guard
    assert response.status_code == 409
    assert "DUPLICATE_CONFLICT" in response.json()["detail"]

def test_enrolment_and_sync_new_animal():
    img_bytes = create_synthetic_muzzle_image(pattern_id=7777)
    b64 = base64.b64encode(img_bytes).decode("ascii")
    burst = [b64] * 5

    response = client.post("/api/v1/biometrics/enrol", json={
        "frames": burst,
        "owner": "Nsubuga David",
        "district": "Mbarara",
        "location": "Bwizibwera",
        "breed": "Ankole",
        "vaccinations": [
            {
                "vaccine": "FMD",
                "administeredAt": "2026-11-14T05:00:00Z"
            }
        ]
    })
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "acknowledged"
    assert data["animal_id"].startswith("UG-MBR-2026-")

def test_batch_sync_offline_enrolments_with_duplicate_detection():
    # Enrolment 1: unique animal
    img1 = base64.b64encode(create_synthetic_muzzle_image(pattern_id=8888)).decode("ascii")
    # Enrolment 2: duplicate of UG-MBR-2026-04192
    img_dup = base64.b64encode(create_synthetic_muzzle_image(pattern_id=4192)).decode("ascii")

    batch_payload = {
        "device_id": "TEST-DEVICE-OFFLINE",
        "enrolments": [
            {
                "id": "LOCAL-NEW-01",
                "owner": "Katongole Paul",
                "district": "Mbarara",
                "frames": [img1] * 5
            },
            {
                "id": "LOCAL-DUP-02",
                "owner": "Impostor",
                "district": "Mbarara",
                "frames": [img_dup] * 5
            }
        ],
        "vaccinations": [
            {
                "id": "VAC-OFFLINE-01",
                "vaccine": "Lumpy skin",
                "administeredAt": "2026-11-14T05:00:00Z"
            }
        ]
    }

    response = client.post("/api/v1/sync/batch", json=batch_payload)
    assert response.status_code == 200
    res = response.json()
    assert res["status"] == "success"
    # One unique acknowledged, one duplicate conflict!
    enrol_results = {e["id"]: e for e in res["enrolments"]}
    assert enrol_results["LOCAL-NEW-01"]["status"] == "acknowledged"
    assert enrol_results["LOCAL-DUP-02"]["status"] == "duplicate_conflict"
    assert enrol_results["LOCAL-DUP-02"]["conflict_animal_id"] == "UG-MBR-2026-04192"

def test_district_manifest():
    response = client.get("/api/v1/manifests/district/Mbarara")
    assert response.status_code == 200
    manifest = response.json()
    assert manifest["district"] == "Mbarara"
    assert "animals" in manifest
    assert len(manifest["animals"]) >= 2
    # Ensure UG-MBR-2026-04192 is in the manifest
    ids = [a["id"] for a in manifest["animals"]]
    assert "UG-MBR-2026-04192" in ids
