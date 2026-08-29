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

Scope discipline: build/validate this against a single-axes-per-figure panel first (the simplest
real case, `plotVessels.m`'s single-metric line panel from `humanMouse`) before tackling panels
that start life as one tile among SEVERAL in a larger `tiledlayout` (`plotGaussianFitPanels.m`,
`plotFaaSpace.m`) — those need their own decomposition step, out of scope for now. **Note (found
2026-08-28, see `docs/findings.md`): `plotVessels.m`'s own "single-axes" panel is itself already a
1×1 `tiledlayout` internally** — this repo's pipeline handles that case (a solo tile spanning nearly
the whole figure) fine, once its own geometric tolerance accounts for tiledlayout's small extra
layout quantization; it's specifically MULTIPLE tiles per figure that remain out of scope.

## Layout

- `bakeTransforms.py` — flattens every `transform="matrix(...)"` MATLAB's exporter emits directly
  into each element's own geometry/size attributes (compulsory first step after export — see
  `docs/findings.md` for why). Preserves `<text>` as real text; a genuinely rotated `<text>`
  (confirmed real, not hypothetical — e.g. a y-axis label) collapses to a single clean
  `rotate(angle,x,y)` on the leaf, pivoting on its own already-baked anchor, rather than a nested
  or distributed transform.
- `dumpFontRegistry.m` — captures the AUTHORITATIVE live `FontSize` for title/xlabel/ylabel/tick
  labels (keyed by exact text content) so baking can bypass a confirmed small (~≤0.38pt) rounding
  artifact in MATLAB's own exported font-size. **Known gap, tracked deliberately, not silently
  accepted:** legend text and any other ad hoc `text()` call (e.g. `plotVessels.m`'s own
  vessel-ID corner label) aren't covered yet — those fall back to the scaled-and-rounded value.
  Extend this registry (or get explicit sign-off that a given case is fine to leave) before
  treating font-size handling as done.
- `snapshotAxesStyle.m` / `matchGraphicsToSvg.m` — the style-fingerprint matcher: captures each
  live Line/Patch's color/style "recipe" before export, then matches it to its SVG counterpart by
  exact color (a byte-exact round-trip, confirmed empirically), with a point-count check as a
  loud (never silent) tie-breaker/failure signal. Validated on `humanMouse`'s real single-metric
  `plotVessels` panel. Also exposes the matched Java DOM node itself (not just its points), for
  `groupAndTagSvg.m` below to tag directly.
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
- `groupAndTagSvg.m` — the grouping/tagging pipeline step itself: orchestrates the primitives above
  and restructures the DOM into real nested `<g id="..." data-role="...">` containers for four
  roles — **furniture** (figure/axes background, gridlines), **axis-spine** (spine lines, one
  sub-`<g>` per tick pairing its mark+label together, axis labels), **dataseries** (+ associated
  error, linking a Line to a same-`DisplayName` Patch as one series), **legend** (box, one
  sub-`<g>` per entry pairing its swatch+label together). Anything left unclaimed (e.g.
  `plotVessels.m`'s own ad hoc vessel-ID corner label) gets `id`/`data-role="annotation"` tagged IN
  PLACE, deliberately not grouped with anything else.

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
  Annotations are the one deliberate exception: unlike axis-spine/dataseries/legend, whose members
  are always drawn as one contiguous cluster in MATLAB's own output, annotations are arbitrary,
  mutually unrelated leftovers with no such guarantee — confirmed for real on this repo's own
  validation panel, where an earlier version of this file that DID combine two leftover elements
  into one shared group dragged one of them backward past the axis-spine/data in paint order, a real
  (if here still visually harmless) regression risk. Tagging them in place avoids the risk entirely.

  Verified NOT to change rendering by rasterizing (`rsvg-convert`) both the pre-grouping baked file
  and the post-grouping tagged file and pixel-diffing them (ImageMagick `compare`, 1% fuzz) — 0
  differing pixels on this repo's own validated panel; `test/test_group_tag.m` runs this check
  automatically when both tools are on `PATH`. Validated end-to-end on `humanMouse`'s real
  `plotVessels` panel, legend on and off, including a real content collision (the panel's own
  y-axis label and its legend entry are both literally the string `"radius"`) — correctly resolved
  to two distinct, correctly-nested elements.
- `test/` — MATLAB scripts validating the above (see file headers for what each proves). Several
  deliberately exercise a real plotting function from `humanMouse` (`plotVessels.m`) rather than
  synthetic data — adjust each test's `workDir` if that project lives elsewhere on this machine.
- `docs/findings.md` — consolidated empirical findings from the 2026-08-26 research session
  (SVG/EPS/PDF export behavior across every MATLAB renderer, the `ScreenPixelsPerInch`/72 scale
  factor, font-size rounding, why no existing tool solves this). Read before extending this tool —
  several of these took many rounds of testing (including two self-corrected mistakes) to nail
  down and are easy to re-break by assumption.

## Status (2026-08-28)

Pillar 1 (grouping/tagging) has a working end-to-end pipeline (`groupAndTagSvg.m`), validated
against `humanMouse`'s real `plotVessels` panel: bake → match data series (+ legend swatch/label) →
identify axis spine/ticks → identify legend box → identify furniture (background/gridlines) →
restructure into real nested `<g id=... data-role=...>` groups, verified pixel-identical to the
un-grouped baked file. Known, deliberately out-of-scope gaps (tracked, not silently accepted): the
ad hoc vessel-ID corner label `plotVessels.m` draws is tagged but not grouped (same known gap
`dumpFontRegistry.m` already tracks for its font-size); `ax.Box='on'` is not handled; a Line/Patch
error-band pairing uses `DisplayName` equality only (no project convention exists yet for a more
explicit link); multi-legend/multi-axes figures are out of scope (single-axes-per-figure panel
only, per this repo's own scope discipline above).

Pillar 2 (the mm-based resize round-trip: harvest a human's SVG edit to the spine → feed back into
MATLAB → regenerate everything else around it → re-place) is designed and spot-verified (MATLAB
`PositionConstraint='innerposition'` + `InnerPosition`, confirmed to work exactly once transforms
are baked) but not yet built.
