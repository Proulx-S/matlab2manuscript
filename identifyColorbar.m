function cbInfo = identifyColorbar(ax, doc, identityDoc)
% identifyColorbar  Locate the SVG elements making up a panel's colorbar (outline, gradient box,
% tick marks, tick labels, own label) in an ALREADY-BAKED real svg, given an ALREADY-BAKED identity
% svg (dumpIdentitySvg.m, which temporarily recolors `ax.Colorbar.Color` to
% colorbarIdentityColorHex.m's own reserved sentinel before that export).
%
% Mechanism (2026-08-29, all confirmed empirically before writing this):
%  - `cb.Color` is the ONE property controlling the colorbar's outline, its own tick marks, AND its
%    tick-label text color all at once -- so recoloring it once in the identity export marks all
%    three at once with zero collision risk (roleCode=3 is never used by any real per-series color,
%    see colorbarIdentityColorHex.m).
%  - The outline renders as 4 SEPARATE 2-point <polyline> segments (NOT a single closed <path>, unlike
%    the figure/axes-background/legend-box rects findClosedRectPaths.m already handles) -- 2 long
%    (spanning the box's own long dimension) and 2 short (the box's own short dimension). Tick marks
%    are shorter STILL than even the short box edges (confirmed: ~2.6pt vs ~21pt in this repo's own
%    probe), so a MAX-SPAN-of-2-per-orientation split (mirroring identifyAxisSpine.m's own
%    spine-vs-tick disambiguation) cleanly separates "the 4 box edges" from "the N tick marks"
%    regardless of orientation (vertical east/west vs horizontal north/south colorbar).
%  - The gradient itself renders as a raster <image> referenced via a <pattern> whose OWN x/y/width/
%    height exactly match the outline's bbox -- but the element actually PAINTING with that pattern
%    (`fill="url(#...)"`) is a plain closed-rect <path>, the exact same 5-point M-L-L-L-L shape
%    findClosedRectPaths.m already parses for figure/axes-background/legend-box -- so the gradient box
%    is just "the one closed-rect <path> whose bbox matches the identity-matched outline's bbox",
%    no <pattern>/<image> parsing needed at all.
%  - Tick LABELS are matched the same way axis tick labels already are (groupAndTagSvg.m's own
%    matchTickLabels): live content (`cb.TickLabels`) + position, directly in the REAL doc -- no
%    identity-color involvement needed for text at all, since content is already an unambiguous
%    signal once restricted to a small geometric window.
%
% ax          live axes (ax.Colorbar read directly)
% doc         org.w3c.dom.Document of the REAL baked svg
% identityDoc org.w3c.dom.Document of the identity-baked svg (dumpIdentitySvg.m + bake)
%
% Returns [] if ax has no live Colorbar. Otherwise a struct:
%   cbInfo.boxNode        the 5-point closed-rect <path> painting the gradient (real doc)
%   cbInfo.outlineNodes    cell array of the 4 real-doc <polyline> box-edge nodes
%   cbInfo.tickNodes       cell array of real-doc tick-mark <polyline> nodes, sorted along the box's
%                          own long axis, one per `cb.Ticks`
%   cbInfo.tickLabelNodes  cell array of real-doc tick-label <text> nodes, same order/count
%   cbInfo.labelNode       real-doc <text> node for `cb.Label.String` ([] if empty/not found)
%   cbInfo.bboxPt          [x0 y0 x1 y1] the box's own bbox, SVG-space, real doc
%   cbInfo.decorationNodes cell array of tiny (~0.5pt) decorative corner-cap <path> nodes MATLAB
%                          draws at the box's own corners -- harmless, tagged only so they don't
%                          fall through to the unrelated "annotations" catch-all

cb = ax.Colorbar;
if isempty(cb)
    cbInfo = [];
    return
end

idHex = colorbarIdentityColorHex();
idPolylines = findTwoPointPolylinesByStroke(identityDoc, idHex);
assert(~isempty(idPolylines), 'identifyColorbar:noIdentityCandidates', ...
    'ax.Colorbar exists but no identity-colored (%s) polyline was found in the identity export.', idHex);

% MATLAB draws the colorbar's own outline/ruler-axis-line as MULTIPLE exactly-overlapping
% <polyline>s (confirmed empirically, 2026-08-29 -- the box edge nearest the ticks is drawn 3x,
% the other 3 edges 2x each; not the 4-unique-edges assumption identifyAxisSpine.m's own primary
% ruler line can make) -- deduped by exact geometry before span-based classification below, or the
% max-span-of-2 split misclassifies duplicate edges as "leftover ticks" in both orientations at
% once.
idPolylines = dedupeByGeometry(idPolylines);

horiz = {}; vert = {};
for i = 1:numel(idPolylines)
    p = idPolylines{i};
    dx = abs(p.pts(2,1)-p.pts(1,1)); dy = abs(p.pts(2,2)-p.pts(1,2));
    if dy < 0.5 && dx >= 0.5
        horiz{end+1} = struct('pts',p.pts,'span',dx); %#ok<AGROW>
    elseif dx < 0.5 && dy >= 0.5
        vert{end+1} = struct('pts',p.pts,'span',dy); %#ok<AGROW>
    end
end

[horizEdges, horizTicks] = splitEdgesFromTicks(horiz);
[vertEdges, vertTicks] = splitEdgesFromTicks(vert);
assert(numel(horizEdges) == 2 && numel(vertEdges) == 2, 'identifyColorbar:unexpectedOutlineShape', ...
    'expected exactly 2 horizontal + 2 vertical box-edge segments, found %d + %d.', numel(horizEdges), numel(vertEdges));
assert(isempty(horizTicks) || isempty(vertTicks), 'identifyColorbar:ambiguousOrientation', ...
    'found tick-like leftover segments in BOTH orientations (%d horizontal, %d vertical) -- cannot determine colorbar orientation.', ...
    numel(horizTicks), numel(vertTicks));

allEdgePts = vertcat(horizEdges{1}.pts, horizEdges{2}.pts, vertEdges{1}.pts, vertEdges{2}.pts);
bboxPt = [min(allEdgePts(:,1)) min(allEdgePts(:,2)) max(allEdgePts(:,1)) max(allEdgePts(:,2))];

isVertical = ~isempty(horizTicks);   % ticks perpendicular to a vertical (tall) box are horizontal segments
if isVertical
    idTickSegs = horizTicks;
    tickPosOf = @(s) mean(s.pts(:,2));   % sort along the box's own y (its long axis)
else
    idTickSegs = vertTicks;
    tickPosOf = @(s) mean(s.pts(:,1));
end
tickPos = cellfun(tickPosOf, idTickSegs);
[~, order] = sort(tickPos);
idTickSegs = idTickSegs(order);

nTicks = numel(cb.Ticks);
assert(numel(idTickSegs) == nTicks, 'identifyColorbar:tickCountMismatch', ...
    'found %d identity-colored tick-mark segment(s), expected %d (numel(cb.Ticks)).', numel(idTickSegs), nTicks);

% --- cross-reference the outline edges + tick marks into the REAL doc by exact geometry (identical
% between the two exports since only color differs -- same discipline as matchGraphicsToSvg.m's own
% identity-color path). The outline's 4 UNIQUE edge geometries can each match MULTIPLE real-doc
% <polyline>s (the same MATLAB duplicate-drawing behavior noted above) -- every one of them is kept
% and relocated. A stroke's own half-width bleeds slightly OUTSIDE the gradient box's exact edge (a
% ~0.5pt stroke centered exactly on a coordinate the gradient rect also uses as its own boundary),
% so an "earlier" duplicate is NOT fully hidden by the gradient's later opaque fill the way a naive
% z-order argument would suggest -- tried keeping only the topmost copy and deleting the rest
% (assuming full occlusion), which made the (already small) known pixel-diff WORSE, not better, by
% under-counting that outer-bleed contribution. Relocating every duplicate, all after the gradient
% box (this function's own boxNode is relocated first, see groupAndTagSvg.m), reproduces the closest
% achievable match -- a small, precisely-diagnosed, PURELY COSMETIC residual (a fraction of a
% percent of canvas pixels, confined to sub-pixel antialiasing blending exactly along the box's own
% edges) documented in docs/findings.md rather than chased further. Tick marks, by contrast, were
% NOT found duplicated (confirmed empirically) -- kept as a strict 1-per-tick match. ---
outlineNodes = {};
edgePtsList = {horizEdges{1}.pts, horizEdges{2}.pts, vertEdges{1}.pts, vertEdges{2}.pts};
for i = 1:4
    outlineNodes = [outlineNodes, findTwoPointPolylinesByGeometry(doc, edgePtsList{i})]; %#ok<AGROW>
end
tickNodes = cell(1, nTicks);
for i = 1:nTicks
    matches_ = findTwoPointPolylinesByGeometry(doc, idTickSegs{i}.pts);
    assert(numel(matches_) == 1, 'identifyColorbar:tickGeometryNotUnique', ...
        'expected exactly 1 real-doc tick-mark match, found %d.', numel(matches_));
    tickNodes{i} = matches_{1};
end

% --- gradient box: the one closed-rect <path> (findClosedRectPaths.m) whose bbox matches the
% identity-matched outline's bbox EXACTLY. MATLAB also draws several tiny (~0.5pt) decorative
% corner-cap closed-rect <path>s AT the colorbar's own corners (confirmed real, 2026-08-29) --
% these are CONTAINED WITHIN bboxPt but don't match it exactly, so a separate, looser containment
% pass collects them as "decoration" (harmless furniture, tagged so they don't fall through to the
% unrelated "annotations" catch-all and get relocated there instead). ---
rects = findClosedRectPaths(doc);
boxNode = [];
decorationNodes = {};
for i = 1:numel(rects)
    r = rects{i}.rect;
    if all(abs(r - bboxPt) < 1.5)
        assert(isempty(boxNode), 'identifyColorbar:ambiguousGradientBox', ...
            'more than one closed-rect <path> matches the colorbar''s own bbox -- cannot disambiguate.');
        boxNode = rects{i}.node;
    elseif r(1) >= bboxPt(1)-1.5 && r(2) >= bboxPt(2)-1.5 && r(3) <= bboxPt(3)+1.5 && r(4) <= bboxPt(4)+1.5
        decorationNodes{end+1} = rects{i}.node; %#ok<AGROW>
    end
end
assert(~isempty(boxNode), 'identifyColorbar:noGradientBox', ...
    'no closed-rect <path> found matching the colorbar''s own bbox -- did baking/export change?');

% --- tick labels: live content (cb.TickLabels) + position, directly in the real doc, mirroring
% groupAndTagSvg.m's own matchTickLabels -- try both perpendicular sides (AxisLocation='out' can put
% labels on either side of the box depending on cb.Location), require exactly one side to match. ---
tickLabelNodes = matchColorbarTickLabels(doc, cb.TickLabels, bboxPt, isVertical, nTicks);

% --- colorbar's own label: direct content match, same discipline as axis-xlabel/-ylabel
% (groupAndTagSvg.m's own findTextByContentExcluding) -- kept local here since it needs no exclude
% list of its own (the caller excludes it from ITS OWN axis-label matching instead, see that file). ---
labelNode = [];
labelContent = strtrim(char(cb.Label.String));
if ~isempty(labelContent)
    texts = doc.getElementsByTagName('text');
    for k = 0:texts.getLength()-1
        n = texts.item(k);
        if strcmp(strtrim(char(n.getTextContent())), labelContent)
            assert(isempty(labelNode), 'identifyColorbar:ambiguousLabel', ...
                'more than one <text> matches the colorbar label content "%s".', labelContent);
            labelNode = n;
        end
    end
end

% Cell-array field values wrapped in an extra {} -- struct()'s own broadcasting rule otherwise
% treats a bare cell-array value as "build a struct ARRAY, one element per cell", which fails
% outright here since outlineNodes/tickNodes/tickLabelNodes generally have different lengths.
cbInfo = struct('boxNode',boxNode, 'outlineNodes',{outlineNodes}, 'tickNodes',{tickNodes}, ...
    'tickLabelNodes',{tickLabelNodes}, 'labelNode',labelNode, 'bboxPt',bboxPt, ...
    'decorationNodes',{decorationNodes});
end

function [edges, ticks] = splitEdgesFromTicks(segs)
if isempty(segs)
    edges = {}; ticks = {};
    return
end
spans = cellfun(@(s) s.span, segs);
[~, order] = sort(spans, 'descend');
segs = segs(order);
edges = segs(1:min(2,numel(segs)));
ticks = segs(3:end);
end

function cands = findTwoPointPolylinesByStroke(doc, hex)
polylines = doc.getElementsByTagName('polyline');
cands = {};
for k = 0:polylines.getLength()-1
    node = polylines.item(k);
    stroke = attrOrParentLocal(node, 'stroke');
    if ~strcmpi(stroke, hex); continue; end
    pts = parsePolylinePointsLocal(node);
    if size(pts,1) ~= 2; continue; end
    cands{end+1} = struct('node',node,'pts',pts); %#ok<AGROW>
end
end

function nodes = findTwoPointPolylinesByGeometry(doc, targetPts)
polylines = doc.getElementsByTagName('polyline');
nodes = {};
for k = 0:polylines.getLength()-1
    n = polylines.item(k);
    pts = parsePolylinePointsLocal(n);
    if isequal(size(pts), size(targetPts)) && all(abs(pts(:) - targetPts(:)) < 1e-6)
        nodes{end+1} = n; %#ok<AGROW>
    end
end
assert(~isempty(nodes), 'identifyColorbar:noGeometryMatch', ...
    'identity-matched colorbar segment geometry not found in the real doc -- did the two exports diverge?');
end

function deduped = dedupeByGeometry(segs)
% Collapses exactly-overlapping segments (same endpoint geometry, regardless of which of possibly
% several duplicate <polyline> nodes each came from) down to ONE representative per unique
% geometry -- see this file's own caller comment for why MATLAB draws some colorbar edges more
% than once. Any one representative works for span-based classification (geometry, not node
% identity, is all that matters there); real-doc cross-referencing afterward independently finds
% and relocates EVERY duplicate node sharing that geometry.
deduped = {};
for i = 1:numel(segs)
    isDup = false;
    for j = 1:numel(deduped)
        if isequal(size(segs{i}.pts), size(deduped{j}.pts)) && all(abs(segs{i}.pts(:) - deduped{j}.pts(:)) < 1e-6)
            isDup = true; break
        end
    end
    if ~isDup; deduped{end+1} = segs{i}; end %#ok<AGROW>
end
end

function labelNodes = matchColorbarTickLabels(doc, tickLabelStrs, bboxPt, isVertical, nTicks)
texts = doc.getElementsByTagName('text');
pad = 30;   % pt -- generous outside-the-box search window, same order of magnitude as
            % groupAndTagSvg.m's own matchTickLabels
sideACands = {}; sideBCands = {};
for k = 0:texts.getLength()-1
    n = texts.item(k);
    content = strtrim(char(n.getTextContent()));
    if ~ismember(content, tickLabelStrs); continue; end
    x = str2double(char(n.getAttribute('x'))); y = str2double(char(n.getAttribute('y')));
    if isVertical
        % side A = right of the box, side B = left of the box; sort candidates along y (the box's
        % own long axis) same as tick marks were sorted above.
        if x > bboxPt(3) - 0.5 && x < bboxPt(3) + pad
            sideACands{end+1} = struct('node',n,'pos',y); %#ok<AGROW>
        elseif x < bboxPt(1) + 0.5 && x > bboxPt(1) - pad
            sideBCands{end+1} = struct('node',n,'pos',y); %#ok<AGROW>
        end
    else
        if y > bboxPt(4) - 0.5 && y < bboxPt(4) + pad
            sideACands{end+1} = struct('node',n,'pos',x); %#ok<AGROW>
        elseif y < bboxPt(2) + 0.5 && y > bboxPt(2) - pad
            sideBCands{end+1} = struct('node',n,'pos',x); %#ok<AGROW>
        end
    end
end
aOk = numel(sideACands) == nTicks; bOk = numel(sideBCands) == nTicks;
assert(aOk || bOk, 'identifyColorbar:tickLabelCountMismatch', ...
    'found %d/%d candidate tick-label <text>(s) on either side of the colorbar box, expected %d.', ...
    numel(sideACands), numel(sideBCands), nTicks);
assert(~(aOk && bOk), 'identifyColorbar:ambiguousTickLabelSide', ...
    'candidate tick labels matched the expected count on BOTH sides of the colorbar box -- cannot disambiguate.');
if aOk; cands = sideACands; else; cands = sideBCands; end
[~, order] = sort(cellfun(@(c) c.pos, cands));
cands = cands(order);
labelNodes = cellfun(@(c) c.node, cands, 'UniformOutput', false);
end

function val = attrOrParentLocal(node, attrName)
val = '';
n = node;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute(attrName)
        val = char(n.getAttribute(attrName));
        return
    end
    n = n.getParentNode();
end
end

function pts = parsePolylinePointsLocal(node)
str = char(node.getAttribute('points'));
vals = sscanf(str, '%f,%f');
pts = reshape(vals, 2, [])';
end
