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
- The ad hoc vessel-ID corner label `plotVessels.m` draws via `drawIdCornerBox` is not tagged by
  `groupAndTagSvg.m` -- same known, deliberately tracked gap `dumpFontRegistry.m` already has for
  its font-size (neither an axis label, tick label, data series, nor legend entry as defined here).
- Pillar 2 (the mm-based resize round-trip itself: harvest a human's edited spine geometry from the
  tagged SVG, feed it back into MATLAB via `ax.InnerPosition`, regenerate, re-place) is not yet
  built -- the mechanism it depends on (`PositionConstraint='innerposition'`) is confirmed working,
  but no code exists yet to actually do the harvest/feedback/regenerate loop.
