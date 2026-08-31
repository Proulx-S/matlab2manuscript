# matlab2manuscript

Reliably matching and controlling MATLAB graphics elements exported to SVG, for building
editable, regenerable manuscript-figure pipelines.

## Why this exists

A "tool development project": unlike a regular `bass/projects/<name>` repo (which analyzes data
from an empirical experiment), this repo's own purpose IS the tool — a from-scratch restart
(2026-08-26) of the manuscript-figure engine originally built inside `humanMouse`
(`manuscriptFigTools/`), narrowed to two problems, worked on one MATLAB-figure-panel at a time:

1. **Grouping/tagging** — reliably identify which SVG element corresponds to which MATLAB
   graphics object, since MATLAB's own vector export (`print`, `exportgraphics`, `saveas`, any
   renderer, any of SVG/EPS/PDF) embeds **zero** identifying metadata (no `id`/`class`/`Tag`/
   `DisplayName`) on any element — confirmed empirically, and confirmed that no third-party tool
   (`plot2svg`/`fig2svg`/`export_fig`) or other plotting ecosystem's MATLAB equivalent solves this
   either (matplotlib's `set_gid()`/R's `gridSVG` are real precedents, but neither has a MATLAB
   analogue). Elements are grouped into three top-level roles per panel — **axis spine**,
   **data series + associated error**, **legend** — each with its own subgroups.
2. **Precise spatial control** — let a human resize/reposition a panel's axis spine (MATLAB's
   `Position`/`InnerPosition`/`tightPosition(ax)`, in mm) directly in the exported SVG, and feed
   that back into MATLAB so it regenerates everything else (ticks, tick labels, gridlines, legend)
   around the new spine geometry. MATLAB controls formatting; the user controls the spine's
   on-page position/size only.

Scope discipline: build/validate this against a **plain, hand-built single-axes figure** first —
not even `plotVessels.m`'s own single-metric panel, once it was discovered (2026-08-28) that
`plotVessels.m` always hosts its axes inside a `TiledChartLayout`, even for one panel (see
`docs/findings.md`). `TiledChartLayout`-hosted axes are now SUPPORTED as of `runPillar1.m`'s own
copy step (2026-08-29, see below and `docs/findings.md`) — `copyobj` detaches such an axes into a
plain axes cleanly, so this restriction only ever applied to code paths that skip `runPillar1.m` and
export directly from the caller's own raw figure.

## Layout

- **`runPillar1.m`** (2026-08-29, revised same day for the copy step, and again for colorbar
  support) — the single-function entry point for the whole pillar-1 pipeline: `stats =
  runPillar1(ax, outDir, figId, panId, opts)` first `copyobj`'s `ax` (and its Legend/Colorbar, if
  any) into a fresh figure on a fixed standard canvas (default US Letter portrait,
  `opts.canvasSize`/`opts.canvasUnits`) -- `ax`/its own figure are NEVER touched -- decoupling any
  Colorbar (`Location='manual'`) BEFORE touching `InnerPosition` at all, since its default
  `'eastoutside'` non-idempotently re-shrinks `InnerPosition` on every set (see `docs/findings.md`),
  then repositioning it (`repositionColorbar`) to track `opts.innerPositionOverride` when given --
  then runs snapshot → raw export → bake → identity export → identity bake → group/tag on the COPY,
  producing just `<figId>_<panId>_tagged.svg`. `figId`/`panId` are compulsory: `figId` names the
  output stem, and `panId` is passed straight through to `groupAndTagSvg.m`, which prefixes every
  tagged element's own `id` with `{panId}-` and wraps the whole panel in one outermost
  `<g id="{panId}-root" data-panel="{panId}">` (2026-08-29 -- see `syncPanel.m` below), so multiple
  panels' output can share one composed document with no id collisions. The four intermediate files
  this needs along the way are deleted once no longer needed by default —
  `opts.keepIntermediates=true` keeps them (`<figId>_<panId>_raw.svg`, `<figId>_<panId>.svg` baked,
  `<figId>_<panId>_identity_raw.svg`/`<figId>_<panId>_identity.svg`). Call with no arguments for a
  self-populating default-opts struct + help text. Validated (`test/test_run_pillar1.m`) to produce
  BYTE-IDENTICAL output to calling every step (including the copy) by hand, and
  (`test/test_tiledlayout_support.m`) that a `TiledChartLayout`-hosted axes produces identical output
  to an equivalent plain axes -- this is the primary way to run pillar 1 now; the individual
  functions below remain directly callable for finer-grained control.
- **`syncPanel.m`** (2026-08-29) — the pillar-2 sync/insert operation: `result = syncPanel(ax,
  outDir, figId, panId, opts)` places one panel into a composed multi-panel figure
  (`<figId>.svg`) and, on every later call, recovers wherever a human repositioned/resized that
  panel POST-INSERTION (in a vector editor -- not on the standalone single-panel SVG, per Seb's own
  framing of this constraint) and feeds it back into `runPillar1.m`'s `opts.innerPositionOverride`
  for regeneration, so a resize is always a real re-render (correct absolute font-size/stroke-width
  at the new size), never a naively-scaled vector. First insertion and every later resync are the
  SAME operation -- there's no separate "insert" step. Mechanism: since every panel (and the
  composed figure) shares one fixed physical canvas (`runPillar1.m`'s copy step), a panel's
  placement in the composed document and its own `ax.InnerPosition` are literally the same number,
  so recovering an edit is a direct measurement (this panel's tagged spine's CURRENT bounding box,
  resolved through the full ancestor-transform chain via `resolveElementCTM.m` -- NOT
  `bakeTransforms.py`, which only ever has to parse MATLAB's own narrow `matrix()`-only export
  dialect, see that file's own header) divided by the canvas size, never a diff against a stored
  "before" value. A translate and an aspect-ratio-changing scale both map directly onto
  `InnerPosition`'s independent `[x y w h]` fractions; only rotation has no equivalent and is
  detected and rejected loudly. **Known validation gap**: exercised only against SIMULATED edits
  (`test/test_sync_panel.m` directly rewrites the composed SVG's DOM between calls) -- not yet
  round-tripped through a real external vector editor (Illustrator/Inkscape). See `docs/findings.md`.
- **`identifyColorbar.m`** (2026-08-29) — colorbar identification/tagging: box (a pattern-filled
  gradient rect, found by bbox match against the identity-matched outline, never by parsing the
  `<pattern>`/`<image>` directly), outline, per-tick mark+label pairs, and the colorbar's own label,
  reusing the SAME identity-color mechanism `dumpIdentitySvg.m`/`matchGraphicsToSvg.m` already use
  for data series (`colorbarIdentityColorHex.m` reserves a roleCode real per-series data never
  uses). Requires `identityBakedSvgFile`; a Colorbar without it falls through to the "annotations"
  catch-all rather than erroring. **Fully tested only for the default `Location='eastoutside'`** --
  see `docs/findings.md` for the several real MATLAB mechanics found while building this (duplicate
  outline strokes, a colorbar tick label colliding with axis tick-label matching, a `<pattern>`'s
  own `<image>` child being mistaken for a stray annotation).
- **Image-type dataseries** (2026-08-30) — `snapshotAxesStyle.m`/`matchGraphicsToSvg.m`/
  `groupAndTagSvg.m` now identify/match/tag an `image`/`imagesc` (heatmap) dataseries as a
  `dataseries-image` leaf, matched by direct GEOMETRIC correlation (`XData`/`YData` → expected
  canvas box) rather than any color-identity trick — a raster image's "color" is baked inside a
  compressed PNG blob, not a plain SVG attribute string, and there's no ambiguity to resolve via
  color anyway since each Image's own live `XData`/`YData` already fully determines its expected
  position. `Image` objects have `Tag` but no `DisplayName` at all (never read; `groupAndTagSvg.m`'s
  existing no-`DisplayName` fallback handles the id-slug). Coexists correctly with a colorbar in the
  same axes and with multiple images in one axes — see `docs/findings.md` for two real false-
  positive mechanisms found and fixed while building this (colorbar's gradient box vs. an image's
  own box; a full-bleed image vs. the true axes-background rect, both sharing the identical
  pattern-filled-closed-rect-`<path>` bbox).
- `bakeTransforms.py` — flattens every `transform="matrix(...)"` MATLAB's exporter emits directly
  into each element's own geometry/size attributes (compulsory first step after export — see
  `docs/findings.md` for why). Preserves `<text>` as real text; a genuinely rotated `<text>`
  (confirmed real, not hypothetical — e.g. a y-axis label) collapses to a single clean
  `rotate(angle,x,y)` on the leaf, pivoting on its own already-baked anchor, rather than a nested
  or distributed transform.
- **Font-size correction** (`groupAndTagSvg.m`, 2026-08-29 — REPLACES the earlier `dumpFontRegistry.m`
  + `bakeTransforms.py` content-keyed registry, removed): `bakeTransforms.py` always writes the
  geometrically-scaled font-size, which carries a confirmed small (~≤0.38pt) MATLAB rounding
  artifact. `groupAndTagSvg.m` overwrites it with the AUTHORITATIVE live value, AFTER each text
  node's role is already known unambiguously — title/xlabel/ylabel/tick-labels/legend-labels are
  corrected by reading the matching `ax`/`Legend` property directly (no content-matching at all);
  an ad hoc annotation is corrected by content-matching against a small, already-narrowed set of
  still-live `text()` objects, tracked (`stats.nAnnotationFontSizeUnresolved`), never silently
  guessed, if that's ambiguous. The old registry's flat `{content: fontSize}` key was fundamentally
  ambiguous once more than 4 roles were covered — this repo's own validation panel has a y-axis
  label and a legend label that are both literally `"signal"` with DIFFERENT font sizes, exactly the
  case a content-only key gets wrong. See `docs/findings.md`.
- `snapshotAxesStyle.m` / `matchGraphicsToSvg.m` / `dumpIdentitySvg.m` — the data-series matcher,
  with two strategies:
  1. **Real-color fingerprint** (the original approach): captures each live Line/Patch's color/style
     "recipe" before export, then matches it to its SVG counterpart by exact color, with a
     point-count check as a loud (never silent) tie-breaker/failure signal. Genuinely unresolvable
     when two objects share BOTH the same real color AND the same point count (confirmed real, see
     `test_edge_cases.m` Case B) — errors loudly rather than guessing.
  2. **Identity-color cross-reference** (2026-08-29, `groupAndTagSvg.m`'s own default): resolves
     that ambiguity outright. `dumpIdentitySvg.m` exports a throwaway copy of the figure with every
     object temporarily given a unique, collision-proof "identity color" (`computeIdentityColors.m`/
     `seriesRoleColorHex.m`: encodes `(seriesIndex, roleCode, occurrence)` directly, not just a bare
     index — see `assignSeriesIndices.m` below), real colors restored before returning.
     `matchGraphicsToSvg.m` then finds each object's shape in that identity export by its unique
     color (never ambiguous by construction), and cross-references it into the REAL export by
     matching its exact geometry (identical between the two exports, since only color differs) — so
     the real SVG's own colors never need to be unique at all. See `test_edge_cases.m` Case D and
     `docs/findings.md`.

  Both strategies also expose the matched Java DOM node itself (not just its points), for
  `groupAndTagSvg.m` below to tag directly. Validated on `humanMouse`'s real single-metric
  `plotVessels` panel (matching only — this doesn't touch `identifyAxisSpine.m`, so `plotVessels.m`'s
  `TiledChartLayout` issue doesn't apply here).
- `identifyAxisSpine.m` — locates the spine's own SVG elements (the long axis-line polyline for
  each ruler) and its tick marks, GEOMETRICALLY, from `ax.InnerPosition`/figure size -- never by
  color/z-order, since spine/gridlines/axes-background routinely share the same palette. Guards
  against two confirmed real ambiguities: MATLAB's first/last gridline often coincides exactly with
  the spine's own position (excluded by opacity: gridlines are always fractional, spine/ticks always
  opaque) and the two rulers' own spines touch at the shared box corner (excluded by bounding
  "spine-like" to near-full-span and "tick-like" to well-short). `ax.Box='off'` only for now (the
  confirmed real case); `Box='on'` errors loudly rather than silently mishandling it.
- `identifyLegend.m` — locates the legend's own box (background+border rects, found by eliminating
  the figure/axes background rects) and, per data series, its swatch + entry text -- using the
  confirmed fact that `DisplayName` text survives export only as a literal legend `<text>` glyph,
  restricted spatially to the legend's own box. Returns `[]` if no live Legend exists (not an
  error).
- `docs/grouping-hierarchy.csv` — a pure OUTLINE view of `groupAndTagSvg.m`'s own group hierarchy:
  columns are hierarchy levels (left→right = shallower→deeper), one label per row at its own
  nesting depth, id patterns only (`{n}`/`{i}`/`{k}` are template placeholders, not tied to any
  specific panel's actual tick/series/entry count). This is the intended way to propose a hierarchy
  change — edit the sheet directly (move a label to a different column to re-nest it, add/remove
  rows) and hand it back, rather than describing the change in prose. `docs/grouping-hierarchy-
  detail.csv` has the same tree with full metadata (parent id, `data-role`, contents, cardinality,
  notes) for implementation reference — edit the outline first, the detail file gets reconciled by
  hand afterward.
- `assignSeriesIndices.m` — groups `snapshotAxesStyle.m` entries into logical series (e.g. a Line +
  its own confidence-band Patch) by shared `Tag`. **Revised 2026-08-29** ("pairing-by-identity",
  Seb's own ask) from keying on `DisplayName`: two unrelated series can legitimately/accidentally
  share a display string (a real risk, not hypothetical — see `test_pairing.m`), whereas `Tag` is the
  MATLAB property meant for exactly this kind of internal/programmatic linking, not display.
  `DisplayName` is still used correctly elsewhere for what it's actually for — `identifyLegend.m`
  matches legend text by `DisplayName` because that's literally what a human reads there.
- `groupAndTagSvg.m` — the grouping/tagging pipeline step itself: orchestrates the primitives above
  and restructures the DOM into real nested `<g id="..." data-role="...">` containers for four
  top-level roles — **furniture** (figure/axes background, gridlines, AND any leftover/unclaimed
  element such as an ad hoc `text()` annotation, folded in per Seb's own ask 2026-08-29 — see that
  section's own comment for the real paint-order tradeoff this involves), **axis-spine** (spine
  lines, one sub-`<g>` per tick pairing its mark+label together, axis labels), **dataseries** (each
  series, per `assignSeriesIndices.m` above, split into its own `value`/Line and `conf`/error-band-
  Patch sub-group), **legend** (box, one sub-`<g>` per entry pairing its swatch+label together). See
  `docs/grouping-hierarchy.csv` for the full, current hierarchy spec (an editable outline — the
  intended way to propose a change).

  **Revised 2026-08-28** from this file's first version, which only stamped attributes onto existing
  leaf elements without moving anything (reasoning that relocating nodes risked changing paint
  order) — Seb's own feedback: that flat, attribute-only structure was useless in an actual SVG
  editor, since click-to-select/collapse there follows DOM nesting, not attribute values, so it took
  exactly as many clicks as no grouping at all. This version physically moves elements into real
  nested groups, made safe by (1) inlining every relocated leaf's inherited presentation attributes
  (fill/stroke/font-\*/etc., MATLAB puts these on the enclosing `<g>`, not the leaf) directly onto
  itself before moving it, so it never depends on whichever new, unstyled semantic group it ends up
  under, and (2) anchoring each new top-level group at whichever of its members occurs EARLIEST in
  the original document, preserving paint order relative to every other group/untouched element.

  **Revised again 2026-08-29** to fold annotations into furniture (Seb's own ask) rather than
  tagging them in place — this DOES carry the real paint-order risk the first revision deliberately
  avoided (annotations have no contiguity guarantee, unlike axis-spine/dataseries/legend, whose own
  members are always one contiguous cluster in MATLAB's own output), confirmed for real on this
  repo's own validation panel: with a 1% pixel-diff fuzz tolerance, folding a corner annotation into
  furniture measurably shifted 4 pixels where its anti-aliased glyph edges cross the data curve.
  Inspected directly and confirmed sub-perceptual (RGB deltas of 1/255, not one element actually
  hiding/covering the other) — 0 pixels differ at a 2% fuzz tolerance, which this repo's own test now
  uses instead of 1%. If this diff count ever grows non-trivially on some other panel, that's the
  real signal an annotation has become genuinely hidden or visibly displaced, not just anti-aliasing
  noise — investigate rather than further loosen the tolerance.

  Verified NOT to (meaningfully) change rendering by rasterizing (`rsvg-convert`) both the
  pre-grouping baked file and the post-grouping tagged file and pixel-diffing them (ImageMagick
  `compare`, 2% fuzz) — 0 differing pixels on this repo's own validated panel; `test/test_group_tag.m`
  runs this check automatically when both tools are on `PATH`. Validated end-to-end on a plain,
  hand-built single-axes panel with a confidence band and a legend (`test/test_group_tag.m`/
  `examples/makeExamplePanelA.m`, NOT `plotVessels.m` — see the Scope discipline note above), legend
  on and off, including a real content collision (the panel's y-axis label and its legend entry
  deliberately share the same string) — correctly resolved to two distinct, correctly-nested
  elements.
- `test/` — MATLAB scripts validating the above (see file headers for what each proves).
  `test_match_prototype.m`/`test_edge_cases.m` (style-fingerprint matching) still deliberately
  exercise a real plotting function from `humanMouse` (`plotVessels.m`) — neither touches
  `identifyAxisSpine.m`/`groupAndTagSvg.m`, so `plotVessels.m`'s `TiledChartLayout` quirk doesn't
  affect them. `test_group_tag.m`/`test_box_on.m`/`test_fontsize_correction.m`/`test_pairing.m` (the
  grouping/tagging pipeline and its own sub-mechanisms) use a plain, hand-built axes instead — see
  the Scope discipline note above. Adjust `workDir` in the `plotVessels.m`-based tests if
  `humanMouse` lives elsewhere on this
  machine.
- `docs/findings.md` — consolidated empirical findings from the 2026-08-26 research session
  (SVG/EPS/PDF export behavior across every MATLAB renderer, the `ScreenPixelsPerInch`/72 scale
  factor, font-size rounding, why no existing tool solves this). Read before extending this tool —
  several of these took many rounds of testing (including two self-corrected mistakes) to nail
  down and are easy to re-break by assumption.

## Status (2026-08-29)

Pillar 1 (grouping/tagging) has a working end-to-end pipeline (`groupAndTagSvg.m`), validated
against a plain, hand-built single-axes panel (see Scope discipline above — NOT `plotVessels.m`,
since it always hosts its axes inside a `TiledChartLayout`): bake → dump+bake an identity-colored
export (`dumpIdentitySvg.m`) → match data series by identity-color cross-reference (+ legend
swatch/label) → identify axis spine/ticks → identify legend box → identify furniture
(background/gridlines) → restructure into real nested `<g id=... data-role=...>` groups (spec:
`docs/grouping-hierarchy.csv`), verified pixel-identical to the un-grouped baked file. Known,
deliberately out-of-scope gap: multi-legend/multi-axes figures are out of scope
(single-axes-per-figure panel only). (`ax.Box='on'` and the legend/annotation font-size gap were
both fixed 2026-08-29 — see `identifyAxisSpine.m` and the font-size correction note above;
Line/Patch error-band pairing previously used `DisplayName` equality only — REVISED 2026-08-29, now
uses `Tag`, see `assignSeriesIndices.m`; `TiledChartLayout`-hosted axes — i.e. `plotVessels.m` and
anything like it — were out of scope, REVISED 2026-08-29, now supported via `runPillar1.m`'s own
`copyobj`-based copy step; embedding `figId`/`panId` into every tagged element's own `id` for safe
multi-panel composition was deferred, REVISED 2026-08-29 same day, now implemented in
`groupAndTagSvg.m` and used by the new `syncPanel.m` pillar-2 sync/insert operation, see above and
`docs/findings.md` -- its round-trip has only been exercised against SIMULATED editor edits so far,
not a real external vector editor.)

Pillar 2 (the round-trip: harvest wherever a human repositioned/resized a panel AFTER inserting it
into the composed multi-panel figure → feed back into MATLAB → regenerate → re-place) is now built
as `syncPanel.m` (2026-08-29), covered by `test/test_sync_panel.m`. Not yet done: a real
external-vector-editor round-trip (only simulated edits tested so far -- see Layout section above
and `docs/findings.md`).

Colorbar support (`identifyColorbar.m`, 2026-08-29) is built end to end: identification/tagging
(box, outline, per-tick mark+label pairs, own label), font-size correction on its two new roles, the
`runPillar1.m` copy-step's decoupling/repositioning, and the `syncPanel.m` round-trip -- covered by
`test/test_colorbar.m`. A small (~0.17% of canvas), precisely-diagnosed, purely cosmetic pixel-diff
residual is expected (sub-pixel antialiasing along the colorbar's own duplicated outline strokes,
see `docs/findings.md`) -- not a correctness issue. Fully tested only for the default
`Location='eastoutside'`.

Image-type dataseries (`imagesc`/`image` as the actual plotted data, not just a colorbar) are now
supported (2026-08-30) -- matched by direct geometric correlation, no color-identity involved,
covered by `test/test_image_dataseries.m` (single image, two images in one axes, an image alongside
a colorbar). See `docs/findings.md` for the mechanics and two real false-positive bugs found and
fixed while building this.
