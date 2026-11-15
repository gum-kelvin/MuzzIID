import base64
import json

import httpx
import pytest
from fastapi.testclient import TestClient

from demo_backend import app, evaluate
from demo_backend.test_api import FakeEngine


def _checkpoint(tmp_path):
    image = tmp_path / "probe.jpg"
    image.write_bytes(b"probe-bytes")
    profile = {
        "id": "cow-a",
        "owner": "Owner A",
        "vaccinations": [{"id": "vax-a", "vaccine": "FMD"}],
    }
    health = {
        "instance_id": "before-restart",
        "model_version": "fake-v1",
        "policy": {"accept": None, "reject": None, "margin": 0.04},
    }
    response = {"decision": "uncertain", "animal": None, "score": 0.83}
    output = tmp_path / "evaluation.json"
    output.write_text(json.dumps({
        "persistence_checkpoint": {
            "health": health,
            "profiles": [profile],
            "reference_path": image.name,
            "reference_response": response,
        }
    }))
    return output, health, [profile], response


@pytest.mark.parametrize(
    "change,expected",
    [(None, "PASS"), ("profile", "FAIL"), ("score", "FAIL")],
)
def test_verify_restart_checks_profiles_and_embedding_result(
    tmp_path, monkeypatch, change, expected
):
    output, before, profiles, reference = _checkpoint(tmp_path)
    health = {**before, "instance_id": "after-restart"}
    current = dict(reference)
    returned_profiles = profiles
    if change == "profile":
        returned_profiles = [{**profiles[0], "owner": "Changed owner"}]
    elif change == "score":
        current["score"] = 0.82

    infer_calls = []

    def handler(request):
        if request.url.path == "/health":
            return httpx.Response(200, json=health)
        if request.url.path == "/animals":
            return httpx.Response(200, json=returned_profiles)
        if request.url.path == "/recognize":
            infer_calls.append(request)
            import json as json_module

            assert base64.b64decode(json_module.loads(request.content)["image"]) == b"probe-bytes"
            return httpx.Response(200, json=current)
        raise AssertionError(f"Unexpected request {request.url}")

    real_client = httpx.Client
    monkeypatch.setattr(
        httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(handler), **kwargs)
    )

    with pytest.raises(SystemExit) if expected == "FAIL" else _nullcontext():
        evaluate.verify_restart(tmp_path, "http://test", output)

    saved = json.loads(output.read_text())
    assert saved["restart_verification"]["result"] == expected
    assert len(infer_calls) == 1
    assert saved["restart_verification"]["checks"]["profiles_and_vaccinations_persisted"] is (change != "profile")
    assert saved["restart_verification"]["checks"]["templates_persisted"] is (change != "score")


class _nullcontext:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def test_verify_restart_rejects_same_instance_before_inference(tmp_path, monkeypatch):
    output, before, _, _ = _checkpoint(tmp_path)
    calls = []

    def handler(request):
        calls.append(request.url.path)
        return httpx.Response(200, json=before)

    real_client = httpx.Client
    monkeypatch.setattr(
        httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(handler), **kwargs)
    )
    with pytest.raises(SystemExit, match="Restart not demonstrated"):
        evaluate.verify_restart(tmp_path, "http://test", output)
    assert calls == ["/health"]
    assert "restart_verification" not in json.loads(output.read_text())


def test_verify_restart_records_connection_refused_as_not_tested(tmp_path, monkeypatch):
    output, _, _, _ = _checkpoint(tmp_path)

    def handler(request):
        raise httpx.ConnectError("Connection refused", request=request)

    real_client = httpx.Client
    monkeypatch.setattr(
        httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(handler), **kwargs)
    )

    with pytest.raises(SystemExit, match="Backend unavailable; start it with the same database"):
        evaluate.verify_restart(tmp_path, "http://test", output)

    saved = json.loads(output.read_text())
    assert saved["restart_verification"]["result"] == "NOT TESTED"
    assert saved["restart_verification"]["error"] == "ConnectError"
    assert saved["persistence_checkpoint"]["reference_path"] == "probe.jpg"


@pytest.mark.parametrize(
    "calibration,match",
    [
        ({"policy": None, "calibration_protocol": "five-image-mean-l2-v1"}, "did not support"),
        ({"policy": {"accept": 0.8, "reject": 0.7, "margin": 0.04}}, "protocol mismatch"),
    ],
)
def test_startup_rejects_unsupported_or_legacy_calibration(
    tmp_path, monkeypatch, calibration, match
):
    policy_path = tmp_path / "policy.json"
    policy_path.write_text(json.dumps({"model_version": "fake-v1", **calibration}))
    monkeypatch.setenv("MUZZLID_POLICY", str(policy_path))
    with pytest.raises(ValueError, match=match):
        with TestClient(app.create_app(FakeEngine(), tmp_path / "registry.sqlite3")):
            pass
