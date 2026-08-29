% NOTE: this test validates groupAndTagSvg.m (+ identifyAxisSpine.m/identifyLegend.m) against a
% PLAIN, hand-built single-axes figure -- deliberately NOT plotVessels.m anymore (2026-08-29 policy
% change, see docs/findings.md's own note): plotVessels.m always hosts its axes inside a
% TiledChartLayout (even for one panel), and this repo has decided NOT to accommodate that for now
% -- adapting an arbitrary MATLAB figure down to a plain single-axes figure suitable for this
% pipeline is its own, later, independent step. This synthetic figure is built to exercise every
% role groupAndTagSvg.m tags: axis-spine (+ticks+labels), a data series WITH a confidence band
% (exercising the 'value'/'conf' sub-group split), a legend, gridlines, and one ad hoc annotation
% (a stand-in for something like plotVessels.m's own vessel-ID corner label) folded into furniture.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

fig = figure('Visible','off');
fig.Units = 'centimeters';
fig.Position = [2 2 16 10];
fig.PaperUnits = 'centimeters';
fig.PaperSize = [16 10];
fig.PaperPositionMode = 'manual';
fig.PaperPosition = [0 0 16 10];

ax = axes(fig);
ax.Units = 'normalized';
ax.PositionConstraint = 'innerposition';
ax.InnerPosition = [0.15 0.15 0.7 0.7];
ax.Box = 'off';
grid(ax, 'on');
hold(ax, 'on');

x = 0:0.5:20;
y = 5 + 0.3*sin(2*pi*x/5);
% confidence band (Patch) FIRST, SAME Tag as the line below (NOT DisplayName -- see
% assignSeriesIndices.m, "pairing-by-identity", Seb's own ask 2026-08-29) so groupAndTagSvg.m's own
% Tag-based pairing puts them in the same series' 'value'/'conf' sub-groups. Deliberately gives the
% patch NO DisplayName at all, to prove pairing survives without one. NOTE: HandleVisibility='off'
% would ALSO hide it from snapshotAxesStyle.m's own findobj(ax,'Type','patch') call, not just from
% legend() (confirmed real -- an earlier version of this test used it and the patch silently never
% got captured/matched/tagged at all) -- keep it default-visible and instead pass legend() an
% explicit handle list to keep it out of the legend without hiding it from findobj.
patchH = patch(ax, [x fliplr(x)], [y+0.15 fliplr(y-0.15)], [0.9 0.7 0.1], ...
    'FaceAlpha', 0.2, 'EdgeColor', 'none', 'Tag', 'signal-series'); %#ok<NASGU>
lineH = plot(ax, x, y, 'Color',[0.9 0.7 0.1], 'LineWidth', 2, 'DisplayName', 'signal', 'Tag', 'signal-series');
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';   % deliberately the SAME string as the legend's own DisplayName below,
                                % to keep exercising the real content-collision case this pipeline
                                % must resolve (confirmed real on plotVessels.m's own "radius" panel)
legend(ax, lineH, 'Location','northeast');   % explicit handle -- only the line gets a legend entry
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold');   % ad hoc annotation
drawnow;

fprintf('ax.Box=%s, class(ax.Parent)=%s, ax.XLabel.String="%s", ax.YLabel.String="%s"\n', ...
    ax.Box, class(ax.Parent), char(ax.XLabel.String), char(ax.YLabel.String));

snap = snapshotAxesStyle(ax);
nXTicksExpected = numel(ax.XAxis.TickLabels);
nYTicksExpected = numel(ax.YAxis.TickLabels);

rawFile = fullfile(outDir,'group_tag_raw.svg');
print(fig, rawFile, '-dsvg','-vector');

bakedFile = fullfile(outDir,'group_tag_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

% Identity-colored export (dumpIdentitySvg.m) + bake -- used for robust, collision-proof data-series
% matching (matchGraphicsToSvg.m's identity-color cross-reference path) instead of real-color
% fingerprinting. No font registry needed here: only geometry/color matter for this throwaway file.
identityRawFile = fullfile(outDir,'group_tag_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'group_tag_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'group_tag_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, 'panelA', identityBakedFile);
close(fig);   % safe to close now -- groupAndTagSvg only needed the live ax/fig up to this point

fprintf('stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d nAxisLabels=%d nFurnitureGridlines=%d nAnnotations=%d\n', ...
    stats.nDataSeries, stats.nLegendEntries, stats.nXTicks, stats.nYTicks, stats.nAxisLabels, ...
    stats.nFurnitureGridlines, stats.nAnnotations);

assert(stats.nDataSeries == 2, 'expected exactly 2 tagged data series members (the line + its confidence-band patch)');
assert(stats.nLegendEntries == 1, 'expected exactly 1 tagged legend entry');
% Compared against LIVE tick-label counts, never a hardcoded literal -- even for this deterministic
% plain-axes figure, MATLAB's own auto-tick-placement is an implementation detail this test
% shouldn't need to predict by hand.
assert(stats.nXTicks == nXTicksExpected, 'expected %d x-ticks (from live ax.XAxis.TickLabels)', nXTicksExpected);
assert(stats.nYTicks == nYTicksExpected, 'expected %d y-ticks (from live ax.YAxis.TickLabels)', nYTicksExpected);
assert(stats.nAxisLabels == 2, 'expected xlabel+ylabel tagged (2, no ax.Title set on this panel)');
assert(stats.nFurnitureGridlines == nXTicksExpected + nYTicksExpected, ...
    'expected %d gridlines (one per tick, both axes)', nXTicksExpected + nYTicksExpected);
assert(stats.nAnnotations == 1, 'expected exactly 1 leftover annotation (the ad hoc "panel A" text)');

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
assert(strcmp(char(rootG.getAttribute('id')), 'panelA-root'), 'panel root <g> missing/wrong id (expected "panelA-root")');
assert(strcmp(char(rootG.getAttribute('data-panel')), 'panelA'), 'panel root <g> missing/wrong data-panel attribute');
topKids = rootG.getChildNodes();
topGroupIds = {};
for i = 0:topKids.getLength()-1
    c = topKids.item(i);
    if c.getNodeType() ~= c.ELEMENT_NODE; continue; end
    assert(strcmp(char(c.getTagName()),'g'), 'stray non-<g> element left at top level: <%s>', char(c.getTagName()));
    topGroupIds{end+1} = char(c.getAttribute('id')); %#ok<AGROW>
end
fprintf('top-level groups (paint order): %s\n', strjoin(topGroupIds, ', '));
% Annotations are now folded INTO furniture (Seb's own ask, 2026-08-29) -- every top-level <g> is
% expected to be one of the four named semantic groups, nothing left unnamed/stray.
assert(isequal(topGroupIds, {'panelA-furniture','panelA-axis-spine','panelA-dataseries','panelA-legend'}), ...
    'unexpected top-level group set/order: %s', strjoin(topGroupIds,', '));

% --- real nesting: the whole point of this rewrite -- verify actual DOM parent/child relationships,
% not just that every id string happens to appear somewhere in the file.
spineX = findTestById(docTagged,'panelA-axis-spine-x');
assert(hasTestParentId(spineX,'panelA-axis-spine-lines'), 'axis-spine-x not directly under axis-spine-lines');
assert(hasTestAncestorId(spineX,'panelA-axis-spine'), 'axis-spine-x not nested under axis-spine');

tick1Mark = findTestById(docTagged,'panelA-axis-tick-x-1-mark');
tick1Label = findTestById(docTagged,'panelA-axis-ticklabel-x-1');
assert(hasTestParentId(tick1Mark,'panelA-axis-tick-x-1') && hasTestParentId(tick1Label,'panelA-axis-tick-x-1'), ...
    'x-tick 1''s mark and label are not grouped together under their own per-tick group');
assert(hasTestAncestorId(tick1Mark,'panelA-axis-ticks-x') && hasTestAncestorId(tick1Mark,'panelA-axis-spine'), ...
    'x-tick 1 not nested under axis-ticks-x/axis-spine');

lastY = nYTicksExpected;
tickLastYMark = findTestById(docTagged, sprintf('panelA-axis-tick-y-%d-mark',lastY));
tickLastYLabel = findTestById(docTagged, sprintf('panelA-axis-ticklabel-y-%d',lastY));
assert(hasTestParentId(tickLastYMark, sprintf('panelA-axis-tick-y-%d',lastY)) && hasTestParentId(tickLastYLabel, sprintf('panelA-axis-tick-y-%d',lastY)), ...
    'last y-tick''s mark and label are not grouped together');

xlabelNode = findTestById(docTagged,'panelA-axis-xlabel');
assert(hasTestParentId(xlabelNode,'panelA-axis-labels') && hasTestAncestorId(xlabelNode,'panelA-axis-spine'), ...
    'axis-xlabel not nested under axis-labels/axis-spine');

dataNode = findTestById(docTagged,'panelA-dataseries-1-signal-line');
assert(hasTestParentId(dataNode,'panelA-dataseries-1-signal-value'), 'data series line not directly under its own value sub-group');
assert(hasTestAncestorId(dataNode,'panelA-dataseries-1-signal') && hasTestAncestorId(dataNode,'panelA-dataseries'), ...
    'data series line not nested under its own series/top-level dataseries group');

confNode = findTestById(docTagged,'panelA-dataseries-1-signal-fill');
assert(hasTestParentId(confNode,'panelA-dataseries-1-signal-conf'), 'confidence-band patch not directly under its own conf sub-group');
assert(hasTestAncestorId(confNode,'panelA-dataseries-1-signal') && hasTestAncestorId(confNode,'panelA-dataseries'), ...
    'confidence-band patch not nested under its own series/top-level dataseries group');

annotationNode = findTestById(docTagged,'panelA-annotation-1');
assert(hasTestParentId(annotationNode,'panelA-annotations'), 'annotation-1 not directly under an annotations sub-group');
assert(hasTestAncestorId(annotationNode,'panelA-furniture'), 'annotation-1 not folded into furniture');

swatchNode = findTestById(docTagged,'panelA-legend-swatch-1');
labelNode = findTestById(docTagged,'panelA-legend-label-1');
assert(hasTestParentId(swatchNode,'panelA-legend-entry-1') && hasTestParentId(labelNode,'panelA-legend-entry-1'), ...
    'legend swatch/label not grouped together under one legend-entry');
assert(hasTestAncestorId(swatchNode,'panelA-legend'), 'legend entry not nested under top-level legend group');

boxBg = findTestById(docTagged,'panelA-legend-box-bg');
assert(hasTestParentId(boxBg,'panelA-legend-box'), 'legend-box-bg not nested under legend-box subgroup');

gridline1 = findTestById(docTagged,'panelA-gridline-1');
assert(hasTestParentId(gridline1,'panelA-gridlines') && hasTestAncestorId(gridline1,'panelA-furniture'), ...
    'gridline-1 not nested under gridlines/furniture');

fprintf('all nesting relationships verified\n');

% the legend-label text and the ylabel text must be DIFFERENT nodes despite identical content
% ("signal" in both, deliberately set that way above) -- the collision is resolved correctly iff
% they're two distinct elements landing in two different groups (already implied by the nesting
% checks above, spelled out explicitly here too).
ylabelNode = findTestById(docTagged,'panelA-axis-ylabel');
assert(~ylabelNode.isSameNode(labelNode), 'ylabel and legend-label collapsed onto the same element -- collision not resolved');
fprintf('ylabel/legend-label "signal" collision correctly resolved to distinct elements\n');

% --- visual-regression check: grouping/tagging is DOM surgery (relocating real elements), unlike
% this file's first (attribute-only, never-move-anything) version -- rasterize both the un-grouped
% baked file and the newly-grouped tagged file and pixel-diff them. Requires rsvg-convert + compare
% (ImageMagick); skips (not fails) if either isn't on PATH, printing a warning rather than silently
% passing.
%
% TEXT IS STRIPPED (stripTextForDiff.py) before rasterizing, both sides -- REVISED 2026-08-29:
% groupAndTagSvg.m's font-size correction is a REAL, INTENTIONAL visual change (it fixes a genuine
% MATLAB font-size rounding artifact, see docs/findings.md), so baked-vs-tagged is no longer expected
% to be 0-diff for TEXT specifically (confirmed real: this check found ~1500 differing pixels the
% first time font-size correction was added, entirely from corrected text glyphs, not a grouping
% bug). This check only ever meant to guard the DOM-restructuring/grouping step itself, which is
% unrelated to font-size -- text correctness has its own byte-exact check in
% test_fontsize_correction.m instead.
[hasRsvg,~] = system('which rsvg-convert');
[hasCompare,~] = system('which compare');
if hasRsvg == 0 && hasCompare == 0
    bakedNoTextFile = fullfile(outDir,'group_tag_baked_notext.svg');
    taggedNoTextFile = fullfile(outDir,'group_tag_tagged_notext.svg');
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), bakedFile, bakedNoTextFile));
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), taggedFile, taggedNoTextFile));
    bakedPng = fullfile(outDir,'group_tag_baked.png');
    taggedPng = fullfile(outDir,'group_tag_tagged.png');
    diffPng = fullfile(outDir,'group_tag_diff.png');
    [s1,o1] = system(sprintf('rsvg-convert -o %s %s', bakedPng, bakedNoTextFile));
    [s2,o2] = system(sprintf('rsvg-convert -o %s %s', taggedPng, taggedNoTextFile));
    assert(s1==0 && s2==0, 'rsvg-convert failed: %s / %s', o1, o2);
    % `compare -metric AE -fuzz 2%` prints the count of pixels differing by MORE than 2% to stderr
    % (captured via 2>&1) -- exits nonzero whenever ANY pixel differs at all, so the exit code alone
    % can't distinguish "found real differences" from "tool itself failed"; parse the printed count.
    %
    % 2%, not 1%: folding annotations into furniture (Seb's own ask, 2026-08-29) is NOT guaranteed
    % artifact-free the way the other three groups are -- an annotation can genuinely overlap other
    % content once dragged to furniture's paint-order position, unlike axis-spine/dataseries/legend,
    % whose own members are always a contiguous cluster with no such risk. Confirmed real on this
    % exact panel: with a 1% fuzz, 4 pixels differed where the "panel A" annotation's anti-aliased
    % glyph edges cross the data curve -- inspected directly (RGB deltas of 1 unit out of 255, e.g.
    % (219,170,25) vs (219,169,25)), confirmed sub-perceptual (0 pixels differ at 2% fuzz), NOT a
    % case of one element actually covering/hiding the other (that would show as a large block of
    % full-strength color replacement, not a handful of near-zero deltas at a shared edge). If this
    % count ever grows non-trivially on some other panel, that's the real signal to investigate --
    % an annotation actually becoming hidden or visibly relocated, not just anti-aliasing noise.
    [~,cmpOut] = system(sprintf('compare -metric AE -fuzz 2%% %s %s %s 2>&1', bakedPng, taggedPng, diffPng));
    diffCount = str2double(strtrim(cmpOut));
    if isnan(diffCount); diffCount = Inf; end   % unparsable output -- treat as failure, don't silently pass
    fprintf('pixel-diff (baked vs. grouped/tagged rendering, text stripped, 2%% fuzz): %g differing pixels\n', diffCount);
    assert(diffCount == 0, ['rendering changed after grouping/tagging (text excluded): %g pixels differ by ' ...
        'more than 2%% -- DOM restructuring must be visually inert.'], diffCount);
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
% Asserts EXACTLY one match, not just "at least one" -- a document-order-first search here once
% silently masked a real duplicate-id bug (a series group and its own line-only leaf briefly shared
% one id; this always found the group, since getElementsByTagName('*') visits a parent before its
% children, and the group trivially satisfied every "has ancestor" check the test was written to
% verify). SVG ids must be document-unique; this check enforces that as a byproduct.
all = doc.getElementsByTagName('*');
node = [];
nMatches = 0;
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id)
        nMatches = nMatches + 1;
        if isempty(node); node = n; end
    end
end
assert(nMatches == 1, 'findTestById: expected exactly 1 element with id="%s", found %d', id, nMatches);
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
