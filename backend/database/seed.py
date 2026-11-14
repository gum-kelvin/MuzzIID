"""
Seed database with realistic livestock records according to project specification.
"""
import io
import os
import numpy as np
from PIL import Image, ImageDraw
from backend.database.db import db
from backend.models.biometric_engine import engine

def create_synthetic_muzzle_image(pattern_id: int = 1) -> bytes:
    """Creates a deterministic synthetic bovine muzzle image with dermatoglyphic ridge patterns."""
    im = Image.new("RGB", (320, 320), color=(140, 100, 70))
    draw = ImageDraw.Draw(im)
    # Draw characteristic dark muzzle border and nostril contours
    draw.ellipse([40, 60, 280, 260], fill=(80, 50, 35))
    draw.ellipse([70, 130, 130, 200], fill=(30, 20, 15))  # Left nostril
    draw.ellipse([190, 130, 250, 200], fill=(30, 20, 15)) # Right nostril
    # Dermatoglyphic ridges unique to pattern_id
    np.random.seed(pattern_id)
    for _ in range(40):
        x = np.random.randint(60, 260)
        y = np.random.randint(70, 250)
        r = np.random.randint(2, 6)
        color = (np.random.randint(40, 90), np.random.randint(25, 60), np.random.randint(15, 45))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)

    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=85)
    return buf.getvalue()

def seed_data():
    # 1. Spec Storyboard Primary Animal: UG-MBR-2026-04192
    img1 = create_synthetic_muzzle_image(pattern_id=4192)
    emb1 = engine.extract_embedding(img1)

    animal1 = {
        "id": "UG-MBR-2026-04192",
        "owner": "Katusiime Samuel",
        "district": "Mbarara",
        "location": "Kashari Sub-county, Mbarara",
        "breed": "Ankole-cross",
        "legacy_tag_id": "MBR-TAG-082",
        "created": "2026-05-10T08:30:00Z",
        "national_id": "CM89023100KL9",
        "phone": "+256772123456",
        "vaccinations": [
            {
                "id": "VAC-UG-MBR-2026-04192-FMD",
                "vaccine": "FMD",
                "administeredAt": "2026-01-15T09:00:00Z",
                "recordedAt": "2026-01-15T09:00:00Z",
                "validUntil": "2026-12-31T23:59:59Z",
                "batch": "FMD-UG-2026-B1",
                "gps": {"latitude": -0.6072, "longitude": 30.6545, "accuracyMeters": 4.5}
            },
            {
                "id": "VAC-UG-MBR-2026-04192-BRU",
                "vaccine": "Brucellosis",
                "administeredAt": "2026-02-10T11:00:00Z",
                "recordedAt": "2026-02-10T11:00:00Z",
                "validUntil": "2027-02-10T23:59:59Z",
                "batch": "BRU-2026-09",
                "gps": {"latitude": -0.6072, "longitude": 30.6545, "accuracyMeters": 4.5}
            }
        ]
    }
    db.add_animal(animal1, emb1)

    # 2. Second Animal in Mbarara: UG-MBR-2026-05201
    img2 = create_synthetic_muzzle_image(pattern_id=5201)
    emb2 = engine.extract_embedding(img2)
    animal2 = {
        "id": "UG-MBR-2026-05201",
        "owner": "Tumusiime Grace",
        "district": "Mbarara",
        "location": "Rwampara, Mbarara",
        "breed": "Ankole",
        "legacy_tag_id": "MBR-TAG-114",
        "created": "2026-06-12T10:15:00Z",
        "national_id": "CF92018274MM1",
        "phone": "+256782987654",
        "vaccinations": [
            {
                "id": "VAC-UG-MBR-2026-05201-LSD",
                "vaccine": "Lumpy skin",
                "administeredAt": "2026-03-01T10:00:00Z",
                "recordedAt": "2026-03-01T10:00:00Z",
                "validUntil": "2026-09-01T23:59:59Z",
                "batch": "LSD-2026-A4"
            }
        ]
    }
    db.add_animal(animal2, emb2)

    # 3. Third Animal in Masaka: UG-MSK-2026-01108
    img3 = create_synthetic_muzzle_image(pattern_id=1108)
    emb3 = engine.extract_embedding(img3)
    animal3 = {
        "id": "UG-MSK-2026-01108",
        "owner": "Mukasa Joseph",
        "district": "Masaka",
        "location": "Bukoto, Masaka",
        "breed": "Friesian-cross",
        "legacy_tag_id": "MSK-TAG-009",
        "created": "2026-07-04T14:20:00Z",
        "vaccinations": [
            {
                "id": "VAC-UG-MSK-2026-01108-ANT",
                "vaccine": "Anthrax",
                "administeredAt": "2026-05-18T08:30:00Z",
                "validUntil": "2027-05-18T23:59:59Z",
                "batch": "ANT-2026-C2"
            }
        ]
    }
    db.add_animal(animal3, emb3)

    print("Database seeded with sample district herds!")

if __name__ == "__main__":
    seed_data()
