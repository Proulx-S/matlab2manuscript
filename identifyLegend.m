function leg = identifyLegend(figOrAx, snap, doc, axesBoxPt, canvasSizePt, excludeRects)
% identifyLegend  Locate legend furniture (background/border box) and, per snapshotAxesStyle.m
% entry, its own legend swatch + entry text -- in an ALREADY-BAKED svg. Uses the SAME two ground-
% truth signals this repo already validated: exact style-fingerprint color (matchGraphicsToSvg.m)
% and the confirmed fact that a Line/Patch's DisplayName text survives export ONLY as a literal
% legend <text> glyph (docs/findings.md) -- never guessed from position/order alone, only used to
% narrow candidates already restricted to the legend's own box.
%
% figOrAx        the figure (or an axes on it) to check for a live Legend object
% snap           snapshotAxesStyle(ax) captured BEFORE export/close
% doc            org.w3c.dom.Document from xmlread(bakedSvgFile) (SAME doc as matchGraphicsToSvg's,
%                so returned nodes can be tagged directly by a caller doing DOM surgery)
% axesBoxPt      identifyAxisSpine(...).expectedBoxPt, [x0 y0 x1 y1] SVG-space -- excluded as the
%                axes-background rect when hunting for the legend's own box
% canvasSizePt   [width height] SVG canvas size (getCanvasSizeFromDoc.m) -- excluded as the figure-
%                background rect
% excludeRects   (optional, default {}) additional [x0 y0 x1 y1] rects to exclude, by CONTAINMENT
%                (not exact match) -- e.g. a colorbar's own bbox (identifyColorbar.m's
%                cbInfo.bboxPt): its own gradient box renders as exactly the same kind of
%                closed-rect <path> findClosedRectPaths.m matches here (would otherwise be mistaken
%                for a second legend-box candidate, confirmed real 2026-08-29), and MATLAB additionally
%                draws several tiny (~0.5pt) decorative corner-cap rects at the colorbar's own
%                corners (confirmed real, same date) that an EXACT-match exclusion would miss --
%                excluding by containment-within-bboxPt catches both at once.
%
% Returns [] if no live Legend object exists on this figure (nothing to find, not an error).
% Otherwise:
%   leg.boxNodes      cell array of the closed-rect <path> node(s) forming the legend background/
%                      border (MATLAB draws these as two separate <path>s sharing identical corner
%                      geometry -- confirmed in this repo's own probe SVG)
%   leg.entries(i)     .snapIndex (into snap), .displayName, .swatchNode, .textNode -- one entry per
%                      snap(i) with a non-empty DisplayName that was actually found in the legend box
%
% Errors loudly (never silently guesses) if more than one Legend exists, or more than one distinct
% leftover rectangle survives elimination -- same "loud, not silent" discipline as the rest of this
% repo (matchGraphicsToSvg.m/identifyAxisSpine.m).

if isa(figOrAx,'matlab.ui.Figure'); fig = figOrAx; else; fig = ancestor(figOrAx,'figure'); end
legHandles = findobj(fig, 'Type', 'legend');
if isempty(legHandles)
    leg = [];
    return
end
assert(isscalar(legHandles), 'identifyLegend:multipleLegends', ...
    'more than one Legend object on this figure -- multi-panel/multi-legend figures are out of scope for this single-axes prototype.');

% bgTol=1.5pt, not a tighter sub-point tolerance: the 72/ScreenPixelsPerInch rounding discrepancy
% (docs/findings.md) scales with absolute canvas size, and a US-Letter canvas (2026-08-29, the new
% runPillar1.m copy-step default) confirmed a real ~1.14pt figure-background mismatch that a 1pt
% tolerance rejected -- same family/magnitude as identifyAxisSpine.m's own already-widened 1.5pt tol.
bgTol = 1.5;
if nargin < 6 || isempty(excludeRects); excludeRects = {}; end
rectPaths = findClosedRectPaths(doc);
candBoxes = {};
for i = 1:numel(rectPaths)
    r = rectPaths{i}.rect;
    isFigureBg = all(abs(r - [0 0 canvasSizePt(1) canvasSizePt(2)]) < bgTol);
    isAxesBg = all(abs(r - axesBoxPt) < bgTol);
    isExcluded = false;
    for ei = 1:numel(excludeRects)
        ex = excludeRects{ei};
        if r(1) >= ex(1)-bgTol && r(2) >= ex(2)-bgTol && r(3) <= ex(3)+bgTol && r(4) <= ex(4)+bgTol
            isExcluded = true; break
        end
    end
    if ~isFigureBg && ~isAxesBg && ~isExcluded
        candBoxes{end+1} = rectPaths{i}; %#ok<AGROW>
    end
end
assert(~isempty(candBoxes), 'identifyLegend:noBoxFound', ...
    'a live Legend exists but no leftover closed-rect <path> was found for its box (after excluding figure/axes background).');

refRect = candBoxes{1}.rect;
leg.boxNodes = {};
for i = 1:numel(candBoxes)
    assert(all(abs(candBoxes{i}.rect - refRect) < 1), 'identifyLegend:ambiguousLegendBox', ...
        'more than one distinct leftover rectangle found -- cannot disambiguate the legend box in this prototype.');
    leg.boxNodes{end+1} = candBoxes{i}.node;
end

texts = doc.getElementsByTagName('text');
leg.entries = struct('snapIndex',{},'displayName',{},'swatchNode',{},'textNode',{});
seenDisplayNames = {};
for i = 1:numel(snap)
    dn = snap(i).displayName;
    if isempty(dn); continue; end
    % A legend entry is per DISPLAYED ITEM, not per snap(i) -- a Line and its own confidence-band
    % Patch share one DisplayName by design (groupAndTagSvg.m's own series-pairing key), and only the
    % Line normally gets an actual legend entry (the confidence band is typically excluded from the
    % legend, e.g. via an explicit legend() handle list). Processing snap(i) a second time for the
    % SAME DisplayName would just re-find the identical text/swatch nodes and hand them a duplicate
    % id downstream (confirmed real: caught by groupAndTagSvg.m producing two <g id="legend-entry-1">
    % elements) -- skip any DisplayName already resolved to an entry.
    if ismember(dn, seenDisplayNames); continue; end
    textNode = findTextByContentInBox(texts, dn, refRect);
    if isempty(textNode); continue; end   % legend off, or this series has no legend entry -- not an error
    hex = snap(i).hex; if isempty(hex); hex = snap(i).fillHex; end
    swatchNode = findSwatchByColorInBox(doc, hex, refRect);
    leg.entries(end+1) = struct('snapIndex',i,'displayName',dn,'swatchNode',swatchNode,'textNode',textNode); %#ok<AGROW>
    seenDisplayNames{end+1} = dn; %#ok<AGROW>
end
end

function node = findTextByContentInBox(texts, content, boxRect)
node = [];
pad = 2;   % pt -- legend text sits just inside the box, small slack for baseline/anchor offsets
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if ~strcmp(strtrim(char(n.getTextContent())), content); continue; end
    x = str2double(char(n.getAttribute('x'))); y = str2double(char(n.getAttribute('y')));
    if x >= boxRect(1)-pad && x <= boxRect(3)+pad && y >= boxRect(2)-pad && y <= boxRect(4)+pad
        assert(isempty(node), 'identifyLegend:ambiguousLegendText', ...
            'more than one <text> with content "%s" found inside the legend box -- cannot disambiguate.', content);
        node = n;
    end
end
end

function node = findSwatchByColorInBox(doc, hex, boxRect)
% Full containment within the (small) legend box already rules out the main data curve -- it spans
% the whole plot area, far outside the legend -- so no separate exclusion list is needed here.
node = [];
pad = 2;
for tag = {'polyline','path'}
    els = doc.getElementsByTagName(tag{1});
    for k = 0:els.getLength()-1
        n = els.item(k);
        col = attrOrParentLocal(n, 'stroke');
        colFill = attrOrParentLocal(n, 'fill');
        if ~strcmpi(col, hex) && ~strcmpi(colFill, hex); continue; end
        bb = elementBBoxLocal(n, tag{1});
        if isempty(bb); continue; end
        if bb(1) >= boxRect(1)-pad && bb(3) <= boxRect(3)+pad && bb(2) >= boxRect(2)-pad && bb(4) <= boxRect(4)+pad
            assert(isempty(node), 'identifyLegend:ambiguousLegendSwatch', ...
                'more than one same-color swatch candidate found inside the legend box for hex=%s.', hex);
            node = n;
        end
    end
end
assert(~isempty(node), 'identifyLegend:noSwatchFound', ...
    'no legend swatch (color=%s) found inside the legend box.', hex);
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

function bb = elementBBoxLocal(node, tag)
if strcmp(tag,'polyline')
    str = char(node.getAttribute('points'));
    vals = sscanf(str, '%f,%f');
else
    d = char(node.getAttribute('d'));
    nums = regexp(d, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match');
    vals = str2double(nums);
end
if isempty(vals); bb = []; return; end
pts = reshape(vals, 2, [])';
bb = [min(pts(:,1)) min(pts(:,2)) max(pts(:,1)) max(pts(:,2))];
end
