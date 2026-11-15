import numpy as np
import pytest

from demo_backend.diagnose import rank_probes
from demo_backend.model import normalize


def test_rank_probes_reports_rank1_and_per_probe_margins():
    templates = {
        "cow-a": np.array([1.0, 0.0]),
        "cow-b": np.array([0.0, 1.0]),
    }
    probes = [
        ("cow-a", "a.jpg", np.array([0.8, 0.6])),
        ("cow-a", "a-wrong.jpg", np.array([0.2, 0.98])),
        ("cow-b", "b.jpg", np.array([0.6, 0.8])),
    ]

    report = rank_probes(templates, probes)

    assert report["correct"] == 2
    assert report["count"] == 3
    assert report["rank1_accuracy"] == 2 / 3
    assert [probe["rank1"] for probe in report["probes"]] == ["cow-a", "cow-b", "cow-b"]
    assert [probe["correct"] for probe in report["probes"]] == [True, False, True]
    assert report["probes"][0]["genuine"] == 0.8
    assert report["probes"][0]["max_impostor"] == 0.6
    assert report["probes"][0]["genuine_margin"] == pytest.approx(0.2)
    assert report["probes"][1]["genuine"] == 0.2
    assert report["probes"][1]["max_impostor"] == 0.98
    assert report["probes"][1]["genuine_margin"] == pytest.approx(-0.78)


def test_rank_probes_breaks_exact_ties_by_id():
    report = rank_probes(
        {"cow-b": np.array([1.0, 0.0]), "cow-a": np.array([1.0, 0.0])},
        [("cow-b", "tie.jpg", np.array([1.0, 0.0]))],
    )

    assert report["probes"][0]["rank1"] == "cow-a"
    assert report["probes"][0]["correct"] is False
    assert report["probes"][0]["genuine_margin"] == 0.0


def test_rank_probes_handles_empty_probes():
    report = rank_probes({"cow-a": np.array([1.0, 0.0])}, [])

    assert report == {
        "probes": [],
        "correct": 0,
        "count": 0,
        "rank1_accuracy": None,
        "min_genuine": None,
        "max_impostor": None,
    }


def test_five_image_template_is_normalized_mean_of_embeddings():
    embeddings = [
        np.array([1.0, 0.0]),
        np.array([0.8, 0.2]),
        np.array([0.6, 0.4]),
        np.array([0.4, 0.6]),
        np.array([0.2, 0.8]),
    ]

    template = normalize(np.mean(embeddings, axis=0), dimension=2)
    report = rank_probes({"cow-a": template}, [("cow-a", "heldout.jpg", template)])

    expected = np.mean(embeddings, axis=0)
    expected = expected / np.linalg.norm(expected)
    np.testing.assert_allclose(template, expected)
    assert report["probes"][0]["rank1"] == "cow-a"
    assert report["probes"][0]["correct"] is True
