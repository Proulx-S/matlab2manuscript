function result = syncPanel(ax, outDir, figId, panId, opts)
% syncPanel  The pillar-2 sync/insert operation (2026-08-29): places one panel into a composed
% multi-panel figure (`<figId>.svg`), and on every later call, recovers wherever a human
% repositioned/resized that panel (in a vector editor, AFTER insertion -- not on the standalone
% single-panel SVG, per Seb's own framing of this constraint) and feeds it back into MATLAB for
% regeneration, so a resize is always a real re-render (correct absolute font-size/stroke-width at
% the new size) rather than a naively-scaled vector.
%
% First call for a given panId: the panel doesn't exist in the composed file yet, so it's placed at
% `opts.defaultInnerPosition`. Every call after that: this panel's current on-canvas geometry is
% measured directly from the composed file AS IT NOW STANDS (however it got there -- a prior
% syncPanel call, or a human's own edit saved over it) and used as the new target `InnerPosition`.
% Insertion and resync are therefore the exact same operation, not two different code paths.
%
% Mechanism: `runPillar1.m`'s copy step (2026-08-29) already puts every panel on one fixed, shared
% physical canvas (the composed figure uses the SAME canvas) -- so a panel's placement/size inside
% the composed document and its own `ax.InnerPosition` are the SAME NUMBER, just expressed as
% absolute points vs. a canvas-relative fraction. Recovering an edit is therefore a direct
% measurement, not a diff against any previously-stored value: measure `{panId}-axis-spine-x`/`-y`'s
% CURRENT bounding box in the composed document's own coordinate frame (resolveElementCTM.m composes
% every ancestor `transform` an external editor may have added or left baked into raw coordinates --
% NOT bakeTransforms.py, which only ever has to parse MATLAB's own narrow matrix()-only dialect, see
% that file's own header), divide by the canvas physical size, done. A translate AND an aspect-
% ratio-changing scale both map directly onto InnerPosition's independent `[x y w h]` fractions with
% no special-casing -- only ROTATION has no InnerPosition equivalent, and is detected (spine no
% longer axis-aligned) and rejected loudly rather than silently mishandled.
%
% KNOWN VALIDATION GAP (2026-08-29, not yet closed): this has only been exercised against SIMULATED
% edits (this repo's own test/test_sync_panel.m directly rewrites the composed SVG's DOM between two
% syncPanel calls to stand in for a human's edit) -- it has NOT been round-tripped through a real
% external vector editor (Illustrator/Inkscape). Simulated edits cover the transform-list forms this
% file's own docstring above anticipates, but an editor's actual save behavior (which exact
% transform-list syntax it emits, whether/how it bakes transforms away, whitespace/precision
% conventions) could differ in ways a simulation doesn't catch. Flagged here so it isn't mistaken
% for a closed, field-tested loop.
%
% Call with NO arguments to see this help and get a fully-populated default opts struct (required
% fields included as empty placeholders) -- the Bass-wide convention for a new user-facing function.
%
% ax        live axes (NOT yet closed, never modified) -- same requirements as runPillar1.m
% outDir    directory holding (or to hold) `<figId>.svg` and this panel's own `<figId>_<panId>_*`
%           files
% figId     compulsory id of the composed multi-panel figure
% panId     compulsory id of this panel within it
% opts.composedFile   (default fullfile(outDir,[figId '.svg'])) the composed multi-panel SVG
% opts.defaultInnerPosition  (default [0.1 0.1 0.35 0.35]) used ONLY the first time this panId is
%           placed into the composed file (it doesn't exist there yet)
% opts.keepIntermediates  (default false) passthrough to runPillar1.m
% opts.pythonExe          (default 'python3') passthrough to runPillar1.m
% opts.canvasUnits/opts.canvasSize  (default 'inches'/[8.5 11]) used ONLY to CREATE opts.composedFile
%           if it doesn't exist yet -- once it exists, the panel's own canvas is always derived from
%           the composed file's OWN root width/height instead, so the two can never silently drift
%           apart.
%
% result.composedFile   path to the (now updated) composed multi-panel SVG
% result.taggedFile      this panel's own standalone tagged SVG (runPillar1.m's own output -- always
%                        kept, same contract as runPillar1.m itself)
% result.innerPosition   the `[x y w h]` InnerPosition actually used to regenerate this panel (either
%                        opts.defaultInnerPosition, on first placement, or the measured/recovered one)
% result.stats           runPillar1.m's own passthrough stats

if nargin == 0
    fprintf(['syncPanel  Places/resyncs one panel into a composed multi-panel figure, recovering\n' ...
        'wherever a human repositioned/resized it (post-insertion, in a vector editor) and feeding\n' ...
        'that back into MATLAB via runPillar1.m''s opts.innerPositionOverride for regeneration.\n' ...
        'First call for a panId places it at opts.defaultInnerPosition; every later call measures\n' ...
        'its current on-canvas geometry directly (no stored history needed -- panel and composed\n' ...
        'canvases are the same physical size). Rotation is detected and rejected.\n\n' ...
        'ax        live axes (NOT yet closed, never modified)\n' ...
        'outDir    directory holding <figId>.svg and this panel''s own files\n' ...
        'figId     compulsory id of the composed multi-panel figure\n' ...
        'panId     compulsory id of this panel\n' ...
        'opts.composedFile   (default outDir/figId.svg)\n' ...
        'opts.defaultInnerPosition  (default [0.1 0.1 0.35 0.35])\n' ...
        'opts.keepIntermediates     (default false)\n' ...
        'opts.pythonExe             (default ''python3'')\n' ...
        'opts.canvasUnits/opts.canvasSize  (default ''inches''/[8.5 11], used only to CREATE a new composed file)\n\n' ...
        'Returns result.composedFile/.taggedFile/.innerPosition/.stats.\n']);
    result = struct('ax',[], 'outDir','', 'figId','', 'panId','', 'composedFile','', ...
        'defaultInnerPosition',[0.1 0.1 0.35 0.35], 'keepIntermediates',false, 'pythonExe','python3', ...
        'canvasUnits','inches', 'canvasSize',[8.5 11]);
    return
end

if nargin < 5 || isempty(opts); opts = struct(); end
if ~isfield(opts,'composedFile'); opts.composedFile = fullfile(outDir, [figId '.svg']); end
if ~isfield(opts,'defaultInnerPosition'); opts.defaultInnerPosition = [0.1 0.1 0.35 0.35]; end
if ~isfield(opts,'keepIntermediates'); opts.keepIntermediates = false; end
if ~isfield(opts,'pythonExe'); opts.pythonExe = 'python3'; end
if ~isfield(opts,'canvasUnits'); opts.canvasUnits = 'inches'; end
if ~isfield(opts,'canvasSize'); opts.canvasSize = [8.5 11]; end

if ~isfile(opts.composedFile)
    createBlankComposedFile(opts.composedFile, opts.canvasUnits, opts.canvasSize);
end

doc = xmlread(opts.composedFile);
docRoot = doc.getDocumentElement();
canvasSizePt = getCanvasSizeFromDoc(doc);

panelNode = findElementById(docRoot, [panId '-root']);

if isempty(panelNode)
    targetInnerPosition = opts.defaultInnerPosition;
else
    targetInnerPosition = measurePanelInnerPosition(doc, panId, canvasSizePt);
end

runOpts = struct('keepIntermediates',opts.keepIntermediates, 'pythonExe',opts.pythonExe, ...
    'canvasUnits','points', 'canvasSize',canvasSizePt, 'innerPositionOverride',targetInnerPosition);
% 'points' isn't itself a MATLAB figure Units value -- convert to inches (the unit runPillar1.m's
% own copy step actually sets figure.Units/PaperUnits to) so the copy figure's canvas is EXACTLY the
% composed file's own canvas, never independently trusted from opts.canvasUnits/opts.canvasSize.
runOpts.canvasUnits = 'inches';
runOpts.canvasSize = canvasSizePt / 72;

pillarResult = runPillar1(ax, outDir, figId, panId, runOpts);

panelDoc = xmlread(pillarResult.taggedFile);
newPanelNode = findElementById(panelDoc.getDocumentElement(), [panId '-root']);
assert(~isempty(newPanelNode), 'syncPanel:noPanelRoot', ...
    'runPillar1.m''s own output for panId="%s" has no "%s-root" element -- unexpected.', panId, panId);
imported = doc.importNode(newPanelNode, true);

if isempty(panelNode)
    docRoot.appendChild(imported);
else
    % Replace whatever currently sits directly under docRoot for this panel -- NOT necessarily
    % `panelNode` itself: an external edit may have wrapped `{panId}-root` in one or more extra
    % ancestor <g transform="..."> groups (simulated by test/test_sync_panel.m). The freshly
    % regenerated panel is already baked to the correct final geometry, so it must replace the WHOLE
    % existing subtree -- including any such wrapper -- and land as a flat child of docRoot with no
    % transform, per this file's own "insert as a flat <g> sibling" design (leaving the old wrapper
    % in place would double-apply its transform on top of the already-correct new geometry).
    oldTop = panelNode;
    p = oldTop.getParentNode();
    while ~isempty(p) && ~p.isSameNode(docRoot)
        oldTop = p;
        p = p.getParentNode();
    end
    docRoot.replaceChild(imported, oldTop);
end

xmlwrite(opts.composedFile, doc);

result.composedFile = opts.composedFile;
result.taggedFile = pillarResult.taggedFile;
result.innerPosition = targetInnerPosition;
result.stats = pillarResult.stats;
end

function createBlankComposedFile(composedFile, canvasUnits, canvasSize)
% A blank composed root <svg>, mirroring MATLAB's own -dsvg export conventions exactly (viewBox in
% points, width/height declared in mm as the physical size) -- see getCanvasSizeFromDoc.m, which
% every panel's own tagged SVG (and this file) is read via, and which assumes exactly this
% convention. No top-level default-style <g> wrapper is needed here (unlike MATLAB's own export):
% every panel's own leaves already have their presentation attributes fully inlined by
% groupAndTagSvg.m's relocateLeaf, so nothing here depends on an inherited default.
sizeIn = convertUnitsToInches(canvasSize, canvasUnits);
ptSize = sizeIn * 72;
mmSize = sizeIn * 25.4;
xmlStr = sprintf(['<?xml version="1.0" encoding="utf-8"?>\n' ...
    '<svg xmlns="http://www.w3.org/2000/svg" baseProfile="tiny" height="%.10gmm" version="1.2" viewBox="0 0 %.10g %.10g" width="%.10gmm">\n' ...
    '</svg>\n'], mmSize(2), ptSize(1), ptSize(2), mmSize(1));
fid = fopen(composedFile, 'w');
assert(fid > 0, 'syncPanel:cannotCreateComposedFile', 'could not create "%s".', composedFile);
fwrite(fid, xmlStr);
fclose(fid);
end

function sizeIn = convertUnitsToInches(sz, units)
switch units
    case 'inches'
        sizeIn = sz;
    case 'centimeters'
        sizeIn = sz / 2.54;
    case 'points'
        sizeIn = sz / 72;
    otherwise
        error('syncPanel:unsupportedCanvasUnits', 'unsupported opts.canvasUnits "%s".', units);
end
end

function ip = measurePanelInnerPosition(doc, panId, canvasSizePt)
% Measures this panel's CURRENT on-canvas geometry directly from `doc` (however it got there -- a
% prior syncPanel call, or a human's own edit saved over the composed file) and inverts
% identifyAxisSpine.m's own InnerPosition -> SVG-box formula to recover the InnerPosition fraction
% that produced it -- see this file's own header for why this is a direct measurement, not a diff.
xNode = findElementById(doc.getDocumentElement(), [panId '-axis-spine-x']);
yNode = findElementById(doc.getDocumentElement(), [panId '-axis-spine-y']);
assert(~isempty(xNode) && ~isempty(yNode), 'syncPanel:missingSpine', ...
    'panel "%s" exists in the composed file but its axis-spine-x/y elements could not be found -- was it edited in a way that removed/renamed them?', panId);

xPts = transformedPoints(xNode);
yPts = transformedPoints(yNode);

tol = 1.5;   % same 72/ScreenPixelsPerInch-rounding-scale family as identifyAxisSpine.m/identifyLegend.m
assert(max(xPts(:,2)) - min(xPts(:,2)) < tol, 'syncPanel:rotatedPanel', ...
    'panel "%s" appears rotated (its axis-spine-x is no longer horizontal) -- rotation has no ax.InnerPosition equivalent and is not supported; only translate/resize (including aspect-ratio changes) can be fed back.', panId);
assert(max(yPts(:,1)) - min(yPts(:,1)) < tol, 'syncPanel:rotatedPanel', ...
    'panel "%s" appears rotated (its axis-spine-y is no longer vertical) -- not supported, see above.', panId);

x0 = min(xPts(:,1)); x1 = max(xPts(:,1));
y0 = min(yPts(:,2)); y1 = max(yPts(:,2));

W = canvasSizePt(1); H = canvasSizePt(2);
ip = [x0/W, 1 - y1/H, (x1-x0)/W, (y1-y0)/H];
end

function pts = transformedPoints(node)
T = resolveElementCTM(node);
raw = sscanf(strrep(char(node.getAttribute('points')), ',', ' '), '%f');
raw = reshape(raw, 2, [])';
pts = zeros(size(raw));
for i = 1:size(raw,1)
    x = raw(i,1); y = raw(i,2);
    pts(i,1) = T(1)*x + T(3)*y + T(5);
    pts(i,2) = T(2)*x + T(4)*y + T(6);
end
end

function node = findElementById(root, id)
node = [];
els = root.getElementsByTagName('*');
for i = 0:els.getLength()-1
    n = els.item(i);
    if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), id)
        node = n;
        return
    end
end
end
