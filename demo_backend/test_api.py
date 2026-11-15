import sys
import types

import numpy as np
import pytest
from fastapi.testclient import TestClient

from demo_backend import app as api
from demo_backend.model import MegaDescriptor, normalize


class FakeEngine:
    dimension = 1536
    version = "fake-v1"

    def embed(self, data):
        # Each five-byte enrollment block shares one deterministic direction.
        if not data:
            raise ValueError("empty image")
        index = data[0]
        vector = np.zeros(self.dimension, dtype=np.float32)
        if index == 250:
            vector[10] = 0.9
            vector[11] = np.sqrt(1 - 0.9**2)
        elif index == 251:
            vector[10] = vector[20] = 1 / np.sqrt(2)
        elif index == 252:
            vector[10] = 0.95
            vector[11] = np.sqrt(1 - 0.95**2)
        else:
            vector[((index // 10) * 10) % self.dimension] = 1
        return vector


class CountingFakeEngine(FakeEngine):
    def __init__(self):
        self.embed_count = 0

    def embed(self, data):
        self.embed_count += 1
        return super().embed(data)


def client(tmp_path, *, engine=None, policy=None):
    return TestClient(api.create_app(engine or FakeEngine(), tmp_path / "registry.sqlite3", policy))


def encoded(value):
    import base64

    return base64.b64encode(bytes([value])).decode("ascii")


def enrollment(animal_id, base):
    return {
        "record": {
            "id": animal_id,
            "owner": f"Owner {animal_id}",
            "created": "2025-01-01",
            "vaccinations": [
                {"id": f"vax-{animal_id}", "vaccine": "FMD", "administeredAt": "2025-01-02"}
            ],
        },
        "images": [encoded(base + i) for i in range(5)],
    }


def test_empty_registry_and_health(tmp_path):
    with client(tmp_path) as c:
        assert c.get("/animals").json() == []
        assert c.get("/health").json()["dimension"] == 1536
        result = c.post("/recognize", json={"image": encoded(1)}).json()
        assert result == {"decision": "unknown", "score": None, "margin": None, "animal": None}


def test_enroll_five_distinct_animals_and_return_profile_with_vaccination(tmp_path):
    policy = api.Policy(accept=0.98, reject=0.6, margin=0.04)
    with client(tmp_path, policy=policy) as c:
        for i in range(5):
            response = c.post("/enroll", json=enrollment(f"cow-{i}", i * 10))
            assert response.status_code == 201
            assert response.json()["vaccinations"] == [
                {"id": f"vax-cow-{i}", "vaccine": "FMD", "administeredAt": "2025-01-02"}
            ]
        profile = c.get("/animals/cow-3").json()
        assert profile["owner"] == "Owner cow-3"
        assert profile["syncState"] == "acknowledged"
        assert profile["vaccinations"][0]["vaccine"] == "FMD"
        assert len(c.get("/animals").json()) == 5


def test_recognition_unknown_uncertain_and_accepted_never_leaks_unaccepted_profile(tmp_path):
    policy = api.Policy(accept=0.98, reject=0.6, margin=0.04)
    with client(tmp_path, policy=policy) as c:
        c.post("/enroll", json=enrollment("cow", 10))
        accepted = c.post("/recognize", json={"image": encoded(10)}).json()
        assert accepted["decision"] == "accepted"
        assert accepted["animal"]["id"] == "cow"
        uncertain = c.post("/recognize", json={"image": encoded(252)}).json()
        assert uncertain["decision"] == "uncertain"
        assert uncertain["animal"] is None
        unknown = c.post("/recognize", json={"image": encoded(20)}).json()
        assert unknown["decision"] == "unknown"
        assert unknown["animal"] is None


def test_uncalibrated_policy_returns_uncertain_without_profile(tmp_path):
    with client(tmp_path) as c:
        assert c.post("/enroll", json=enrollment("cow", 10)).status_code == 201
        result = c.post("/recognize", json={"image": encoded(10)}).json()
        assert result["decision"] == "uncertain"
        assert result["animal"] is None


def test_blocked_enrollments_do_not_extract_images(tmp_path):
    engine = CountingFakeEngine()
    with client(tmp_path, engine=engine) as c:
        assert c.post("/enroll", json=enrollment("A", 10)).status_code == 201
        assert engine.embed_count == 5

        retry = c.post("/enroll", json=enrollment("A", 30))
        assert retry.status_code == 409
        assert engine.embed_count == 5

        other = c.post("/enroll", json=enrollment("B", 50))
        assert other.status_code == 409
        assert "uncalibrated" in other.json()["detail"].lower()
        assert "not evidence" in other.json()["detail"].lower()
        assert engine.embed_count == 5


def test_ambiguous_recognition_hides_animal(tmp_path):
    policy = api.Policy(accept=0.69, reject=0.5, margin=0.04)
    with client(tmp_path, policy=policy) as c:
        # Enrollment directions are orthogonal. Probe 251 has equal similarity to both.
        assert c.post("/enroll", json=enrollment("cow-a", 10)).status_code == 201
        assert c.post("/enroll", json=enrollment("cow-b", 20)).status_code == 201
        result = c.post("/recognize", json={"image": encoded(251)}).json()
        assert result["decision"] == "uncertain"
        assert result["animal"] is None


def test_duplicate_image_and_duplicate_identity_rejected(tmp_path):
    policy = api.Policy(accept=0.98, reject=0.6, margin=0.04)
    with client(tmp_path, policy=policy) as c:
        first = enrollment("cow", 10)
        assert c.post("/enroll", json=first).status_code == 201
        assert c.post("/enroll", json=first).status_code == 409
        repeated = enrollment("other", 20)
        repeated["images"][0] = repeated["images"][1]
        assert c.post("/enroll", json=repeated).status_code == 422


@pytest.mark.parametrize("image", ["%%%", ""])
def test_invalid_base64_and_invalid_embedding_dimensions_return_422(tmp_path, image):
    with client(tmp_path) as c:
        assert c.post("/recognize", json={"image": image}).status_code == 422

    class BadDimensionEngine(FakeEngine):
        def embed(self, data):
            return np.ones(3, dtype=np.float32)

    (tmp_path / "bad").mkdir()
    with client(tmp_path / "bad", engine=BadDimensionEngine()) as c:
        assert c.post("/recognize", json={"image": encoded(1)}).status_code == 422


def test_normalize_rejects_bad_vectors():
    with pytest.raises(ValueError):
        normalize(np.zeros(1536, dtype=np.float32))
    with pytest.raises(ValueError):
        normalize(np.full(1536, np.nan, dtype=np.float32))
    with pytest.raises(ValueError):
        normalize(np.ones(3, dtype=np.float32))


def test_missing_model_directory_fails_during_configuration_read(tmp_path, monkeypatch):
    # Stub heavyweight imports so this contract reaches the missing config file check.
    monkeypatch.setitem(sys.modules, "torch", types.ModuleType("torch"))
    monkeypatch.setitem(sys.modules, "timm", types.ModuleType("timm"))
    torchvision = types.ModuleType("torchvision")
    torchvision.transforms = types.SimpleNamespace()
    monkeypatch.setitem(sys.modules, "torchvision", torchvision)
    with pytest.raises(FileNotFoundError):
        MegaDescriptor(tmp_path / "missing")


def test_persistence_after_restart_and_rejects_version_mismatch(tmp_path):
    database = tmp_path / "registry.sqlite3"
    with TestClient(api.create_app(FakeEngine(), database)) as c:
        assert c.post("/enroll", json=enrollment("persisted", 10)).status_code == 201
    with TestClient(api.create_app(FakeEngine(), database)) as c:
        assert c.get("/animals/persisted").json()["id"] == "persisted"

    class NewVersionEngine(FakeEngine):
        version = "fake-v2"

    with pytest.raises(ValueError, match="incompatible model version"):
        with TestClient(api.create_app(NewVersionEngine(), database)):
            pass
