import io

from PIL import Image

MAX_IMAGE_PIXELS = 40_000_000


class OCRDependencyError(RuntimeError):
    pass


class OCRProcessingError(RuntimeError):
    pass


def extract_image_text(content: bytes) -> str:
    try:
        import pytesseract
    except ImportError as exc:
        raise OCRDependencyError(
            "OCR requires the optional 'ocr' extra and Tesseract installed locally."
        ) from exc

    try:
        with Image.open(io.BytesIO(content)) as image:
            if image.width * image.height > MAX_IMAGE_PIXELS:
                raise OCRProcessingError("The image dimensions exceed the OCR limit.")
            return pytesseract.image_to_string(image)
    except pytesseract.TesseractNotFoundError as exc:
        raise OCRDependencyError(
            "OCR requires the Tesseract executable installed locally and available on PATH."
        ) from exc
    except OCRProcessingError:
        raise
    except (Image.DecompressionBombError, OSError, pytesseract.TesseractError) as exc:
        raise OCRProcessingError("Local image OCR failed.") from exc
