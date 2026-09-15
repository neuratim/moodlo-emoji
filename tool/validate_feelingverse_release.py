"""Validate packaged Feelingverse episodes and write production evidence."""

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re

from PIL import Image

# Text that went through a non-UTF-8 pipe: unrepresentable characters became
# "?" (or U+FFFD). A real question mark is never doubled or followed by a letter.
DAMAGED_TEXT = re.compile(r"\ufffd|\?\?|\?[^\W\d_]")

LOCALES = (
    "ar",
    "bn",
    "cs",
    "de",
    "en",
    "es",
    "fr",
    "hi",
    "id",
    "it",
    "ja",
    "ko",
    "pl",
    "pt",
    "ru",
    "tr",
    "vi",
    "zh",
)


def _caption(scene):
    dialogue = "\n".join(scene["dialogue"])
    return f"{scene['narration']}\n\n{dialogue}"


def _load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _validate_backdrop(backdrop):
    data = base64.b64decode(backdrop["data"], validate=True)
    assert len(data) == backdrop["bytes"]
    assert len(data) <= 64 * 1024
    assert hashlib.sha256(data).hexdigest() == backdrop["sha256"]
    with Image.open(io.BytesIO(data)) as image:
        assert image.size == (240, 135)


def _validate_narrative(narrative):
    """One backdrop per narrative, one per episode, and no damaged text."""
    _validate_backdrop(narrative["backdrop"])
    for episode in narrative["episodes"]:
        _validate_backdrop(episode["backdrop"])
    texts = [
        text
        for localization in narrative["localizations"].values()
        for text in (localization["title"], localization["description"])
    ] + [
        localization["title"]
        for episode in narrative["episodes"]
        for localization in episode["localizations"].values()
    ]
    damaged = [text for text in texts if DAMAGED_TEXT.search(text)]
    assert not damaged, f"encoding-damaged text: {damaged}"


def _validate_episode(
    root,
    catalogue_episode,
    catalogue_revision,
    narrative_id,
    narrative_number,
    number,
):
    episode_number = number - 100
    episode_id = f"N{narrative_number:02}E{episode_number:02}"
    episode_folder = f"E{episode_number:02}"
    production = root / "feelingverse/production" / narrative_id / episode_folder
    source = root / "feelingverse/source" / narrative_id / episode_folder
    delivery = root / "feelingverse" / narrative_id / "episodes" / episode_folder
    source_metadata = _load(source / f"{episode_id}.json")
    delivery_metadata = _load(delivery / f"{episode_id}.json")
    script = _load(production / "script.json")
    typesetting = _load(production / "typesetting.json")
    expected_names = [f"{episode_id}P{index:02}.png" for index in range(1, 8)]

    assert source_metadata["id"] == episode_id
    assert source_metadata["version"] == 1
    assert source_metadata["artworkHeightFraction"] == 0.72
    assert list(source_metadata["localizations"]) == list(LOCALES)
    assert [panel["image"] for panel in source_metadata["panels"]] == expected_names
    assert [panel["image"] for panel in delivery_metadata["panels"]] == expected_names
    assert sorted(path.name for path in source.glob("*.png")) == expected_names
    assert sorted(path.name for path in delivery.glob("*.png")) == expected_names
    assert source_metadata["localizations"]["en"]["captions"] == [
        _caption(scene) for scene in script
    ]
    for locale in LOCALES:
        localization = source_metadata["localizations"][locale]
        assert localization["title"].strip()
        assert len(localization["captions"]) == 7
        assert all(0 < len(caption) <= 1000 for caption in localization["captions"])

    cards = {card["id"]: card for card in typesetting["cards"]}
    panels = []
    for index, name in enumerate(expected_names):
        panel_id = name.removesuffix(".png")
        source_image = source / name
        delivery_image = delivery / name
        with Image.open(source_image) as image:
            assert image.mode == "RGB"
            assert image.size == (1200, 1500)
        with Image.open(delivery_image) as image:
            assert image.mode == "RGB"
            assert image.size == (1024, 1280)
        # Manifests name their panels without pinning them; the catalogue's
        # advisory fingerprints must describe the files actually published.
        delivery_bytes = delivery_image.stat().st_size
        delivery_sha256 = _sha256(delivery_image)
        assert set(delivery_metadata["panels"][index]) == {"altText", "image"}
        assert delivery_bytes <= 5 * 1024 * 1024
        assert catalogue_episode["files"][name] == delivery_sha256
        assert cards[panel_id]["cardSha256"] == _sha256(source_image)
        assert cards[panel_id]["lastTextBottom"] <= 1476
        panels.append(
            {
                "bytes": delivery_bytes,
                "id": panel_id,
                "sha256": delivery_sha256,
                "textBottom": cards[panel_id]["lastTextBottom"],
            }
        )

    episode_bytes = sum(
        path.stat().st_size for path in delivery.iterdir() if path.is_file()
    )
    assert catalogue_episode["files"][f"{episode_id}.json"] == _sha256(
        delivery / f"{episode_id}.json"
    )
    assert catalogue_episode["id"] == episode_id
    assert catalogue_episode["version"] == 1
    evidence = {
        "catalogueRevision": catalogue_revision,
        "downloadSize": [1024, 1280],
        "episodeBytes": episode_bytes,
        "episodeVersion": 1,
        "exactEnglishText": "PASS",
        "imageCount": 7,
        "locales": list(LOCALES),
        "panels": panels,
        "sourceSize": [1200, 1500],
        "status": "PASS",
    }
    (production / "validation.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Validated {episode_id}: {episode_bytes} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--end", default=125, type=int)
    parser.add_argument("--narrative-id", default="00-the-stolen-wonder")
    parser.add_argument("--narrative-number", default=0, type=int)
    parser.add_argument("--start", default=101, type=int)
    args = parser.parse_args()
    if not 101 <= args.start <= args.end <= 125:
        parser.error("episode range must satisfy 101 <= start <= end <= 125")

    root = Path(__file__).resolve().parents[1]
    catalogue = _load(root / "feelingverse/catalogue.json")
    assert catalogue["schema"] == 3
    narrative = next(
        narrative
        for narrative in catalogue["narratives"]
        if narrative["id"] == args.narrative_id
    )
    _validate_narrative(narrative)
    episodes = {episode["id"]: episode for episode in narrative["episodes"]}
    for number in range(args.start, args.end + 1):
        _validate_episode(
            root,
            episodes[f"N{args.narrative_number:02}E{number - 100:02}"],
            catalogue["revision"],
            args.narrative_id,
            args.narrative_number,
            number,
        )


if __name__ == "__main__":
    main()
