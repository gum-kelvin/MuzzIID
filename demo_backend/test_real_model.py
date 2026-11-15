"""Opt-in real CPU checkpoint test. May take minutes; never downloads weights."""
import os
from pathlib import Path

import numpy as np
import pytest

from .model import MegaDescriptor
from .selection import ROOT

@pytest.mark.skipif(os.getenv('MUZZLID_REAL_TEST') != '1', reason='User-run prolonged CPU test: set MUZZLID_REAL_TEST=1')
def test_pretrained_checkpoint_and_genuine_photo():
    model = MegaDescriptor()
    path = sorted((ROOT / 'cattle_0100').glob('*.jpg'))[0]
    vector = model.embed(path.read_bytes())
    assert vector.shape == (1536,)
    assert np.isfinite(vector).all()
    assert float(np.linalg.norm(vector)) == pytest.approx(1, abs=1e-5)
    with pytest.raises(ValueError, match='Invalid or corrupt image'):
        model.embed(b'not an image')
