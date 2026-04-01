import os
import json
from fastapi import FastAPI, UploadFile, File
import uvicorn
from ai_agents.ocr_agent import extract_text
from ai_agents.cognitive_agent import analyze_image_context
from psdm_engine.plonk_runner import run_plonk_inference
from psdm_engine.intersection_logic import calculate_spatial_score

app = FastAPI(title="GeoEngine PoC")

@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    file_bytes = await file.read()

    ocr_text = extract_text(file_bytes)

    api_key = os.getenv("GEMINI_API_KEY")
    cognitive_analysis = analyze_image_context(file_bytes, api_key) if api_key else "{}"

    plonk_result = run_plonk_inference(file_bytes)

    # Parse country names from Gemini's JSON response
    try:
        cognitive_json = json.loads(cognitive_analysis)
        # Gemini returns a list of objects; extract any key that looks like a country name
        cognitive_countries = [
            entry.get("country") or entry.get("ülke") or ""
            for entry in (cognitive_json if isinstance(cognitive_json, list) else [])
        ]
        cognitive_countries = [c for c in cognitive_countries if c]
    except (json.JSONDecodeError, AttributeError):
        cognitive_countries = []

    spatial_results = calculate_spatial_score(plonk_result, cognitive_countries)

    return {
        "status": "success",
        "filename": file.filename,
        "ocr_extracted_text": ocr_text,
        "cognitive_analysis": cognitive_analysis,
        "plonk_spatial_distribution": plonk_result,
        "results": spatial_results,
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
