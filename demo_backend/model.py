"""Offline MegaDescriptor inference, following the publisher's model-card transform."""
import hashlib
import io
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps, UnidentifiedImageError

DEFAULT_MODEL = '/home/kelvin/Models/MegaDescriptor-L-384'

class MegaDescriptor:
    dimension = 1536

    def __init__(self, directory=None):
        import torch
        import timm
        from torchvision import transforms as T
        root = Path(directory or os.getenv('MUZZLID_MODEL', DEFAULT_MODEL))
        config = json.loads((root / 'config.json').read_text())
        if config['architecture'] != 'swin_large_patch4_window12_384' or config['num_features'] != self.dimension:
            raise ValueError('Incompatible MegaDescriptor configuration')
        torch.set_num_threads(int(os.getenv('MUZZLID_THREADS', '4')))
        checkpoint = root / 'pytorch_model.bin'
        digest = hashlib.file_digest(checkpoint.open('rb'), 'sha256').hexdigest()
        self.version = f'megadescriptor-L-384:{digest}:resize-bilinear-384:mean-std-0.5:l2:v1'
        self.model = timm.create_model(config['architecture'], pretrained=False, num_classes=0)
        # timm converts older Swin checkpoint layouts before strict loading.
        from timm.models.swin_transformer import checkpoint_filter_fn
        weights = torch.load(checkpoint, map_location='cpu', weights_only=True)
        self.model.load_state_dict(checkpoint_filter_fn(weights, self.model), strict=True)
        self.model.eval()
        self.transform = T.Compose([T.Resize((384, 384)), T.ToTensor(), T.Normalize([.5]*3, [.5]*3)])

    def embed(self, data):
        import torch
        try:
            with Image.open(io.BytesIO(data)) as image:
                if image.width * image.height > 25_000_000:
                    raise ValueError('Image exceeds 25 megapixels')
                tensor = self.transform(ImageOps.exif_transpose(image).convert('RGB')).unsqueeze(0)
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
            raise ValueError('Invalid or corrupt image') from exc
        with torch.inference_mode():
            vector = self.model(tensor).squeeze(0).numpy()
        return normalize(vector, self.dimension)


def normalize(vector, dimension=1536):
    vector = np.asarray(vector, dtype=np.float32)
    if vector.shape != (dimension,) or not np.isfinite(vector).all() or np.linalg.norm(vector) <= 1e-12:
        raise ValueError('Invalid embedding dimensions, values or norm')
    return vector / np.linalg.norm(vector)
