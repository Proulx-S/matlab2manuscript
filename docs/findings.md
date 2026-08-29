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
live MATLAB value.

**How that override is done changed 2026-08-29** (a real, not hypothetical, correctness bug found
extending it): the original approach (`dumpFontRegistry.m`, removed) dumped a flat `{content:
fontSize}` JSON registry BEFORE export, keyed purely by text content, consulted by
`bakeTransforms.py` while baking. This is fundamentally ambiguous once more than
title/xlabel/ylabel/tick-labels are covered — legend text and ad hoc annotations both routinely
share content with SOMETHING else (this repo's own validation panel has a y-axis label and a legend
label that are both literally `"signal"`), and a flat dict can only hold one value per key.
Correction now happens in `groupAndTagSvg.m` instead, AFTER each text node's role is already known
unambiguously from its own identification mechanism (position/content-restricted-to-a-narrow-box/
elimination — never a second, unrestricted content lookup): title/xlabel/ylabel/tick-labels/legend-
labels are corrected by reading the matching `ax`/`Legend` property DIRECTLY (no matching needed at
all, since which property to read is already determined by the role); only an ad hoc annotation still
needs content-matching, but against a small set already narrowed to "still-live text() objects that
aren't title/xlabel/ylabel" — the exact same "restrict first, then match content" discipline
`identifyLegend.m` already used. `bakeTransforms.py` itself now always writes the geometrically-
scaled (uncorrected) value; it no longer accepts a registry argument at all. Validated:
`test/test_fontsize_correction.m` gives all 6 roles distinct font sizes (including the exact
`"signal"`/`"signal"` collision above, with DIFFERENT sizes on each) and confirms every one resolves
to its own exact, correct value.

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
- **A second, separate `FontSize`/`FontSizeMode` reset gotcha (2026-08-29), NOT the same as the one
  above**: setting `ax.XAxis.FontSize` (or `ax.YAxis.FontSize`) resets `ax.XLabel.FontSizeMode` (or
  `ax.YLabel.FontSizeMode`) back to `'auto'`, silently reverting any `ax.XLabel.FontSize` already
  set to `ax.XAxis.FontSize * ax.LabelFontSizeMultiplier` (default `1.1`) instead. Confirmed real by
  hitting it directly in `test/test_fontsize_correction.m`'s own setup (set labels before rulers,
  got `XLabel.FontSize=9.9` instead of the requested `16`) — order matters: set
  `XAxis`/`YAxis.FontSize` FIRST, then `XLabel`/`YLabel.FontSize` after, not the reverse.

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
`groupAndTagSvg.m` — `plotVessels.m` is still used for the style-fingerprint matching tests
(`test_match_prototype.m`/`test_edge_cases.m`), which don't touch axis-spine identification and
aren't affected by this.

## Identity-color matching: resolving the "two objects share a color" ambiguity (2026-08-29)

The real-color style-fingerprint matcher (`matchGraphicsToSvg.m`, `docs` above) has one genuine,
unresolvable-by-design gap: if two Line/Patch objects share BOTH the same real color AND the same
point count, nothing in the SVG distinguishes them — confirmed real, `test_edge_cases.m` Case B,
correctly errors loudly (`ambiguousMatch`) rather than guessing. Seb's own proposal, discussed before
building it: render a second, disposable copy of the same figure where every object gets a unique,
deliberately-arbitrary "identity color" instead of its real one (the "ID buffer"/"color picking"
technique from graphics engines: render a hidden pass with flat unique colors per object so a color
read-back always identifies the object unambiguously, no matter its real appearance) — then use that
disposable export purely as a lookup key into the real one.

**Why this works cleanly for SVG specifically** (unlike the rasterized-image version of this
technique): SVG `fill`/`stroke` attribute values are exact text in the markup, never blended/
rasterized, so there is no antialiasing risk the way there would be reading back pixels from a
rendered image — adjacent identity values like `#000001`/`#000002` are exactly as reliable as
maximally-different colors would be.

**Implementation**: `identityColorHex.m` is the single shared encoding (index *i* → `#000000+i`,
both a hex string and a `[0,1]` RGB triple) that `dumpIdentitySvg.m` (assigns colors, exports,
restores real colors) and `matchGraphicsToSvg.m` (looks them up) both rely on to agree. Colors are
restored via an explicit try/catch around the whole recolor+export sequence, not `onCleanup` — an
`onCleanup` closure captures its captured variables' VALUES at creation time, so creating it before
the loop that populates the restore-function list would have captured an eternally-empty list (a
real bug caught before it shipped, not hypothetical).

`matchGraphicsToSvg.m`'s new identity path: for object *i*, find the identity-colored export's own
shape by EXACT color `identityColorHex(i)` (unambiguous by construction — unlike the real-color path,
more than one candidate here can only mean the SAME object's shape was split by an axis-clip boundary,
never a different object, since identity colors never collide), then find the shape with that EXACT
SAME geometry in the real export (identical between the two exports, since only color differs) — so
the real SVG's own colors are never consulted for this at all. Validated: `test_edge_cases.m` Case D
reproduces Case B's exact "same color, same point count" scenario and confirms it resolves correctly
with an identity SVG present, where Case B itself (no identity SVG) still correctly errors loudly —
both paths coexist, `identitySvgFile` is an optional third argument, so the original,
already-validated real-color-only behavior is unchanged when it's omitted. `groupAndTagSvg.m` now
always supplies one.

**Scope note**: the above fixes SVG-identity-matching robustness, not the SEPARATE Line+Patch
series-pairing question — identity colors alone tell you "this exact shape is object *i*," not
"object *i* and object *j* are the same logical series." That's a different signal, addressed next.

## Pairing-by-identity: `Tag`, not `DisplayName`, decides which objects are one series (2026-08-29)

Seb's own direct follow-up ask, same day: extend the identity mechanism above to also fix Line+Patch
series pairing, which previously grouped objects by `DisplayName` equality — genuinely fragile, since
`DisplayName` is meant for what a human reads in the legend, and two unrelated series sharing one
(legitimately or by accident) would silently merge into a single series that was never meant to be
linked.

Considered encoding `(seriesIndex, roleCode)` directly into the identity-color channel as the sole
source of truth for pairing, so decoding a shape's color alone would reveal series/role — but this
turned out to be unnecessary complexity: `matchGraphicsToSvg.m` always has live `snap` (hence live
`Tag`/`DisplayName`) available at matching time, so there is no scenario here where pairing must be
recovered FROM the SVG alone (unlike shape identity, which genuinely can't be recovered from the real
SVG's own colors when they collide). Re-deriving it via color would just be re-encoding something
already directly available.

**What was actually built**: `assignSeriesIndices.m` (extracted from `groupAndTagSvg.m`'s own local
function into a shared file) now keys on `Tag` instead of `DisplayName` — same grouping logic, same
"no Tag = its own standalone series" fallback, different (more appropriate) property. The identity-
color scheme (`computeIdentityColors.m`/`seriesRoleColorHex.m`) DOES still encode `(seriesIndex,
roleCode, occurrence)` rather than a bare sequential index, though — not because matching needs it,
but so `dumpIdentitySvg.m`'s color assignment and `groupAndTagSvg.m`'s own grouping decision are
provably derived from the exact same `assignSeriesIndices.m` call, rather than being two independent
computations that could silently drift apart. `identityColorHex.m` (the original bare-index scheme
from the same-day identity-matching work above) was deleted, superseded before it ever shipped.

**A real, independent bug surfaced fixing this**: once the Patch no longer needs a `DisplayName` to
pair with its Line (the whole point), a series' Line and Patch leaves could end up with inconsistent
ids -- e.g. `dataseries-1-signal-line` next to `dataseries-1-series1-fill` -- since each object's own
id slug was derived independently from ITS OWN (possibly empty) `DisplayName`. Fixed by computing one
shared slug per SERIES (preferring any member's non-empty `DisplayName`, falling back to `series<n>`
only if none exists across the whole series) in a precompute pass, before building any ids.

**Validated**: `test_pairing.m`, three cases — (1) two objects sharing a `DisplayName` but different
`Tag`s stay separate series (the exact fragility being fixed); (2) two objects sharing a `Tag`, one
with no `DisplayName` at all, still pair correctly (the normal confidence-band case now that pairing
doesn't need `DisplayName`); (3) two entirely untagged objects don't accidentally merge via an empty-
string key collision. `test_group_tag.m`/`examples/makeExamplePanelA.m`'s own confidence-band Patch
now carries no `DisplayName` at all (previously shared one with the Line) specifically to prove
pairing survives without it — full pipeline re-verified: 0 pixel-diff, no duplicate ids, all other
tests unaffected. `DisplayName` is still used correctly elsewhere for what it's actually for --
`identifyLegend.m` matches legend text by `DisplayName` because that's literally the string shown.

## `runPillar1.m`: wrapping pillar 1 into a single function, intermediates cleaned by default (2026-08-29)

Seb's own direct ask, same day: once pillar 1's individual steps (raw export, bake, identity export,
identity bake, group/tag) were each independently solid, the natural next step was collapsing them
into one call — `examples/makeExamplePanelA.m` had been hand-chaining all five steps since the very
start of this pipeline, and every new caller would otherwise have to re-learn and re-chain the same
five calls, including the easy-to-forget "bake the identity export too, not just the raw export" step.

**What was built**: `runPillar1.m` — `result = runPillar1(ax, outDir, baseName, opts)` runs
`snapshotAxesStyle` → `print(-dsvg)` → `bakeTransforms.py` → `dumpIdentitySvg.m` →
`bakeTransforms.py` (again, on the identity export) → `groupAndTagSvg.m`, returning
`result.taggedFile` (path to `<baseName>_tagged.svg`) and `result.stats` (passed through unchanged
from `groupAndTagSvg.m`). The four intermediate files this needs along the way
(`<baseName>_raw.svg`, `<baseName>.svg`, `<baseName>_identity_raw.svg`, `<baseName>_identity.svg`) are
deleted once `groupAndTagSvg.m` has consumed them, by default — `opts.keepIntermediates=true` keeps
them instead, using the exact naming convention `examples/makeExamplePanelA.m` had already established
by hand. Follows the Bass-wide "self-populating default opts" convention (zero-arg call prints help
text and returns a fully-populated default opts struct) since this is a new user-facing entry point —
deliberately NOT applied to the internal helper functions it calls, consistent with the precedent set
earlier for `groupAndTagSvg.m`/`identifyAxisSpine.m` etc., which aren't standalone entry points.

**Validated** (`test/test_run_pillar1.m`): default call cleans up all 4 intermediates and produces the
tagged SVG; `opts.keepIntermediates=true` keeps all 4; a from-scratch build of the same synthetic panel
run through the manual step-by-step pipeline (independently, in the same test) produces a
`fileread()`-BYTE-IDENTICAL tagged SVG and an `isequal`-identical `stats` struct compared to
`runPillar1.m`'s own output — i.e. the wrapper is provably not just "close to" but exactly equivalent
to calling every step by hand; zero-arg call returns a properly-populated default opts struct.
`examples/makeExamplePanelA.m` rewritten to call `runPillar1.m` with `keepIntermediates=true` instead
of hand-chaining the five steps, re-run and re-verified (6 output files, no duplicate ids) as a live
example of the intended calling convention. `test_group_tag.m` deliberately still calls each step by
hand — it exercises pipeline internals in fine-grained detail and serves as the independent
"ground truth" reference `test_run_pillar1.m`'s byte-identical comparison depends on, so collapsing it
into `runPillar1.m` too would remove that independence.

## Not yet investigated / open

- The `ScreenPixelsPerInch`-dependent bug documented in the OLD `humanMouse` engine
  (`project_humanMouse_manuscript_figure_svg_workflow.md`, a ~32% size mismatch between headless
  and interactive sessions) was NOT reproduced by the simple point-quantization rounding found
  here (sub-millimeter, universal, not environment-dependent) — its real root cause is still
  unknown and likely lives elsewhere in that engine's `copyForManuscriptPanel.m`/`savefig`/
  `openfig` round-trip, which this tool does not yet use or reproduce.
- `ax.Box='on'` (mirrored top/right spine lines) is not handled by `identifyAxisSpine.m` yet --
  errors loudly rather than silently mishandling it.
- Line+error-band pairing into one "series" now uses `Tag` equality (`assignSeriesIndices.m`,
  RESOLVED 2026-08-29 -- see this file's own "Pairing-by-identity" section above); no `humanMouse`
  convention establishes what `Tag` a real project's Line/Patch pair should share yet, so a real
  caller still has to set matching `Tag`s itself for now.
- An ad hoc `text()` annotation (e.g. `plotVessels.m`'s own vessel-ID corner label, drawn via
  `drawIdCornerBox`) is now folded into `furniture > annotations > annotation-{k}` (Seb's own ask,
  2026-08-29 -- see this file's own note above for the paint-order tradeoff this involves and how it
  was measured). Its font-size IS now corrected (RESOLVED 2026-08-29, see this file's own "Font-size
  rounding" section above) whenever exactly one still-live ad hoc `text()` object shares its exact
  content; `stats.nAnnotationFontSizeUnresolved` tracks the (rare, non-silent) case where it isn't.
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
