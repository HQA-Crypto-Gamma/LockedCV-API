#!/usr/bin/env python3
"""Graphics-aware PDF rebuild spike using pdfplumber word extraction."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

try:
    import pdfplumber
except ImportError:
    print("Missing dependency: pdfplumber")
    print("Install with: pip install pdfplumber")
    sys.exit(0)

try:
    from reportlab.lib.colors import Color
    from reportlab.pdfbase.pdfmetrics import stringWidth
    from reportlab.pdfgen import canvas
except ImportError:
    print("Missing dependency: reportlab")
    print("Install with: pip install reportlab")
    sys.exit(0)


ROOT_DIR = Path(__file__).resolve().parents[1]
INPUT_PATH = ROOT_DIR / "spec/fixtures/files/fake_resume_alan.pdf"
OUTPUT_DIR = ROOT_DIR / "tools/output"
OUTPUT_PATH = OUTPUT_DIR / "alan_rebuild_pdfplumber_graphics_label_masked.pdf"
GRAPHICS_PATH = OUTPUT_DIR / "alan_pdfplumber_graphics.json"
STRATEGY_NAME = "pdfplumber graphics-aware rebuild with bbox-preserving gray masks"
DRAW_LABEL_TEXT = False
LABELS = {
    "full_name": "NAME",
    "first_name": "NAME",
    "email": "EMAIL",
    "phone": "TEL",
    "id_number": "ID",
}
SHORT_LABELS = {
    "NAME": "NM",
    "EMAIL": "MAIL",
    "TEL": "TEL",
    "ID": "ID",
}
SENSITIVE_PATTERNS = [
    {
        "value": "Alan Turing",
        "kind": "full_name",
        "label": LABELS["full_name"],
    },
    {
        "value": "Alan",
        "kind": "first_name",
        "label": LABELS["first_name"],
    },
    {
        "value": "alan@example.com",
        "kind": "email",
        "label": LABELS["email"],
    },
    {
        "value": "0912-000-002",
        "kind": "phone",
        "label": LABELS["phone"],
    },
    {
        "value": "B987654321",
        "kind": "id_number",
        "label": LABELS["id_number"],
    },
]
SENSITIVE_VALUES = [pattern["value"] for pattern in SENSITIVE_PATTERNS]
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
    "pts",
]
HORIZONTAL_TOLERANCE = 1.5
THIN_RECTANGLE_LIMIT = 2.0


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    pages = extract_pages()
    labels = mark_sensitive_words(pages)
    GRAPHICS_PATH.write_text(json.dumps(graphics_json(pages), indent=2), encoding="utf-8")

    restore_counts = rebuild_pdf(pages, labels)
    presence = sensitive_presence(OUTPUT_PATH)

    word_count = sum(len(page["words"]) for page in pages)
    sensitive_word_count = sum(1 for page in pages for word in page["words"] if word["sensitive"])
    line_count = sum(len(page["lines"]) for page in pages)
    rect_count = sum(len(page["rects"]) for page in pages)
    curve_count = sum(len(page["curves"]) for page in pages)

    print(f"Input path: {INPUT_PATH}")
    print(f"Output path: {OUTPUT_PATH}")
    print(f"Graphics JSON path: {GRAPHICS_PATH}")
    print(f"Strategy name: {STRATEGY_NAME}")
    print(f"Number of pages processed: {len(pages)}")
    print(f"Number of words/chars extracted: {word_count} words")
    print(f"Number of sensitive phrases matched: {len(labels)}")
    print(f"Number of original sensitive tokens skipped: {sensitive_word_count}")
    print(f"Number of labels drawn: {len(labels) if DRAW_LABEL_TEXT else 0}")
    print(f"Number of gray masks drawn: {len(labels)}")
    print(f"Number of lines extracted: {line_count}")
    print(f"Number of rects extracted: {rect_count}")
    print(f"Number of curves extracted: {curve_count}")
    print(f"Number of vector lines restored: {restore_counts['lines']}")
    print(f"Number of vector rects restored: {restore_counts['rects']}")
    print(f"Whether output file was created: {OUTPUT_PATH.exists()}")
    print("Label bbox debug:")
    for label in labels:
        x0, top, x1, bottom = label["bbox"]
        print(
            f"  LABEL {label['kind']} {label['label']} page={label['page_number']} "
            f"bbox=({x0:.2f}, {top:.2f}, {x1:.2f}, {bottom:.2f})"
        )
    print("Sensitive value text-layer check results:")
    for value, found in presence.items():
        print(f"  {value}: {'FOUND' if found else 'not found'}")
    print("Curves were extracted for inspection but not restored in the rebuilt PDF.")


def extract_pages() -> list[dict[str, Any]]:
    pages = []
    with pdfplumber.open(INPUT_PATH) as pdf:
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
        "match_id": None,
    }


def graphic_data(graphic: dict[str, Any]) -> dict[str, Any]:
    return {field: clean_json_value(graphic[field]) for field in GRAPHIC_FIELDS if field in graphic}


def clean_json_value(value: Any) -> Any:
    if isinstance(value, (int, float, str)) or value is None:
        return value
    if isinstance(value, tuple):
        return [clean_json_value(item) for item in value]
    if isinstance(value, list):
        return [clean_json_value(item) for item in value]
    if isinstance(value, dict):
        return {str(key): clean_json_value(item) for key, item in value.items()}
    return str(value)


def graphics_json(pages: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "pages": [
            {
                "page_number": page["page_number"],
                "width": page["width"],
                "height": page["height"],
                "lines": page["lines"],
                "rects": page["rects"],
                "curves": page["curves"],
            }
            for page in pages
        ]
    }


def mark_sensitive_words(pages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    labels = []
    for page in pages:
        words = page["words"]
        for pattern in sorted(SENSITIVE_PATTERNS, key=pattern_priority, reverse=True):
            labels.extend(match_pattern(page, words, pattern))
    return labels


def pattern_priority(pattern: dict[str, str]) -> tuple[int, int]:
    return (len(pattern["value"].split()), len(pattern["value"]))


def match_pattern(page: dict[str, Any], words: list[dict[str, Any]], pattern: dict[str, str]) -> list[dict[str, Any]]:
    labels = []
    tokens = pattern["value"].lower().split()
    token_count = len(tokens)
    for index in range(0, len(words) - token_count + 1):
        candidate = words[index : index + token_count]
        if any(word["sensitive"] for word in candidate):
            continue
        if not candidate_matches(candidate, tokens):
            continue
        for word in candidate:
            word["sensitive"] = True
            word["match_id"] = len(labels)
        labels.append(label_data(page, candidate, pattern))
    return labels


def candidate_matches(words: list[dict[str, Any]], tokens: list[str]) -> bool:
    if len(tokens) == 1:
        return tokens[0] in words[0]["text"].lower()
    return [trim_word(word["text"]).lower() for word in words] == tokens and same_line(words)


def trim_word(text: str) -> str:
    return text.strip(".,;:()[]{}|")


def label_data(page: dict[str, Any], words: list[dict[str, Any]], pattern: dict[str, str]) -> dict[str, Any]:
    return {
        "page_number": page["page_number"],
        "kind": pattern["kind"],
        "label": pattern["label"],
        "bbox": merged_bbox(words),
        "source_text": " ".join(word["text"] for word in words),
        "fontname": words[0]["fontname"],
        "size": max(float(word["size"]) for word in words),
    }


def merged_bbox(words: list[dict[str, Any]]) -> tuple[float, float, float, float]:
    return (
        min(float(word["x0"]) for word in words),
        min(float(word["top"]) for word in words),
        max(float(word["x1"]) for word in words),
        max(float(word["bottom"]) for word in words),
    )


def same_line(words: list[dict[str, Any]]) -> bool:
    tops = [word["top"] for word in words]
    bottoms = [word["bottom"] for word in words]
    return max(tops) - min(tops) <= 2.0 and max(bottoms) - min(bottoms) <= 2.0


def rebuild_pdf(pages: list[dict[str, Any]], labels: list[dict[str, Any]]) -> dict[str, int]:
    pdf = canvas.Canvas(str(OUTPUT_PATH), pagesize=(pages[0]["width"], pages[0]["height"]))
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


def labels_by_page_number(labels: list[dict[str, Any]]) -> dict[int, list[dict[str, Any]]]:
    grouped: dict[int, list[dict[str, Any]]] = {}
    for label in labels:
        grouped.setdefault(int(label["page_number"]), []).append(label)
    return grouped


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
    if not DRAW_LABEL_TEXT:
        return

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


def draw_word(pdf: canvas.Canvas, page: dict[str, Any], word: dict[str, Any]) -> None:
    font = "Helvetica-Bold" if "bold" in word["fontname"].lower() else "Helvetica"
    pdf.setFillColor(Color(0, 0, 0))
    pdf.setFont(font, word["size"])
    # pdfplumber word boxes use top-based coordinates. ReportLab draws text
    # from a bottom-left baseline, so bottom is converted back from page height.
    pdf.drawString(word["x0"], page["height"] - word["bottom"], f"{word['text']} ")


def draw_lines(pdf: canvas.Canvas, page: dict[str, Any]) -> int:
    restored = 0
    for line in page["lines"]:
        if not horizontal_line(line):
            continue
        pdf.setStrokeColor(color_for(line.get("stroking_color")))
        pdf.setLineWidth(float(line.get("linewidth") or 1))
        # For horizontal dividers, use the center of the top/bottom box when
        # available. This converts pdfplumber's top-origin y to ReportLab's
        # bottom-origin y while preserving x coordinates.
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
        # ReportLab rectangles are drawn from the lower-left corner. pdfplumber
        # exposes top/bottom from the upper-left, so bottom maps to page_height - bottom.
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


def sensitive_presence(path: Path) -> dict[str, bool]:
    if not path.exists():
        return {value: False for value in SENSITIVE_VALUES}
    with pdfplumber.open(path) as pdf:
        text = "\n".join(page.extract_text() or "" for page in pdf.pages).lower()
    return {value: value.lower() in text for value in SENSITIVE_VALUES}


if __name__ == "__main__":
    main()
