# Processing Moodlo movies

Movies are public, downloadable emoji adventures. A movie contains ordered
seven-card episodes. The app refreshes its catalogue at most once per 24 hours
and downloads the entire episode when the viewer opens it. Every source episode
must declare its `releaseDate` as a real calendar date (`YYYY-MM-DD`). Users may
open all episodes released by their local date, including the entire backlog;
future episodes unlock on their dates. Local development Settings can override
the dates and download all catalogue episodes for preview.

## Current assignment and style

`feelingverse_movie_assignments_101_125_v2_precise.md` supersedes the earlier
wordless/optional-caption assignment. The completed release contains Assignments
101–125: seven images per episode with every narration and dialogue line.

The user selected the original episode's frame 4 as the BEST style, and frame 3
as another good example. Use the published s101 frame 4 and frame 3 as the
durable references. Match their dimensional comic-fantasy finish.
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
- Every episode entry has an illustrated background. The builder crops the
  episode's first approved artwork frame into a lightweight 240 × 135 JPEG,
  verifies it is at most 64 KiB, and embeds its bytes and SHA-256 in that
  episode's catalogue JSON summary. The movie entry uses the first episode's
  backdrop. A future episode whose first frame is not suitable must provide or
  create suitable approved artwork before publication; a missing backdrop is a
  build error, never an empty runtime card.
- Set source `artworkHeightFraction` to 0.72 for the 1080/1500 composition. The
  builder copies it to the catalogue. The app shows only that top artwork portion
  and one localized caption underneath, so the printed English band never doubles
  the story text. Full standalone PNG cards stay intact. Use 1 for artwork without
  a printed caption band.
- The seven `captions` mirror the full copy for normal in-app reading in all 18
  locales. English matches the assignment; the other locales are translated.
- Keep internal art, references, exact prompts and review records in the local,
  gitignored `production/` workspace. The final high-resolution cards and build
  metadata go into the local, gitignored `source/<movie>/<episode>/` workspace.
  Only `catalogue.json` and the generated `<movie>/episodes/<episode>/` download
  files belong in Git.

## Build and inspect assignments

From `packages/moodlo/emoji`:

```sh
python tool/compose_movie_cards.py --prepare --start 102 --end 110
# Generate and inspect artwork with the built-in image tool.
# Save accepted art to movies/production/feelingverse/sNNN/art/sNNN_pNN.png.
python tool/prepare_feelingverse_episodes.py --start 102 --end 110
python tool/compose_movie_cards.py --start 102 --end 110
dart format tool
dart run tool/build_movies.dart
```

The compositor uses Pillow and the app's bundled Manrope fonts. It extracts exact
copy from the assignment, measures 32-pixel text, rejects clipping and records
every line, crop and hash in `typesetting.json`. Inspect every resulting card.
The image tool makes visual corrections; the compositor only frames and typesets.

The builder reads the local `source/` workspace and owns all published hashes,
byte counts and catalogue revisions. Increase movie and episode versions for
the replacement, then copy generated `movies/catalogue.json` into the app's
`assets/media/movie_catalogue.json`.
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
