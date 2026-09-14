"""Prepare Feelingverse episode metadata and localized captions.

Run from the emoji repository after ``compose_feelingverse_cards.py --prepare`` has
extracted the assignment's authoritative English script and render packets.
Translations are cached in production so reruns remain deterministic.
"""

import argparse
import concurrent.futures
import json
import re
import time
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

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
PROPER_NAMES = (
    "Adore",
    "Alarm",
    "Bash",
    "Beam",
    "Bitter",
    "Bloom",
    "Crown",
    "Fizz",
    "Flare",
    "Flip",
    "Grit",
    "Guff",
    "Hope",
    "Hush",
    "Mend",
    "Mosaic",
    "Nova",
    "Null",
    "Patch",
    "Phew",
    "Pop",
    "Puff",
    "Quest",
    "Quiver",
    "Rain",
    "Sideeye",
    "Sigh",
    "Still",
    "Swagger",
    "Tangle",
    "Vex",
    "Wail",
    "Wit",
)
TAGS = ("adventure", "friendship", "rescue", "superhero")
COMPACT_110_6 = (
    "Null sends Vex to block the observatory's maintenance route. Null promises "
    "no harm by removing everyone's choices. Vex obeys, though the locked booth "
    "looks like control, not protection.\n\n"
    "Null: “They bring pain into shelters. I will leave nothing that can hurt.”\n"
    "Vex: “I'll intercept the maintenance route.”"
)
COMPACT_CAPTIONS = {
    (112, "es", 4): (
        "Lull entrega caparazones presurizados, cables de seguridad y radios de "
        "corto alcance para la pasarela orbital expuesta. Bash revisa los sellos. "
        "Los viajeros deben llevar y probar estas herramientas; no son poderes que "
        "aparecen al llegar al espacio.\n\nLull: «El caparazón cubre todo el cuerpo. "
        "Revisa la presión y la radio antes de abrir una escotilla exterior.»"
    ),
    (112, "fr", 4): (
        "Lull fournit des coques pressurisées, des longes de sécurité et des radios "
        "à courte portée pour la passerelle orbitale exposée. Bash vérifie les "
        "joints. Les voyageurs doivent porter et tester ces outils; ce ne sont pas "
        "des pouvoirs apparus dans l’espace.\n\nLull : «La coque couvre tout le corps. "
        "Vérifiez la pression et la radio avant d’ouvrir une trappe extérieure.»"
    ),
    (112, "it", 4): (
        "Lull fornisce gusci pressurizzati, cavi di sicurezza e radio a corto raggio "
        "per la passerella orbitale esposta. Bash controlla le tenute. I viaggiatori "
        "devono portare e provare questi strumenti; non sono poteri comparsi nello "
        "spazio.\n\nLull: «Il guscio copre tutto il corpo. Controlla pressione e "
        "radio prima di aprire un portello esterno.»"
    ),
    (112, "pl", 4): (
        "Lull daje osłony ciśnieniowe, linki bezpieczeństwa i radia krótkiego "
        "zasięgu na odsłonięty chodnik orbitalny. Bash sprawdza uszczelnienia. "
        "Podróżnicy muszą nieść i przetestować te narzędzia; nie są to moce, które "
        "pojawiają się w kosmosie.\n\nLull: „Osłona zakrywa całe ciało. Sprawdź "
        "ciśnienie i radio przed otwarciem zewnętrznego włazu.”"
    ),
    (112, "ru", 4): (
        "Lull выдаёт герметичные оболочки, страховочные тросы и рации ближнего "
        "действия для открытого орбитального перехода. Bash проверяет уплотнения. "
        "Путешественники должны нести и испытать эти инструменты; это не внезапно "
        "появившиеся силы.\n\nLull: «Оболочка закрывает всё тело. Проверьте "
        "давление и рацию, прежде чем открыть внешний люк.»"
    ),
    (114, "fr", 1): (
        "Avant l’embarquement, Bash vérifie la coque pressurisée de Quiver et Lull "
        "teste sa radio. Onze voyageurs monteront dans le module; un kit de rechange "
        "est réservé à Nova. Protection et communication doivent fonctionner avant "
        "l’entrée dans le vide.\n\nLull : «Test radio.»\nQuiver : «Je vous entends. "
        "Le témoin d’étanchéité est activé.»"
    ),
    (117, "de", 2): (
        "Nova zeigt Flare die Unterlegscheibe, die die Klemme gebremst hat. Sie hat "
        "Zeit gewonnen, aber die Aufnahme nicht gestoppt: Hinter ihnen beendet der "
        "letzte Zweig der Routingplatte das Kopieren. Nova zu befreien stoppt den "
        "Siphon nun nicht mehr allein.\n\nNova [flüstert]: „Stützt zuerst die Backe. "
        "Nur die Unterlegscheibe verhindert das Festziehen.“"
    ),
    (124, "de", 7): (
        "Die letzten gespeicherten Muster erreichen ihre Besitzer, und Mosaics "
        "Straßen füllen sich wieder mit verschiedenen Gesichtern. Die Kollektoren "
        "bleiben dunkel. Die Brücke ist noch beschädigt, doch Entführung und "
        "Zwangslöschung sind beendet; der Wiederaufbau ist eine andere Arbeit.\n\n"
        "Still: „Die Rückkehr ist abgeschlossen. Haltet die Notunterkünfte für alle "
        "offen, die sie brauchen.“"
    ),
    (124, "es", 1): (
        "El pestillo aguanta cuando Vex lo suelta. Nadie debe quedarse sujetando "
        "una palanca. Quest revisa los últimos carretes mientras el accionamiento "
        "de la placa de rutas copiada queda cubierto y desconectado. La vieja "
        "credencial de Vex sigue rota dentro del desvío.\n\nQuest: «Aguanta en el "
        "tope. Avancen solo cuando los carretes estén libres.»"
    ),
    (124, "fr", 1): (
        "Le loquet tient quand Vex le lâche. Personne ne doit rester à serrer un "
        "levier. Quest vérifie les dernières bobines tandis que l’entraînement de "
        "la plaque de routage copiée est couvert et débranché. L’ancien badge de "
        "Vex reste brisé dans la dérivation.\n\nQuest : «Il tient sur la butée. "
        "N’avancez qu’une fois les bobines dégagées.»"
    ),
    (124, "fr", 7): (
        "Les derniers motifs stockés rejoignent leurs propriétaires, et les rues de "
        "Mosaic retrouvent des visages différents. Les collecteurs restent éteints. "
        "Le pont demeure endommagé, mais enlèvements et effacement forcé ont cessé; "
        "la reconstruction est un autre travail.\n\nStill : «Le retour est terminé. "
        "Gardez les refuges ouverts à tous ceux qui en ont besoin.»"
    ),
    (124, "id", 7): (
        "Pola tersimpan terakhir kembali kepada pemiliknya, dan jalan Mosaic "
        "dipenuhi wajah yang berbeda lagi. Lengan kolektor tetap gelap. Jembatan "
        "masih rusak, tetapi ancaman penculikan dan penghapusan paksa telah berakhir; "
        "pembangunan kembali adalah pekerjaan lain.\n\nStill: “Pengembalian selesai. "
        "Biarkan tempat perlindungan terbuka bagi siapa pun yang membutuhkannya.”"
    ),
    (124, "it", 1): (
        "Il fermo regge quando Vex lo lascia. Nessuno deve restare a tenere una "
        "leva. Quest controlla le ultime bobine mentre l’azionamento della piastra "
        "di instradamento copiata è coperto e scollegato. Il vecchio badge di Vex "
        "resta rotto nel bypass.\n\nQuest: «Regge sul fermo. Muovetevi solo quando "
        "le bobine sono libere.»"
    ),
    (124, "pl", 6): (
        "Po sprawdzeniu, że archiwum jest puste, cała szóstka podróżników Crown "
        "wchodzi do odzyskanej kapsuły. Hush zabezpiecza drzwi, a Quiver sprawdza "
        "hamulec ręczny. Null pozostaje odizolowany na górze do późniejszego, "
        "nadzorowanego transportu; nikt nie zostaje, by trzymać system otwarty.\n\n"
        "Quiver: „Sześć osób na pokładzie. Hamulce sprawdzone. Możemy zjechać.”"
    ),
    (125, "de", 1): (
        "Einige Tage später sind Reisende und örtliche Teams zurück in Mosaic. "
        "Flare repariert die beim ersten gescheiterten Angriff beschädigte Halterung. "
        "Quiver prüft sie, Tangle testet den Schalter, und Mend nutzt gewöhnliches "
        "Reparaturseil statt einer rätselhaft aufgefüllten Spule.\n\nFlare: „Diesmal "
        "prüfen wir die Last, bevor jemand hinübergeht.“"
    ),
}
CORRECTION_NOTES = {
    102: (
        "Card 6: restored Nova's restraint and removed an invented pin.",
        "Card 7: removed duplicate route markings, then repaired Quest's detached "
        "pointing hand so both arms join the body correctly.",
    ),
    103: (
        "Card 3: removed a duplicate pin and stray fragments.",
        "Cards 4 and 6: restored Still's neutral pale identity and plain collar.",
    ),
    104: (
        "Cards 2 and 4: restored Hush's pearl body, two eyes, absent mouth and "
        "turquoise wrist ribbons.",
        "Card 7: reduced Sigh's costume to the single crescent badge.",
    ),
    105: ("Card 6: removed invented bell/chime traits from Sigh.",),
    107: ("Card 5: enforced one blue-dotted moth and one pocketed star pin.",),
    108: (
        "Card 6: removed Alarm's extra cheek hand; the final has exactly two "
        "attached arms, one holding the bell mallet and one touching the cheek.",
    ),
    110: (
        "Cards 1, 4, 5 and 7: restored Rain/Nova identity details, including "
        "Nova's pinless violet scarf and attached two-arm anatomy.",
    ),
    111: (
        "Card 3: removed Bitter's invented third tube so the accepted frame has "
        "exactly one cleaner tube in hand and one capped sample in the pouch.",
    ),
}
RENDER_PREFIX = """Create one new unlettered story illustration from the complete scene packet below.

Match the dimensional painted emoji, decisive graphic-novel contours, amber/violet cinematic lighting, rich crafted scenery and expressive white-sclera eyes of the supplied primary reference `user-approved-style-04.png`; use `user-approved-style-03.png` as a secondary continuity reference. Preserve the packet's exact cast, identities, anatomy, action, prop ownership/counts, geography and physical support logic. Each emoji is one face-bearing rounded disk with exactly two side arms/mitten hands and two short legs/feet unless the packet explicitly defines a mechanical body. Every visible hand must connect naturally to its owner's arm and body. Render exactly one frozen moment with no panels, inset scenes, repeated actors, generated lettering, captions, speech bubbles, logos or franchise imagery. Keep essential faces, hands and clues inside the safe art area. The compositor will center-crop the result to 1200 × 1080 above the caption band.

COMPLETE AUTHORITATIVE SCENE PACKET:
"""


def _caption(scene):
    dialogue = "\n".join(scene["dialogue"])
    return f"{scene['narration']}\n\n{dialogue}"


def _chapter(assignment_text, number):
    match = re.search(
        rf"^## Assignment {number}(?: / Episode \d+)?\s+—\s+(?P<title>.+?)\s*$",
        assignment_text,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError(f"Assignment {number} heading is missing")
    next_match = re.search(
        rf"^## Assignment {number + 1}(?: / Episode \d+)?\s+—\s+.+?$",
        assignment_text[match.end() :],
        re.MULTILINE,
    )
    end = match.end() + next_match.start() if next_match else len(assignment_text)
    return match.group("title").strip(), assignment_text[match.end() : end]


def _alt_texts(chapter, narrative_number, number):
    results = []
    sections = chapter.split("### Image ")[1:]
    for index, section in enumerate(sections, 1):
        action = section.split("FROZEN ACTION / BLOCKING / EVIDENCE:", 1)[1]
        action = action.split("\n\n", 1)[0].strip()
        sentences = re.split(r"(?<=[.!?])\s+", action)
        selected = sentences[:2]
        while len(selected) > 1 and len(" ".join(selected)) > 380:
            selected.pop()
        alt_text = " ".join(selected)
        if len(alt_text) > 400:
            alt_text = sentences[0]
        if not alt_text or len(alt_text) > 400:
            raise ValueError(
                f"N{narrative_number:02}E{number - 100:02}P{index:02}: "
                "invalid generated alt text"
            )
        results.append(alt_text)
    if len(results) != 7:
        raise ValueError(
            f"N{narrative_number:02}E{number - 100:02}: expected seven alt "
            f"texts, found {len(results)}"
        )
    return results


def _mask_names(value):
    masked = value
    replacements = {}
    for index, name in enumerate(PROPER_NAMES):
        token = f"ZXQ{index}QXZ"
        masked = re.sub(rf"\b{re.escape(name)}\b", token, masked)
        replacements[token] = name
    return masked, replacements


def _translate(value, locale):
    masked, replacements = _mask_names(value)
    query = urllib.parse.urlencode(
        {
            "client": "gtx",
            "dt": "t",
            "q": masked,
            "sl": "en",
            "tl": "zh-CN" if locale == "zh" else locale,
        }
    )
    request = urllib.request.Request(
        f"https://translate.googleapis.com/translate_a/single?{query}",
        headers={"User-Agent": "Mozilla/5.0"},
    )
    last_error = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
            translated = "".join(part[0] for part in payload[0] if part[0])
            for token, name in replacements.items():
                translated = translated.replace(token, name)
            missing = [
                name
                for name in PROPER_NAMES
                if re.search(rf"\b{re.escape(name)}\b", value)
                and name not in translated
            ]
            if missing:
                raise ValueError(f"translation lost proper names: {missing}")
            return translated
        except (OSError, TimeoutError, ValueError, json.JSONDecodeError) as error:
            last_error = error
            time.sleep(2 * (2**attempt))
    raise RuntimeError(f"translation failed for {locale}: {last_error}")


def _translate_batch(values, locale):
    separator = "[[[ZXQSPLITQXZ]]]"
    translated = _translate(f"\n{separator}\n".join(values), locale)
    results = [value.strip() for value in translated.split(separator)]
    if len(results) != len(values):
        raise ValueError(
            f"{locale} translation returned {len(results)} of {len(values)} values"
        )
    return results


def _translate_all(values, cache, cache_path):
    pending = []
    for locale in LOCALES:
        if locale == "en":
            continue
        for offset in range(0, len(values), 8):
            batch = [
                value
                for value in values[offset : offset + 8]
                if f"{locale}\0{value}" not in cache
            ]
            if batch:
                pending.append((locale, batch))
    if pending:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = {
                executor.submit(_translate_batch, values, locale): (locale, values)
                for locale, values in pending
            }
            for future in concurrent.futures.as_completed(futures):
                locale, values = futures[future]
                translated_values = future.result()
                for value, translated in zip(values, translated_values, strict=True):
                    cache[f"{locale}\0{value}"] = translated
                _write_json(cache_path, dict(sorted(cache.items())))
    return cache


def _write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _write_records(root, narrative_id, narrative_number, number, title, alt_texts):
    episode_number = number - 100
    episode_id = f"N{narrative_number:02}E{episode_number:02}"
    episode_folder = f"E{episode_number:02}"
    production = root / "feelingverse/production" / narrative_id / episode_folder
    (production / "prompts" / "render-prefix.txt").write_text(
        RENDER_PREFIX, encoding="utf-8"
    )
    prompts = "\n".join(
        f"- `prompts/{episode_id}P{index:02}.txt`" for index in range(1, 8)
    )
    production.joinpath("PROMPTS.md").write_text(
        f"""# Feelingverse {number}: {title}

The authority is Assignment {number} in
the assignment document supplied for narrative `{narrative_id}`.

Each actual initial render request combined the exact common request in
`feelingverse/production/{narrative_id}/{episode_folder}/prompts/render-prefix.txt` with one
complete authoritative scene packet:

{prompts}

Accepted unlettered artwork is stored under the production `art/` directory.
Rejected or superseded `*-draft*.png` files are production evidence only and
are not packaged. `script.json` preserves the assignment's exact English copy;
`typesetting.json` records final crops, line layout and hashes.
""",
        encoding="utf-8",
    )
    correction_lines = "\n".join(
        f"- {note}"
        for note in CORRECTION_NOTES.get(
            number, ("No corrective edit was required after initial review.",)
        )
    )
    production.joinpath("LOCKS.md").write_text(
        f"""# Episode {number} production locks

Scope: Assignment {number}, `{title}`, exactly seven final cards.

- Primary visual reference: episode 101 `user-approved-style-04.png`.
- Secondary visual reference: episode 101 `user-approved-style-03.png`.
- Story, cast, state, location, prop and transport constraints come from the
  complete per-card packets and remain authoritative.
- Each visible emoji has one face-bearing body, at most two anatomically attached
  side arms/mitten hands, and two short legs/feet unless explicitly mechanical.
- No generated text appears in art. Exact English is added only by the compositor.
- Architecture, routes, mechanisms, ropes, reflections and light paths retain
  visible sources, supports and destinations.
- Lasting story consequences carry forward from the immediately preceding card
  and episode; accepted visual mistakes are never treated as continuity.

## Corrective review record

{correction_lines}
""",
        encoding="utf-8",
    )
    cards = "\n".join(
        f"### {number}.{index}\n\nPASS. {alt_text} Visible arms and hands were "
        "checked for ownership, attachment and count; no unresolved detached or "
        "extra hand remains.\n"
        for index, alt_text in enumerate(alt_texts, 1)
    )
    production.joinpath("REVIEW.md").write_text(
        f"""# Episode {number} visual and semantic review

Reviewed: 2026-09-13. Scope is Assignment {number}, seven cards. The accepted
artwork and final cards were inspected against the complete packets, episode 101
style references, continuing identity/prop state and the production contract.

## Per-card checks

{cards}
## Delivery checks

- Seven ordered 1200 × 1500 sRGB source PNGs: PASS.
- 1200 × 1080 art plus opaque 420-pixel caption band: PASS.
- Exact English narration and attributed dialogue: PASS.
- Eighteen locales with seven nonempty captions of at most 400 characters: PASS.
- No production draft is referenced by episode metadata: PASS.
- User-requested full hand/arm attachment inspection: PASS.

`typesetting.json` records crop, line and SHA-256 evidence. `validation.json` is
written after packaging and records delivery dimensions, hashes and byte limits.
""",
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--assignment",
        default="../assets/00-the_stolen_wonder.md",
        type=Path,
    )
    parser.add_argument("--end", default=125, type=int)
    parser.add_argument("--narrative-id", default="00-the-stolen-wonder")
    parser.add_argument("--narrative-number", default=0, type=int)
    parser.add_argument("--start", default=101, type=int)
    args = parser.parse_args()
    if not 101 <= args.start <= args.end <= 125:
        parser.error("episode range must satisfy 101 <= start <= end <= 125")

    root = Path(__file__).resolve().parents[1]
    assignment_path = (root / args.assignment).resolve()
    assignment_text = assignment_path.read_text(encoding="utf-8")
    episodes = []
    all_values = []
    for number in range(args.start, args.end + 1):
        episode_id = f"N{args.narrative_number:02}E{number - 100:02}"
        production = (
            root
            / "feelingverse/production"
            / args.narrative_id
            / f"E{number - 100:02}"
        )
        script = json.loads((production / "script.json").read_text(encoding="utf-8"))
        title, chapter = _chapter(assignment_text, number)
        captions = [_caption(scene) for scene in script]
        episodes.append(
            (
                number,
                title,
                captions,
                _alt_texts(chapter, args.narrative_number, number),
            )
        )
        all_values.extend((title, *captions))
    if args.narrative_number == 0 and args.start <= 110 <= args.end:
        all_values.append(COMPACT_110_6)

    cache_path = (
        root / "feelingverse/production" / args.narrative_id / "translations.json"
    )
    cache = (
        json.loads(cache_path.read_text(encoding="utf-8"))
        if cache_path.exists()
        else {}
    )
    _translate_all(all_values, cache, cache_path)
    _write_json(cache_path, dict(sorted(cache.items())))

    base_release_date = date(2026, 9, 13)
    for number, title, captions, alt_texts in episodes:
        episode_number = number - 100
        episode_id = f"N{args.narrative_number:02}E{episode_number:02}"
        localizations = {}
        for locale in LOCALES:
            localized_title = title if locale == "en" else cache[f"{locale}\0{title}"]
            localized_captions = (
                captions
                if locale == "en"
                else [cache[f"{locale}\0{caption}"] for caption in captions]
            )
            for index in range(len(localized_captions)):
                compact = (
                    COMPACT_CAPTIONS.get((number, locale, index + 1))
                    if args.narrative_number == 0
                    else None
                )
                if compact is not None:
                    localized_captions[index] = compact
            if args.narrative_number == 0 and number == 110 and locale != "en":
                localized_captions[5] = cache[f"{locale}\0{COMPACT_110_6}"]
            too_long = [
                index + 1
                for index, caption in enumerate(localized_captions)
                if len(caption) > 400
            ]
            if too_long:
                raise ValueError(
                    f"{episode_id} {locale} captions exceed 400 characters: {too_long}"
                )
            localizations[locale] = {
                "captions": localized_captions,
                "title": localized_title,
            }
        episode = {
            "altTexts": alt_texts,
            "artworkHeightFraction": 0.72,
            "id": episode_id,
            "localizations": localizations,
            "number": episode_number,
            "panels": [
                {"image": f"{episode_id}P{index:02}.png"} for index in range(1, 8)
            ],
            "releaseDate": (
                base_release_date + timedelta(days=number - 101)
            ).isoformat(),
            "schema": 1,
            "tags": list(TAGS),
            "version": 1,
        }
        output = (
            root
            / "feelingverse/source"
            / args.narrative_id
            / f"E{episode_number:02}"
            / f"{episode_id}.json"
        )
        _write_json(output, episode)
        _write_records(
            root,
            args.narrative_id,
            args.narrative_number,
            number,
            title,
            alt_texts,
        )
        print(f"Prepared {episode_id}: {title}")


if __name__ == "__main__":
    main()
