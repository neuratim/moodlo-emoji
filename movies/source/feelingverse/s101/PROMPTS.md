# Feelingverse 101: version 2 production

This episode replaces the previous seven illustrations and wordless metadata.
The authority is `movies/feelingverse_movie_assignments_101_125_v2_precise.md`,
Assignment 101 only. No later episode is packaged.

The user explicitly selected the original frame 4 as BEST and frame 3 as a
secondary reference. Preserved copies live in
`movies/production/feelingverse/s101/references/user-approved-style-04.png`
and `user-approved-style-03.png`. Their dimensional painted emoji, comic
contours and amber/violet fantasy lighting override the assignment's matte-only
style sentence. The new assignment's actions, cast, geometry and exact copy
remain authoritative.

Production records, relative to `movies/production/feelingverse/s101/`:

- `LOCKS.md`: approved direction, local geography and prop inventories.
- `prompts/s101_p01.txt` through `s101_p07.txt`: complete original scene packets.
- `prompts/*render*.txt` and `prompts/*correction*.txt`: actual built-in image
  generation requests and recorded local corrections.
- `art/s101_p01.png` through `s101_p07.png`: reviewed unlettered artwork.
- `script.json`: exact English narration and attributed dialogue extracted
  directly from the assignment, with no rewriting.
- `typesetting.json`: crop, line layout and SHA-256 evidence for each card.
- `REVIEW.md`: visual and semantic review of the seven delivered cards.

`tool/compose_movie_cards.py` typesets the exact English copy using Moodlo's
Manrope fonts beneath each 1200x1080 art viewport. Finished source cards are
1200x1500 sRGB PNG. `tool/build_movies.dart` produces the app's existing
1024x1280 delivery format, panel hashes and catalogue metadata. English plus
17 complete caption translations remain separately readable in the app.

Reference sheets and rejected drafts are production material, never additional
reader frames. The packaged episode contains exactly seven final images.
