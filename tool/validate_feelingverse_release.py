"""Validate packaged Feelingverse episodes and write production evidence."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

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
        assert all(0 < len(caption) <= 400 for caption in localization["captions"])

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
        delivery_panel = delivery_metadata["panels"][index]
        assert delivery_panel["bytes"] == delivery_image.stat().st_size
        assert delivery_panel["sha256"] == _sha256(delivery_image)
        assert delivery_panel["bytes"] < 3 * 1024 * 1024
        assert cards[panel_id]["cardSha256"] == _sha256(source_image)
        assert cards[panel_id]["lastTextBottom"] <= 1476
        panels.append(
            {
                "bytes": delivery_panel["bytes"],
                "id": panel_id,
                "sha256": delivery_panel["sha256"],
                "textBottom": cards[panel_id]["lastTextBottom"],
            }
        )

    episode_bytes = sum(
        path.stat().st_size for path in delivery.iterdir() if path.is_file()
    )
    assert episode_bytes == catalogue_episode["bytes"]
    assert episode_bytes < 24 * 1024 * 1024
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
    narrative = next(
        narrative
        for narrative in catalogue["narratives"]
        if narrative["id"] == args.narrative_id
    )
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
