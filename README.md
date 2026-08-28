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
that start life as one tile inside a larger `tiledlayout` (`plotGaussianFitPanels.m`,
`plotFaaSpace.m`) — those need their own decomposition step, out of scope for now.

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
  `plotVessels` panel.
- `test/` — MATLAB scripts validating the above (see file headers for what each proves). Several
  deliberately exercise a real plotting function from `humanMouse` (`plotVessels.m`) rather than
  synthetic data — adjust each test's `workDir` if that project lives elsewhere on this machine.
- `docs/findings.md` — consolidated empirical findings from the 2026-08-26 research session
  (SVG/EPS/PDF export behavior across every MATLAB renderer, the `ScreenPixelsPerInch`/72 scale
  factor, font-size rounding, why no existing tool solves this). Read before extending this tool —
  several of these took many rounds of testing (including two self-corrected mistakes) to nail
  down and are easy to re-break by assumption.

## Status (2026-08-26)

Early prototype stage. The matching primitive and the baking/registry mechanism are both validated
against real data; the axis-spine grouping/tagging pass and the mm-based resize round-trip
(MATLAB `PositionConstraint='innerposition'` + `InnerPosition`, confirmed to work exactly once
transforms are baked) are designed and spot-verified but not yet assembled into an end-to-end
per-panel pipeline.
