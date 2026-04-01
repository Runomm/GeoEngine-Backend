import io
from PIL import Image
import google.generativeai as genai

def analyze_image_context(image_bytes: bytes, api_key: str) -> str:
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-1.5-flash")
    img = Image.open(io.BytesIO(image_bytes))
    prompt = "Sen bir OSINT uzmanısın. Bu fotoğraftaki mimari stili, bitki örtüsünü ve kültürel ipuçlarını analiz et. Bana sadece JSON formatında olası ülkeleri ve sebeplerini dön. Başka hiçbir açıklama yazma."
    response = model.generate_content([img, prompt])
    return response.text
