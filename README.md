# GeoEngine Backend

[Türkçe](README.tr.md)

GeoEngine tries to guess where a photo was taken. The idea comes from OSINT work: when an image has no GPS data, an analyst looks at signs, buildings, plants and so on, and narrows the location down step by step. GeoEngine automates a small part of that by combining a few independent guesses.

It's an early proof of concept, not a finished tool. This repo contains the FastAPI backend and a Flutter client (`app/`). The project proposal and the literature review are in [GeoEngine-web](https://github.com/Runomm/GeoEngine-web).

## How it works

`POST /analyze` takes an image and runs four steps in sequence:

1. **OCR:** Tesseract reads any text in the image.
2. **Gemini:** the image goes to Gemini with a prompt asking for likely countries and the reasons, returned as JSON. This step is skipped if `GEMINI_API_KEY` isn't set.
3. **PLONK:** the `nicolas-dufour/PLONK_YFCC` model predicts latitude and longitude from the image. It uses the GPU if there is one, and the model is unloaded after every request to free VRAM.
4. **Intersection:** GeoPandas and Shapely check whether the PLONK point falls inside one of the countries Gemini suggested (Natural Earth 1:110m borders). If it does, confidence is `high`; if not, `low`.

The response contains the raw output of each step plus the combined result:

```json
{
  "status": "success",
  "filename": "photo.jpg",
  "ocr_extracted_text": "...",
  "cognitive_analysis": "...",
  "plonk_spatial_distribution": { "type": "Feature", "geometry": { "type": "Point", "coordinates": [2.35, 48.85] } },
  "results": {
    "latitude": 48.85,
    "longitude": 2.35,
    "confidence": "high",
    "intersecting_countries": ["France"],
    "cognitive_candidates": ["France", "Belgium"]
  }
}
```

## Running the backend

You need Python 3, [Tesseract](https://github.com/tesseract-ocr/tesseract) installed on the system (`pytesseract` only wraps it), and ideally an NVIDIA GPU. PLONK also runs on the CPU, just slowly.

```bash
pip install -r requirements.txt
python main.py
```

The server listens on port 8000, and FastAPI's interactive docs are at `http://localhost:8000/docs`. To enable the Gemini step, set the `GEMINI_API_KEY` environment variable before starting it.

An internet connection is needed: the PLONK weights are downloaded from Hugging Face on the first request, and the country borders are downloaded on every request.

## The Flutter client

`app/` is a small Flutter client. You pick a photo and send it to `/analyze`, then see the predicted point on an OpenStreetMap map along with the raw JSON.

```bash
cd app
flutter pub get
flutter run
```

The backend address is hard-coded in `app/lib/main.dart`: `localhost:8000` on web and desktop, `10.0.2.2:8000` on the Android emulator.

## Known issues

- `ai_agents/cognitive_agent.py` still calls `gemini-1.5-flash`, which Google has retired. It needs to be changed to a current model before the Gemini step will work.
- Gemini's answer is parsed with `json.loads`. If the model wraps it in a Markdown code block, parsing fails, no candidate countries are used, and confidence ends up `low`.
- CORS isn't enabled on the backend, so the client can't reach it from a browser (`flutter run -d chrome`). The desktop and mobile builds aren't affected.
- PLONK is reloaded and the border file is downloaded again on every request, so each request is slow.
- The proposal also plans EXIF reading, shadow and sun-angle analysis, and a React/Leaflet web client. None of these are implemented.

## Layout

```
main.py                            FastAPI app and the /analyze endpoint
ai_agents/ocr_agent.py             Tesseract OCR
ai_agents/cognitive_agent.py       Gemini prompt
psdm_engine/plonk_runner.py        PLONK inference
psdm_engine/intersection_logic.py  point vs. country check
app/                               Flutter client
```

## Related repos

- [GeoEngine-web](https://github.com/Runomm/GeoEngine-web): proposal, literature review, presentation
- [GeoEngine-app](https://github.com/Runomm/GeoEngine-app): the first, minimal client
