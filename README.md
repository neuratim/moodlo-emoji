# NeuraTiM Moodlo — emoji style library

This public repository contains Moodlo's downloadable visual styles and
Feelingverse narratives. Each style is one versioned ZIP with the same 74
canonical emoji identities, so changing style changes presentation without
changing the meaning of a saved mood or emotion.

Moodlo ships Ceramic, Pixel Art, and Watercolor in the application. The other
styles are shown from `catalogue.json` and downloaded only when somebody asks
for one. Downloaded packs remain available offline.

## Repository layout

```text
.github/workflows/             Feelingverse catalogue sync on every push
catalogue.json                 generated catalogue read by the app
feelingverse/catalogue.json    dynamic narrative catalogue read by installed apps
feelingverse/<id>/episodes/    episode JSON and seven PNG panels, editable in place
packs/<style>-<version>.zip    downloadable immutable package
previews/<style>.webp          compact store preview
source/<style>/                reviewed WebP source arranged by role
styles.json                    names, versions, translations, and bundled flags
tool/build_feelingverse.dart   narrative builder; --sync refreshes the catalogue
tool/build_packs.dart          validator and deterministic catalogue builder
```

The app reads `catalogue.json` from:

```text
https://raw.githubusercontent.com/neuratim/moodlo-emoji/main/catalogue.json
```

See [EMOJI_PACKS.md](EMOJI_PACKS.md) for the complete authoring contract and
the single build command used for new styles.

## Feelingverse releases

The app permanently bundles narrative `00` as its offline fallback. It checks
the following schema-3 catalogue automatically and on manual refresh, so
narrative `01` and every later release appear with localized text, episode
metadata, tags, and verified background artwork without an app update:

```text
https://raw.githubusercontent.com/neuratim/moodlo-emoji/main/feelingverse/catalogue.json
```

The catalogue contains one compact backdrop per narrative and one per episode
(its first panel, centred, so every episode card shows its own scene) and
references the episode files under that narrative. The builder and
the release validator refuse titles and descriptions damaged by a non-UTF-8
pipe — `?` in place of every character the code page could not hold. Publishing a later narrative
means committing its complete episode tree and the updated catalogue together
in this repository; the bundled app catalogue is not updated. The production
contract and all 18 required locales are defined in `../assets/PROCESSING.md`
in the Moodlo workspace.

### Correcting a published episode

Edit `N<NN>E<EE>.json`, or replace any `N<NN>E<EE>P##.png`, in place and push.
Nothing records a byte count or hash of these files, so no other JSON has to
change for the download to work. Keep the object structure:

- `schema` 1, the episode's own `id` and `number`, and a whole-number `version`;
- all 18 locales, each with a `title` of at most 160 characters and exactly
  seven `captions` of at most 1,000 characters (an empty caption is a silent
  frame);
- `tags`, one to twelve of them;
- exactly seven `panels`, each with its `altText` and its fixed `image` name.

A panel is a PNG in 4:5 portrait shape, 640 to 2048 pixels wide and at most
5 MiB.

The catalogue copies each episode's titles, tags and version, derives the card
backdrop from panel 1, and keeps an advisory fingerprint of every file so that
installed apps update the copies people keep offline. The
`Feelingverse catalogue` workflow refreshes all of that on every push, and
fails with a message naming the file and field when an edit breaks the
structure. To check before pushing, run from this directory:

```sh
dart run tool/build_feelingverse.dart --sync
```

To also download every episode from this working copy with the real app code,
run `npm run test moodlo tool/verify_local_feelingverse_download_test.dart`
from the workspace root.

## Licence

CC0 1.0 Universal; no attribution is required.
