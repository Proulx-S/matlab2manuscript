function leg = identifyLegend(figOrAx, snap, doc, axesBoxPt, canvasSizePt)
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

rectPaths = findClosedRectPaths(doc);
candBoxes = {};
for i = 1:numel(rectPaths)
    r = rectPaths{i}.rect;
    isFigureBg = all(abs(r - [0 0 canvasSizePt(1) canvasSizePt(2)]) < 1);
    isAxesBg = all(abs(r - axesBoxPt) < 1);
    if ~isFigureBg && ~isAxesBg
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
for i = 1:numel(snap)
    dn = snap(i).displayName;
    if isempty(dn); continue; end
    textNode = findTextByContentInBox(texts, dn, refRect);
    if isempty(textNode); continue; end   % legend off, or this series has no legend entry -- not an error
    hex = snap(i).hex; if isempty(hex); hex = snap(i).fillHex; end
    swatchNode = findSwatchByColorInBox(doc, hex, refRect);
    leg.entries(end+1) = struct('snapIndex',i,'displayName',dn,'swatchNode',swatchNode,'textNode',textNode); %#ok<AGROW>
end
end

function rects = findClosedRectPaths(doc)
% A MATLAB-exported axis-aligned closed rectangle serializes (post-bake) as
% "M x0,y0 L x1,y0 L x1,y1 L x0,y1 L x0,y0" (5 point commands, first==last, axis-aligned edges).
paths = doc.getElementsByTagName('path');
rects = {};
for k = 0:paths.getLength()-1
    node = paths.item(k);
    d = char(node.getAttribute('d'));
    nums = regexp(d, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match');
    vals = str2double(nums);
    if numel(vals) ~= 10; continue; end
    pts = reshape(vals, 2, [])';
    if any(abs(pts(1,:) - pts(5,:)) > 1e-6); continue; end
    xs = pts(1:4,1); ys = pts(1:4,2);
    isAxisAligned = numel(unique(round(xs,4))) == 2 && numel(unique(round(ys,4))) == 2;
    if ~isAxisAligned; continue; end
    rects{end+1} = struct('node',node,'rect',[min(xs) min(ys) max(xs) max(ys)]); %#ok<AGROW>
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
