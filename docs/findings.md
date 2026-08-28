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

## Not yet investigated / open

- The `ScreenPixelsPerInch`-dependent bug documented in the OLD `humanMouse` engine
  (`project_humanMouse_manuscript_figure_svg_workflow.md`, a ~32% size mismatch between headless
  and interactive sessions) was NOT reproduced by the simple point-quantization rounding found
  here (sub-millimeter, universal, not environment-dependent) — its real root cause is still
  unknown and likely lives elsewhere in that engine's `copyForManuscriptPanel.m`/`savefig`/
  `openfig` round-trip, which this tool does not yet use or reproduce.
- Legend-internal grouping/tagging (individual legend entries) not yet designed.
- The axis-spine identification pass itself (finding which SVG element(s) correspond to the spine,
  vs. tick marks/gridlines) is designed conceptually but not yet built as real code in this repo.
