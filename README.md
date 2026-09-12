# NeuraTiM Moodlo — emoji style library

This public repository contains the downloadable visual styles used by Moodlo.
Each style is one versioned ZIP with the same 74 canonical emoji identities, so
changing style changes presentation without changing the meaning of a saved
mood or emotion.

Moodlo ships Ceramic, Pixel Art, and Watercolor in the application. The other
styles are shown from `catalogue.json` and downloaded only when somebody asks
for one. Downloaded packs remain available offline.

## Repository layout

```text
catalogue.json                 generated catalogue read by the app
packs/<style>-<version>.zip    downloadable immutable package
previews/<style>.webp          compact store preview
source/<style>/                reviewed WebP source arranged by role
styles.json                    names, versions, translations, and bundled flags
tool/build_packs.dart          validator and deterministic catalogue builder
```

The app reads `catalogue.json` from:

```text
https://raw.githubusercontent.com/neuratim/moodlo-emoji/main/catalogue.json
```

See [EMOJI_PACKS.md](EMOJI_PACKS.md) for the complete authoring contract and
the single build command used for new styles.

## Licence

CC0 1.0 Universal; no attribution is required.

