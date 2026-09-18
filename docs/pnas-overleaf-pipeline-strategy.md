# Strategy: porting huMoMain's figures onto a PNAS/Overleaf pipeline

Written 2026-09-17. This is a **strategy, not an implementation plan with code** — the
agreed approach is to port figures one at a time, together, so this document sketches the
shared architecture and a starting order, and deliberately stops short of designing each
figure's layout.

**Treat it as provisional.** The delivery end (§8) is measured and can be relied on; the
figure-side design (§3, §4) is a considered proposal that has not yet met a real figure,
and the first one or two ports should be expected to change it. §12 lists what is most
likely to shift. Where this document sounds decided, read "current best guess" — it is
written in the declarative to be useful, not because the questions are closed.

Scope: main figures 1–5 of huMoMain, plus supporting information. Two companion
documents, neither of them in this repository: `scratch/pnas/README.md` in this worktree
(gitignored, so it does not survive the worktree) records the PNAS specification and the
template provenance; `figtest/README.md`, now committed in the Overleaf manuscript
project, records what the delivery end is already proven to do and the six traps found
while proving it.

## 1. The two properties that must hold at once

1. **Regeneration.** Change the underlying data, re-run, and the figure is correct with
   no manual work.
2. **Manual adjustment.** Hand adjustments survive that regeneration.

These two are in direct conflict unless every manual adjustment is captured somewhere
durable and machine-readable *outside* the artifact that regeneration overwrites. That
single sentence is the whole design; everything below follows from it.

The existing engine already understands this — `manuscriptFigures/FigxN.layout.json`
holds positions and sizes in millimetres, and the `.svg` is rebuilt from it. What it
does not have is a way to tell *which side moved*, which is the problem §3 solves.

## 2. Layer model

| Layer | What it is | Durable? | Hand-edited? |
|---|---|---|---|
| **L1 Content** | Upstream analysis code draws MATLAB axes/figures from data | code + data are durable | never |
| **L2 Layout** | Per-figure JSON: which panel, where, how big, on which PNAS canvas | **yes — version controlled** | **yes, this is the only place** |
| **L3 Composition** | One SVG per figure, assembled from L1 at L2 positions | no — build artifact | in an editor, then harvested back to L2 |
| **L4 Delivery** | SVG → PDF at exact publication size → lint → Overleaf | no — build artifact | never |

The invariant: **the SVG is disposable, `layout.json` is durable.** Anything done in
Inkscape that cannot be expressed in L2 will be lost on the next regeneration — so the
system must either harvest it or say loudly that it cannot, never silently drop it.

That makes the set of permitted manual adjustments a deliberate, closed list. Proposed:
panel position, panel size, panel-label position, and annotation (arrow/text) position.
Everything else — a nudged tick label, a legend moved inside the axes, a recoloured
trace — belongs in MATLAB, because the SVG cannot keep it. Being explicit about this
closed list up front is what stops the pipeline from quietly eroding.

## 3. Fixing the ordering hazard (the one real architectural change)

This is worth doing properly because it is the current engine's sharpest edge, and it is
documented at length in `manuscriptFigTools/harvestManuscriptFigureLayout.m`:

> "this ALWAYS overwrites layout.json's xMM/yMM/widthMM/heightMM with values derived
> from whatever is currently in the .svg. If you hand-edit layout.json directly (any
> field), run this panel's makeFigX_Z_z.m next … BEFORE ever running updateFigX_Z_z.m
> again — otherwise update just re-derives your old values back from the still-stale
> .svg."

The cause: there are **two mutable copies of the same state** — `layout.json` and the
SVG's `transform` — and each can be edited independently, with no record of what they
agreed on last. So a pure *move* is genuinely ambiguous with a hand-edited-but-unapplied
`layout.json`, which is exactly why a resize can be auto-harvested but a move needs an
explicit `updateFigxN.m` call, and why the ordering hazard exists at all.

**The proposal is to record the base** — untested, but the diagnosis above is solid and
this is the standard remedy for it. At every composition, write a sidecar
`FigxN.built.json` stamping, per panel, the exact layout values the SVG was built from,
plus a content fingerprint:

```json
{"panel-1-a": {"xMM": 12.5, "yMM": 30.0, "widthMM": 60.0, "heightMM": 45.0,
               "contentHash": "ab12cd…", "builtAt": "2026-09-17T19:40:00Z"}}
```

Now every field has three values — BASE (stamped), SVG (current, possibly edited in
Inkscape), JSON (current, possibly hand-edited) — and reconciliation is an ordinary
three-way merge:

| SVG vs BASE | JSON vs BASE | Action |
|---|---|---|
| same | same | nothing to do |
| **differs** | same | edited in Inkscape → harvest SVG → JSON |
| same | **differs** | hand-edited JSON → apply JSON → SVG on compose |
| **differs** | **differs** | genuine conflict → **fail loudly**, print both |

Three consequences, if it holds up (see §12.1 for the case this table does not cover):

- **A pure move becomes auto-harvestable**, because it is no longer ambiguous. The
  `updateFigxN.m` family disappears — only two exist today (`updateFigx1xa.m`,
  `updateFigx2xa.m`), but one per repositionable panel was the trajectory, and the
  ordering hazard goes with them.
- The conflict case fails loudly with both values rather than silently picking, per the
  project's standing no-fallbacks rule.
- `contentHash` gives §4 its staleness signal for free.

Use a **sidecar file rather than attributes on the SVG group.** Custom attributes would
be more elegant and would travel with the file, but they are hostage to whatever the
external editor chooses to preserve on save, and the entire point of the base record is
that it must be trustworthy. A sidecar cannot be clobbered by Inkscape.

## 4. Regeneration on data change

Two separable questions: how do we know content changed, and what do we rebuild.

**Knowing:** fingerprint each panel over (its input data's content hash or mtime+size) +
(the plotting code's commit or mtime) + (the serialized style opts). Store it as
`contentHash` in `FigxN.built.json`.

**Rebuilding — and here it is worth resisting over-engineering.** In this codebase panel
content arrives as *live MATLAB handles* from `doIt_human.m`, which has already run the
analysis:

```matlab
opts = makeFigx1human;
makeFigx1human([Figx1xa_singleRun_radius … ], hFcrossSection, opts, insertIt);
```

By the time the figure function is called, the content already exists in memory, so
per-panel incremental rebuild has nothing to save — the expensive part happened upstream,
governed by the doIt script's own section structure. Recomposing a whole figure is cheap.

So the fingerprint should not drive incremental rebuild. It should drive **staleness
detection**, which is the thing actually worth having:

- warn when a delivered PDF is older than the inputs it claims to be built from;
- refuse to deliver a figure whose content changed but whose layout has not been looked
  at since, so a data update cannot silently ship a broken layout;
- let `doIt_human.m` end with a single delivery step for whatever was rebuilt this
  session.

That is the honest version of "automatic regeneration": automatic recomposition and
delivery, with an explicit gate where a human's judgement is genuinely required.

## 5. The canvas retarget — the main porting cost

The current engine composes every figure on a **US-letter page**:

```matlab
% initManuscriptFigureSvg.m
pageWidthMM  = 215.9;
pageHeightMM = 279.4;
% makeFigx5.m: widthMM = (215.9 - 2*10 - 2*5) / 3 = ~61.97 mm
```

PNAS does not want a page. It wants a standalone figure at one of exactly three widths —
87 / 114.3 / 178 mm — and at most 225 mm tall, and explicitly less, to leave room for the
legend. So porting is fundamentally **retargeting the canvas**, and the good news is that
`runPillar1.m`'s `opts.canvasSize` already drives `fig2.Position`, `fig2.PaperSize` and
`fig2.PaperPosition`, so this is a one-argument change rather than a redesign.

The consequence to plan around: **font sizes do not scale with the canvas.** Panels are
replotted natively at their target size (this is deliberate, and the reason
`harvestManuscriptFigureLayout.m` folds an Inkscape scale into `widthMM`/`heightMM`
instead of leaving a transform), so shrinking the canvas makes text *relatively larger*.
Legibility improves, but existing `layout.json` numbers stop meaning anything:

- full-width figures shrink 195.9 → 178 mm usable, a mild 0.91× — layouts mostly survive;
- 1-column figures shrink 195.9 → 87 mm, a 2.25× reduction — layouts must be rebuilt.

Which is precisely why the width class has to be decided per figure, first, and why
doing this one figure at a time with a human looking at it is the right call rather than
a batch conversion.

## 6. Per-figure assessment

What can be said before touching anything:

| Figure | Current shape | Port notes |
|---|---|---|
| **1** `makeFigx1human.m` (430 ln) | N metric panels + a cross-section panel; since 2026-08-19 **each metric input already gets its own top-level `panelId`** so Inkscape repositioning is not lost on regeneration | Best-prepared of the five — it already assumes the L2/L3 split. Likely 2-column. Its cross-section panel is copied as-is and aspect-preserving, i.e. it is already the passthrough of §7. |
| **2** `makeFigx2xabcdefgh.m` (216 ln) | 8 panels: brain, crops, overlays, patches | Image-heavy, so this is the one where the raster ppi rules bite. Port **last**, once the lint works. Likely 2-column. |
| **3** `makeFigx3.m` (307 ln) | returns `Fig3panels` | Needs a read before it can be characterised. |
| **4** `makeFigx4human.m` (312 ln) | one call per metric; cell arrays `{a, radius, flow}` plus a response-timeseries panel; `[]` means "not ready yet" | Variable panel count — the layout has to tolerate a growing figure. |
| **5** `makeFigx5.m` (239 ln) | fixed 1×3 full-width row of equal squares, `(215.9−20−10)/3 ≈ 61.97 mm` | Cleanest retarget: the same formula at 178 mm gives `(178−2m−2g)/3`. Smallest and most self-contained. |
| **SI** | **no code exists** — no `figS*`, no supplement machinery anywhere | Not a port at all: greenfield. Combined with "the supplementary figures are very dirty", the right answer is the passthrough of §7, not the full pipeline. |

The SI is a different document with different geometry, and it is worth knowing before
planning anything for it: the SI project ships `pnas-new.cls` **v1.45**, not the
manuscript project's v1.47, and its template is **single-column** (`[9pt,twoside,lineno]`
with no `twocolumn`). Measured, its text measure is 505.694 pt = **177.74 mm** — the
2-column figure width to within 0.06 mm — on a full US Letter page rather than the
manuscript's shrunk layout. So SI figures are naturally authored at 178 mm and there is
no column structure to reason about at all. An 87 mm figure in the SI would sit at half
measure, which is permitted but probably not what anyone wants.

That PNAS ships two different class versions across its own two templates is their
inconsistency, not something to fix; it just means the SI's numbers must be measured
separately, as above, rather than assumed from the manuscript's.

**Suggested order: 5 → 1 → 3 → 4 → 2, then SI.** Figure 5 as the pathfinder — small
enough that the shared layer gets shaped by a real case rather than by speculation, and
its sizing math retargets almost by inspection. Figure 1 second because it already has
the per-panel structure and would exercise both composition and passthrough. Figure 2
last because it is the one that needs the ppi lint to be real.

This order is a guess from file sizes, headers and one reading of each figure's inputs —
not from having built any of them. If figure 5 turns out to be unrepresentative, or if
figure 1's existing per-panel structure means it would actually teach us more, reorder
without ceremony. The point of going one at a time is precisely to be able to.

## 7. Escape hatch: passthrough figures

Not every figure should be composed. A **passthrough** figure's content is a committed,
hand-made SVG or PDF — a schematic, a montage, a legacy figure nobody wants to
reconstruct. It gets the whole delivery path (canvas size check, compliance lint, stable
filename, push) and none of the composition or layout harvesting.

This matters for three reasons: the dirty SI figures start here and cost almost nothing;
any of them can graduate to the full pipeline later without anything downstream changing;
and the engine already has the precedent, since figure 1's cross-section panel is copied
as-is today.

## 8. The Overleaf contract

Proven today by `figtest` (pushed to the manuscript project as `d67ca14`):

- **The pipeline writes only figure PDFs, at stable filenames, and never touches a
  `.tex` file.** `figures/fig1.pdf` … `fig5.pdf`, `figures/figS1.pdf` … . The
  `\includegraphics` lines are written once, by hand, in Overleaf. This is what keeps the
  conflict surface at zero while a human edits prose in the browser.
- Deliver **PDF only**. TIFF and SVG cannot be included at all; EPS rounds its bounding
  box up to whole points; JPEG is discouraged by PNAS. PDF keeps text as text and embeds
  ArialMT, which is on PNAS's accepted-font list.
- `\includegraphics` takes **no width or scale option** — the file is already at final
  size. A scaling option would mask exactly the defects the lint should catch.
- **Four float layouts are available, and the width class is what selects between them.**
  `figure` at 87 mm, `figure*` at 178 mm, and `SCfigure*` — a full-width float with the
  caption beside the figure — at either 114.3 mm (the good balance) or 87 mm (for a long
  legend). `SCfigure*` needs no extra package; the class already loads
  `sidecap[rightcaption]`. Crucially for us, sidecap keeps the *graphic's* natural width
  and shrinks the *caption* to whatever is left of the 512 pt block, so a side-caption
  figure is still authored at one of the three permitted widths and **the pipeline needs
  no special case for it** — only the manuscript's `\begin{...}` line changes. This is
  also the most plausible reason the 1.5-column width exists: it is the one that leaves a
  usable caption strip (62.1 mm, against 89.7 mm behind an 87 mm graphic).
- **Figures go after the first-page text block.** Placing a float while `\Firstpage` is
  in effect overflows the page by 199.69 pt; this is a defect in `pnas-new.cls` v1.47
  that the pristine PNAS template triggers too. Call `\Endparasplit` first, as the
  template does.
- **Fetch and rebase before every push.** Already hit today: the remote had moved because
  of a UI edit, and the push was rejected. The bridge allows no branching, so delivery
  must always be a fast-forward onto current `main`.

## 9. What gets built once, in matlab2manuscript

1. **PNAS canvas preset** — the three widths, the height cap, 1:1 mm authoring.
2. **Compose + base stamping + three-way reconcile** (§3), replacing the ordering hazard
   and the `updateFigxN.m` family.
3. **SVG → PDF export** via librsvg, with assertions on page box, embedded fonts and
   text-preservation. Proven today; note that Inkscape's
   `--export-text-to-path=false` silently *enables* text-to-path, so it is not the tool
   to use here.
4. **Compliance lint**, failing loudly: text ≥ 6 pt, strokes ≥ 0.25 pt, RGB only, font
   family on the accepted list, raster ppi ≥ 300/600/1000 by artwork class, height under
   the cap, page box equal to one of the three permitted widths.
5. **Passthrough path** (§7).
6. **Delivery** — copy into the Overleaf clone, fetch, rebase, commit, push.

Every new user-facing MATLAB function follows the project's no-arg-call convention: a
bare call prints help and returns fully-populated default opts, with every documented
field present even as an empty placeholder.

## 10. Decisions to make, per figure and up front

Up front:

- **Font: standardise on Arial everywhere.** Genuine Arial is now installed, it is on
  PNAS's accepted list, and it embeds as `ArialMT`. Naming `Helvetica` in MATLAB is a
  lottery between Nimbus Sans, TeX Gyre Heros and Liberation Sans depending on which
  converter runs, none of which is on the list.
- **Where the Overleaf clone lives** — inside huMoMain at a fixed path, or outside it.
  Inside is more convenient; outside keeps a credential-bearing remote out of the project
  repo.
- **Whether delivered PDFs keep text as text.** Recommended yes: outlining text would
  make the lint's 6 pt check impossible and would defeat the editable round-trip.

Per figure, when we get to it: its PNAS width class, its panel inventory, and which of
its panels are composed versus passthrough.

## 11. Migration stance

Do **not** extend `manuscriptFigTools/`. It is the engine `matlab2manuscript` was
restarted from scratch to replace, and it is superseded rather than a base to build on.

The two can coexist safely during the port because `manuscriptFigures/` is absent from
this clone, so the old engine currently produces nothing here and there is nothing to
break. Per figure: pick the width class, build the replacement on `runPillar1`, re-tune
the layout, lint, deliver, accept — and only then delete that figure's `makeFigxN.m` and
`updateFigxN.m`.

## 12. What we will only find out by doing it

Listed so the first port does not have to rediscover that these were open, and so nobody
reads §3 and §4 as settled. Roughly in order of how likely each is to change the design.

1. **Whether the three-way merge of §3 is sufficient, and what it does when the panel
   set changes.** A panel that did not exist at the last composition has no BASE to
   compare against, so the table in §3 has no row for it. Figure 4 makes this concrete
   rather than hypothetical, since its metric list grows (`[]` means "not ready yet").
   Some rule is needed — probably "no BASE → take `layout.json` if it has an entry, else
   place by default" — but that is a guess, and the same question arises for a panel that
   *disappears*.
2. **What a real Inkscape save actually does to the file.** Pillar 2's `syncPanel.m`
   already round-trips a resize, so the basic machinery works, but reconciling against a
   stamped base is new, and external-editor validation was already the standing next item
   before any of this. If Inkscape rewrites structure more aggressively than expected,
   §3's sidecar is still safe but the harvest may need to be more forgiving about what it
   matches on.
3. **The content fingerprint of §4 may not be implementable as described.** Panel content
   arrives as live MATLAB handles, not files, so "hash the input data" may have nothing
   concrete to hash at the point where the figure function runs. The fallback is to
   fingerprint the *rendered* panel, which changes on cosmetic replots too and therefore
   cries stale more often than it should. Unresolved; possibly the honest answer is a
   coarser, figure-level "inputs touched since last delivery" flag driven by
   `doIt_human.m`'s own structure.
4. **How much MATLAB-side style work each retarget needs.** §5's arithmetic says a
   1-column figure shrinks 2.25×, and since fonts do not scale, relative text grows.
   Whether that lands legible, or needs per-panel font/tick/label intervention, cannot be
   known without replotting a real panel at 87 mm and looking at it. This is the single
   biggest unknown in the per-figure cost.
5. **Whether the compliance lint should read the PDF or the SVG.** Measuring text size
   and stroke width from a PDF needs a parser, and this machine has no `pypdf`, `qpdf` or
   `fitz`. Linting the SVG before conversion is probably easier and just as valid, but it
   cannot catch anything the conversion itself introduces. Likely both, eventually;
   start with whichever proves cheaper.
6. **Which of the spec's three disagreeing width values to author at.** The pica values
   match the class best (0.03 mm), the cm values are what the guidelines headline. The
   difference is 0.19 mm and well inside PNAS's own internal spread, so this probably does
   not matter at all — but "probably does not matter" is not the same as knowing, and only
   a real submission settles it.
7. **How much friction the Overleaf bridge actually causes.** One push was already
   rejected today because of a concurrent UI edit; fetch-and-rebase handles it. Whether
   that stays a non-event once prose editing and figure delivery are both happening often
   is a question about working habits, not about the tooling.
8. **The height budget.** The guidelines say at most 225 mm and explicitly less, to leave
   room for the legend, without naming a number. We will have to pick a cap, and revise it
   the first time a real caption does not fit.

None of these block starting. They are the reason to start with one small figure.
