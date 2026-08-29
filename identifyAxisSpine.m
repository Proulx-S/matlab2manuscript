function spine = identifyAxisSpine(ax, doc, canvasSizePt)
% identifyAxisSpine  Locate the SVG elements that make up this axes' spine -- ax.Position ==
% ax.InnerPosition, confirmed identical, the red box in MathWorks' own Axes Properties doc diagram
% (see docs/findings.md) -- plus its own tick marks, in an ALREADY-BAKED svg (bakeTransforms.py run
% first; absolute coordinates assumed, no ancestor transform to compose).
%
% Matched GEOMETRICALLY against the expected spine rectangle computed from live ax/figure
% properties, never by color/z-order/draw-order guessing -- spine, gridlines and axes background
% frequently share the same white/black palette (confirmed in this repo's own probe SVG). MATLAB
% bundles the spine line and its own axis' tick marks together as sibling <polyline> elements inside
% ONE shared-style <g> per ruler (confirmed empirically); disambiguated here purely by span (the
% spine is the long polyline spanning the whole inner box; ticks are short).
%
% `ax.Box='on'` (2026-08-29 -- confirmed real, previously errored loudly rather than mishandled it)
% draws a SECOND long line on the opposite side of each ruler (top mirrors bottom, right mirrors
% left), bundled with a full set of MIRRORED tick marks in the SAME <g> as the primary side's --
% confirmed empirically that MATLAB does NOT draw tick LABELS on the mirror side, only marks.
%
% ax             live axes (already plotted+exported; Units='normalized',
%                PositionConstraint='innerposition' assumed per docs/findings.md)
% doc            org.w3c.dom.Document from xmlread(bakedSvgFile)
% canvasSizePt   [width height] of the SVG canvas in the SAME units as its own coordinates -- pass
%                the baked SVG's own viewBox width/height (getCanvasSizeFromDoc.m), NOT the figure's
%                physical size; MATLAB's own export already applies the points conversion.
%
% Returns a struct:
%   spine.expectedBoxPt          [x0 y0 x1 y1] expected spine rect in SVG points, SVG-space (y-down)
%   spine.xSpineNode/.ySpineNode the long axis-line <polyline> for each ruler's PRIMARY side (bottom/
%                                 left) -- the spine itself, always present
%   spine.xTickNodes/.yTickNodes cell array of the PRIMARY side's short tick-mark <polyline> nodes,
%                                 sorted along the ruler's own axis -- these are the ones with labels
%   spine.xSpineTopNode/.ySpineRightNode   the MIRROR side's long line -- [] unless ax.Box='on'
%   spine.xTickMirrorNodes/.yTickMirrorNodes   the MIRROR side's short tick-mark nodes, sorted the
%                                 same way -- {} unless ax.Box='on' (never has labels, see above)

assert(strcmp(ax.PositionConstraint,'innerposition'), 'identifyAxisSpine:wrongPositionConstraint', ...
    'ax.PositionConstraint must be ''innerposition'' (see docs/findings.md) -- got ''%s''.', ax.PositionConstraint);
boxOn = strcmp(ax.Box,'on');

ip = ax.InnerPosition;   % normalized [x y w h], MATLAB-space origin bottom-left
W = canvasSizePt(1); H = canvasSizePt(2);
x0 = ip(1)*W;
x1 = (ip(1)+ip(3))*W;
yBottomMatlab = ip(2)*H;
yTopMatlab = (ip(2)+ip(4))*H;
y0 = H - yTopMatlab;   % SVG-space (origin top-left) -- flipped vs. MATLAB-space
y1 = H - yBottomMatlab;
spine.expectedBoxPt = [x0 y0 x1 y1];

polylines = doc.getElementsByTagName('polyline');
% 1.5pt, not the 0.5pt sub-point tolerance seen elsewhere in this repo: confirmed real, specific to
% the "far" box edges (x1/y0) that ONLY get checked when ax.Box='on' (touchesX1/touchesY0 below) --
% Box='off' never needed them, so this asymmetry (the "near" edges x0/y1 stay accurate to ~0.1-0.4pt;
% x1/y0 can be off by ~0.9pt) went unnoticed until Box='on' support was added. Root cause not fully
% pinned down (not explained by the already-understood canvas-size-rounding/ScreenPixelsPerInch
% mechanics -- the canvas width itself checks out to within 0.0003pt against the SVG's own width=
% attribute) -- still comfortably tighter than any real ambiguity (ticks are ~4.75pt, the spine
% itself hundreds of pt).
tol = 1.5;
boxSpanX = x1 - x0; boxSpanY = y1 - y0;

% A tick mark is perpendicular to its own axis (an x-tick is a short VERTICAL segment, a y-tick a
% short HORIZONTAL one) -- easy to get backwards, confirmed against this repo's own probe SVG.
% Two real ambiguities, both confirmed in that same probe, are guarded against explicitly rather
% than left to a geometric coincidence:
%  (1) MATLAB's first/last gridline commonly coincides EXACTLY with the spine's own position (e.g.
%      the leftmost vertical gridline sits at the same x as the y-spine) -- excluded here by
%      opacity: gridlines are always drawn with a fractional stroke-opacity, spine/ticks always
%      opaque (confirmed: probe's gridline <g> has stroke-opacity="0.14902" vs. the ruler <g>'s "1").
%  (2) the OTHER ruler's own spine also touches this ruler's anchor line at the shared corner point
%      (the y-spine's bottom endpoint IS (x0,y1)) -- excluded by bounding a "tick-like" segment's
%      length well below the box span, so only the other ruler's own (much longer) spine is
%      rejected, never a real tick. With Box='on' this applies at all 4 corners symmetrically.
xBottomCands = {}; xTopCands = {}; yLeftCands = {}; yRightCands = {};
for k = 0:polylines.getLength()-1
    node = polylines.item(k);
    pts = parsePolylinePoints(node);
    if size(pts,1) ~= 2; continue; end   % rulers only ever emit 2-point segments after baking
    if getElementOpacity(node) < 0.99; continue; end   % excludes gridlines (see (1) above)
    dx = abs(pts(2,1)-pts(1,1)); dy = abs(pts(2,2)-pts(1,2));
    touchesY1 = abs(pts(1,2)-y1) < tol || abs(pts(2,2)-y1) < tol;
    touchesY0 = abs(pts(1,2)-y0) < tol || abs(pts(2,2)-y0) < tol;
    touchesX0 = abs(pts(1,1)-x0) < tol || abs(pts(2,1)-x0) < tol;
    touchesX1 = abs(pts(1,1)-x1) < tol || abs(pts(2,1)-x1) < tol;
    % Both branches of each pair are bounded (near-full-span for "spine-like", well-short for
    % "tick-like") -- an unbounded "isVertSpineLike" would also match a short x-tick that happens to
    % touch x0 (the very first x-tick, at the box's own left edge, unavoidably shares that corner
    % point with the y-spine) and wrongly land it as a spurious extra y-tick (confirmed by hitting
    % exactly this with plotVessels.m's real 7-y-tick/11-x-tick panel).
    isHorizSpineLike = dy < tol && dx > 0.7*boxSpanX;
    isVertTickLike   = dx < tol && dy > tol && dy < 0.3*boxSpanX;   % see (2) above
    if touchesY1 && (isHorizSpineLike || isVertTickLike)
        xBottomCands{end+1} = struct('node',node,'pts',pts); %#ok<AGROW>
    end
    if boxOn && touchesY0 && (isHorizSpineLike || isVertTickLike)
        xTopCands{end+1} = struct('node',node,'pts',pts); %#ok<AGROW>
    end
    isVertSpineLike  = dx < tol && dy > 0.7*boxSpanY;
    isHorizTickLike  = dy < tol && dx > tol && dx < 0.3*boxSpanY;   % see (2) above
    if touchesX0 && (isVertSpineLike || isHorizTickLike)
        yLeftCands{end+1} = struct('node',node,'pts',pts); %#ok<AGROW>
    end
    if boxOn && touchesX1 && (isVertSpineLike || isHorizTickLike)
        yRightCands{end+1} = struct('node',node,'pts',pts); %#ok<AGROW>
    end
end

[spine.xSpineNode, spine.xTickNodes] = pickSpineAndTicks(xBottomCands, x0, x1, 'x', tol);
[spine.ySpineNode, spine.yTickNodes] = pickSpineAndTicks(yLeftCands, y0, y1, 'y', tol);
spine.xSpineTopNode = []; spine.xTickMirrorNodes = {};
spine.ySpineRightNode = []; spine.yTickMirrorNodes = {};
if boxOn
    [spine.xSpineTopNode, spine.xTickMirrorNodes] = pickSpineAndTicks(xTopCands, x0, x1, 'x', tol);
    [spine.ySpineRightNode, spine.yTickMirrorNodes] = pickSpineAndTicks(yRightCands, y0, y1, 'y', tol);
end
end

function [spineNode, tickNodes] = pickSpineAndTicks(cands, lo, hi, axisName, tol)
assert(~isempty(cands), 'identifyAxisSpine:noRulerCandidates', ...
    'no %s-ruler polyline found near the expected spine position -- check Box/tolerance/baking.', axisName);

spans = zeros(numel(cands),1);
for i = 1:numel(cands)
    spans(i) = hypot(cands{i}.pts(2,1)-cands{i}.pts(1,1), cands{i}.pts(2,2)-cands{i}.pts(1,2));
end
[bestSpan, spineIdx] = max(spans);
assert(abs(bestSpan - abs(hi-lo)) < tol*4, 'identifyAxisSpine:spineSpanMismatch', ...
    ['longest %s-ruler candidate spans %.3f pt, expected %.3f pt from ax.InnerPosition -- refusing ' ...
     'to guess this is really the spine.'], axisName, bestSpan, abs(hi-lo));

spineNode = cands{spineIdx}.node;
tickIdx = setdiff(1:numel(cands), spineIdx);
if axisName == 'x'
    tickPos = cellfun(@(c) c.pts(1,1), cands(tickIdx));
else
    tickPos = cellfun(@(c) c.pts(1,2), cands(tickIdx));
end
[~, order] = sort(tickPos);
tickIdx = tickIdx(order);
tickNodes = cellfun(@(c) c.node, cands(tickIdx), 'UniformOutput', false);
end

function pts = parsePolylinePoints(node)
str = char(node.getAttribute('points'));
vals = sscanf(str, '%f,%f');
pts = reshape(vals, 2, [])';
end
