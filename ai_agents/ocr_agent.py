import io
from PIL import Image
import pytesseract

def extract_text(image_bytes: bytes) -> str:
    """Extract text from image bytes using Tesseract OCR.
    Returns the extracted string.
    """
    with io.BytesIO(image_bytes) as buf:
        img = Image.open(buf)
        return pytesseract.image_to_string(img)
