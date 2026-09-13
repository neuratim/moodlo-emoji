# Processing Moodlo movies

Movies are public, downloadable emoji adventures. A movie contains ordered
seven-card episodes. The app refreshes its catalogue at most once per 24 hours
and downloads the entire episode when the viewer opens it.

## Current assignment and style

`feelingverse_movie_assignments_101_125_v2_precise.md` supersedes the earlier
wordless/optional-caption assignment. This requested release contains only
Assignment 101: seven images with every narration and dialogue line.

The user selected the original episode's frame 4 as the BEST style, and frame 3
as another good example. Preserved copies are in
`production/feelingverse/s101/references/user-approved-style-04.png` and
`user-approved-style-03.png`. Match their dimensional comic-fantasy finish.
The user rejected the flatter coin-like redesign. Their choice supersedes the
assignment's matte-only style; its story, anatomy and physical logic still apply.

## Production contract

- One unlettered illustration of one frozen moment per scene: no comic grids,
  inset moments, repeated actors, generated text or lettering.
- Use the complete scene packet, cast/state inventory, spatial plan and accepted
  references. Inspect actual pixels, including distant people and props.
- Every object needs support, every route a destination and every reflection its
  source. Reject stacked architecture, extra bridges, floating ropes and malformed
  hands. Check exact prop counts and ownership.
- Add the EXACT narration and attributed dialogue in an opaque dark caption band.
  Silent frames are not allowed in this assignment. Do not typeset production
  labels, headings or scene IDs.
- Source masters are 1200 × 1500 sRGB PNGs: 1200 × 1080 art and a 420-pixel caption
  band. The existing app format remains 1024 × 1280; the builder scales the
  complete card proportionally, preserving all art and text.
- The seven `captions` mirror the full copy for normal in-app reading in all 18
  locales. English matches the assignment; the other locales are translated.
- Keep internal art, references, exact prompts and review records in
  `production/`. Only final cards belong in `source/<movie>/<episode>/` and
  the generated `<movie>/episodes/<episode>/` directory.

## Build and inspect Assignment 101

From `packages/moodlo/emoji`:

```sh
python tool/compose_movie_cards.py --prepare
# Generate and inspect artwork with the built-in image tool.
# Save accepted art to movies/production/feelingverse/s101/art/s101_pNN.png.
python tool/compose_movie_cards.py
dart format tool
dart run tool/build_movies.dart
```

The compositor uses Pillow and the app's bundled Manrope fonts. It extracts exact
copy from the assignment, measures 32-pixel text, rejects clipping and records
every line, crop and hash in `typesetting.json`. Inspect every resulting card.
The image tool makes visual corrections; the compositor only frames and typesets.

The builder owns all published hashes, byte counts and catalogue revisions.
Increase movie and episode versions for the replacement, then copy generated
`movies/catalogue.json` into the app's `assets/media/movie_catalogue.json`.
Run `npm run verify moodlo --skip-visual` from the workspace root and verify
all seven download images and the normal movie-reader flow.

Publishing is a separate repository operation: the generated episode and its
catalogue must reach `neuratim/moodlo-emoji` together. Local packaging does not
make files available at public download URLs.

## Another episode

Read all seven records and applicable cast/location/state locks. Preserve the
accepted style and lasting story consequences. Save exact prompts and actual
review evidence, accurate English alt text, seven complete localized captions,
ordered filenames and the correct version. Keep the movie's stable ID.
