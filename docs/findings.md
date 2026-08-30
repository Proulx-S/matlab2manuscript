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

## `plotVessels.m` always hosts its axes in a `TiledChartLayout` — decided out of scope (2026-08-29, SUPERSEDED later the same day -- see "The copy step" section below)

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

**SUPERSEDED later the same day**, once `runPillar1.m` gained a copy step (see "The copy step:
`runPillar1.m` now normalizes `ax` onto a shared standard canvas" below): that step never exports or
bakes the ORIGINAL tiled axes at all — it only ever reads its `InnerPosition` PROPERTY value and
re-imposes that same value on a plain-axes copy, which is what actually gets exported/baked/tagged.
The ~1.2pt discrepancy documented above is specifically between a tiled axes' `InnerPosition`
property and ITS OWN rendered/exported spine geometry (a tiled-layout-engine quantization effect) —
irrelevant once nothing downstream ever exports the tiled axes itself. Confirmed empirically
(`test/test_tiledlayout_support.m`): a `TiledChartLayout`-hosted axes and a plain axes given the
SAME `InnerPosition` and identical content produce byte-for-byte-identical `stats` and a 0-pixel-diff
tagged SVG once both are routed through `runPillar1.m`.

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

## The copy step: `runPillar1.m` now normalizes `ax` onto a shared standard canvas (2026-08-29, id-prefixing note below SUPERSEDED later the same day -- see "Multi-panel composition" section below)

Seb's own design ask, same day: pillar 2's round-trip will need every panel `runPillar1.m` ever
produces to live in ONE shared physical coordinate system with the eventual composed multi-panel
figure, so that "the human resized/repositioned this panel inside the composed figure" can be read
back directly as a new `ax.InnerPosition` fraction, with no scale-factor bookkeeping. Concretely:
`runPillar1.m` now `copyobj`'s the caller's `ax` (never mutating it) into a fresh figure built on a
fixed standard canvas (default US Letter portrait, `opts.canvasSize`/`opts.canvasUnits`) before doing
anything else — every downstream step (snapshot, export, bake, identity export/bake, group/tag) runs
against this copy, never the caller's own figure. `figId`/`panId` became compulsory arguments purely
to name this copy's output files (`<figId>_<panId>_raw.svg` etc.) — embedding them into every tagged
element's own `id`, which is what will actually be needed for safe multi-panel composition, is a
DELIBERATELY DEFERRED later step (the composition/insertion step itself), not done here.

**Empirical `copyobj` fidelity investigation, before trusting this design** (scratch scripts, no
repo changes at the time): most properties survive `copyobj` untouched (`Tag`, `DisplayName`,
`LineWidth`, `Color`, ad hoc `text()` annotations, `Legend.FontSize`) but two real gotchas:
- **`copyobj(ax, newFig)` alone silently DROPS the Legend entirely** (`ax2.Legend` comes back empty)
  — must copy axes and legend together: `copyobj([ax, ax.Legend], newFig)`.
- **`XAxis`/`YAxis`/`XLabel`/`YLabel` `FontSize` are silently reset to auto-mode defaults by
  `copyobj`**, regardless of the source's mode/value — must be captured from the original BEFORE
  copying and re-applied explicitly afterward, RULERS BEFORE LABELS (same ordering rule as the
  `XAxis.FontSize -> XLabel.FontSizeMode` reset gotcha documented above, since setting a ruler's
  `FontSize` resets its own label's `FontSizeMode` back to auto if done afterward).
- **`axis square`/`axis image` (`PlotBoxAspectRatioMode`/`DataAspectRatioMode='manual'`) survive the
  copy and keep constraining the copy's drawn box**, even though `InnerPosition` itself is never
  touched by them (MATLAB shrinks/centers the drawn box inside the unchanged `InnerPosition` rect
  instead — measured directly: `axis image` squeezed a 316.8×172.8pt box down to 316.8×68.6pt).
  Resetting both Modes to `'auto'` after the copy, then re-setting `InnerPosition`, fully restores the
  undistorted box — confirmed empirically, no third property (`PlotBoxAspectRatio` value,
  `CameraViewAngleMode`, etc.) needed.

The resulting copy-step recipe, in order (see `copyAxesToStandardCanvas` inside `runPillar1.m`):
capture `ax.InnerPosition` and the four ruler/label `FontSize` values from the ORIGINAL `ax` →
`copyobj([ax, ax.Legend], fig2)` (or just `ax` if no Legend) → `ax2.PlotBoxAspectRatioMode='auto'`,
`DataAspectRatioMode='auto'` → `ax2.InnerPosition = <captured>` → re-apply the four captured
`FontSize` values, rulers then labels.

**A second, unrelated bug this surfaced**: a US-Letter canvas is large enough that the already-
documented `72/ScreenPixelsPerInch` export-rounding discrepancy (see above) exceeds the `<1pt`
tolerance `identifyLegend.m`/`groupAndTagSvg.m`'s `identifyFurniture` used for recognizing the
figure-background and axes-background rects (confirmed: this machine's `ScreenPixelsPerInch=95`, a
non-round value; a Letter canvas's actual rendered background rect came out `[0 0 613.14 792.76]`pt
against a declared/expected `[0 0 612 792]`pt — a ~1.14pt/0.76pt miss). This is NOT a
`TiledChartLayout`-specific issue (reproduces identically for a plain axes at Letter size) — it's the
existing 16×10cm test fixtures simply never having been big enough to hit it. Fixed by widening both
tolerances to `1.5pt` (matching `identifyAxisSpine.m`'s own already-widened constant for the same
underlying phenomenon), with an inline comment at both sites; the tight duplicate-rect-detection
assert a few lines below (used to recognize MATLAB's own two-`<path>` legend-box duplication) was
deliberately left untouched, since that comparison is between two paths drawn from the SAME baked
document and stays exact regardless of canvas size.

**Validated**: `test/test_run_pillar1.m` — byte-identical to the manual pipeline INCLUDING the copy
step now (a from-scratch `manualCopyStep()` helper, not just the post-copy stages, or the comparison
would silently stop being meaningful); `opts.canvasUnits`/`opts.canvasSize` override confirmed via
the exported SVG's own declared canvas size; all prior default/keepIntermediates/zero-arg-call
behavior re-verified unchanged. `test/test_tiledlayout_support.m` (new, permanent, supersedes the
scratch validation script) — see the superseded-scope note above.

## Multi-panel composition: id-prefixing in `groupAndTagSvg.m`, and `syncPanel.m`'s sync/insert operation (2026-08-29)

Seb's own design ask, same day as the copy step above: build the piece that actually lets a human
resize a panel AFTER it's inserted into a composed multi-panel figure (not on the standalone
single-panel SVG), and feed that back into MATLAB for regeneration. Two parts.

**Id-prefixing (`groupAndTagSvg.m`)**: took a required `panId` argument. Confirmed empirically
first that this is safe as a BLANKET rewrite -- neither MATLAB's own `-dsvg` export nor
`bakeTransforms.py` ever emits an `id` attribute of its own (checked directly on a probe SVG at
every stage: raw export, baked, both empty of ids) -- so there's nothing pre-existing to collide
with or need to leave alone. At the very end of the function (right before `xmlwrite`), every `id`
this function already generated gets a `{panId}-` prefix, and the SAME `<g>` MATLAB's own exporter
already wraps everything in (`getRootGroup.m`) gets `id="{panId}-root"` + `data-panel="{panId}"` set
on it directly -- reusing that existing wrapper rather than inserting a redundant new one, since by
construction every one of a panel's top-level semantic groups (furniture/axis-spine/dataseries/
legend) is already a child of it. `data-role`/`data-group` attribute VALUES are deliberately left
untouched -- unlike `id`, those are meant to repeat identically across panels (selecting every
panel's own `axis-spine` at once, e.g., is a real, intended cross-panel operation). This supersedes
the "DELIBERATELY DEFERRED" note in the copy-step section above.

**`syncPanel.m`**: places a panel into `<figId>.svg` and, on every later call, recovers wherever a
human moved/resized it and regenerates. First insertion and every later resync are the SAME
operation -- there's no separate "insert" code path -- because since the copy step (above) already
puts every panel on one shared physical canvas, a panel's placement inside the composed document and
its own `ax.InnerPosition` are the same number, just expressed as absolute points vs. a
canvas-relative fraction. Recovering an edit is therefore a DIRECT measurement (this panel's tagged
`{panId}-axis-spine-x`/`-y`'s current bounding box, divided by canvas size), never a diff against a
stored "before" value -- confirmed by inverting `identifyAxisSpine.m`'s own
`InnerPosition -> SVG box` formula and checking it reproduces a known `InnerPosition=[0.15 0.15 0.7
0.7]` from a real tagged file's own spine coordinates before writing any code (recovered
`[0.14985 0.15037 0.70092 0.69952]` -- within the same rounding budget already documented elsewhere
in this file).

**Two risk checks done before committing to this design** (Seb's own explicit ask, since both were
load-bearing assumptions):
1. **Does `bakeTransforms.py` generalize to a post-insertion human edit's transform syntax?** No --
   confirmed by inspection, not assumed: its `parse_transform` uses `MATRIX_RE.fullmatch`, which
   ONLY accepts `matrix(a,b,c,d,e,f)` and raises `ValueError` on anything else. That's correct FOR
   ITS OWN JOB (MATLAB's own `-dsvg` exporter only ever emits that one form) but wrong for a
   composed SVG a human may have re-saved from a vector editor, which can add compound
   `translate(...) scale(...)`-style transform-lists. Built a SEPARATE, general resolver instead
   (`resolveElementCTM.m`) rather than stretching `bakeTransforms.py` to a job it wasn't designed
   for -- it walks a node's ancestor chain and composes every `matrix()`/`translate()`/`scale()`/
   `rotate()` transform-list found (no `skewX`/`skewY`, same stance `bakeTransforms.py` already
   takes on shear, for the same reason: this repo's own geometry never needs it).
2. **Does `ax.InnerPosition` really correspond 1:1 to the tagged spine's own box?** Yes -- this was
   already implied by `identifyAxisSpine.m`'s own deterministic forward formula (`expectedBoxPt`
   computed directly from `ax.InnerPosition`+canvas size, no other unknowns), and confirmed the
   inverse numerically against a real file, see above.

**A real, unrelated bug surfaced writing the test for this (`test/test_sync_panel.m`)**:
`javax.xml.transform.Transformer.transform(DOMSource(node), ...)`, used to try to serialize JUST one
DOM node (to byte-compare one panel's subtree before/after an unrelated panel's resync), does NOT do
that in this MATLAB/Java environment -- confirmed with a minimal repro (two sibling `<g>` elements,
`DOMSource` given the SECOND one) that it serializes the node's entire OWNER DOCUMENT regardless of
which node was passed as the source, silently producing a passing-looking (both "before"/"after"
snapshots equally wrong) but meaningless comparison. Fixed by using DOM Level 3
`LSSerializer.writeToString(node)` instead, which IS correctly scoped to just the given node --
confirmed via the same minimal repro. Flagged here since it's a genuinely surprising, easy-to-not-notice
gotcha, not specific to this repo's own code, that could resurface anywhere else a single-node
(rather than whole-document) XML serialization is needed.

**Validated** (`test/test_sync_panel.m`): first-time insertion lands at
`opts.defaultInnerPosition`; a no-op resync (nothing edited) recovers ~the same `InnerPosition`
within the same rounding tolerance noted above; a resync after a SIMULATED edit (a hand-added
`translate(...) scale(...)` wrapper, including an aspect-ratio-changing anisotropic scale) recovers
an analytically-predicted `InnerPosition` to within 0.005 -- not just "didn't error"; two panels
sharing one composed file produce no duplicate ids and resyncing one leaves the other's own subtree
byte-identical; a simulated rotation is detected (`{panId}-axis-spine-x`/`-y` no longer
axis-aligned) and rejected with a clear `syncPanel:rotatedPanel` error rather than silently
mishandled.

**Known, explicitly flagged validation gap, NOT yet closed**: everything above is exercised against
SIMULATED edits (this repo's own test directly rewriting the composed SVG's DOM between two
`syncPanel` calls to stand in for a human's edit) -- this has NOT yet been round-tripped through a
real external vector editor (Illustrator/Inkscape). Simulated edits cover the transform-list forms
anticipated above, but an editor's actual save behavior (exact transform-list syntax emitted,
whether/how it bakes transforms away, whitespace/precision conventions) could differ in ways a
simulation doesn't catch. This is the next thing to close before trusting this loop end to end.

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
- `TiledChartLayout`-hosted axes (i.e. `plotVessels.m` and anything like it) -- RESOLVED 2026-08-29,
  see "The copy step" section above: `runPillar1.m`'s `copyobj`-based copy detaches cleanly from a
  `TiledChartLayout` parent, confirmed via `test/test_tiledlayout_support.m`.
- Pillar 2 (the round-trip: harvest wherever a human repositioned/resized a panel after inserting it
  into a composed multi-panel figure, feed back into MATLAB, regenerate, re-place) -- BUILT
  2026-08-29 as `syncPanel.m`, see "Multi-panel composition" section above. Still open: a real
  external-vector-editor round-trip has not been exercised, only simulated edits (see that section's
  own explicitly-flagged validation gap).
- `id` collisions across multiple panels in one composed manuscript figure -- RESOLVED 2026-08-29,
  see "Multi-panel composition" section above: `groupAndTagSvg.m` now takes a required `panId` and
  prefixes every id it generates with it.
- Colorbar support (RESOLVED 2026-08-29, see "Colorbar support" section above) is fully tested only
  for the default `Location='eastoutside'` -- `west`/`north`/`south` (with or without `outside`)
  share the same `repositionColorbar` formula but have no dedicated test.
- Image-type dataseries (`imagesc`/`image` as the actual plotted data) -- explicitly deferred, its
  own separate round: `Image` objects have `Tag` but no `DisplayName` at all (a real gap in the
  existing pairing/legend logic, which assumes `DisplayName` exists), multiple images CAN coexist
  in one axes (no "only one" assumption is safe), and a data image renders via the exact same
  pattern-filled-rect mechanism the colorbar's own gradient does (confirmed real while building
  colorbar support -- `isDescendantOfTag(node,'pattern')` in `groupAndTagSvg.m`'s annotation
  catch-all will matter again here).

## Colorbar support (2026-08-29)

Full colorbar identification/tagging, plus the `runPillar1.m` copy-step and `syncPanel.m` round-trip
support it needs, built on top of the pillar-2 mechanism above. Several real, non-obvious mechanics
found along the way, in the order they surfaced:

**`imagesc()`/`image()` resets `ax.XColor`/`YColor` back to default** -- exactly the same family as
the already-documented "`plot()` resets `FontSize`" gotcha. Only matters for color-identity work
(see below); set axis colors AFTER the data-plotting call, never before.

**Identity-color encoding extends cleanly to the colorbar's own outline/ticks/tick-labels.**
`cb.Color` is the single property controlling all three at once (confirmed empirically: an exact
hex match appears in the raw SVG for all three). `colorbarIdentityColorHex.m` reserves `roleCode=3`
in `seriesRoleColorHex.m`'s own `(seriesIndex,roleCode,occurrence)` scheme -- a value real
per-series data never uses (`computeIdentityColors.m` only ever assigns 1='value'/2='conf') -- so it
can never collide. `dumpIdentitySvg.m` temporarily recolors `ax.Colorbar.Color` the same
explicit-try/catch way it already recolors Line/Patch objects.

**The gradient itself is a raster `<image>`, referenced via a `<pattern>` whose own `x`/`y`/`width`/
`height` exactly match the outline's bbox** -- but the element that actually PAINTS with that
pattern (`fill="url(#...)"`) is a plain closed-rect `<path>`, the exact same 5-point M-L-L-L-L shape
`findClosedRectPaths.m` already parses for figure/axes-background/legend-box. So the gradient box is
found as "the one closed-rect `<path>` whose bbox matches the identity-matched outline's bbox" --
no `<pattern>`/`<image>` parsing needed. Two real consequences of this, both confirmed real while
building `identifyColorbar.m`/`groupAndTagSvg.m`:
  - The colorbar's gradient box is exactly the same *kind* of closed-rect `<path>`
    `identifyLegend.m` hunts for, and was mistaken for a second legend-box candidate. Fixed by
    identifying the colorbar BEFORE the legend and passing its bbox as a new `excludeRects`
    parameter to `identifyLegend.m`, excluded by CONTAINMENT (not exact match) -- MATLAB also draws
    several tiny (~0.5pt) decorative corner-cap closed-rect `<path>`s at the colorbar's own corners,
    which an exact-bbox exclusion would miss (`identifyColorbar.m`'s own `decorationNodes`, tagged
    and folded into the colorbar group so they don't fall to the unrelated "annotations" catch-all).
  - The `<pattern>` definition's own `<image>` child (a resource DEFINITION, never itself a directly
    rendered element) was being caught by `groupAndTagSvg.m`'s annotation catch-all, since a bare
    `getElementsByTagName('image')` scan doesn't distinguish definition content from real content.
    Fixed with a new `isDescendantOfTag(node,'pattern')` check in that catch-all loop. This will
    matter again for image-type dataseries (a separate, not-yet-built round) -- same fix applies.

**MATLAB draws the colorbar's own box-edge/ruler line duplicated multiple times** (confirmed via
direct inspection: the tick-side edge 3x, the other 3 edges 2x each), interleaved with the gradient
box's own opaque fill in a specific original order. Tried keeping only the last (topmost) duplicate
per edge and deleting the rest as "provably redundant" -- this made the (already small) pixel-diff
WORSE, not better: a stroke's own half-width bleeds slightly OUTSIDE the gradient rect's exact edge
coordinate, so an earlier duplicate is NOT actually fully hidden by the later opaque fill the way a
naive single-z-order argument suggests. Reverted to relocating every duplicate (all ending up after
the gradient box, since that's relocated first) -- the closest achievable match without abandoning
the "flatten into semantic groups" design for this one corner case. Residual: a small, precisely
understood, PURELY COSMETIC pixel-diff (~0.17% of canvas, confined to sub-pixel antialiasing
blending exactly along the colorbar's own edges) -- `test/test_colorbar.m` asserts a budget (5000)
well above the observed ~1500, not zero, with this reasoning inline.

**A colorbar's own tick-label `<text>` can coincidentally collide with axis tick-label matching.**
Since a colorbar spans the box's full height, one of its own tick labels can land inside
`matchTickLabels`'s generous "just below/left of the box" geometric window purely by y/x-coordinate
coincidence, AND happen to share numeric content with an axis tick label (e.g. both showing "0").
Fixed by adding an `excludeText` parameter to `matchTickLabels`, same exclude-list discipline
`identifyLegend.m` already uses for legend text.

**`ax.Colorbar.Location`'s default (`'eastoutside'`) is what non-idempotently re-shrinks
`InnerPosition`** every time it's set (the "InnerPosition + colorbar" problem flagged as
investigate-in-depth two rounds ago) -- confirmed exactly per that investigation's own hypothesis.
`'east'`/`'west'`/etc. (no `outside` suffix) and `'manual'` do not touch `InnerPosition` at all and
are idempotent under repeated sets. Fix in `runPillar1.m`'s copy step: capture the colorbar's
current `Position` while still in its original `Location`, copy it together with `ax`/`Legend`
(`copyobj(ax)` alone drops BOTH Legend and Colorbar, confirmed empirically), then immediately switch
the copy's colorbar to `Location='manual'` and reapply the captured position -- BEFORE touching
`InnerPosition` at all. `cb.FontSize`/`cb.Label.FontSize`, unlike the axis ruler/label FontSize
properties, are NOT reset by `copyobj` (confirmed empirically) -- no re-application needed.

**Repositioning a decoupled colorbar for the round-trip** (`syncPanel.m`'s `innerPositionOverride`
case): since `Location='manual'` no longer auto-follows the box, `repositionColorbar` (in
`runPillar1.m`) recomputes the colorbar's `Position` to preserve the same physical gap and width (or
height, for horizontal orientations) relative to the box's own relevant edge, now anchored to the
NEW `InnerPosition` instead of the old one -- implemented generally for all 4 base directions
(east/west/north/south, with or without the `outside` suffix); a colorbar left in `Location='manual'`
by the CALLER (not by this tool) is left untouched, since there's no directional reference to
recompute from. **Fully tested only for the default `'eastoutside'`** (`test/test_colorbar.m`,
including an aspect-ratio-changing resize) -- the other 3 directions share the same formula but have
not been exercised by a test.

**Deliberately out of scope for this round**: image-type dataseries (`imagesc`/`image` as the actual
plotted data, not just a colorbar) -- confirmed real complications while building this (a data image
renders via the exact same pattern-filled-rect mechanism as the colorbar's own gradient, and
`Image` objects have `Tag` but no `DisplayName` at all) are tracked as their own, separate,
not-yet-built round.
