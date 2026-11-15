"""Deterministic manifest, with encoded and decoded-image duplicate checks."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path('/home/kelvin/Downloads/BeefCattle_Muzzle_database/BeefCattle_Muzzle_Individualized')

def create(root=ROOT):
    samples, counts, seen = [], {}, {}
    for animal in ['cattle_0100', 'cattle_0200', 'cattle_0300']:
        files = sorted((root / animal).glob('*.jpg'))
        counts[animal] = len(files)
        if len(files) < 7:
            raise ValueError(f'{animal} needs seven distinct images')
        for index, path in enumerate(files[:7]):
            with Image.open(path) as image:
                image.load()
                pixels = ImageOps.exif_transpose(image).convert('RGB')
                pixel_hash = hashlib.sha256(str(pixels.size).encode() + pixels.tobytes()).hexdigest()
                fmt, size = image.format, image.size
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest in seen or pixel_hash in seen:
                raise ValueError(f'Duplicate image: {path}')
            seen[digest] = seen[pixel_hash] = str(path)
            samples.append(dict(animal=animal, path=str(path.relative_to(root)),
                                role='enrollment' if index < 5 else 'probe',
                                sha256=digest, pixel_sha256=pixel_hash, format=fmt, size=size))
    return dict(seed='lexical-first-seven-v1', counts=counts, samples=samples,
                notes='C is unknown initially; its five enrollment files are reserved for subsequent enrollment. No calibration identities in this split.')

if __name__ == '__main__':
    output = create()
    Path('demo_backend/selection.json').write_text(json.dumps(output, indent=2) + '\n')
    print(output['counts'])
