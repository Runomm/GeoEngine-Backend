import base64
import io
import os
from PIL import Image
from pydantic import BaseModel, Field
from google import genai

# gemini-1.5-flash was shut down; GEMINI_MODEL switches models without code changes
DEFAULT_MODEL = "gemini-3.8-flash"

PROMPT = (
    "Sen bir OSINT uzmanısın. Bu fotoğraftaki mimari stili, bitki örtüsünü ve kültürel ipuçlarını analiz et. "
    "Fotoğrafın çekilmiş olabileceği ülkeleri olasılık sırasıyla listele; her biri için ülkenin İngilizce adını, "
    "ISO 3166-1 alpha-3 kodunu ve kısa bir gerekçe ver."
)

# Pillow format -> MIME type; everything else (JPEG, MPO from phones) is sent as JPEG
_MIME_TYPES = {"PNG": "image/png", "WEBP": "image/webp"}


class CountryGuess(BaseModel):
    country: str = Field(description="Country name in English, e.g. 'France'.")
    iso_a3: str = Field(description="ISO 3166-1 alpha-3 code, e.g. 'FRA'.")
    reason: str = Field(description="Short reason based on clues in the photo.")


class CountryGuesses(BaseModel):
    candidates: list[CountryGuess]


def analyze_image_context(image_bytes: bytes, api_key: str) -> str:
    img = Image.open(io.BytesIO(image_bytes))
    client = genai.Client(api_key=api_key)
    interaction = client.interactions.create(
        model=os.getenv("GEMINI_MODEL", DEFAULT_MODEL),
        input=[
            {
                "type": "image",
                "mime_type": _MIME_TYPES.get(img.format, "image/jpeg"),
                "data": base64.b64encode(image_bytes).decode("utf-8"),
            },
            {"type": "text", "text": PROMPT},
        ],
        response_format={
            "type": "text",
            "mime_type": "application/json",
            "schema": CountryGuesses.model_json_schema(),
        },
    )
    return interaction.output_text or "{}"
