"""Typeset the assignment's exact copy beneath reviewed, unlettered artwork.

Run from the emoji repository. --prepare extracts the seven complete renderer
packets without touching finished cards. Pillow only frames and typesets approved
art; visual corrections belong in the image generator.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFont


def extract_chapter(root):
    assignment = root / "movies/feelingverse_movie_assignments_101_125_v2_precise.md"
    text = assignment.read_text(encoding="utf-8")
    chapter = text.split("## Assignment 101 —", 1)[1].split("## Assignment 102 —", 1)[0]
    scenes = []
    for index, section in enumerate(chapter.split("### Image ")[1:], 1):
        copy = section.split("**EXACT TEXT", 1)[1].split(
            "**Viewer must understand:", 1
        )[0]
        narration, dialogue = copy.split("**Dialogue**", 1)
        narration = " ".join(re.findall(r"^> (.+)$", narration, re.MULTILINE))
        dialogue = [
            line.replace("**", "")
            for line in re.findall(r"^> (.+)$", dialogue, re.MULTILINE)
        ]
        packet = re.search(r"```text\s*(.*?)\s*```", section, re.DOTALL).group(1)
        assert narration and dialogue and f"SCENE 101.{index}" in packet
        scenes.append(
            {
                "dialogue": dialogue,
                "id": f"s101_p{index:02}",
                "narration": narration,
                "packet": packet,
            }
        )
    assert len(scenes) == 7
    return assignment, scenes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    assignment, scenes = extract_chapter(root)
    production = root / "movies/production/feelingverse/s101"
    prompts = production / "prompts"
    prompts.mkdir(parents=True, exist_ok=True)
    for scene in scenes:
        (prompts / f"{scene['id']}.txt").write_text(
            scene["packet"] + "\n", encoding="utf-8"
        )
    script = [
        {key: value for key, value in scene.items() if key != "packet"}
        for scene in scenes
    ]
    (production / "script.json").write_text(
        json.dumps(script, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if args.prepare:
        print("Extracted seven complete scene packets and exact English text blocks.")
        return

    font_root = root.parent / "app/assets/fonts"
    font_pixels, line_height = 40, 52
    normal = ImageFont.truetype(str(font_root / "Manrope-Regular.ttf"), font_pixels)
    spoken = ImageFont.truetype(str(font_root / "Manrope-SemiBold.ttf"), font_pixels)
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    layouts = []
    for scene in scenes:
        art_path = production / "art" / f"{scene['id']}.png"
        with Image.open(art_path) as original:
            original.load()
            # Explicit center framing: never distort bodies to fill the viewport.
            width, height = original.size
            target_ratio = 10 / 9
            crop_width = min(width, round(height * target_ratio))
            crop_height = min(height, round(width / target_ratio))
            left, top = (width - crop_width) // 2, (height - crop_height) // 2
            crop = (left, top, left + crop_width, top + crop_height)
            framed = (
                original.convert("RGB")
                .crop(crop)
                .resize((1200, 1080), Image.Resampling.LANCZOS)
            )
        card = Image.new("RGB", (1200, 1500), "#15242c")
        card.paste(framed, (0, 0))
        draw = ImageDraw.Draw(card)
        y = 1110
        blocks = []
        for index, paragraph in enumerate([scene["narration"], *scene["dialogue"]]):
            font = normal if index == 0 else spoken
            lines = wrap(paragraph, font, 1104)
            blocks.append({"lines": lines, "text": paragraph, "top": y})
            for line in lines:
                if y + line_height > 1476:
                    raise ValueError(
                        f"{scene['id']}: caption would clip; recompose before acceptance"
                    )
                draw.text(
                    (48, y),
                    line,
                    anchor="lt",
                    fill="#f4f0e6" if index == 0 else "#bde5df",
                    font=font,
                )
                y += line_height
            y += 16 if index == 0 else 8
        output = root / "movies/source/feelingverse/s101" / f"{scene['id']}.png"
        card.save(output, icc_profile=profile, optimize=True)
        layouts.append(
            {
                "artSha256": hashlib.sha256(art_path.read_bytes()).hexdigest(),
                "blocks": blocks,
                "cardSha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "crop": crop,
                "fontPixels": font_pixels,
                "id": scene["id"],
                "lastTextBottom": y - 8,
                "sourceSize": [width, height],
            }
        )
        print(f"Composed {output.name}: last text bottom {y - 8}/1476")
    record = {
        "assignmentSha256": hashlib.sha256(assignment.read_bytes()).hexdigest(),
        "cards": layouts,
    }
    (production / "typesetting.json").write_text(
        json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def wrap(paragraph, font, width):
    lines = []
    line = ""
    for word in paragraph.split():
        candidate = f"{line} {word}".strip()
        if font.getlength(candidate) <= width:
            line = candidate
        else:
            if not line or font.getlength(word) > width:
                raise ValueError("A word cannot fit the caption band")
            lines.append(line)
            line = word
    lines.append(line)
    assert " ".join(lines) == paragraph
    return lines


if __name__ == "__main__":
    main()
