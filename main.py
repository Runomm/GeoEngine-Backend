from fastapi import FastAPI, UploadFile, File
import uvicorn

app = FastAPI(title="GeoEngine PoC")

@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    return {
        "status": "success",
        "filename": file.filename,
        "results": {
            "latitude": 0.0,
            "longitude": 0.0,
            "confidence": "low",
            "visual_elements": ["pending"],
            "reasoning": "System initialization phase."
        }
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
