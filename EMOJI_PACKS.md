# Creating a Moodlo emoji style

This file is the complete contract for humans and coding agents. When asked to
create a new Moodlo emoji pack, follow it without inventing another layout or
editing `catalogue.json` by hand.

## The invariant

Every style contains exactly the same 74 canonical identities:

- 11 files in `emotions/`;
- 54 files in `gallery/`;
- 9 files in `levels/`.

Names are semantic and stable. A new style copies the directory and filenames
from an existing `source/<style>/` folder, then replaces only the image bytes.
Images must be reviewed, square WebP files with transparency, at most 768 × 768
pixels and at most 1 MiB each. Evaluation scenes and application backgrounds do
not belong in an emoji pack.

## Add or update a style

1. Create `source/<style-id>/emotions`, `source/<style-id>/gallery`, and
   `source/<style-id>/levels` by copying the structure of `source/ceramic`.
2. Replace every WebP with the reviewed artwork for the new style; do not rename
   or omit identities.
3. Add the style to `styles.json` in alphabetical order with a lowercase ASCII
   id, name, natural Czech localization, description, positive version, and
   `bundled: false` unless an app release will also carry the full style.
4. For any change to image bytes, increment that style's version; published ZIP
   files are immutable and an id/version pair must never be reused.
5. Run the only build command:

   ```sh
   dart pub get
   dart run tool/build_packs.dart
   ```

The builder validates the identity set, file type, size, dimensions, duplicate
ids, metadata, and existing version history. It then creates the ZIP, selects
`emotions/happy.webp` as the overview image, calculates every SHA-256 and byte
count, and rewrites `catalogue.json`. A validation failure leaves the published
catalogue unchanged.

The catalogue is generated. Never hand-edit archive or preview paths, byte
counts, SHA-256 values, timestamps, or its revision.

## ZIP structure

```text
pack.json
emoji/emotions/amazing.webp
emoji/emotions/angry.webp
...
emoji/gallery/angry_fists.webp
...
emoji/levels/extremelyNegative.webp
...
```

`pack.json` uses schema 1 and contains the immutable style id and version plus a
sorted asset list. Each asset declares its canonical key
(`emotion:<id>`, `gallery:<id>`, or `level:<id>`), relative path, byte count,
and SHA-256. Paths are relative, use `/`, and may not contain `..`.

## Publishing

Review the generated diff, commit, and push this repository. Never hand-edit
the generated catalogue or ZIP. Moodlo checks the catalogue at most once per
day and also exposes a manual refresh in Settings → Emoji styles.

Removing a style from `styles.json` removes it from future catalogues but does
not invalidate an installed copy. Removing a pack inside Moodlo deletes the
downloaded archive; any image already assigned to a personal mood or custom
emotion is copied into the encrypted vault first and therefore remains visible.
