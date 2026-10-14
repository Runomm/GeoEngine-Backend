import os
import json
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from ai_agents.ocr_agent import extract_text
from ai_agents.cognitive_agent import analyze_image_context
from psdm_engine.plonk_runner import run_plonk_inference
from psdm_engine.intersection_logic import calculate_spatial_score

app = FastAPI(title="GeoEngine PoC")

# The backend runs locally, so any origin may call it (the Flutter web client needs this)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    file_bytes = await file.read()

    ocr_text = extract_text(file_bytes)

    api_key = os.getenv("GEMINI_API_KEY")
    cognitive_analysis = "{}"
    cognitive_error = None
    if api_key:
        try:
            cognitive_analysis = analyze_image_context(file_bytes, api_key)
        except Exception as exc:
            # Bad key, quota, network...: carry on with OCR + PLONK only
            cognitive_error = str(exc)

    plonk_result = run_plonk_inference(file_bytes)

    # Gemini returns {"candidates": [{"country": ..., "iso_a3": ..., "reason": ...}, ...]}
    try:
        cognitive_json = json.loads(cognitive_analysis)
        entries = (cognitive_json.get("candidates") or []) if isinstance(cognitive_json, dict) else []
        cognitive_countries = [
            {"name": str(entry.get("country") or ""), "iso_a3": str(entry.get("iso_a3") or "")}
            for entry in entries
            if isinstance(entry, dict)
        ]
        cognitive_countries = [c for c in cognitive_countries if c["name"] or c["iso_a3"]]
    except json.JSONDecodeError:
        cognitive_countries = []

    spatial_results = calculate_spatial_score(plonk_result, cognitive_countries)

    return {
        "status": "success",
        "filename": file.filename,
        "ocr_extracted_text": ocr_text,
        "cognitive_analysis": cognitive_analysis,
        "cognitive_error": cognitive_error,
        "plonk_spatial_distribution": plonk_result,
        "results": spatial_results,
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
