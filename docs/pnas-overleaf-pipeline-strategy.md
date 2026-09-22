# Strategy: porting huMoMain's figures onto a PNAS/Overleaf pipeline

Written 2026-09-17, **revised 2026-09-22** after a review against the engine as it actually
exists and a panel-by-panel inventory of the five figures. This is a **strategy, not an
implementation plan with code** — the agreed approach is to port figures one at a time,
together, so this document fixes the shared architecture and a starting order, and stops
short of designing each figure's layout.

**What changed in the revision, in one paragraph.** The first draft proposed a stamped base
and a three-way merge to reconcile a hand-edited `layout.json` against the SVG. That solves
the *old* engine's problem (two mutable copies of layout state), which the new engine's
`syncPanel.m` already avoids by keeping exactly one: the composed SVG. The revision keeps
that single writer (§3), drops the content hash (§4), replaces the file-size-based figure
assessment with a grounded inventory that moves figure 1 to the front and figure 5 back
(§6), states the content-preservation narrowing as a decision rather than an omission and
gives panel letters a mechanism (§2), and adds a readiness checklist for the first real test
(§13).

**Treat it as provisional.** The delivery end (§8) is measured and can be relied on; the
figure-side design (§2–§4) is a considered proposal that has not yet met a real figure, and
the first port should be expected to change it. §12 lists what is most likely to shift.

Scope: main figures 1–5 of huMoMain, plus supporting information. Two companion documents,
neither of them in this repository: `scratch/pnas/README.md` in the original worktree
(gitignored, so it does not survive the worktree) records the PNAS specification and the
template provenance; `figtest/README.md`, committed in the Overleaf manuscript project,
records what the delivery end is already proven to do and the six traps found while proving
it.

## 1. The two properties that must hold at once

1. **Regeneration.** Change the underlying data, re-run, and the figure is correct with no
   manual work.
2. **Manual adjustment.** Hand adjustments survive that regeneration.

These two are in direct conflict unless every manual adjustment is captured somewhere durable
and machine-readable that regeneration reads *before* it overwrites anything. That single
sentence is the whole design; everything below follows from it.

The old engine (`manuscriptFigTools/`) satisfied it with a `layout.json` sidecar that was
both the source of truth and hand-editable, alongside an SVG that was also hand-editable —
two writers, and hence its documented ordering hazard. The new engine already made the other
choice (§3).

## 2. Layer model

| Layer | What it is | Durable? | Hand-edited? |
|---|---|---|---|
| **L1 Content** | Upstream analysis code draws MATLAB axes from data | code + data are durable | never |
| **L2 Composition** | One committed SVG per figure, on a PNAS canvas, holding every panel at its place plus a manual layer | **yes — version controlled, the single source of layout truth** | **yes, in a vector editor or numerically (§3)** |
| **L2′ Layout record** | Per-figure `FigN.layout.json`, *derived* from L2 on every compose | yes, committed beside the SVG | **never** — read only to re-seed a lost SVG |
| **L3 Delivery** | SVG → PDF at exact publication size → lint → Overleaf | no — build artifact | never |

The invariant, inverted from the first draft: **the composed SVG is durable and is the one
place layout lives.** Each panel inside it is disposable — regeneration replaces that panel's
own subtree wholesale — but the document, the positions, and the manual layer persist. The
layout JSON is a by-product for diffing, review, and disaster recovery, never an input.

**Permitted manual adjustments, as a deliberate closed list:** panel position and panel size
(via the spine box, which is what `syncPanel.m` measures), and anything drawn in the
figure-level manual layer (arrows, brackets, free text). Everything *inside* a panel — a
nudged tick label, a legend moved inside the axes, a recoloured or deleted trace — is
regenerated and belongs in MATLAB.

**This is a narrowing, stated as a decision.** In August the old engine grew three
mechanisms (keyed content patching, an `inkscape:label` survival rule, a per-panel manual
group) because Seb explicitly wanted a recolour or a deletion made in Inkscape to survive
regeneration. This strategy does not carry them over. The reasoning: each of them
re-introduces a second writer for content the pipeline also writes, which is precisely the
class of problem §3 removes, and the one legitimate need they served — "I want this trace
gone / this colour changed in the paper" — is a one-line style option in the plotting call
that is then also correct in every diagnostic figure. If a real port shows a manual content
edit that genuinely cannot be expressed upstream, that is the moment to revisit, with the
concrete case in hand.

**Panel letters.** Today no code draws them; they exist only as hand-typed Inkscape text. The
pipeline should draw them: one `<text>` per panel in a figure-level `labels` group, at a
fixed offset from that panel's spine box, regenerated on every compose so a moved panel
carries its letter with it. A letter hand-moved in Inkscape is lost on the next compose, by
design — the offset is a figure-wide style setting, not a per-letter adjustment. Font, size,
and case are set once per manuscript (PNAS: uppercase, bold, same family as the figure).

## 3. One writer for layout (replaces the first draft's three-way merge)

The first draft diagnosed the old engine's hazard correctly and then proposed the standard
remedy for two writers: stamp the base, merge three ways. But `syncPanel.m` never had two
writers. On every call it **measures the panel's current spine box directly from the
composed SVG**, however it got there, re-renders the panel natively at that geometry, and
splices the fresh subtree back in. There is no sidecar, no "which side moved", no ordering
hazard, and no `updateFigxN.m` family. Reintroducing a hand-editable JSON, and a third file
to referee it, would be building the old engine's problem back in order to solve it.

So the revised proposal is to **keep one writer** and add two small things around it:

1. **Numeric placement writes into the SVG.** A `placePanel(composedFile, panId, boxMM)`
   that sets a panel's spine box in millimetres by editing the composed document directly
   (the same wrapper-transform an editor would leave) — so precise placement never needs a
   second file. First placement of a new panel goes through the same function with a
   default box. `syncPanel.m`'s next call then measures it back like any other edit.
2. **A derived layout record.** Every compose writes `FigN.layout.json` — per panel, the
   measured spine box in mm plus the canvas — as a *report*, never read on the normal path.
   Its two uses: a readable diff in code review when a figure changes, and re-seeding the
   composed SVG if it is ever lost or corrupted (`placePanel` per entry, then re-sync). It
   is written after the SVG, so it can never be newer than the truth.

Consequences:

- **Position and size edits, moves included, are captured with no extra step.** A pure move
  was the old engine's ambiguous case; here it is just a different measured box.
- **Panel set changes are not a special case.** A new panel has no box in the SVG, so it gets
  the default placement. A panel that disappears from the MATLAB side simply stops being
  re-synced and stays in the SVG until removed explicitly (`removePanel`); it is never
  silently deleted, and the layout record shows it as stale. This retires §12.1 of the
  first draft.
- **The conflict case cannot arise**, so nothing needs to fail loudly about it. What *does*
  need to fail loudly is rotation (already does) and a panel whose spine elements can no
  longer be found after an editor save (already does).

**The number that had to be checked before trusting this at PNAS scale — now measured.**
`test_sync_panel.m` only asserts that a no-edit resync recovers the same box to within 0.01
of the canvas, which at 87 mm is 0.87 mm and visible. Measured 2026-09-22 (six no-edit cycles
per canvas, `scratch/measure_resync_drift.m`, R2025a headless):

| Canvas | First resync vs. requested box, max over x/y/w/h | Cycles 2–6 |
|---|---|---|
| 87 × 60 mm | 0.29 mm | identical to cycle 2, zero drift |
| 178 × 120 mm | 0.22 mm | identical to cycle 2, zero drift |

So the residual is a **one-time quantisation** between the box requested and the box MATLAB
actually renders (the same `72/ScreenPixelsPerInch` rounding family the matchers already
tolerate), after which the measured box is a fixed point. It does not accumulate. A quarter
of a millimetre on first placement is below what a manuscript reader can see; if it ever
matters, `placePanel` can iterate once. The test's tolerance should still be tightened to
what was measured, so a regression shows up.

## 4. Regeneration on data change

Two separable questions: how do we know content changed, and what do we rebuild.

**Rebuilding — resist over-engineering.** Panel content arrives as *live MATLAB handles* from
`doIt_human.m`, which has already run the analysis, so by the time a figure function is
called the expensive part has happened and recomposing a whole figure is cheap. Per-panel
incremental rebuild has nothing to save.

**Knowing — drop the content hash.** The first draft proposed fingerprinting each panel's
inputs. §12.3 of that draft already conceded there is nothing concrete to hash at the point
where the figure function runs. The honest, sufficient mechanism is coarser:

- Delivery (§8) is an **explicit step**, never a side effect of composing. It records, per
  figure, the hash of the composed SVG it last delivered.
- Delivery lists what changed since it last ran — SVG hash differs, or a panel was added or
  removed per the layout record — and delivers only on an explicit call per figure. A human
  has therefore looked at a changed figure before it ships; that is the gate.
- Staleness the other way round — a delivered PDF older than its SVG — is one mtime
  comparison and a warning at the end of `doIt_human.m`.

That is the honest version of "automatic regeneration": automatic recomposition, with an
explicit gate where a human's judgement is genuinely required.

## 5. The canvas retarget — the main porting cost

The old engine composes every figure on a **US-letter page**:

```matlab
% initManuscriptFigureSvg.m
pageWidthMM  = 215.9;
pageHeightMM = 279.4;
% makeFigx5.m: widthMM = (215.9 - 2*10 - 2*5) / 3 = ~61.97 mm
```

PNAS does not want a page. It wants a standalone figure at one of exactly three widths —
87 / 114.3 / 178 mm — and at most 225 mm tall, and explicitly less, to leave room for the
legend. So porting is fundamentally **retargeting the canvas**, and `syncPanel.m` already
takes the canvas as an argument (`opts.canvasUnits`/`opts.canvasSize`, used once to create
the composed file; thereafter the file's own root size is the truth). This is a one-argument
change rather than a redesign. Millimetres are not a MATLAB figure unit, so the preset is
expressed in centimetres.

The consequence to plan around: **font sizes do not scale with the canvas.** Panels are
replotted natively at their target size (deliberate — a resize is a re-render, never a
scaled vector), so shrinking the canvas makes text *relatively larger*. Legibility improves,
but the old engine's layout numbers stop meaning anything:

- full-width figures shrink 195.9 → 178 mm usable, a mild 0.91× — layouts mostly survive;
- 1-column figures shrink 195.9 → 87 mm, a 2.25× reduction — layouts must be rebuilt.

Which is why the width class has to be decided per figure, first, and why doing this one
figure at a time with a human looking at it is the right call rather than a batch
conversion.

## 6. Per-figure assessment — grounded

Every panel in all five figures resolves to exactly one axes (three of the five figure
functions assert it). What varies is the graphics *content*, checked against what the engine
matches today — Line, Patch (error bands and stim bars), Image, Legend, Colorbar at
`eastoutside`, ad hoc `text()`:

| Figure | Panels | Content | Blocker for the engine as it stands |
|---|---|---|---|
| **1** `makeFigx1human.m` | 4 metric panels (Line, CI Patch, stim Patch, id text, Legend) + 1 cross-section (Image, contour Lines) | all supported | **none** |
| **4** `makeFigx4human.m` | group-metric panels and response-timeseries tiles (Line, CI Patch, Legend, id text) | all supported | **none** — but its `doIt_human.m` call is currently broken: two of the inputs it passes are commented out just above it |
| **5** `makeFigx5.m` | 2 Faa-space panels (~256 Lines each, one `eastoutside` Colorbar) + 1 histogram panel | panels 1–2 supported | **Histogram** (two `histogram` objects, panel 3). Driven from `doIt_faa.m`, not `doIt_human.m` |
| **3** `makeFigx3.m` | 3 image panels (Image, scale-bar Line + text, `eastoutside` Colorbar) + 3 scatter panels | a/c/e supported | **Scatter** (panels b, d, f) |
| **2** `makeFigx2xabcdefgh.m` | 8 brain/crop/overlay panels | Image supported | **Polygon** mask outlines (`plot(ax, polyshape)`), **two stacked Images** per axes (grey underlay + alpha-masked RGB overlay), and **thin colorbars on a hidden helper axes** that the old engine's copy step silently deletes |
| **SI** | no code at all — plain `printFigs` of whole tiled diagnostic figures, plus `quiver` arrows | — | not a port: greenfield, passthrough (§7) |

The SI is a different document with different geometry: its project ships `pnas-new.cls`
**v1.45**, not the manuscript's v1.47, and its template is **single-column**. Measured, its
text measure is 505.694 pt = **177.74 mm** — the 2-column figure width to within 0.06 mm —
on a full US Letter page. So SI figures are naturally authored at 178 mm and there is no
column structure to reason about.

**Order: 1 → 4 → 5 → 3 → 2, then SI.** Figure 1 leads because it is the only figure that is
both fully within the engine's current content support *and* already structured one axes
per panel with a passthrough-shaped image panel, so it exercises the whole path — composition,
re-sync, letters, PDF, lint, delivery — without a single new matcher. Figure 4 second for
the same reason, once its call site is repaired. Figure 5 third: small, but it needs either
a Histogram matcher or a passthrough for its third panel. Figure 3 adds Scatter. Figure 2
last: it is the one that needs the raster ppi lint to be real, and it carries three content
blockers of its own.

The first draft put figure 5 first from file sizes alone; the inventory reversed that. If
figure 1's port shows something that makes another figure the better teacher, reorder
without ceremony — the point of going one at a time is to be able to.

## 7. Escape hatch: passthrough figures and panels

Not every figure should be composed. A **passthrough** figure's content is a committed,
hand-made SVG or PDF — a schematic, a montage, a legacy figure nobody wants to reconstruct.
It gets the whole delivery path (canvas size check, compliance lint, stable filename, push)
and none of the composition or layout harvesting.

The same hatch applies at **panel** granularity: a panel whose content the engine cannot yet
match (a histogram, a scatter) can be exported as a plain baked SVG group and placed with
`placePanel`, giving up only re-sync for that panel. That is how figure 5 can be ported
before a Histogram matcher exists, and how any panel can graduate to full support later
without anything downstream changing.

## 8. The Overleaf contract

Proven by `figtest` (committed in the manuscript project):

- **The pipeline writes only figure PDFs, at stable filenames, and never touches a `.tex`
  file.** `figures/fig1.pdf` … `fig5.pdf`, `figures/figS1.pdf` … . The `\includegraphics`
  lines are written once, by hand, in Overleaf. This is what keeps the conflict surface at
  zero while a human edits prose in the browser.
- Deliver **PDF only**. TIFF and SVG cannot be included at all; EPS rounds its bounding box
  up to whole points; JPEG is discouraged by PNAS. PDF keeps text as text and embeds
  ArialMT, which is on PNAS's accepted-font list.
- `\includegraphics` takes **no width or scale option** — the file is already at final
  size. A scaling option would mask exactly the defects the lint should catch.
- **Four float layouts are available, and the width class is what selects between them.**
  `figure` at 87 mm, `figure*` at 178 mm, and `SCfigure*` — a full-width float with the
  caption beside the figure — at either 114.3 mm (the good balance) or 87 mm (for a long
  legend). `SCfigure*` needs no extra package; the class already loads
  `sidecap[rightcaption]`. sidecap keeps the *graphic's* natural width and shrinks the
  *caption* to whatever is left of the 512 pt block, so a side-caption figure is still
  authored at one of the three permitted widths and **the pipeline needs no special case for
  it** — only the manuscript's `\begin{...}` line changes. This is also the most plausible
  reason the 1.5-column width exists: it is the one that leaves a usable caption strip
  (62.1 mm, against 89.7 mm behind an 87 mm graphic).
- **Figures go after the first-page text block.** Placing a float while `\Firstpage` is in
  effect overflows the page by 199.69 pt; this is a defect in `pnas-new.cls` v1.47 that the
  pristine PNAS template triggers too. Call `\Endparasplit` first, as the template does.
- **Fetch and rebase before every push.** Already hit once: the remote had moved because of
  a UI edit, and the push was rejected. The bridge allows no branching, so delivery must
  always be a fast-forward onto current `main`.
- The bridge token lives only in `~/.netrc` and must never reach a command line, a remote
  URL, or a commit — this repository is public.

## 9. What gets built once, in matlab2manuscript

Status against the engine as of 2026-09-22:

| # | Piece | Status |
|---|---|---|
| 1 | **PNAS canvas preset** — the three widths in cm, a height cap, 1:1 authoring | trivial: `syncPanel.m` already takes `canvasUnits`/`canvasSize`; needs a named preset and the height guard |
| 2 | **Compose + re-sync** | **built** (`syncPanel.m`, `runPillar1.m`), simulated edits only |
| 3 | **`placePanel` / `removePanel`** + derived `FigN.layout.json` (§3) | not built, small |
| 4 | **Panel letters** (§2) | not built, small |
| 5 | **SVG → PDF export** via librsvg, asserting page box, embedded font, text kept as text | proven by hand in `figtest/build.sh`; needs a MATLAB wrapper. Not Inkscape: its `--export-text-to-path=false` silently *enables* text-to-path |
| 6 | **Compliance lint**, failing loudly: text ≥ 6 pt, strokes ≥ 0.25 pt, RGB only, font family on the accepted list, raster ppi ≥ 300/600/1000 by artwork class, height under the cap, page box equal to one permitted width | not built. **Lint the SVG**, not the PDF: `groupAndTagSvg.m` already writes MATLAB's live font size back as the authoritative value, and this machine has no PDF parser |
| 7 | **Passthrough path** (§7) | not built, small |
| 8 | **Delivery** — copy into the Overleaf clone, fetch, rebase, commit, push, record the delivered hash (§4) | not built; the manual sequence is proven |
| 9 | **Real-editor round trip** — save the composed file from Inkscape, re-sync | not done; the standing next item since 2026-08-30 |

Every new user-facing MATLAB function follows the project's no-arg-call convention: a bare
call prints help and returns fully-populated default opts, with every documented field
present even as an empty placeholder.

## 10. Decisions to make, per figure and up front

Up front:

- **Font: standardise on Arial everywhere.** Genuine Arial is installed, it is on PNAS's
  accepted list, and it embeds as `ArialMT`. Naming `Helvetica` in MATLAB is a lottery
  between Nimbus Sans, TeX Gyre Heros and Liberation Sans depending on which converter runs,
  none of which is on the list.
- **Where the Overleaf clone lives** — inside huMoMain at a fixed path, or outside it. Inside
  is more convenient; outside keeps a credential-bearing remote out of the project repo.
  Recommendation: outside, e.g. a sibling of the project, path given in the doIt.
- **Delivered PDFs keep text as text.** Yes: outlining text would make the 6 pt check
  impossible and would defeat the editable round-trip.
- **The composed SVGs are committed** in huMoMain (§2), under a fixed directory. The old
  engine's output directory was never tracked, which is why no `manuscriptFigures/` exists
  in either clone today.

Per figure, when we get to it: its PNAS width class, its panel inventory, and which of its
panels are composed versus passthrough. **For figure 1 the proposal is 178 mm** (2-column,
`figure*`): the four metric panels stack in a column on the left, the cross-section sits on
the right, each metric panel roughly 105 × 21 mm and the cross-section roughly 65 mm wide.
To be looked at, not assumed.

## 11. Migration stance

Do **not** extend `manuscriptFigTools/`. It is the engine `matlab2manuscript` was restarted
from scratch to replace, and it is superseded rather than a base to build on. The one thing
worth carrying across is knowledge, not code: its history of what Seb wanted (§2's
narrowing is written against it), its render-to-raster verification discipline, and its
list of MATLAB gotchas (`copyobj` cannot copy a `yyaxis` axes; a `TiledChartLayout` tile
must be reparented before it can be positioned; the machine's dark `GraphicsTheme` default
makes axis furniture invisible on a white page unless forced black).

The two can coexist safely during the port because `manuscriptFigures/` is absent from both
clones, so the old engine currently produces nothing and there is nothing to break. Per
figure: pick the width class, build the replacement on `syncPanel`, re-tune the layout,
lint, deliver, accept — and only then delete that figure's `makeFigxN.m` and `updateFigxN.m`.

## 12. What we will only find out by doing it

Roughly in order of how likely each is to change the design.

1. **What a real Inkscape save actually does to the file.** `syncPanel.m` round-trips a
   simulated resize; an editor's real save (transform syntax, baking behaviour, precision,
   whether it preserves the `{panId}-axis-spine-*` ids the measurement depends on) has not
   been exercised. If Inkscape rewrites structure more aggressively than expected the design
   survives — the SVG is still the one writer — but the measurement may need to be more
   forgiving about what it matches on.
2. **How much MATLAB-side style work each retarget needs.** §5's arithmetic says a 1-column
   figure shrinks 2.25×, and since fonts do not scale, relative text grows. Whether that
   lands legible, or needs per-panel font/tick/label intervention, cannot be known without
   replotting a real panel at the target size and looking at it. This is the single biggest
   unknown in the per-figure cost, and figure 1 at 178 mm is the gentle case.
3. **Whether panel letters at a fixed offset are enough**, or whether a real figure needs
   per-letter placement. If it does, the offset becomes a per-panel attribute in the SVG
   (measured like the box), not a JSON field.
4. **Whether the compliance lint on the SVG misses anything the conversion introduces.**
   Probably a PDF-side check of page box and embedded font is enough, and both are already
   measured by hand in `figtest`.
5. **Which of the spec's three disagreeing width values to author at.** The pica values
   match the class best (0.03 mm), the cm values are what the guidelines headline. The
   difference is 0.19 mm and well inside PNAS's own internal spread, so this probably does
   not matter — only a real submission settles it.
6. **How much friction the Overleaf bridge actually causes** once prose editing and figure
   delivery are both happening often. A question about working habits, not tooling.
7. **The height budget.** The guidelines say at most 225 mm and explicitly less, without
   naming a number. Pick a cap, revise it the first time a real caption does not fit.

None of these block starting. They are the reason to start with one figure.

## 13. Readiness for the first test: figure 1

"Ready to test" means: run `doIt_human.m`'s figure-1 section, get a committed `fig1.svg` on a
178 mm canvas with five placed panels and letters, open it in Inkscape and move a panel,
re-run, see the move kept, render to PDF, and see it sit in the manuscript at the right size
with no scaling option. Against §9, that needs:

**Already in place**
- Compose and re-sync on an arbitrary canvas (`syncPanel.m`; centimetres accepted).
- Every figure-1 panel's content is within current matcher support (§6).
- PDF rendering and the Overleaf placement, by hand (`figtest/build.sh`).

**Must exist before the test** (all small; none is research)
- A canvas preset and height guard (§9.1).
- `placePanel` for first placement and numeric nudges, and the derived layout record (§9.3).
- Panel letters (§9.4).
- A MATLAB wrapper for the librsvg export with its page-box and font assertions (§9.5).
- A figure-1 wrapper in huMoMain that calls `syncPanel` once per input axes and once for the
  cross-section, replacing `makeFigx1human.m`'s call site in `doIt_human.m` — Seb's live
  script, so edited via a checkpointed worktree, never in place.

**Measured, no longer a question**
- No-edit resync drift on PNAS-sized canvases: a one-time ≤ 0.29 mm quantisation, then a
  fixed point (§3). Nothing to build for it.

**Can wait until after the first look**
- The compliance lint (§9.6) — the first PDF can be checked by hand.
- Automated delivery (§9.8) — copy, commit and push by hand the first time.
- The real Inkscape round trip is *part of* the test, not a prerequisite for it.

Delivery of figure 1 into the manuscript closes the test. After that, figure 4.
