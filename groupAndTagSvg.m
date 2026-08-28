function stats = groupAndTagSvg(ax, snap, bakedSvgFile, taggedSvgFile)
% groupAndTagSvg  The grouping/tagging half of this repo's round-trip pipeline (README pillar 1):
% restructures an ALREADY-BAKED svg's DOM into real nested <g> containers for four roles --
% furniture (figure/axes background, gridlines), axis-spine (spine lines, per-tick mark+label pairs,
% axis labels), dataseries (+ associated error), legend (box, per-entry swatch+label) -- each
% element also getting its own `id`/`data-role` for direct addressing. Anything left unclaimed (e.g.
% plotVessels.m's own ad hoc vessel-ID corner label) gets `id`/`data-role="annotation"` tagged IN
% PLACE instead, deliberately NOT grouped together -- see that section's own comment below for why.
% This gives a real SVG editor's own click-to-select/collapse behavior a usable hierarchy (select
% the whole axis-spine, or one tick's mark+label together, in one click) instead of 60+ flat,
% one-element-each groups at the document root.
%
% REVISED 2026-08-28 from this file's first version, which stamped `id`/`data-role`/`data-group`
% directly onto existing leaf elements without moving anything, reasoning that relocating nodes
% risked changing paint order. Seb's own feedback: that flat, attribute-only structure is useless in
% practice -- a real SVG editor's grouping/selection model is DOM nesting, not attribute values, so
% it required exactly as many clicks as no grouping at all. This version actually moves elements,
% verified NOT to change rendering by (1) inlining every relocated leaf's inherited presentation
% attributes (fill/stroke/font-*/etc, walked up from its original ancestor <g>) directly onto itself
% before moving it, so it never depends on whatever new ancestor it ends up under, and (2) anchoring
% each new top-level group at the document position of whichever of its members occurs EARLIEST in
% the original document, which preserves every group's paint order relative to untouched/other-group
% siblings exactly (empirically confirmed via rasterized pixel-diff against the un-grouped baked
% file, both in this file's own test and ad hoc verification during development -- see
% docs/findings.md).
%
% ax             live axes (NOT yet closed -- ax.Box/.InnerPosition/.Title/.XAxis etc. read live;
%                Box='off', PositionConstraint='innerposition' required, see identifyAxisSpine.m)
% snap           snapshotAxesStyle(ax), captured BEFORE export/close
% bakedSvgFile   path to the baked (bakeTransforms.py) SVG -- absolute coordinates required
% taggedSvgFile  output path (written via xmlwrite)
%
% stats: struct of counts (nDataSeries, nLegendEntries, nXTicks, nYTicks, nAxisLabels,
% nFurnitureGridlines, nAnnotations) so a caller can sanity-check nothing was silently skipped.
%
% Known, deliberately out-of-scope gaps (tracked, not silently accepted -- see docs/findings.md):
% `ax.Box='on'` not handled (identifyAxisSpine.m errors loudly); a Line+error-band Patch is paired
% into one series by DisplayName equality only, no more explicit project convention exists yet;
% multi-legend/multi-axes figures out of scope.

doc = xmlread(bakedSvgFile);
canvasSizePt = getCanvasSizeFromDoc(doc);
root = getRootGroup(doc);

% --- identification only below (read-only queries against the still-untouched doc; every node
% reference collected here stays valid after later mutation -- Java DOM objects don't invalidate
% when detached, only their position changes) ---
matches = matchGraphicsToSvg(snap, doc);
spineInfo = identifyAxisSpine(ax, doc, canvasSizePt);
legInfo = identifyLegend(ax, snap, doc, spineInfo.expectedBoxPt, canvasSizePt);
xLabelNodes = matchTickLabels(doc, ax.XAxis.TickLabels, spineInfo.xTickNodes, 'x', spineInfo.expectedBoxPt);
yLabelNodes = matchTickLabels(doc, ax.YAxis.TickLabels, spineInfo.yTickNodes, 'y', spineInfo.expectedBoxPt);
furn = identifyFurniture(doc, canvasSizePt, spineInfo.expectedBoxPt);

seriesIndexOf = assignSeriesIndices(snap);

% Axis title/xlabel/ylabel: content-only match, excluding whatever legend/tick-label matching above
% already claimed (this repo's own real test panel has a genuine collision -- its y-axis label and
% its legend entry both render the literal string "radius").
excludeText = {};
if ~isempty(legInfo)
    for ei = 1:numel(legInfo.entries); excludeText{end+1} = legInfo.entries(ei).textNode; end %#ok<AGROW>
end
excludeText = [excludeText, xLabelNodes(:)', yLabelNodes(:)'];
texts = doc.getElementsByTagName('text');
labelDefs = {'title',char(ax.Title.String); 'xlabel',char(ax.XLabel.String); 'ylabel',char(ax.YLabel.String)};
axisLabelNode = struct('title',[],'xlabel',[],'ylabel',[]);
for li = 1:size(labelDefs,1)
    role = labelDefs{li,1}; content = labelDefs{li,2};
    if isempty(content); continue; end
    node = findTextByContentExcluding(texts, content, excludeText);
    if ~isempty(node); axisLabelNode.(role) = node; end
end

% Catch-all "annotations": anything with real geometry/text that isn't claimed by any role above.
claimed = [{spineInfo.xSpineNode, spineInfo.ySpineNode}, spineInfo.xTickNodes(:)', spineInfo.yTickNodes(:)', ...
    xLabelNodes(:)', yLabelNodes(:)', {axisLabelNode.title, axisLabelNode.xlabel, axisLabelNode.ylabel}, ...
    {furn.figureBgNode, furn.axesBgNode}, furn.gridlineNodes(:)'];
for i = 1:numel(snap)
    if ~isempty(matches(i).node); claimed{end+1} = matches(i).node; end %#ok<AGROW>
end
if ~isempty(legInfo)
    claimed = [claimed, legInfo.boxNodes(:)'];
    for ei = 1:numel(legInfo.entries)
        claimed{end+1} = legInfo.entries(ei).swatchNode; %#ok<AGROW>
        claimed{end+1} = legInfo.entries(ei).textNode; %#ok<AGROW>
    end
end
annotationNodes = {};
for tagName = {'polyline','path','text','circle','image'}
    els = doc.getElementsByTagName(tagName{1});
    for k = 0:els.getLength()-1
        n = els.item(k);
        if isNodeInList(n, claimed); continue; end
        annotationNodes{end+1} = n; %#ok<AGROW>
    end
end

% --- anchors: computed BEFORE any mutation, off the still-original document, so each new group's
% insertion point reflects whichever of its members occurs earliest in draw order ---
furnitureMembers = [{furn.figureBgNode, furn.axesBgNode}, furn.gridlineNodes(:)'];
spineMembers = [{spineInfo.xSpineNode, spineInfo.ySpineNode}, spineInfo.xTickNodes(:)', spineInfo.yTickNodes(:)', ...
    xLabelNodes(:)', yLabelNodes(:)', {axisLabelNode.title, axisLabelNode.xlabel, axisLabelNode.ylabel}];
dataMembers = {};
for i = 1:numel(snap)
    if ~isempty(matches(i).node); dataMembers{end+1} = matches(i).node; end %#ok<AGROW>
end
legendMembers = {};
if ~isempty(legInfo)
    legendMembers = legInfo.boxNodes(:)';
    for ei = 1:numel(legInfo.entries)
        legendMembers{end+1} = legInfo.entries(ei).swatchNode; %#ok<AGROW>
        legendMembers{end+1} = legInfo.entries(ei).textNode; %#ok<AGROW>
    end
end

anchorFurniture = earliestOriginalChild(root, furnitureMembers);
anchorSpine = earliestOriginalChild(root, spineMembers);
anchorData = earliestOriginalChild(root, dataMembers);
anchorLegend = earliestOriginalChild(root, legendMembers);

stats = struct('nDataSeries',0, 'nLegendEntries',0, 'nXTicks',0, 'nYTicks',0, 'nAxisLabels',0, ...
    'nFurnitureGridlines',0, 'nAnnotations',0);

% --- furniture ---
if ~isempty(furn.figureBgNode) || ~isempty(furn.axesBgNode) || ~isempty(furn.gridlineNodes)
    furnitureG = newGroup(doc, 'furniture', 'furniture');
    insertAt(root, furnitureG, anchorFurniture);
    if ~isempty(furn.figureBgNode)
        relocateLeaf(furn.figureBgNode, furnitureG);
        tagLeaf(furn.figureBgNode, 'figure-background', 'figure-background');
    end
    if ~isempty(furn.axesBgNode)
        relocateLeaf(furn.axesBgNode, furnitureG);
        tagLeaf(furn.axesBgNode, 'axes-background', 'axes-background');
    end
    if ~isempty(furn.gridlineNodes)
        gridG = newGroup(doc, 'gridlines', 'gridlines');
        furnitureG.appendChild(gridG);
        for k = 1:numel(furn.gridlineNodes)
            relocateLeaf(furn.gridlineNodes{k}, gridG);
            tagLeaf(furn.gridlineNodes{k}, sprintf('gridline-%d',k), 'gridline');
        end
        stats.nFurnitureGridlines = numel(furn.gridlineNodes);
    end
end

% --- axis spine (spine lines, per-tick mark+label pairs, axis labels) ---
spineG = newGroup(doc, 'axis-spine', 'axis-spine');
insertAt(root, spineG, anchorSpine);

linesG = newGroup(doc, 'axis-spine-lines', 'spine-lines');
spineG.appendChild(linesG);
relocateLeaf(spineInfo.xSpineNode, linesG); tagLeaf(spineInfo.xSpineNode, 'axis-spine-x', 'spine-line');
relocateLeaf(spineInfo.ySpineNode, linesG); tagLeaf(spineInfo.ySpineNode, 'axis-spine-y', 'spine-line');

ticksXG = newGroup(doc, 'axis-ticks-x', 'ticks'); ticksXG.setAttribute('data-axis','x');
spineG.appendChild(ticksXG);
for k = 1:numel(spineInfo.xTickNodes)
    tickG = newGroup(doc, sprintf('axis-tick-x-%d',k), 'tick');
    ticksXG.appendChild(tickG);
    relocateLeaf(spineInfo.xTickNodes{k}, tickG);
    tagLeaf(spineInfo.xTickNodes{k}, sprintf('axis-tick-x-%d-mark',k), 'tick-mark');
    if k <= numel(xLabelNodes) && ~isempty(xLabelNodes{k})
        relocateLeaf(xLabelNodes{k}, tickG);
        tagLeaf(xLabelNodes{k}, sprintf('axis-ticklabel-x-%d',k), 'tick-label');
    end
end
stats.nXTicks = numel(spineInfo.xTickNodes);

ticksYG = newGroup(doc, 'axis-ticks-y', 'ticks'); ticksYG.setAttribute('data-axis','y');
spineG.appendChild(ticksYG);
for k = 1:numel(spineInfo.yTickNodes)
    tickG = newGroup(doc, sprintf('axis-tick-y-%d',k), 'tick');
    ticksYG.appendChild(tickG);
    relocateLeaf(spineInfo.yTickNodes{k}, tickG);
    tagLeaf(spineInfo.yTickNodes{k}, sprintf('axis-tick-y-%d-mark',k), 'tick-mark');
    if k <= numel(yLabelNodes) && ~isempty(yLabelNodes{k})
        relocateLeaf(yLabelNodes{k}, tickG);
        tagLeaf(yLabelNodes{k}, sprintf('axis-ticklabel-y-%d',k), 'tick-label');
    end
end
stats.nYTicks = numel(spineInfo.yTickNodes);

labelsG = newGroup(doc, 'axis-labels', 'axis-labels');
spineG.appendChild(labelsG);
for role = {'title','xlabel','ylabel'}
    node = axisLabelNode.(role{1});
    if isempty(node); continue; end
    relocateLeaf(node, labelsG);
    tagLeaf(node, ['axis-' role{1}], 'axis-label');
    stats.nAxisLabels = stats.nAxisLabels + 1;
end

% --- data series (+ associated error, linked by shared DisplayName) ---
if ~isempty(dataMembers)
    dataG = newGroup(doc, 'dataseries', 'dataseries');
    insertAt(root, dataG, anchorData);
    seriesGroupOf = containers.Map('KeyType','double','ValueType','any');
    for i = 1:numel(snap)
        if isempty(matches(i).node); continue; end
        si = seriesIndexOf(i);
        if ~isKey(seriesGroupOf, si)
            slug = slugify(snap(i).displayName, sprintf('series%d',si));
            sg = newGroup(doc, sprintf('dataseries-%d-%s',si,slug), 'series');
            sg.setAttribute('data-series-index', num2str(si));
            if ~isempty(snap(i).displayName); sg.setAttribute('data-display-name', snap(i).displayName); end
            dataG.appendChild(sg);
            seriesGroupOf(si) = sg;
        end
        role = 'dataseries-line'; suffix = '';
        if strcmp(snap(i).type,'patch'); role = 'dataseries-fill'; suffix = '-fill'; end
        relocateLeaf(matches(i).node, seriesGroupOf(si));
        slug = slugify(snap(i).displayName, sprintf('series%d',si));
        tagLeaf(matches(i).node, sprintf('dataseries-%d-%s%s',si,slug,suffix), role);
        stats.nDataSeries = stats.nDataSeries + 1;
    end
end

% --- legend (box, per-entry swatch+label) ---
if ~isempty(legInfo)
    legendG = newGroup(doc, 'legend', 'legend');
    insertAt(root, legendG, anchorLegend);
    boxG = newGroup(doc, 'legend-box', 'legend-box');
    legendG.appendChild(boxG);
    for bi = 1:numel(legInfo.boxNodes)
        suffix = 'bg'; if bi > 1; suffix = 'border'; end
        relocateLeaf(legInfo.boxNodes{bi}, boxG);
        tagLeaf(legInfo.boxNodes{bi}, sprintf('legend-box-%s',suffix), sprintf('legend-box-%s',suffix));
    end
    for ei = 1:numel(legInfo.entries)
        e = legInfo.entries(ei);
        si = seriesIndexOf(e.snapIndex);
        entryG = newGroup(doc, sprintf('legend-entry-%d',si), 'legend-entry');
        entryG.setAttribute('data-series-index', num2str(si));
        legendG.appendChild(entryG);
        relocateLeaf(e.swatchNode, entryG); tagLeaf(e.swatchNode, sprintf('legend-swatch-%d',si), 'legend-swatch');
        relocateLeaf(e.textNode, entryG); tagLeaf(e.textNode, sprintf('legend-label-%d',si), 'legend-label');
        stats.nLegendEntries = stats.nLegendEntries + 1;
    end
end

% --- annotations (catch-all for anything not claimed above, e.g. plotVessels.m's ad hoc vessel-ID
% corner label -- known, deliberately tracked gap: this tags it, but doesn't further interpret it).
% Deliberately tagged IN PLACE, never relocated or combined into one shared group: unlike axis-
% spine/dataseries/legend, whose own members are always drawn as one contiguous cluster in MATLAB's
% output (verified empirically), annotations are by definition arbitrary, mutually-unrelated
% leftovers with no such guarantee -- confirmed for real on this repo's own validation panel, where
% combining two leftover elements (a whole-figure title-ish text and the vessel-ID corner label, far
% apart in the original document) into one shared group at the EARLIER one's position dragged the
% LATER one backward past the axis-spine and data series in paint order, a genuine visual-regression
% risk this file's whole design is meant to avoid. Tagging in place carries none of that risk. ---
for k = 1:numel(annotationNodes)
    if isempty(char(annotationNodes{k}.getAttribute('id')))
        annotationNodes{k}.setAttribute('id', sprintf('annotation-%d',k));
    end
    annotationNodes{k}.setAttribute('data-role','annotation');
end
stats.nAnnotations = numel(annotationNodes);

pruneEmptyGroups(root);

xmlwrite(taggedSvgFile, doc);
end

% ============================== identification helpers ==============================

function furn = identifyFurniture(doc, canvasSizePt, axesBoxPt)
% The figure-background rect (spans the whole canvas) and axes-background rect (spans the spine's
% own box, found via findClosedRectPaths.m -- shared with identifyLegend.m), plus every gridline
% polyline (excluded from identifyAxisSpine.m's own spine/tick candidacy by the SAME opacity signal
% -- gridlines are always drawn with a fractional stroke-opacity, confirmed in this repo's probe SVG).
rects = findClosedRectPaths(doc);
furn.figureBgNode = [];
furn.axesBgNode = [];
for i = 1:numel(rects)
    r = rects{i}.rect;
    if all(abs(r - [0 0 canvasSizePt(1) canvasSizePt(2)]) < 1)
        furn.figureBgNode = rects{i}.node;
    elseif all(abs(r - axesBoxPt) < 1)
        furn.axesBgNode = rects{i}.node;
    end
end
polylines = doc.getElementsByTagName('polyline');
furn.gridlineNodes = {};
for k = 0:polylines.getLength()-1
    node = polylines.item(k);
    if getElementOpacity(node) < 0.99
        furn.gridlineNodes{end+1} = node; %#ok<AGROW>
    end
end
end

function labelNodes = matchTickLabels(doc, tickLabelStrs, tickNodes, axisName, boxRect)
% Candidate <text> nodes: content is one of the live tick label strings (ground truth, same source
% dumpFontRegistry.m uses), AND positioned just outside the spine on the expected side (below for x,
% left for y) -- content alone risks a cross-axis collision, position alone has no exact distance to
% anchor a threshold against, so both are required; loudly refuses to pair if the resulting count
% doesn't match the tick marks.
texts = doc.getElementsByTagName('text');
cands = {};
for k = 0:texts.getLength()-1
    n = texts.item(k);
    content = strtrim(char(n.getTextContent()));
    if ~ismember(content, tickLabelStrs); continue; end
    x = str2double(char(n.getAttribute('x'))); y = str2double(char(n.getAttribute('y')));
    if axisName == 'x'
        inRange = y > boxRect(4) - 0.5 && y < boxRect(4) + 30;   % below the box, SVG y-down
        pos = x;
    else
        inRange = x < boxRect(1) + 0.5 && x > boxRect(1) - 30;   % left of the box
        pos = y;
    end
    if ~inRange; continue; end
    cands{end+1} = struct('node',n,'pos',pos); %#ok<AGROW>
end
assert(numel(cands) == numel(tickNodes), 'groupAndTagSvg:tickLabelCountMismatch', ...
    ['found %d %s-tick-label <text> candidate(s), expected %d (one per tick mark) -- refusing to ' ...
     'guess the pairing.'], numel(cands), axisName, numel(tickNodes));
[~, order] = sort(cellfun(@(c) c.pos, cands));
cands = cands(order);
labelNodes = cellfun(@(c) c.node, cands, 'UniformOutput', false);
end

function node = findTextByContentExcluding(texts, content, excludeList)
node = [];
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if isNodeInList(n, excludeList); continue; end
    if strcmp(strtrim(char(n.getTextContent())), content)
        assert(isempty(node), 'groupAndTagSvg:ambiguousAxisLabel', ...
            'more than one <text> (outside already-claimed nodes) matches content "%s" -- cannot disambiguate.', content);
        node = n;
    end
end
end

function idx = assignSeriesIndices(snap)
idx = zeros(numel(snap),1);
keyToIdx = containers.Map('KeyType','char','ValueType','double');
nextIdx = 0;
for i = 1:numel(snap)
    key = snap(i).displayName;
    if isempty(key); key = sprintf('__unnamed_%d__', i); end
    if ~isKey(keyToIdx, key)
        nextIdx = nextIdx + 1;
        keyToIdx(key) = nextIdx;
    end
    idx(i) = keyToIdx(key);
end
end

function s = slugify(name, fallback)
if isempty(name); s = fallback; return; end
s = regexprep(lower(name), '[^a-z0-9]+', '-');
s = regexprep(s, '(^-+|-+$)', '');
if isempty(s); s = fallback; end
end

% ============================== DOM-surgery helpers ==============================

function g = getRootGroup(doc)
% MATLAB's -dsvg exporter wraps its entire drawing in exactly one top-level <g> (confirmed in this
% repo's own probe SVG) -- every semantic group this file builds is inserted as a sibling within it.
docRoot = doc.getDocumentElement();
kids = docRoot.getChildNodes();
g = [];
for i = 0:kids.getLength()-1
    c = kids.item(i);
    if c.getNodeType() == c.ELEMENT_NODE && strcmp(char(c.getTagName()),'g')
        assert(isempty(g), 'groupAndTagSvg:multipleRootGroups', ...
            'more than one top-level <g> found under <svg> -- unexpected MATLAB export structure.');
        g = c;
    end
end
assert(~isempty(g), 'groupAndTagSvg:noRootGroup', 'no top-level <g> found under <svg>.');
end

function g = newGroup(doc, id, role)
g = doc.createElement('g');
g.setAttribute('id', id);
g.setAttribute('data-role', role);
end

function insertAt(root, newG, anchor)
if ~isempty(anchor)
    root.insertBefore(newG, anchor);
else
    root.appendChild(newG);
end
end

function tagLeaf(node, id, role)
node.setAttribute('id', id);
node.setAttribute('data-role', role);
end

function relocateLeaf(node, newParent)
% Moves node into newParent, first inlining every inherited presentation attribute (fill/stroke/
% font-*/etc, walked up from node's CURRENT ancestor chain) directly onto node itself -- so its
% rendering never depends on whichever new (unstyled, id/data-role-only) semantic <g> it ends up
% nested under. MATLAB's own <text> elements already self-declare these directly (confirmed in this
% repo's own probe SVG) so this is a no-op for them; geometry primitives (polyline/path/circle) rely
% on their original style-batching wrapper <g> for most of it, so this matters there.
inlinePresentationAttrs(node);
oldParent = node.getParentNode();
oldParent.removeChild(node);
newParent.appendChild(node);
end

function inlinePresentationAttrs(node)
attrs = {'fill','fill-opacity','fill-rule','stroke','stroke-opacity','stroke-width', ...
    'stroke-linecap','stroke-linejoin','stroke-miterlimit','font-family','font-size', ...
    'font-weight','font-style','vector-effect'};
for i = 1:numel(attrs)
    a = attrs{i};
    if node.hasAttribute(a); continue; end
    v = attrFromAncestor(node, a);
    if ~isempty(v); node.setAttribute(a, v); end
end
end

function val = attrFromAncestor(node, attrName)
val = '';
n = node.getParentNode();
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute(attrName)
        val = char(n.getAttribute(attrName));
        return
    end
    n = n.getParentNode();
end
end

function anchor = earliestOriginalChild(root, nodes)
% Whichever DIRECT CHILD of root contains (or equals) the earliest-in-document-order member of
% `nodes` -- used to insert a new semantic group at the position of its earliest original member,
% preserving paint order relative to every untouched/other-group sibling.
children = root.getChildNodes();
bestIdx = Inf; anchor = [];
for i = 0:children.getLength()-1
    child = children.item(i);
    if child.getNodeType() ~= child.ELEMENT_NODE; continue; end
    for k = 1:numel(nodes)
        if isempty(nodes{k}); continue; end
        if isSelfOrAncestor(child, nodes{k})
            if i < bestIdx; bestIdx = i; anchor = child; end
            break
        end
    end
end
end

function tf = isSelfOrAncestor(candidateAncestor, node)
n = node;
tf = false;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.isSameNode(candidateAncestor); tf = true; return; end
    n = n.getParentNode();
end
end

function tf = isNodeInList(node, list)
tf = false;
for i = 1:numel(list)
    if ~isempty(list{i}) && node.isSameNode(list{i}); tf = true; return; end
end
end

function pruneEmptyGroups(root)
% Removes any now-empty <g> left behind by relocateLeaf (an original MATLAB style-batching wrapper
% whose entire content was moved out) -- checked by ELEMENT children specifically, since Java DOM
% keeps insignificant whitespace as real Text child nodes that survive a leaf's removal.
kids = root.getChildNodes();
toRemove = {};
for i = 0:kids.getLength()-1
    c = kids.item(i);
    if c.getNodeType() == c.ELEMENT_NODE && strcmp(char(c.getTagName()),'g') && ~hasElementChildren(c)
        toRemove{end+1} = c; %#ok<AGROW>
    end
end
for i = 1:numel(toRemove)
    root.removeChild(toRemove{i});
end
end

function tf = hasElementChildren(node)
kids = node.getChildNodes();
tf = false;
for i = 0:kids.getLength()-1
    if kids.item(i).getNodeType() == kids.item(i).ELEMENT_NODE; tf = true; return; end
end
end
