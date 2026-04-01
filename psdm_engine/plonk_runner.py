import io
import gc
import torch
from PIL import Image
from plonk import PlonkPipeline

def run_plonk_inference(image_bytes: bytes) -> dict:
    device = "cuda" if torch.cuda.is_available() else "cpu"

    pipeline = PlonkPipeline.from_pretrained("nicolas-dufour/PLONK_YFCC")
    pipeline = pipeline.to(device)

    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    gps_coords = pipeline([img], batch_size=1)

    # VRAM cleanup
    del pipeline
    del img
    gc.collect()
    if device == "cuda":
        torch.cuda.empty_cache()

    lat = float(gps_coords[0][0])
    lon = float(gps_coords[0][1])

    return {
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [lon, lat]
        },
        "properties": {
            "latitude": lat,
            "longitude": lon
        }
    }
