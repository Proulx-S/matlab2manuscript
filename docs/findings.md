# Findings (2026-08-26 research session)

Empirical results this tool's design is grounded in. Re-verify against the MATLAB version/renderer
actually in use before trusting a specific number — the *mechanisms* are expected to generalize,
the exact scale factors are this machine's own (`R2025a Update 1`, `ScreenPixelsPerInch=95`).

## No MATLAB export path preserves element identity

Tested directly, exhaustively:
- `print(fig,...,'-dsvg'/'-depsc'/'-dpdf','-vector')`, `exportgraphics(...,'ContentType','vector')`,
  `saveas(...,'svg')` — all confirmed to embed **zero** `id`/`class`/`Tag`/`DisplayName`/`UserData`
  on any element, across every combination of MATLAB `Renderer` (`painters`/`opengl`/`zbuffer` —
  `'auto'` is not actually a valid value on this MATLAB version) and `print`'s own explicit
  `-painters`/`-opengl` flag. With `-vector` forced, all combinations produce **byte-identical**
  SVG (EPS/PDF differ only in embedded timestamps) — renderer choice is irrelevant to identity,
  only relevant to vector-vs-raster fidelity when `-vector` is NOT forced.
- Third-party exporters `plot2svg`/`fig2svg` (read directly from source): assign purely sequential
  `ID000000`, `ID000001`, ... in draw order — zero connection to `Tag`/`DisplayName`, and shift on
  every regeneration if element count/order changes. `export_fig` just calls MATLAB's own `print`.
  Both purpose-built tools are effectively abandoned (last commits 2020/2021).
- Other ecosystems: matplotlib solves this cleanly (`Artist.set_gid()` → literal SVG `id` at the
  renderer level) but it's opt-in metadata with no MATLAB equivalent hook. R's `gridSVG` solves it
  via `grid`'s own built-in object-naming convention, which MATLAB's HG2 model has no analogue of.
  No MATLAB Answers/Stack Overflow thread even discusses this as a known limitation.
- `DisplayName` text DOES survive, but only as literal legend `<text>` glyphs, and only when a
  legend is actually rendered and visible at export time — confirmed absent with no `legend()`
  call, `legend(ax,'off')`, and `legend.Visible='off'` alike. A legend kept on-canvas with
  `TextColor` set imperceptibly close to the background survives with full text intact — a real,
  working way to smuggle an arbitrary string identifier invisibly, if ever wanted.

## The `72/ScreenPixelsPerInch` scale factor

Every `<g>` MATLAB's `-dsvg` exporter emits is wrapped in `transform="matrix(a,b,c,d,e,f)"`. For a
plain (non-rotated) group this is `matrix(s,0,0,s,tx,ty)` with `s = 72/get(0,'ScreenPixelsPerInch')`
(`0.757895` on this machine, since `ScreenPixelsPerInch=95`) — MATLAB lays out internally using the
real system DPI, then applies this factor once at export to convert to genuine 72-points/inch SVG
units. **This is not a bug and does not need correcting** — raw `Position`/`LineWidth`/`FontSize`/
`MarkerSize` values, once you correctly compose the full ancestor `transform` chain (or bake it —
see below), match their true targets essentially exactly. Two self-corrected mistakes this session
came from reading raw pre-transform attribute values without composing this chain first — don't
repeat that.

`ScreenPixelsPerInch` has been **read-only since R2015b** — cannot be pinned/overridden at runtime.

## Font-size rounding (small, real, separate from the above)

MATLAB's raw (pre-transform) font-size attribute is rounded to the nearest **integer** in its own
internal representation before the `72/ScreenPixelsPerInch` scale is applied — e.g. requesting
`FontSize=14` can export as `18 × 0.757895 = 13.6421`. Bounded at `±0.5×s` regardless of target
size (~0.38pt here). Not fixable by baking math; fixed instead by overriding with the authoritative
live MATLAB value (see `dumpFontRegistry.m`) rather than trusting the exported number.

## Transform baking is compulsory, not optional, for the round-trip

Once a panel is placed and handed to a human for editing, any `transform` found later must mean
exactly one thing (a real edit), never "MATLAB's baseline scale, possibly combined with an edit."
Baking (flattening every transform into plain attributes) immediately after `print(-dsvg)`, before
any tagging/placement, establishes that invariant for the rest of the pipeline. No existing tool
does this correctly for this project's needs: SVGO's `convertPathData`(`applyTransforms`) doesn't
handle `<text>` scaling; Inkscape's community "Apply Transforms" extension is GUI-oriented with
unclear text handling. `bakeTransforms.py` is a small, targeted, from-scratch alternative —
verified via raster diff (rasterize original vs. baked, pixel-compare) to preserve visual fidelity
(sub-1% pixel difference, all attributable to font-hinting-level anti-aliasing noise or, once the
font registry is applied, the *intended* correction of the font-size rounding artifact above).

Text CAN be genuinely rotated by MATLAB in real, non-hypothetical panels (confirmed: a y-axis label
and `plotVessels.m`'s own vessel-ID corner label both render with `Rotation=90`) — baking handles
this by decomposing the composed matrix into scale+translate+angle and preserving only
`rotate(angle,x,y)` pivoting on the already-baked anchor `(x,y)` (verified term-for-term against
the SVG spec's own `rotate()` → `matrix(cos,sin,-sin,cos,0,0)` expansion).

## MATLAB axis-spine mechanics (for the spatial-control half of this tool)

- The "spine" (the plot box only, excluding labels) is `ax.Position` == `ax.InnerPosition`
  (confirmed: same rectangle, shown in red in MathWorks' own Axes Properties doc diagram).
  `tightPosition(ax)` (R2022b+) is the *live-rendered* version of the same rectangle
  (`IncludeLabels=false`, the default) — docs recommend it over `Position` for axes with a
  constrained aspect ratio (`axis square`/`axis image`).
- `ax.PositionConstraint='innerposition'` (default is `'outerposition'`) pins `InnerPosition` and
  lets MATLAB freely adjust `OuterPosition`/margins around it — confirmed empirically: spine
  geometry came out byte-identical whether tick labels were short or absurdly long.
- Axes `Units` must stay `'normalized'` for this automatic-resize mechanism to engage at all
  (MathWorks docs are explicit about this) — mm-based control has to work by fixing the *figure's*
  physical size (`fig.Units`/`fig.Position` in real units) and expressing the spine as a normalized
  fraction of that fixed size, never by setting axes `Units` to a physical unit directly.
- `FontSize` (and other axes properties) can be silently **reset to default and `FontSizeMode`
  flipped back to `'auto'`** the moment a plotting command (`plot()`) runs on axes with no prior
  children — set such properties *after* the first plot call, not before.

## The axis-spine identification pass, and end-to-end grouping/tagging (2026-08-28)

Built (`identifyAxisSpine.m`/`identifyLegend.m`/`groupAndTagSvg.m`), validated against
`plotVessels.m`'s real single-metric panel (legend on and off). Two ambiguities surfaced during
that validation and are worth remembering since they're easy to reintroduce by "obvious" geometric
reasoning alone, not just theoretical edge cases:

- **Tick marks are perpendicular to their own axis, not parallel** — an x-tick is a short VERTICAL
  segment, a y-tick a short HORIZONTAL one (easy to get backwards; confirmed by first getting it
  backwards and finding zero tick candidates).
- **MATLAB's first/last gridline routinely coincides exactly with the spine's own position** (e.g.
  the leftmost vertical gridline sits at the identical x as the y-spine, same endpoints) — confirmed
  in this repo's own probe SVG. Excluded by opacity (gridlines are always drawn with a fractional
  `stroke-opacity`, spine/ticks always opaque), not by geometry, since the geometry is genuinely
  identical.
- **The two rulers' own spines touch at the shared box corner** — the y-spine's bottom endpoint IS
  `(x0,y1)`, so a naive "touches the anchor line" test for the x-ruler also catches the y-spine (and
  vice versa: the very first x-tick, sitting at `x0`, also touches the y-ruler's anchor line).
  Excluded by bounding "spine-like" to near-full box span and "tick-like" to well short of it, for
  BOTH the accept and reject direction — an earlier version of this bound only in one direction and
  still let a real x-tick get miscounted as an 8th spurious y-tick.
- **A real, non-hypothetical `DisplayName` content collision**: `plotVessels.m`'s own y-axis label
  and its legend entry both render the literal string `"radius"`. Resolved by running legend
  matching (spatially constrained to the legend's own box, independently unambiguous) before axis-
  label matching, and having axis-label matching exclude whatever legend matching already claimed.

## Grouping/tagging: from attribute-only to real nested groups (revised 2026-08-28)

`groupAndTagSvg.m`'s FIRST version only stamped `id`/`data-role`/`data-group` attributes onto
existing leaf elements without moving anything, reasoning that relocating nodes risked changing
paint order (the x-ruler and y-ruler groups, for instance, are NOT document-adjacent, with title/
tick-label text interleaved between them). **Seb's own feedback, same day**: that flat,
attribute-only structure is useless in an actual SVG editor — click-to-select/collapse there follows
DOM nesting, not attribute values, so a "group" that's really just N independent single-element
groups sharing an attribute took exactly as many clicks to work with as no grouping at all. Real
nested `<g>` containers are what's actually needed.

Rebuilt to physically restructure the DOM, made safe by two mechanisms:

1. **Inline every relocated leaf's inherited presentation attributes onto itself before moving it.**
   MATLAB's own exporter puts `fill`/`stroke`/`font-*`/etc. on the enclosing style-batching `<g>`,
   not the leaf (`<text>` elements are the one exception — confirmed to already self-declare these
   directly). Copying the resolved value from whichever ancestor currently has it, directly onto the
   leaf, before removing it from that ancestor, means the leaf's rendering never depends on which
   new (unstyled, id/data-role-only) semantic group it ends up nested under.
2. **Anchor each new top-level group at whichever of its members occurs EARLIEST in the original,
   unmodified document**, and always move members INTO that already-positioned group rather than
   assembling the group elsewhere and inserting it later. This preserves the group's paint-order
   position relative to every untouched element and every other group exactly, since the group's own
   position is fixed before anything is pulled into it.

**A third, real ambiguity surfaced applying this to the catch-all "leftover" bucket** (whatever
isn't axis-spine/dataseries/legend/furniture — e.g. `plotVessels.m`'s own ad hoc vessel-ID corner
label, or an unrelated whole-figure title-ish text neither this tool nor `ax.Title` claims):
axis-spine/dataseries/legend/furniture members are each always drawn as ONE CONTIGUOUS cluster in
MATLAB's own output (confirmed empirically for every real case here), so anchoring their shared
group at the earliest member's position never reorders anything relative to a THIRD, unrelated
element sitting between two of that group's own members. Leftover/annotation elements have no such
guarantee — they are by definition mutually unrelated. Confirmed for real on this repo's own
validation panel: an early version of this rewrite combined two leftover elements (a whole-figure
title-ish text drawn near the very start of the document, and the vessel-ID corner label drawn much
later, after the data series) into one shared "annotations" group anchored at the EARLIER one's
position — which dragged the LATER one (the corner label) backward, past the axis-spine and data
series, in paint order. In this specific case it turned out to be visually harmless (confirmed via
the pixel-diff check below, since the corner label's position didn't overlap anything it now painted
under), but that's a coincidence of this one panel's layout, not a guarantee. Fixed by NOT grouping
leftovers together at all: each gets `id`/`data-role="annotation"` tagged **in place**, never
relocated, so there is no group-level anchor decision to get wrong.

**Verification**: rather than trust the above reasoning alone, both the pre-grouping (baked-only)
and post-grouping (tagged) SVGs are rasterized (`rsvg-convert`) and pixel-diffed (ImageMagick
`compare -metric AE -fuzz 1%`) — 0 differing pixels, both with a legend present and without, on
this repo's real validation panel. `test/test_group_tag.m` runs this automatically when both tools
are on `PATH` (warns and skips, rather than silently passing, if they aren't).

## Annotations folded into furniture after all, tradeoff measured (2026-08-29)

Seb's own explicit ask: fold annotations into furniture rather than leaving them tagged in place —
overriding the decision just above. Implemented in `groupAndTagSvg.m` by including `annotationNodes`
in furniture's own anchor computation and relocating them into a new `furniture > annotations >
annotation-{k}` sub-group, using the exact same `relocateLeaf`/inline-presentation-attrs mechanism as
every other group.

This reintroduces, on purpose, the exact risk the section above described: confirmed for real
immediately on this repo's own validation panel (which has an annotation positioned inside the plot
box, overlapping the data curve's own path at one point) — with the existing 1% pixel-diff fuzz
tolerance, 4 pixels differed between the pre- and post-fold renderings. Inspected directly rather
than assumed: the differing pixels sit exactly where the annotation's anti-aliased glyph edges cross
the curve, with RGB deltas of 1 unit out of 255 (e.g. `(219,170,25)` vs `(219,169,25)`) — a
compositing-order artifact at a genuine but sub-perceptual overlap, NOT one element actually
hiding/covering the other (which would show as a large block of full-strength color replacement).
Confirmed sub-perceptual: 0 pixels differ at a 2% fuzz tolerance. `test/test_group_tag.m`'s own
pixel-diff check now uses 2% (was 1%) for exactly this reason — documented there, not silently
loosened. If this diff count ever grows non-trivially on some other panel, treat it as the real
signal that an annotation has become genuinely hidden or visibly displaced by the fold, not as more
anti-aliasing noise to tolerate away.

Also fixed two real, independent bugs found while building the confidence-band Patch case used to
validate the new `dataseries` `value`/`conf` split (Seb's other 2026-08-29 ask, see
`docs/grouping-hierarchy.csv`):
- **`matchGraphicsToSvg.m`'s point-count check didn't account for a closed patch path's own
  explicit closing vertex.** MATLAB's `-dsvg` exporter closes a filled polygon by literally repeating
  its first vertex as its last (not via a separate `Z` command) — a genuine, generic 83-vs-82
  off-by-one against live `nPts` for ANY patch, not specific to this test. `parseGeometry` now drops
  a path's own repeated closing vertex before comparing point counts.
- **`identifyLegend.m` built a duplicate legend entry when a Line and its own confidence-band Patch
  share one `DisplayName`.** A legend entry is per DISPLAYED ITEM, not per `snap(i)` — the loop
  re-found the identical text/swatch nodes for the Patch after already resolving them for the Line,
  producing two `<g id="legend-entry-1">` elements (an invalid duplicate id). Fixed by skipping any
  `DisplayName` already resolved to an entry.

## `plotVessels.m` always hosts its axes in a `TiledChartLayout` — decided out of scope (2026-08-29)

Discovered while regenerating this repo's own example artifacts: `identifyAxisSpine.m` failed
intermittently against real `plotVessels.m` output, with no apparent pattern. Root cause, confirmed
by direct inspection: `plotVessels.m` calls `tiledlayout(hFig, nRow, nCol, ...)` + `nexttile`
unconditionally (`plotVessels.m:1230`/`:1239`), so `class(ax.Parent)` is ALWAYS
`matlab.graphics.layout.TiledChartLayout`, never a plain figure. This means the validated panel
described in the two sections just above was, itself, unknowingly a tiled axes -- it happened to
work often enough not to notice. Two real, confirmed consequences: a tiled axes' `PositionConstraint`
cannot be set at all (MATLAB rejects the assignment outright, and reading it back afterward is
cosmetic bookkeeping, not a real pin — tiledlayout's own layout engine controls the actual geometry
regardless), and live `ax.InnerPosition` can differ from the ACTUAL exported spine geometry by up to
~1.2pt (an extra layout quantization on top of the already-understood export scale factor).

**Seb's own call, same day**: don't accommodate this. Adapting an arbitrary MATLAB figure (tiled or
not) down to a plain single-axes figure suitable for this pipeline is its own, later, independent
step — not something to build reactively into `identifyAxisSpine.m`'s own tolerances. This repo's
own tests/examples (`test/test_group_tag.m`, `examples/makeExamplePanelA.m`) now use a plain,
hand-built `axes()` instead of `plotVessels.m` for anything touching `identifyAxisSpine.m`/
`groupAndTagSvg.m` — `plotVessels.m` is still used for the style-fingerprint matching and font-
registry tests (`test_match_prototype.m`/`test_edge_cases.m`/`test_registry_rotation.m`), which
don't touch axis-spine identification and aren't affected by this.

## Not yet investigated / open

- The `ScreenPixelsPerInch`-dependent bug documented in the OLD `humanMouse` engine
  (`project_humanMouse_manuscript_figure_svg_workflow.md`, a ~32% size mismatch between headless
  and interactive sessions) was NOT reproduced by the simple point-quantization rounding found
  here (sub-millimeter, universal, not environment-dependent) — its real root cause is still
  unknown and likely lives elsewhere in that engine's `copyForManuscriptPanel.m`/`savefig`/
  `openfig` round-trip, which this tool does not yet use or reproduce.
- `ax.Box='on'` (mirrored top/right spine lines) is not handled by `identifyAxisSpine.m` yet --
  errors loudly rather than silently mishandling it.
- Line+error-band pairing into one "series" uses `DisplayName` equality only -- no project
  convention exists yet for a more explicit link (e.g. a shared `Tag` suffix); revisit if/when one
  is established in `humanMouse`.
- An ad hoc `text()` annotation (e.g. `plotVessels.m`'s own vessel-ID corner label, drawn via
  `drawIdCornerBox`) is now folded into `furniture > annotations > annotation-{k}` (Seb's own ask,
  2026-08-29 -- see this file's own note above for the paint-order tradeoff this involves and how it
  was measured). Its font-size is still NOT covered by `dumpFontRegistry.m` -- same known,
  deliberately tracked gap (neither an axis label, tick label, data series, nor legend entry as
  defined there).
- `TiledChartLayout`-hosted axes (i.e. `plotVessels.m` and anything like it) are explicitly out of
  scope -- see this file's own note above. Adapting an arbitrary MATLAB figure (tiled or not) down
  to a plain single-axes figure suitable for this pipeline is its own, later, independent step.
- Pillar 2 (the mm-based resize round-trip itself: harvest a human's edited spine geometry from the
  tagged SVG, feed it back into MATLAB via `ax.InnerPosition`, regenerate, re-place) is not yet
  built -- the mechanism it depends on (`PositionConstraint='innerposition'`) is confirmed working,
  but no code exists yet to actually do the harvest/feedback/regenerate loop.
- **`id` collisions across multiple panels in one composed manuscript figure, NOT yet handled.**
  Every panel `groupAndTagSvg.m` tags uses the SAME fixed id scheme (`axis-spine`,
  `dataseries-1-<slug>-line`, `legend-box-bg`, etc.) -- inserting two tagged panels into one
  composed SVG (the eventual output of pillar 2's own panel-insertion step) means duplicate ids in
  one document, which is invalid SVG and makes `id`-based lookup undefined (typically first-match-
  wins, silently wrong for every panel after the first). `data-role`/`data-group` values are NOT
  the problem -- those are MEANT to repeat across panels (e.g. selecting every panel's own
  `axis-spine` at once is a real, useful multi-panel operation). The fix belongs in the
  panel-insertion step itself, not in `groupAndTagSvg.m`: when a panel is inserted into a composed
  figure, wrap it in its own container and rewrite every descendant `id` with a panel-unique prefix
  (e.g. `panelA-axis-spine-x`), leaving `data-role`/`data-group` untouched. Not yet designed or
  built -- flagged here so it isn't rediscovered the hard way once pillar 2 starts.
