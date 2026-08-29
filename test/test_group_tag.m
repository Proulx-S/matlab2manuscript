% NOTE: this test deliberately validates groupAndTagSvg.m (+ identifyAxisSpine.m/identifyLegend.m)
% against a REAL plotting function (plotVessels.m) from a real consuming project (humanMouse), with
% a legend ON, so the DisplayName-content-collision case (this repo's own probe SVG has a legend
% entry AND a y-axis label that are both literally "radius") is actually exercised, not hypothetical.
% Adjust workDir if humanMouse lives elsewhere on this machine.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

% Seeded for reproducibility -- the exact random noise here affects auto-computed y-tick VALUES
% (hence label string widths), which shifts how much horizontal space plotVessels.m's tiledlayout
% leaves for the plot box, which changes how many x-ticks MATLAB's own auto-tick-placement draws.
% Confirmed real: an earlier unseeded run of this same test produced 11 x-ticks, a later one only 5.
% Assertions below compare against LIVE tick-label counts (captured before close(fig)), not
% hardcoded literals, so this test stays correct even if that chain shifts again for some other
% reason -- the seed just keeps THIS run's own numbers stable and inspectable.
rng(0);
t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct('legendVerbose',1));
ax = findobj(fig,'Type','axes'); ax = ax(1);
% plotVessels.m ALWAYS hosts its axes inside a tiledlayout (even for a single panel, confirmed via
% class(ax.Parent)=='matlab.graphics.layout.TiledChartLayout') -- PositionConstraint cannot be set
% for a tiled axes at all (MATLAB rejects it: "Unable to set ... for objects in a TiledChartLayout"),
% so identifyAxisSpine.m skips that check for one. See its own comment for why the real invariant
% (exported spine geometry matches live ax.InnerPosition within a small, confirmed tolerance) is
% what's actually verified instead, empirically, downstream.
fprintf('ax.Box=%s, class(ax.Parent)=%s, ax.Title.String="%s", ax.XLabel.String="%s", ax.YLabel.String="%s"\n', ...
    ax.Box, class(ax.Parent), char(ax.Title.String), char(ax.XLabel.String), char(ax.YLabel.String));

snap = snapshotAxesStyle(ax);
nXTicksExpected = numel(ax.XAxis.TickLabels);
nYTicksExpected = numel(ax.YAxis.TickLabels);

rawFile = fullfile(outDir,'group_tag_raw.svg');
print(fig, rawFile, '-dsvg','-vector');

bakedFile = fullfile(outDir,'group_tag_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

taggedFile = fullfile(outDir,'group_tag_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile);
close(fig);   % safe to close now -- groupAndTagSvg only needed the live ax/fig up to this point

fprintf('stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d nAxisLabels=%d nFurnitureGridlines=%d nAnnotations=%d\n', ...
    stats.nDataSeries, stats.nLegendEntries, stats.nXTicks, stats.nYTicks, stats.nAxisLabels, ...
    stats.nFurnitureGridlines, stats.nAnnotations);

assert(stats.nDataSeries == 1, 'expected exactly 1 tagged data series');
assert(stats.nLegendEntries == 1, 'expected exactly 1 tagged legend entry');
assert(stats.nXTicks == nXTicksExpected, 'expected %d x-ticks (from live ax.XAxis.TickLabels)', nXTicksExpected);
assert(stats.nYTicks == nYTicksExpected, 'expected %d y-ticks (from live ax.YAxis.TickLabels)', nYTicksExpected);
% ax.Title.String is empty for this real panel (the top text seen in this repo's own probe SVG is a
% separate whole-figure title/annotation, not ax.Title -- not this tool's concern yet) -- only
% xlabel+ylabel are real ax-level labels here.
assert(stats.nAxisLabels == 2, 'expected xlabel+ylabel tagged (2, ax.Title.String is empty for this panel)');
assert(stats.nFurnitureGridlines == nXTicksExpected + nYTicksExpected, ...
    'expected %d gridlines (one per tick, both axes)', nXTicksExpected + nYTicksExpected);
assert(stats.nAnnotations == 2, 'expected 2 leftover annotations (whole-figure title-ish text + vessel-ID corner label)');

% --- element-count invariant: grouping/tagging must never add/remove/duplicate a rendering-bearing
% element -- only <g> wrapper counts should change (new semantic groups added, now-empty original
% style-batching wrappers pruned).
docBaked = xmlread(bakedFile);
docTagged = xmlread(taggedFile);
for tag = {'polyline','path','text','circle'}
    nBaked = docBaked.getElementsByTagName(tag{1}).getLength();
    nTagged = docTagged.getElementsByTagName(tag{1}).getLength();
    assert(nBaked == nTagged, 'element count changed for <%s>: baked=%d tagged=%d', tag{1}, nBaked, nTagged);
    fprintf('<%s> count preserved: %d\n', tag{1}, nBaked);
end

% --- top-level structure: exactly the expected semantic groups, in the expected (paint-order-safe)
% sequence -- nothing left as a stray element directly under MATLAB's own outer wrapper <g>.
rootG = getTestRootGroup(docTagged);
topKids = rootG.getChildNodes();
topGroupIds = {};
for i = 0:topKids.getLength()-1
    c = topKids.item(i);
    if c.getNodeType() ~= c.ELEMENT_NODE; continue; end
    assert(strcmp(char(c.getTagName()),'g'), 'stray non-<g> element left at top level: <%s>', char(c.getTagName()));
    topGroupIds{end+1} = char(c.getAttribute('id')); %#ok<AGROW>
end
fprintf('top-level groups (paint order): %s\n', strjoin(topGroupIds, ', '));
% Annotations are tagged IN PLACE, never grouped (see groupAndTagSvg.m's own comment on why) -- each
% one's ORIGINAL, untouched, un-ided MATLAB wrapper <g> is still a top-level sibling, so exactly
% nAnnotations of these top-level ids are expected to be empty; every NAMED one must be one of the
% four real semantic groups, nothing else.
namedTopGroupIds = topGroupIds(~cellfun(@isempty, topGroupIds));
nUnnamed = sum(cellfun(@isempty, topGroupIds));
assert(isequal(namedTopGroupIds, {'furniture','axis-spine','dataseries','legend'}), ...
    'unexpected named top-level group set/order: %s', strjoin(namedTopGroupIds,', '));
assert(nUnnamed == stats.nAnnotations, ...
    'expected %d unnamed leftover wrapper <g>s (one per in-place-tagged annotation), found %d', ...
    stats.nAnnotations, nUnnamed);

% --- real nesting: the whole point of this rewrite -- verify actual DOM parent/child relationships,
% not just that every id string happens to appear somewhere in the file.
spineX = findTestById(docTagged,'axis-spine-x');
assert(hasTestParentId(spineX,'axis-spine-lines'), 'axis-spine-x not directly under axis-spine-lines');
assert(hasTestAncestorId(spineX,'axis-spine'), 'axis-spine-x not nested under axis-spine');

tick1Mark = findTestById(docTagged,'axis-tick-x-1-mark');
tick1Label = findTestById(docTagged,'axis-ticklabel-x-1');
assert(hasTestParentId(tick1Mark,'axis-tick-x-1') && hasTestParentId(tick1Label,'axis-tick-x-1'), ...
    'x-tick 1''s mark and label are not grouped together under their own per-tick group');
assert(hasTestAncestorId(tick1Mark,'axis-ticks-x') && hasTestAncestorId(tick1Mark,'axis-spine'), ...
    'x-tick 1 not nested under axis-ticks-x/axis-spine');

lastY = nYTicksExpected;
tickLastYMark = findTestById(docTagged, sprintf('axis-tick-y-%d-mark',lastY));
tickLastYLabel = findTestById(docTagged, sprintf('axis-ticklabel-y-%d',lastY));
assert(hasTestParentId(tickLastYMark, sprintf('axis-tick-y-%d',lastY)) && hasTestParentId(tickLastYLabel, sprintf('axis-tick-y-%d',lastY)), ...
    'last y-tick''s mark and label are not grouped together');

xlabelNode = findTestById(docTagged,'axis-xlabel');
assert(hasTestParentId(xlabelNode,'axis-labels') && hasTestAncestorId(xlabelNode,'axis-spine'), ...
    'axis-xlabel not nested under axis-labels/axis-spine');

dataNode = findTestById(docTagged,'dataseries-1-radius');
assert(hasTestAncestorId(dataNode,'dataseries'), 'data series line not nested under top-level dataseries group');

swatchNode = findTestById(docTagged,'legend-swatch-1');
labelNode = findTestById(docTagged,'legend-label-1');
assert(hasTestParentId(swatchNode,'legend-entry-1') && hasTestParentId(labelNode,'legend-entry-1'), ...
    'legend swatch/label not grouped together under one legend-entry');
assert(hasTestAncestorId(swatchNode,'legend'), 'legend entry not nested under top-level legend group');

boxBg = findTestById(docTagged,'legend-box-bg');
assert(hasTestParentId(boxBg,'legend-box'), 'legend-box-bg not nested under legend-box subgroup');

gridline1 = findTestById(docTagged,'gridline-1');
assert(hasTestParentId(gridline1,'gridlines') && hasTestAncestorId(gridline1,'furniture'), ...
    'gridline-1 not nested under gridlines/furniture');

fprintf('all nesting relationships verified\n');

% the legend-label text and the ylabel text must be DIFFERENT nodes despite identical content
% ("radius" in both, confirmed in this repo's own probe.svg) -- the collision is resolved correctly
% iff they're two distinct elements landing in two different groups (already implied by the nesting
% checks above, spelled out explicitly here too).
ylabelNode = findTestById(docTagged,'axis-ylabel');
assert(~ylabelNode.isSameNode(labelNode), 'ylabel and legend-label collapsed onto the same element -- collision not resolved');
fprintf('ylabel/legend-label "radius" collision correctly resolved to distinct elements\n');

% --- visual-regression check: grouping/tagging is DOM surgery (relocating real elements), unlike
% this file's first (attribute-only, never-move-anything) version -- rasterize both the un-grouped
% baked file and the newly-grouped tagged file and pixel-diff them. Requires rsvg-convert + compare
% (ImageMagick); skips (not fails) if either isn't on PATH, printing a warning rather than silently
% passing.
[hasRsvg,~] = system('which rsvg-convert');
[hasCompare,~] = system('which compare');
if hasRsvg == 0 && hasCompare == 0
    bakedPng = fullfile(outDir,'group_tag_baked.png');
    taggedPng = fullfile(outDir,'group_tag_tagged.png');
    diffPng = fullfile(outDir,'group_tag_diff.png');
    [s1,o1] = system(sprintf('rsvg-convert -o %s %s', bakedPng, bakedFile));
    [s2,o2] = system(sprintf('rsvg-convert -o %s %s', taggedPng, taggedFile));
    assert(s1==0 && s2==0, 'rsvg-convert failed: %s / %s', o1, o2);
    % `compare -metric AE -fuzz 1%` prints the count of pixels differing by MORE than 1% to stderr
    % (captured via 2>&1) -- exits nonzero whenever ANY pixel differs at all, so the exit code alone
    % can't distinguish "found real differences" from "tool itself failed"; parse the printed count.
    [~,cmpOut] = system(sprintf('compare -metric AE -fuzz 1%% %s %s %s 2>&1', bakedPng, taggedPng, diffPng));
    diffCount = str2double(strtrim(cmpOut));
    if isnan(diffCount); diffCount = Inf; end   % unparsable output -- treat as failure, don't silently pass
    fprintf('pixel-diff (baked vs. grouped/tagged rendering, 1%% fuzz): %g differing pixels\n', diffCount);
    assert(diffCount == 0, ['rendering changed after grouping/tagging: %g pixels differ by more than 1%% -- ' ...
        'DOM restructuring must be visually inert.'], diffCount);
else
    warning('test_group_tag:noRasterTools', 'rsvg-convert/compare not found on PATH -- skipping the visual-regression pixel-diff check.');
end

disp('GROUP/TAG VALIDATION: PASS');

function g = getTestRootGroup(doc)
docRoot = doc.getDocumentElement();
kids = docRoot.getChildNodes();
g = [];
for i = 0:kids.getLength()-1
    c = kids.item(i);
    if c.getNodeType() == c.ELEMENT_NODE && strcmp(char(c.getTagName()),'g'); g = c; end
end
end

function node = findTestById(doc, id)
all = doc.getElementsByTagName('*');
node = [];
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
assert(~isempty(node), 'findTestById: no element with id="%s" found', id);
end

function tf = hasTestParentId(node, parentId)
p = node.getParentNode();
tf = ~isempty(p) && p.getNodeType() == p.ELEMENT_NODE && strcmp(char(p.getAttribute('id')), parentId);
end

function tf = hasTestAncestorId(node, ancestorId)
n = node.getParentNode();
tf = false;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if strcmp(char(n.getAttribute('id')), ancestorId); tf = true; return; end
    n = n.getParentNode();
end
end
