function stats = groupAndTagSvg(ax, snap, bakedSvgFile, taggedSvgFile)
% groupAndTagSvg  The grouping/tagging half of this repo's round-trip pipeline (README pillar 1):
% tags an ALREADY-BAKED svg's (bakeTransforms.py) axis-spine/ticks/labels, matched data series (+
% legend swatch/label), and legend furniture with `id`/`data-role`/`data-group` attributes, so a
% later spatial-control pass (pillar 2) or any downstream tool can select an element by role instead
% of by fragile draw-order/color guessing.
%
% Deliberately ATTRIBUTE-based, not a DOM-restructuring pass: `id`/`data-*` are inert for rendering,
% so tagging existing leaf elements in place can never change paint order or visual output -- unlike
% wrapping non-adjacent siblings (e.g. the x-ruler and y-ruler <g>s, which sit far apart in the
% document with title/tick-label text interleaved between them, confirmed in this repo's own probe
% SVG) into a new shared parent, which WOULD require relocating nodes and risk exactly that. A
% logical "axis-spine" group is instead represented as the shared `data-group="axis-spine"` value on
% however many physically-scattered elements belong to it; a consumer selects by attribute
% (`[data-group="axis-spine"]`), not by DOM nesting.
%
% ax             live axes (NOT yet closed -- ax.Box/.InnerPosition/.Title/.XAxis etc. read live;
%                Box='off', PositionConstraint='innerposition' required, see identifyAxisSpine.m)
% snap           snapshotAxesStyle(ax), captured BEFORE export/close
% bakedSvgFile   path to the baked (bakeTransforms.py) SVG -- absolute coordinates required
% taggedSvgFile  output path (written via xmlwrite)
%
% stats: struct of counts (nDataSeries, nLegendEntries, nXTicks, nYTicks, nAxisLabels) so a caller
% can sanity-check nothing was silently skipped -- e.g. nDataSeries should equal numel(snap) minus
% any snap(i) with no visible style (nothing to match, see matchGraphicsToSvg.m's own header).
%
% Known, deliberately out-of-scope gaps (tracked, not silently accepted -- see docs/findings.md):
% gridlines/figure-background/axes-background are left untouched (not part of the three major roles
% this tool's plan defines); the ad hoc vessel-ID corner label plotVessels.m draws via
% drawIdCornerBox is NOT tagged (same known gap dumpFontRegistry.m already tracks for its font-size
% -- neither an axis label, tick label, data series, nor legend entry in the sense defined here).

doc = xmlread(bakedSvgFile);
canvasSizePt = getCanvasSizeFromDoc(doc);

matches = matchGraphicsToSvg(snap, doc);
spineInfo = identifyAxisSpine(ax, doc, canvasSizePt);
legInfo = identifyLegend(ax, snap, doc, spineInfo.expectedBoxPt, canvasSizePt);

stats = struct('nDataSeries',0, 'nLegendEntries',0, 'nXTicks',0, 'nYTicks',0, 'nAxisLabels',0);

% A "series" groups every snap(i) sharing the same non-empty DisplayName (e.g. a Line + its own
% error-band Patch) under one data-series-index -- the only linking signal available without a
% project-specific convention for pairing a line with its error band (not yet established anywhere
% in humanMouse; revisit if/when one is).
seriesIndexOf = assignSeriesIndices(snap);

% --- data series (+ associated error) ---
for i = 1:numel(snap)
    if isempty(matches(i).node); continue; end   % nothing to tag -- e.g. a hidden helper line (matchGraphicsToSvg.m's own documented skip)
    role = 'dataseries-line';
    if strcmp(snap(i).type,'patch'); role = 'dataseries-fill'; end
    slug = slugify(snap(i).displayName, sprintf('series%d', seriesIndexOf(i)));
    id = sprintf('dataseries-%d-%s', seriesIndexOf(i), slug);
    if strcmp(role,'dataseries-fill'); id = [id '-fill']; end
    setTag(matches(i).node, id, role, 'dataseries', struct('seriesIndex',seriesIndexOf(i), 'displayName',snap(i).displayName));
    stats.nDataSeries = stats.nDataSeries + 1;
end

% --- legend (text-content-sensitive -- must run before tick-label/axis-label matching below, which
% assume already-tagged text is claimed and skip it, so a coincidental content collision -- e.g. this
% repo's own probe SVG has a legend entry reading "radius" AND a y-axis label reading "radius" --
% resolves to the legend's own copy first, since legend matching is independently spatially
% constrained to the legend box and therefore unambiguous regardless of order) ---
if ~isempty(legInfo)
    for bi = 1:numel(legInfo.boxNodes)
        suffix = 'bg'; if bi > 1; suffix = 'border'; end
        setTag(legInfo.boxNodes{bi}, sprintf('legend-box-%s',suffix), 'legend-box', 'legend');
    end
    for ei = 1:numel(legInfo.entries)
        e = legInfo.entries(ei);
        si = seriesIndexOf(e.snapIndex);
        setTag(e.swatchNode, sprintf('legend-swatch-%d',si), 'legend-swatch', 'legend', struct('seriesIndex',si));
        setTag(e.textNode, sprintf('legend-label-%d',si), 'legend-label', 'legend', struct('seriesIndex',si));
        stats.nLegendEntries = stats.nLegendEntries + 1;
    end
end

% --- axis spine + its own tick marks (geometry-only, no text -- order-independent) ---
setTag(spineInfo.xSpineNode, 'axis-spine-x', 'spine-line', 'axis-spine');
setTag(spineInfo.ySpineNode, 'axis-spine-y', 'spine-line', 'axis-spine');
for k = 1:numel(spineInfo.xTickNodes)
    setTag(spineInfo.xTickNodes{k}, sprintf('axis-tick-x-%d',k), 'tick-mark', 'axis-spine', struct('subgroup','ticks-x'));
end
for k = 1:numel(spineInfo.yTickNodes)
    setTag(spineInfo.yTickNodes{k}, sprintf('axis-tick-y-%d',k), 'tick-mark', 'axis-spine', struct('subgroup','ticks-y'));
end
stats.nXTicks = numel(spineInfo.xTickNodes);
stats.nYTicks = numel(spineInfo.yTickNodes);

% --- tick labels (content+position sensitive -- must run after legend tagging above) ---
xLabelNodes = matchTickLabels(doc, ax.XAxis.TickLabels, spineInfo.xTickNodes, 'x', spineInfo.expectedBoxPt);
for k = 1:numel(xLabelNodes)
    setTag(xLabelNodes{k}, sprintf('axis-ticklabel-x-%d',k), 'tick-label', 'axis-spine', struct('subgroup','ticks-x'));
end
yLabelNodes = matchTickLabels(doc, ax.YAxis.TickLabels, spineInfo.yTickNodes, 'y', spineInfo.expectedBoxPt);
for k = 1:numel(yLabelNodes)
    setTag(yLabelNodes{k}, sprintf('axis-ticklabel-y-%d',k), 'tick-label', 'axis-spine', struct('subgroup','ticks-y'));
end

% --- axis title/xlabel/ylabel (content-only -- must run LAST so it correctly skips whatever legend/
% tick-label matching above already claimed) ---
texts = doc.getElementsByTagName('text');
labelDefs = {'title',char(ax.Title.String); 'xlabel',char(ax.XLabel.String); 'ylabel',char(ax.YLabel.String)};
for li = 1:size(labelDefs,1)
    role = labelDefs{li,1}; content = labelDefs{li,2};
    if isempty(content); continue; end
    node = findUntaggedTextByContent(texts, content);
    if isempty(node); continue; end   % not drawn (e.g. no title set) -- not an error
    setTag(node, ['axis-' role], 'axis-label', 'axis-spine', struct('subgroup','axis-labels'));
    stats.nAxisLabels = stats.nAxisLabels + 1;
end

xmlwrite(taggedSvgFile, doc);
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

function setTag(node, id, role, group, extra)
node.setAttribute('id', id);
node.setAttribute('data-role', role);
node.setAttribute('data-group', group);
if nargin >= 5
    fn = fieldnames(extra);
    for i = 1:numel(fn)
        v = extra.(fn{i});
        if ~ischar(v); v = num2str(v); end
        node.setAttribute(['data-' camelToKebab(fn{i})], v);
    end
end
end

function k = camelToKebab(s)
k = regexprep(s, '([a-z0-9])([A-Z])', '$1-$2');
k = lower(k);
end

function node = findUntaggedTextByContent(texts, content)
node = [];
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if ~isempty(char(n.getAttribute('id'))); continue; end
    if strcmp(strtrim(char(n.getTextContent())), content)
        assert(isempty(node), 'groupAndTagSvg:ambiguousAxisLabel', ...
            'more than one untagged <text> matches content "%s" -- cannot disambiguate.', content);
        node = n;
    end
end
end

function labelNodes = matchTickLabels(doc, tickLabelStrs, tickNodes, axisName, boxRect)
% Candidate <text> nodes: untagged, content is one of the live tick label strings (ground truth,
% same source dumpFontRegistry.m uses), AND positioned just outside the spine on the expected side
% (below for x, left for y) -- the position check alone would be too fragile (nothing to anchor an
% exact distance threshold against) and the content check alone risks a cross-axis collision, so
% both are required; loudly refuses to pair if the resulting count doesn't match the tick marks.
texts = doc.getElementsByTagName('text');
cands = {};
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if ~isempty(char(n.getAttribute('id'))); continue; end
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
