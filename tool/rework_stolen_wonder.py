"""Stage, review, and explicitly install the revised Stolen Wonder narrative.

Existing cards remain the visual-design references, per the author's explicit
direction. Each review starts pending; extraction never certifies artwork.
"""

import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

from compose_feelingverse_cards import extract_chapter, wrap

ROOT = Path(__file__).resolve().parents[1]
NARRATIVE = "00-the-stolen-wonder"
MASTER = (
    ROOT.parent
    / "feelingverse-assets/the_stolen_wonder_v5"
    / "00_the_stolen_wonder_v3_1_reviewed_master.md"
)
PRODUCTION = ROOT / "feelingverse/production" / NARRATIVE / "revision-v5"

ALT_CORRECTIONS = {
    "N00E05P04": "Tangle is halfway through the return: one eye and part of the doubtful mouth have appeared on the amber face; the rest remains smooth beneath the crooked blue hat.",
    "N00E14P02": "Vex inserts the single square badge into the old service keyway while Hush checks the mechanism and Bitter supervises. The badge's chest clip is empty.",
    "N00E14P03": "The travelers are restrained inside the sealed white service pod with its copper interior. Rain and Beam sit beside the forward window; one seat remains empty for Nova.",
    "N00E14P04": "Bash demonstrates the manual brake beside the pod's cable mechanism. Quiver practices the sequence while Quest studies the brass route disk with its damaged hinge.",
    "N00E18P05": "Flare and Quiver remain on the Crown side of the latched transfer gate while the ground party departs. The rail and closed gate keep the two groups physically separated.",
    "N00E19P01": "Inside the descending white service pod, Rain steadies blank Beam's red support while golden Nova looks toward the mountain station. Beam's white visor remains on the same featureless body.",
    "N00E22P05": "Flare has freed the spindle collar and withdrawn the heated cuff. Pop waits beside the retaining pin, hands apart. The spindle remains connected beside an empty padded cradle.",
    "N00E23P03": "Nova opens all three signal shutters beneath the fixed conical prisms. Mend ties the final thread to a mounted ring; the original spool on the sash is bare.",
    "N00E23P05": "Pop draws the retaining pin by hand into its catch cup. Flare rests the completely removed spindle in the padded cradle, leaving a visible gap at the empty socket. Quest keeps the reel shield locked.",
    "N00E24P04": "Beam's golden original travels through the receiving cup and guarded diffuser to the same body on its red pad. One crescent eye and part of the mouth return while Rain steadies the pad and Nova checks the fixed prism.",
    "N00E24P05": "Beam has two familiar crescent eyes and a small, tired mouth again. Rain sits close on the red pad. Hope's wrinkled paper moth with one blue dot rests on the dry shelf.",
    "N00E24P06": "Six travelers are restrained inside the sealed returning pod. Quiver, Flare, Pop and Quest occupy the first row; Hush and Vex sit in the second. Quiver checks the brake; the remaining seats are empty.",
    "N00E25P04": "Gray Still sits neutrally on a garden bench. Lull adjusts a shade, Doze rests behind a tied-back curtain, and Sigh sits beside Wail and the one surviving seed jar. The exits remain open.",
    "N00E25P07": "One new unmarked paper moth rises from Nova toward the lantern tree. Rain's hands are empty beside restored Beam. Fizz, Guff, Flip, Fret, Grit, Alarm and Pop finish the supported lantern line behind them.",
}


def metadata():
    """Stage updated manifests; public files are changed only by install()."""
    import prepare_feelingverse_episodes as translation

    translation.PROPER_NAMES = tuple(
        sorted(set(translation.PROPER_NAMES) | {"Doze", "Fret", "Lull", "Manylight"})
    )
    narrative = json.loads((PRODUCTION / "narrative.json").read_text("utf-8"))
    cache_path = PRODUCTION / "translation-drafts.json"
    cache = json.loads(cache_path.read_text("utf-8"))
    edits = {
        path.stem: json.loads(path.read_text("utf-8"))
        for path in (PRODUCTION / "language-edits").glob("*.json")
    }
    alts = {}
    for episode in narrative["episodes"]:
        folder = PRODUCTION / episode["id"][3:]
        original = json.loads((folder / "original-manifest.json").read_text("utf-8"))
        for scene, panel in zip(episode["scenes"], original["panels"], strict=True):
            alts[scene["id"]] = ALT_CORRECTIONS.get(scene["id"], panel["altText"])
    write_json(PRODUCTION / "alt-texts.json", alts)
    for episode in narrative["episodes"]:
        folder = PRODUCTION / episode["id"][3:]
        manifest = json.loads((folder / "original-manifest.json").read_text("utf-8"))
        manifest["version"] += 1
        for locale in translation.LOCALES:

            def localized(value):
                return value if locale == "en" else cache[f"{locale}\0{value}"]

            values = {
                "captions": [localized(s["caption"]) for s in episode["scenes"]],
                "introduction": localized(episode["introduction"]),
                "title": localized(episode["title"]),
            }
            values.update(edits.get(locale, {}).get(episode["id"], {}))
            # The translated narration describes each scene accessibly and
            # preserves reviewed story facts without dialogue repetition.
            values["altTexts"] = [s.split("\n\n", 1)[0] for s in values["captions"]]
            manifest["localizations"][locale] = values
        for scene, panel in zip(episode["scenes"], manifest["panels"], strict=True):
            panel["altText"] = alts[scene["id"]]
        write_json(folder / f"{episode['id']}.json", manifest)
        print(f"{episode['id']}: metadata staged.", flush=True)


def install():
    """Check the complete reviewed staging tree before replacing public files."""
    from PIL import Image
    from prepare_feelingverse_episodes import LOCALES

    narrative = json.loads((PRODUCTION / "narrative.json").read_text("utf-8"))
    language_review = json.loads(
        (PRODUCTION / "language-review.json").read_text("utf-8")
    )
    if language_review["status"] != "PASS":
        raise ValueError("Language review is not complete")
    copies = []
    evidence = []
    previous = None
    for episode in narrative["episodes"]:
        episode_id = episode["id"]
        folder = PRODUCTION / episode_id[3:]
        public = ROOT / "feelingverse" / NARRATIVE / "episodes" / folder.name
        layouts = json.loads((folder / "typesetting.json").read_text("utf-8"))
        manifest_path = folder / f"{episode_id}.json"
        manifest = json.loads(manifest_path.read_text("utf-8"))
        if set(manifest["localizations"]) != set(LOCALES):
            raise ValueError(f"{episode_id}: expected exactly 18 locales")
        if hashlib.sha256(manifest_path.read_bytes()).hexdigest() != language_review[
            "manifestSha256"
        ].get(episode_id):
            raise ValueError(f"{episode_id}: metadata changed after language review")
        copies.append((manifest_path, public / manifest_path.name))
        for scene, layout, panel in zip(
            episode["scenes"], layouts, manifest["panels"], strict=True
        ):
            review = json.loads(
                (folder / f"{scene['id']}.review.json").read_text("utf-8")
            )
            if any(
                review[key] != "PASS"
                for key in ("artStatus", "cardStatus", "sequenceStatus")
            ):
                raise ValueError(f"{scene['id']}: review incomplete")
            if layout["status"] != "PASS":
                raise ValueError(f"{scene['id']}: typesetting review incomplete")
            if scene["previousId"] != previous:
                raise ValueError(f"{scene['id']}: broken sequence")
            previous = scene["id"]
            card = folder / "cards" / panel["image"]
            digest = hashlib.sha256(card.read_bytes()).hexdigest()
            if digest != layout["cardSha256"] or digest != review["reviewedCardSha256"]:
                raise ValueError(f"{scene['id']}: card changed after review")
            with Image.open(card) as image:
                if image.size != (1200, 1500) or not image.info.get("icc_profile"):
                    raise ValueError(
                        f"{scene['id']}: invalid dimensions or missing color profile"
                    )
            if card.stat().st_size > 5 * 1024 * 1024:
                raise ValueError(f"{scene['id']}: exceeds download byte limit")
            copies.append((card, public / card.name))
            evidence.append(
                {"bytes": card.stat().st_size, "id": scene["id"], "sha256": digest}
            )
        if manifest["localizations"]["en"]["captions"] != [
            s["caption"] for s in episode["scenes"]
        ]:
            raise ValueError(f"{episode_id}: English differs from reviewed master")
        for locale, values in manifest["localizations"].items():
            if len(values["captions"]) != 7 or any(
                not s.strip() or len(s) > 1000 for s in values["captions"]
            ):
                raise ValueError(f"{episode_id}/{locale}: invalid captions")
            if not values["title"].strip() or len(values["title"]) > 160:
                raise ValueError(f"{episode_id}/{locale}: invalid title")
            if len(values["altTexts"]) != 7 or any(
                not s.strip() or len(s) > 500 for s in values["altTexts"]
            ):
                raise ValueError(f"{episode_id}/{locale}: invalid accessibility text")
            if re.search(r"ZXQ|QXZ|\ufffd", json.dumps(values, ensure_ascii=False)):
                raise ValueError(f"{episode_id}/{locale}: damaged translation")
    if len(evidence) != 175 or len(copies) != 200:
        raise ValueError("Expected 175 cards and 25 manifests")
    for source, target in copies:
        backup = PRODUCTION / "original-public" / target.parent.name / target.name
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
        shutil.copy2(source, target)
        if (
            hashlib.sha256(source.read_bytes()).digest()
            != hashlib.sha256(target.read_bytes()).digest()
        ):
            raise ValueError(f"Copy verification failed: {target}")
    write_json(
        PRODUCTION / "installed.json",
        {
            "cards": evidence,
            "masterSha256": narrative["masterSha256"],
            "status": "PASS",
        },
    )
    print("Installed and hash-verified 175 cards and 25 manifests.")


def compose():
    """Typeset only episodes whose seven art reviews have actually passed."""
    from PIL import Image, ImageCms, ImageDraw, ImageFont

    fonts = ROOT.parent / "app/assets/fonts"
    normal = ImageFont.truetype(str(fonts / "Manrope-Regular.ttf"), 36)
    spoken = ImageFont.truetype(str(fonts / "Manrope-SemiBold.ttf"), 36)
    profile = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    narrative = json.loads((PRODUCTION / "narrative.json").read_text("utf-8"))
    for episode in narrative["episodes"]:
        folder = PRODUCTION / episode["id"][3:]
        reviews = [
            json.loads((folder / f"{scene['id']}.review.json").read_text("utf-8"))
            for scene in episode["scenes"]
        ]
        if any(review["artStatus"] != "PASS" for review in reviews):
            continue
        output = folder / "cards"
        output.mkdir(exist_ok=True)
        layouts = []
        for scene, review in zip(episode["scenes"], reviews, strict=True):
            selected = review.get("selectedArt") or review.get("artSource")
            if selected and not selected.startswith("art/"):
                selected = None
            art_path = (
                folder / selected
                if selected
                else ROOT
                / "feelingverse"
                / NARRATIVE
                / "episodes"
                / episode["id"][3:]
                / f"{scene['id']}.png"
            )
            with Image.open(art_path) as original:
                original.load()
                art = original.convert("RGB")
                if not selected:
                    # Existing public cards have 922 art pixels above captions.
                    art = art.crop((0, 0, 1024, 922))
                width, height = art.size
                crop_width = min(width, round(height * 10 / 9))
                crop_height = min(height, round(width * 9 / 10))
                left, top = (width - crop_width) // 2, (height - crop_height) // 2
                crop = (left, top, left + crop_width, top + crop_height)
                framed = art.crop(crop).resize((1200, 1080), Image.Resampling.LANCZOS)
            card = Image.new("RGB", (1200, 1500), "#15242c")
            card.paste(framed, (0, 0))
            draw = ImageDraw.Draw(card)
            blocks = []
            y = 1104
            for index, paragraph in enumerate([scene["narration"], *scene["dialogue"]]):
                font = normal if index == 0 else spoken
                lines = wrap(paragraph, font, 1104)
                blocks.append({"lines": lines, "text": paragraph, "top": y})
                for line in lines:
                    if y + 44 > 1476:
                        raise ValueError(f"{scene['id']}: caption overflow")
                    draw.text(
                        (48, y),
                        line,
                        anchor="lt",
                        font=font,
                        fill="#f4f0e6" if index == 0 else "#bde5df",
                    )
                    y += 44
                y += 8
            target = output / f"{scene['id']}.png"
            card.save(target, icc_profile=profile, optimize=True)
            layouts.append(
                {
                    "artSha256": hashlib.sha256(art_path.read_bytes()).hexdigest(),
                    "blocks": blocks,
                    "cardSha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                    "crop": crop,
                    "fontPixels": 36,
                    "id": scene["id"],
                    "lastTextBottom": y - 8,
                    "sourceSize": [width, height],
                    "status": "PENDING_VISUAL_REVIEW",
                }
            )
        write_json(folder / "typesetting.json", layouts)
        print(f"{episode['id']}: seven cards staged for visual review.")


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def prepare():
    text = MASTER.read_text(encoding="utf-8")
    episodes = []
    previous_id = None
    for number in range(101, 126):
        _, scenes = extract_chapter(MASTER, number, 0)
        episode_id = f"N00E{number - 100:02}"
        folder = f"E{number - 100:02}"
        published = ROOT / "feelingverse" / NARRATIVE / "episodes" / folder
        chapter = text.split(f"## Assignment {number} — ", 1)[1]
        title = chapter.splitlines()[0]
        chapter = chapter.split("\n## Assignment ", 1)[0]
        introduction = re.search(
            r"\*\*Episode introduction — reader-facing:\*\* (.+)", chapter
        ).group(1)
        episode = json.loads((published / f"{episode_id}.json").read_text("utf-8"))
        records = []
        for scene, section in zip(scenes, chapter.split("### Image ")[1:], strict=True):
            scene_id = scene["id"]
            target = PRODUCTION / folder
            target.mkdir(parents=True, exist_ok=True)
            packet = scene.pop("packet")
            # Preserve the supplied brief intact. Author overrides are recorded
            # separately and applied explicitly to actual render requests.
            (target / f"{scene_id}.prompt.txt").write_text(packet + "\n", "utf-8")
            (target / f"{scene_id}.editorial.md").write_text(
                "### Image " + section, "utf-8"
            )
            caption = scene["narration"] + "\n\n" + "\n".join(scene["dialogue"])
            bridge = re.search(
                r"CONTINUITY BRIDGE — WHERE / WHEN / WHY THIS CUT: (.+)", section
            ).group(1)
            action = re.search(
                r"FROZEN ACTION / BLOCKING / EVIDENCE: (.+)", packet
            ).group(1)
            evidence = re.search(
                r"MANDATORY POSITIVE PIXEL EVIDENCE: (.+)", packet
            ).group(1)
            scene.update(
                action=action,
                bridge=bridge,
                caption=caption,
                evidence=evidence,
                previousId=previous_id,
            )
            review_path = target / f"{scene_id}.review.json"
            if not review_path.exists():
                write_json(
                    review_path,
                    {
                        "artStatus": "PENDING",
                        "cardStatus": "PENDING",
                        "corrections": [],
                        "expectedEvidence": evidence,
                        "id": scene_id,
                        "observations": [],
                        "originalSha256": hashlib.sha256(
                            (published / f"{scene_id}.png").read_bytes()
                        ).hexdigest(),
                        "previousId": previous_id,
                        "sequenceStatus": "PENDING",
                    },
                )
            records.append(scene)
            previous_id = scene_id
        write_json(target / "script.json", records)
        episodes.append(
            {
                "id": episode_id,
                "introduction": introduction,
                "scenes": records,
                "title": title,
            }
        )
        if not (target / "original-manifest.json").exists():
            write_json(target / "original-manifest.json", episode)
    write_json(
        PRODUCTION / "narrative.json",
        {
            "authorOverrides": [
                "Preserve the current visual style and character designs; correct narrative and visual continuity.",
                "The recurring gray-apron resident retains the existing E24P03 gray body and apron in both E19P06 and E24P03; do not introduce the master's proposed terracotta redesign.",
            ],
            "episodes": episodes,
            "masterSha256": hashlib.sha256(MASTER.read_bytes()).hexdigest(),
            "status": "IN_PROGRESS",
        },
    )
    print(
        f"Staged {len(episodes)} episodes / {sum(len(e['scenes']) for e in episodes)} scenes at {PRODUCTION}"
    )


def translate():
    import prepare_feelingverse_episodes as translation

    translation.PROPER_NAMES = tuple(
        sorted(set(translation.PROPER_NAMES) | {"Doze", "Fret", "Lull", "Manylight"})
    )
    narrative = json.loads((PRODUCTION / "narrative.json").read_text("utf-8"))
    cache_path = PRODUCTION / "translation-drafts.json"
    cache = json.loads(cache_path.read_text("utf-8")) if cache_path.exists() else {}
    for episode in narrative["episodes"]:
        values = [
            episode["title"],
            episode["introduction"],
            *(scene["caption"] for scene in episode["scenes"]),
        ]
        cache = translation._translate_all(values, cache, cache_path)
        print(
            f"{episode['id']}: 17 translation drafts staged; human-language review pending.",
            flush=True,
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compose", action="store_true")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--metadata", action="store_true")
    parser.add_argument("--translate", action="store_true")
    args = parser.parse_args()
    if args.install:
        install()
    elif args.metadata:
        metadata()
    elif args.compose:
        compose()
    elif args.translate:
        translate()
    else:
        prepare()
