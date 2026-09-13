# Episode 101 visual and semantic review

Reviewed: 2026-09-13, by the implementation agent. Scope is Assignment 101,
seven cards only. This is pixel inspection and data validation, not a claim
that the user has approved every new frame.

## Final art direction and references

The user's original frame 4 is the primary style authority; original frame 3
is secondary. Both originals are preserved under `references/user-approved-style-*`.
All final art was created or corrected with the built-in image generator.
The flat cast sheets served only as accessory inventories; their flat rendering
and the rejected coin-like experiment were not adopted.

Continuity references checked: Rain/Nova/Beam identity sheet v2, the corrected
scene 1, Fizz/Bloom/Puff sheet v2, Flare/Quiver/Mend and Bitter/Pop/Quest design
sheets, and Still/Hope/Vex sheet v2. Location and prop plans are in `LOCKS.md`.
Full original packets, actual render requests and local correction requests are
preserved in `prompts/`; reference images are never additional episode frames.

## Per-card checks

### 101.1 — shared damp moth

PASS. Foreground is Rain and Nova only; no background people. Rain is blue with
one tear on the anatomical left, a short scalloped collar, one pocket and one
bottle; Nova has two star pupils and an intact scarf pin. They hold one folded,
unmarked damp ivory paper moth. Feet and bodies meet the same supported stone
step. The bridge joins two banks; one lighthouse rests on its round east-bank
foundation; the canal remains open. Corrected tear placement, excess clothing
and a redundant background bridge before acceptance. Meaning: an apparently
spoiled object receives a friend's attention.

### 101.2 — an accessible shared task

PASS. Four foreground actors: Beam, Fizz, Bloom and smaller Puff. Exactly three
plain residents wait in the background, without duplicate hero accessories.
Beam's ordinary short arm reaches a lowered lamp hood; the lamp has a grounded
post. Fizz holds one continuous cord routed through the post-mounted pulley.
The suspended lantern has connected hardware. Bloom steadies the frame while
both Puff mittens contact the paper shade. Fizz's three hat dots, Bloom's bow,
Puff's red cap and Beam's notched ivory visor are present. Corrected background
hero duplicates, hand contact, visor and the stretched arm introduced by a
contact edit. Meaning: Puff contributes through a reachable practical task.

### 101.3 — controlled repair

PASS. Flare, Quiver and Mend only; no distant crowd. Flare's right cuff warms
one bolted bronze hinge locally. Quiver has three attached chimes. Mend has
three rim hearts and one partly used spool; the rose safety line passes through
a fixed wall ring. The continuous stone shelf has masonry supports and rails;
the bronze pipe is clamped to the wall. Background houses stand on one
supported bank. Removed unwanted distant people and reframed the original wide
draft so the ring, line and all actors remain visible. Meaning: anger, caution
and care cooperate on one repair.

### 101.4 — the coating clue

PASS. Bitter, Pop and Quest only. One intact detached mosaic glass globe sits
inside one wooden cradle on a supported table. Its narrow oily white streak is
a surface coating, not a hovering cloud. Bitter has two capped tubes total:
one held and one retained in the pouch. Pop's two cream mittens stop short of
the globe; both white fins are rounded. Quest's single goggle sits above both
visible eyes, and his one hinged brass disk is closed and attached to the
crossbody strap. Corrected pointed fins, fingered hands, eye-covering goggle
and invented dial lettering. Shop walls, rack and hanging lamps have visible
supports. Meaning: the group notices physical tampering.

### 101.5 — voluntary quiet

PASS. Still and small Hope only. Still retains two eyes and a straight neutral
mouth. Hope wears the blue ribbon and holds a separate ivory folded paper moth
with one blue dot on its anatomical left wing. One shaded lamp supplies the
quiet alcove's light. The bench has stone supports; the curtain is tied to a
wall hook; the visible inside latch is reachable through a ground-level open
exit. No lock, cage, coercion or ominous villain cues. Extended the original
wide composition to preserve both the lamp and latch in the final crop.
Meaning: choosing quiet is safe and voluntary.

### 101.6 — the optical connection

PASS. Beam, Rain and Nova only, above the established stone step. One modest
source at Beam's mitten passes through the original damp paper moth held by
Rain, then Nova's transparent triangular pane, then exactly three separate
branches ending on nearby stone. No ray reaches the city or sky. Nova's pin
is intact and does not emit light. Rain's tear, collar, pocket and bottle remain
consistent. Corrected Beam's multiple-corner visor edge to one notch.
Meaning: three different contributions create the three paths.

### 101.7 — the physical intruder

PASS. Rain and Nova stand freely on the west step; one original paper moth
rests beside Rain's foot. One white barge fits in the open canal without
intersecting the pier. Its one oval hood is mounted on visible deck struts.
One small plum operator is mostly hidden behind the hood; no readable second
protagonist or Null appears. Pale rippled reflections sit beneath the real
boat and hood. Nearby east-bank lamps are dimmer. Removed extra distant bridges
and moved the initially exposed operator behind the hood. Meaning: a real
intruder is noticed before its purpose is understood.

## Text and final delivery checks

Every final 1200x1500 source card was opened and inspected after typesetting.
The exact English narration and attributed dialogue are present with no
paraphrasing, missing words, clipping or generated lettering. Manrope is 40 px
with 52 px line advance; the longest card ends at y=1446, above the y=1476
safety boundary. The art is fitted to 1200x1080 without stretching, above a
420 px caption band. Final art crops preserve the clue objects.

The normalized 1024x1280 delivery card was also inspected for resampling and
text clarity. `validation.json` records seven decoded PNGs, exact ordered
filenames, byte counts and SHA-256 hashes, one version-2 episode, matching
bundled catalogue, and exact English comparison against the assignment. Every
one of the 18 app locales has seven nonempty captions below the 400 UTF-16
code-unit limit. The package is 12,748,114 bytes, within the 24 MiB cap; every
panel is below 3 MiB.

Semantic rejection signals remaining: none observed in the reviewed final
cards. Pixel review does not promise that generative illustrations are
mathematically perfect. The recorded corrections target concrete anatomy,
contact, support, cast-count and continuity defects rather than treating
fantasy as permission for incoherent objects.

The asset files and app catalogue are local workspace changes. Running the
packager does not upload them to the public GitHub download URLs.

## App verification

`npm run verify moodlo --skip-visual` exited 0: 10 checks ran, zero failed.
All 61 Dart unit, widget, flow and security tests passed, including the movie
navigation and seven-frame atomic-download flows. Formatting, analysis,
dependency checks, site lint/types and web security headers passed. The user's
visual-review CLI was skipped as instructed; the seven actual image cards were
inspected directly. No runtime code was changed for this content replacement.
The verification server and its browser have exited, the temporary Python
bytecode file was removed, and no session-owned background process remains.
