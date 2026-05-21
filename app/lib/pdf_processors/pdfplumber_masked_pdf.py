#!/usr/bin/env python3
"""Build a bbox-preserving masked PDF with pdfplumber and ReportLab.

Manual smoke test:

    mkdir -p tmp/pdfplumber_test
    cat > tmp/pdfplumber_test/alan_payload.json <<'JSON'
    {
      "sensitive_items": [
        {"field_name": "full_name", "value": "Alan Turing", "kind": "full_name", "label": "NAME"},
        {"field_name": "email", "value": "alan@example.com", "kind": "email", "label": "EMAIL"},
        {"field_name": "phone_number", "value": "0912-000-002", "kind": "phone", "label": "TEL"},
        {"field_name": "identification_number", "value": "B987654321", "kind": "id_number", "label": "ID"}
      ]
    }
    JSON

    python3 app/lib/pdf_processors/pdfplumber_masked_pdf.py \
      --input spec/fixtures/files/fake_resume_alan.pdf \
      --output tmp/pdfplumber_test/alan_processor_masked.pdf \
      --payload tmp/pdfplumber_test/alan_payload.json
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import pdfplumber
except ImportError:  # pragma: no cover - depends on local Python environment
    print("Missing dependency: pdfplumber. Install with: pip install pdfplumber reportlab", file=sys.stderr)
    sys.exit(2)

try:
    from reportlab.lib.colors import Color
    from reportlab.pdfbase.pdfmetrics import stringWidth
    from reportlab.pdfgen import canvas
except ImportError:  # pragma: no cover - depends on local Python environment
    print("Missing dependency: reportlab. Install with: pip install pdfplumber reportlab", file=sys.stderr)
    sys.exit(2)


DEFAULT_LABELS = {
    "full_name": "NAME",
    "first_name": "NAME",
    "last_name": "NAME",
    "email": "EMAIL",
    "phone": "TEL",
    "phone_number": "TEL",
    "id": "ID",
    "id_number": "ID",
    "identification_number": "ID",
}
SHORT_LABELS = {
    "NAME": "NM",
    "EMAIL": "MAIL",
    "TEL": "TEL",
    "ID": "ID",
}
GRAPHIC_FIELDS = [
    "x0",
    "x1",
    "y0",
    "y1",
    "top",
    "bottom",
    "width",
    "height",
    "linewidth",
    "stroking_color",
    "non_stroking_color",
]
HORIZONTAL_TOLERANCE = 1.5
THIN_RECTANGLE_LIMIT = 2.0


@dataclass(frozen=True)
class SensitiveItem:
    field_name: str
    value: str
    kind: str
    label: str


class ProcessorError(Exception):
    """Raised for clear command-line processor failures."""


def main() -> int:
    try:
        args = parse_args()
        process(input_path=args.input, output_path=args.output, payload_path=args.payload)
    except ProcessorError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a bbox-preserving masked PDF with pdfplumber.")
    parser.add_argument("--input", required=True, type=Path, help="Path to the source PDF.")
    parser.add_argument("--output", required=True, type=Path, help="Path to write the masked PDF.")
    parser.add_argument("--payload", required=True, type=Path, help="Path to masking payload JSON.")
    return parser.parse_args()


def process(input_path: Path, output_path: Path, payload_path: Path) -> None:
    validate_paths(input_path=input_path, output_path=output_path, payload_path=payload_path)
    sensitive_items = load_sensitive_items(payload_path)
    pages = extract_pages(input_path)
    labels = mark_sensitive_words(pages, sensitive_items)
    restore_counts = rebuild_pdf(pages, labels, output_path)

    print(f"Input path: {input_path}")
    print(f"Output path: {output_path}")
    print("Strategy name: pdfplumber bbox-preserving label processor")
    print(f"Number of pages processed: {len(pages)}")
    print(f"Number of words/chars extracted: {sum(len(page['words']) for page in pages)} words")
    print(f"Number of sensitive phrases matched: {len(labels)}")
    print(f"Number of original sensitive tokens skipped: {sum_sensitive_words(pages)}")
    print(f"Number of labels drawn: {len(labels)}")
    print(f"Number of vector lines restored: {restore_counts['lines']}")
    print(f"Number of vector rects restored: {restore_counts['rects']}")
    print(f"Whether output file was created: {output_path.exists()}")


def validate_paths(input_path: Path, output_path: Path, payload_path: Path) -> None:
    if not input_path.is_file():
        raise ProcessorError(f"input PDF does not exist: {input_path}")
    if not payload_path.is_file():
        raise ProcessorError(f"payload JSON does not exist: {payload_path}")
    if input_path.suffix.lower() != ".pdf":
        raise ProcessorError(f"input file must be a PDF: {input_path}")
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise ProcessorError(f"could not create output directory {output_path.parent}: {error}") from error


def load_sensitive_items(payload_path: Path) -> list[SensitiveItem]:
    try:
        payload = json.loads(payload_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ProcessorError(f"payload JSON is invalid: {error}") from error
    except OSError as error:
        raise ProcessorError(f"could not read payload JSON: {error}") from error

    raw_items = payload.get("sensitive_items")
    if not isinstance(raw_items, list):
        raise ProcessorError("payload must include sensitive_items as a list")

    items = []
    for index, raw_item in enumerate(raw_items):
        if not isinstance(raw_item, dict):
            raise ProcessorError(f"sensitive_items[{index}] must be an object")
        value = str(raw_item.get("value", "")).strip()
        if not value:
            continue
        kind = str(raw_item.get("kind") or raw_item.get("field_name") or "unknown").strip()
        field_name = str(raw_item.get("field_name") or kind).strip()
        label = str(raw_item.get("label") or DEFAULT_LABELS.get(kind, "MASK")).strip()
        items.append(SensitiveItem(field_name=field_name, value=value, kind=kind, label=label))

    return sorted(items, key=lambda item: (len(item.value.split()), len(item.value)), reverse=True)


def extract_pages(input_path: Path) -> list[dict[str, Any]]:
    pages = []
    try:
        with pdfplumber.open(input_path) as pdf:
            for page_number, page in enumerate(pdf.pages, start=1):
                words = page.extract_words(extra_attrs=["fontname", "size"], keep_blank_chars=False)
                pages.append(
                    {
                        "page_number": page_number,
                        "width": float(page.width),
                        "height": float(page.height),
                        "words": [word_data(word) for word in words],
                        "lines": [graphic_data(line) for line in page.lines],
                        "rects": [graphic_data(rect) for rect in page.rects],
                        "curves": [graphic_data(curve) for curve in page.curves],
                    }
                )
    except Exception as error:
        raise ProcessorError(f"could not read input PDF: {error}") from error
    return pages


def word_data(word: dict[str, Any]) -> dict[str, Any]:
    return {
        "text": word.get("text", ""),
        "x0": float(word.get("x0", 0)),
        "x1": float(word.get("x1", 0)),
        "top": float(word.get("top", 0)),
        "bottom": float(word.get("bottom", 0)),
        "fontname": word.get("fontname", ""),
        "size": float(word.get("size", 10) or 10),
        "sensitive": False,
    }


def graphic_data(graphic: dict[str, Any]) -> dict[str, Any]:
    return {field: clean_graphic_value(graphic[field]) for field in GRAPHIC_FIELDS if field in graphic}


def clean_graphic_value(value: Any) -> Any:
    if isinstance(value, (int, float, str)) or value is None:
        return value
    if isinstance(value, tuple):
        return [clean_graphic_value(item) for item in value]
    if isinstance(value, list):
        return [clean_graphic_value(item) for item in value]
    return str(value)


def mark_sensitive_words(
    pages: list[dict[str, Any]],
    sensitive_items: list[SensitiveItem],
) -> list[dict[str, Any]]:
    labels = []
    for page in pages:
        for item in sensitive_items:
            labels.extend(match_item(page, page["words"], item))
    return labels


def match_item(
    page: dict[str, Any],
    words: list[dict[str, Any]],
    item: SensitiveItem,
) -> list[dict[str, Any]]:
    labels = []
    tokens = item.value.lower().split()
    token_count = len(tokens)
    for index in range(0, len(words) - token_count + 1):
        candidate = words[index : index + token_count]
        if any(word["sensitive"] for word in candidate):
            continue
        if not candidate_matches(candidate, tokens):
            continue
        for word in candidate:
            word["sensitive"] = True
        labels.append(label_data(page, candidate, item))
    return labels


def candidate_matches(words: list[dict[str, Any]], tokens: list[str]) -> bool:
    if len(tokens) == 1:
        return tokens[0] in trim_word(words[0]["text"]).lower()
    return [trim_word(word["text"]).lower() for word in words] == tokens and same_line(words)


def trim_word(text: str) -> str:
    return text.strip(".,;:()[]{}|")


def same_line(words: list[dict[str, Any]]) -> bool:
    tops = [word["top"] for word in words]
    bottoms = [word["bottom"] for word in words]
    return max(tops) - min(tops) <= 2.0 and max(bottoms) - min(bottoms) <= 2.0


def label_data(
    page: dict[str, Any],
    words: list[dict[str, Any]],
    item: SensitiveItem,
) -> dict[str, Any]:
    return {
        "page_number": page["page_number"],
        "field_name": item.field_name,
        "kind": item.kind,
        "label": item.label,
        "bbox": merged_bbox(words),
        "source_text": " ".join(word["text"] for word in words),
    }


def merged_bbox(words: list[dict[str, Any]]) -> tuple[float, float, float, float]:
    return (
        min(float(word["x0"]) for word in words),
        min(float(word["top"]) for word in words),
        max(float(word["x1"]) for word in words),
        max(float(word["bottom"]) for word in words),
    )


def rebuild_pdf(
    pages: list[dict[str, Any]],
    labels: list[dict[str, Any]],
    output_path: Path,
) -> dict[str, int]:
    try:
        pdf = canvas.Canvas(str(output_path), pagesize=(pages[0]["width"], pages[0]["height"]))
        restored = {"lines": 0, "rects": 0}
        labels_by_page = labels_by_page_number(labels)

        for page_index, page in enumerate(pages):
            if page_index > 0:
                pdf.showPage()
            pdf.setPageSize((page["width"], page["height"]))
            restored["lines"] += draw_lines(pdf, page)
            restored["rects"] += draw_rectangles(pdf, page)
            for label in labels_by_page.get(page["page_number"], []):
                draw_label(pdf, page, label)
            for word in page["words"]:
                if word["sensitive"]:
                    continue
                draw_word(pdf, page, word)

        pdf.save()
        return restored
    except Exception as error:
        raise ProcessorError(f"could not write masked PDF: {error}") from error


def labels_by_page_number(labels: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for label in labels:
        grouped.setdefault(int(label["page_number"]), []).append(label)
    return grouped


def draw_word(pdf: canvas.Canvas, page: dict[str, Any], word: dict[str, Any]) -> None:
    font = "Helvetica-Bold" if "bold" in word["fontname"].lower() else "Helvetica"
    pdf.setFillColor(Color(0, 0, 0))
    pdf.setFont(font, word["size"])
    # pdfplumber word boxes use top-based coordinates. ReportLab draws text
    # from a bottom-left baseline, so bottom is converted back from page height.
    pdf.drawString(word["x0"], page["height"] - word["bottom"], f"{word['text']} ")


def draw_label(pdf: canvas.Canvas, page: dict[str, Any], label: dict[str, Any]) -> None:
    x0, top, x1, bottom = label["bbox"]
    width = x1 - x0
    height = bottom - top
    if width <= 0 or height <= 0:
        return

    pdf_y = page["height"] - bottom
    pdf.setStrokeColor(Color(0.68, 0.68, 0.68))
    pdf.setFillColor(Color(0.90, 0.90, 0.90))
    pdf.setLineWidth(0.4)
    pdf.rect(x0, pdf_y, width, height, stroke=1, fill=1)

    text, font_size = fitted_label(label["label"], width, height)
    font = "Helvetica-Bold"
    text_width = stringWidth(text, font, font_size)
    text_x = x0 + max((width - text_width) / 2.0, 0)
    text_y = pdf_y + max((height - font_size) / 2.0, 0) + (font_size * 0.18)
    pdf.setFillColor(Color(0.12, 0.12, 0.12))
    pdf.setFont(font, font_size)
    pdf.drawString(text_x, text_y, text)


def fitted_label(label: str, width: float, height: float) -> tuple[str, float]:
    font = "Helvetica-Bold"
    text = label
    font_size = max(min(height * 0.72, 9.0), 4.0)
    while font_size > 4.0 and stringWidth(text, font, font_size) > width - 2:
        font_size -= 0.5
    if stringWidth(text, font, font_size) <= width - 2:
        return text, font_size

    text = SHORT_LABELS.get(label, label[:2])
    while font_size > 3.0 and stringWidth(text, font, font_size) > width - 2:
        font_size -= 0.5
    return text, max(font_size, 3.0)


def draw_lines(pdf: canvas.Canvas, page: dict[str, Any]) -> int:
    restored = 0
    for line in page["lines"]:
        if not horizontal_line(line):
            continue
        pdf.setStrokeColor(color_for(line.get("stroking_color")))
        pdf.setLineWidth(float(line.get("linewidth") or 1))
        top = float(line.get("top", 0))
        bottom = float(line.get("bottom", top))
        pdf_y = page["height"] - ((top + bottom) / 2.0)
        pdf.line(float(line.get("x0", 0)), pdf_y, float(line.get("x1", 0)), pdf_y)
        restored += 1
    return restored


def draw_rectangles(pdf: canvas.Canvas, page: dict[str, Any]) -> int:
    restored = 0
    for rect in page["rects"]:
        width = float(rect.get("width") or abs(float(rect.get("x1", 0)) - float(rect.get("x0", 0))))
        height = float(rect.get("height") or abs(float(rect.get("bottom", 0)) - float(rect.get("top", 0))))
        if width > THIN_RECTANGLE_LIMIT and height > THIN_RECTANGLE_LIMIT:
            continue
        x0 = float(rect.get("x0", 0))
        top = float(rect.get("top", 0))
        pdf_y = page["height"] - float(rect.get("bottom", top + height))
        pdf.setStrokeColor(color_for(rect.get("stroking_color")))
        pdf.setFillColor(color_for(rect.get("non_stroking_color"), fallback=(0.85, 0.85, 0.85)))
        pdf.setLineWidth(float(rect.get("linewidth") or 1))
        pdf.rect(x0, pdf_y, width, height, stroke=1, fill=1)
        restored += 1
    return restored


def horizontal_line(line: dict[str, Any]) -> bool:
    if "y0" in line and "y1" in line and abs(float(line["y0"]) - float(line["y1"])) <= HORIZONTAL_TOLERANCE:
        return True
    if "top" in line and "bottom" in line and abs(float(line["bottom"]) - float(line["top"])) <= HORIZONTAL_TOLERANCE:
        return True
    return False


def color_for(value: Any, fallback: tuple[float, float, float] = (0.75, 0.75, 0.75)) -> Color:
    if isinstance(value, list) and len(value) >= 3:
        return Color(float(value[0]), float(value[1]), float(value[2]))
    if isinstance(value, tuple) and len(value) >= 3:
        return Color(float(value[0]), float(value[1]), float(value[2]))
    return Color(*fallback)


def sum_sensitive_words(pages: list[dict[str, Any]]) -> int:
    return sum(1 for page in pages for word in page["words"] if word["sensitive"])


if __name__ == "__main__":
    sys.exit(main())
