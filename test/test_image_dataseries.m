% NOTE: validates image-type dataseries support (2026-08-30) -- snapshotAxesStyle.m/
% matchGraphicsToSvg.m/groupAndTagSvg.m's own "dataseries-image" leaf role for a heatmap/`image`/
% `imagesc` dataseries, matched by direct geometric correlation (XData/YData -> expected canvas box)
% rather than any color-identity trick (a raster image's "color" is baked inside a compressed PNG
% blob, not a plain SVG attribute string -- see snapshotAxesStyle.m's own header). No legend is used
% here -- confirmed empirically that Image objects never produce real legend entries (legend(ax)
% returns a non-empty handle but an empty String/PlotChildren), so there's no image-to-legend
% matching path to validate.
%
% Explicit XTick/YTick values are used throughout to sidestep an unrelated, pre-existing gap this
% round exposed while building: with YDir='reverse' (which imagesc sets), a Y-tick label can
% coincidentally land inside matchTickLabels' own X-tick-label position window while sharing numeric
% CONTENT with a real X-tick value (e.g. both showing "50") -- confirmed real, not fixed here (out of
% scope for image-dataseries support specifically), see docs/findings.md.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

function fig = buildImagePanel(tag, xTick, yTick)
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
ax.InnerPosition = [0.15 0.15 0.6 0.7];
ax.Box = 'off';

[X,Y] = meshgrid(1:50,1:50);
im = imagesc(ax, X+Y);
im.Tag = tag;
ax.XTick = xTick; ax.YTick = yTick;
ax.XLabel.String = 'x'; ax.YLabel.String = 'y';
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold');
drawnow;
end

% --- Case 1: single image dataseries, direct groupAndTagSvg.m validation (manual step-by-step
% pipeline, same discipline as test_group_tag.m) ---
fig = buildImagePanel('heatmap-series', [10 20 30 40 50], [3 13 23 33 43]);
ax = findobj(fig, 'Type', 'axes');
imLive = findobj(ax, 'Type', 'image');
assert(~isprop(imLive,'DisplayName'), 'sanity check: Image objects are NOT expected to have a DisplayName property');
snap = snapshotAxesStyle(ax);

rawFile = fullfile(outDir,'imgds_raw.svg');
print(fig, rawFile, '-dsvg','-vector');
bakedFile = fullfile(outDir,'imgds_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

identityRawFile = fullfile(outDir,'imgds_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'imgds_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'imgds_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, 'panelA', identityBakedFile);
close(fig);

fprintf('Case 1: stats.nDataSeries=%d (expect 1) nAnnotations=%d (expect 1)\n', stats.nDataSeries, stats.nAnnotations);
assert(stats.nDataSeries == 1, 'expected exactly 1 dataseries leaf (the image)');
assert(stats.nAnnotations == 1, 'expected exactly 1 annotation ("panel A") -- the axes-background rect must NOT fall through here (see docs/findings.md)');

docTagged = xmlread(taggedFile);
% id-slug falls back to "series<n>" here -- an Image object has no DisplayName to slug from (only
% Tag, which is not what the slug is derived from -- see groupAndTagSvg.m's own seriesDisplayNameOf).
assert(~isempty(findTestById(docTagged, 'panelA-dataseries-1-series1-image')), 'missing tagged image dataseries leaf');
assert(~isempty(findTestById(docTagged, 'panelA-axes-background')), 'axes-background must still be correctly identified when an image spans the full axes extent');
assert(~isempty(findTestById(docTagged, 'panelA-figure-background')), 'missing figure-background');
fprintf('Case 1: image dataseries correctly tagged, axes/figure background correctly identified: PASS\n');

txt = fileread(taggedFile);
ids = regexp(txt, 'id="([^"]*)"', 'tokens');
ids = cellfun(@(c) c{1}, ids, 'UniformOutput', false);
assert(numel(ids) == numel(unique(ids)), 'duplicate id found in image-dataseries tagged output');
fprintf('Case 1: no duplicate ids: PASS\n');

% Visual-regression check, same discipline as test_group_tag.m/test_box_on.m -- text stripped before
% rasterizing.
[hasRsvg,~] = system('which rsvg-convert');
[hasCompare,~] = system('which compare');
if hasRsvg == 0 && hasCompare == 0
    bakedNoTextFile = fullfile(outDir,'imgds_baked_notext.svg');
    taggedNoTextFile = fullfile(outDir,'imgds_tagged_notext.svg');
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), bakedFile, bakedNoTextFile));
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), taggedFile, taggedNoTextFile));
    bakedPng = fullfile(outDir,'imgds_baked.png');
    taggedPng = fullfile(outDir,'imgds_tagged.png');
    diffPng = fullfile(outDir,'imgds_diff.png');
    system(sprintf('rsvg-convert -o %s %s', bakedPng, bakedNoTextFile));
    system(sprintf('rsvg-convert -o %s %s', taggedPng, taggedNoTextFile));
    [~,cmpOut] = system(sprintf('compare -metric AE -fuzz 2%% %s %s %s 2>&1', bakedPng, taggedPng, diffPng));
    diffCount = str2double(strtrim(cmpOut));
    if isnan(diffCount); diffCount = Inf; end
    fprintf('Case 1: pixel-diff (baked vs. grouped/tagged rendering, text stripped, 2%% fuzz): %g differing pixels\n', diffCount);
    assert(diffCount == 0, 'image-dataseries rendering changed unexpectedly: %g pixels differ', diffCount);
else
    warning('test_image_dataseries:noRasterTools', 'rsvg-convert/compare not found on PATH -- skipping the visual-regression pixel-diff check.');
end

% --- Case 2: TWO image dataseries in one axes, distinct XData/YData so their expected bboxes
% differ -- confirm both match to their own distinct series, no cross-assignment. ---
fig2 = figure('Visible','off');
fig2.Units = 'centimeters'; fig2.Position = [2 2 16 10];
fig2.PaperUnits = 'centimeters'; fig2.PaperSize = [16 10]; fig2.PaperPositionMode = 'manual'; fig2.PaperPosition = [0 0 16 10];
ax2 = axes(fig2);
ax2.Units = 'normalized'; ax2.PositionConstraint = 'innerposition';
ax2.InnerPosition = [0.1 0.1 0.8 0.8];
ax2.Box = 'off';
hold(ax2, 'on');
[Xa,Ya] = meshgrid(1:20,1:20);
imA = image(ax2, [1 20], [1 20], Xa+Ya, 'CDataMapping','scaled');
imA.Tag = 'heatmap-A';
[Xb,Yb] = meshgrid(1:20,1:20);
imB = image(ax2, [30 49], [1 20], Xb+Yb, 'CDataMapping','scaled');
imB.Tag = 'heatmap-B';
ax2.XLim = [0.5 49.5]; ax2.YLim = [0.5 20.5];
ax2.XTick = [10 39]; ax2.YTick = [5 15];
drawnow;

snap2 = snapshotAxesStyle(ax2);
assert(numel(snap2) == 2, 'expected 2 snapshotted Image objects');
rawFile2 = fullfile(outDir,'imgds2_raw.svg');
print(fig2, rawFile2, '-dsvg','-vector');
bakedFile2 = fullfile(outDir,'imgds2_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile2, bakedFile2));
identityRawFile2 = fullfile(outDir,'imgds2_identity_raw.svg');
dumpIdentitySvg(fig2, snap2, identityRawFile2);
identityBakedFile2 = fullfile(outDir,'imgds2_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile2, identityBakedFile2));
taggedFile2 = fullfile(outDir,'imgds2_tagged.svg');
stats2 = groupAndTagSvg(ax2, snap2, bakedFile2, taggedFile2, 'panelB', identityBakedFile2);
close(fig2);

fprintf('Case 2: stats.nDataSeries=%d (expect 2)\n', stats2.nDataSeries);
assert(stats2.nDataSeries == 2, 'expected 2 dataseries leaves (two images)');
docTagged2 = xmlread(taggedFile2);
nodeA = findTestById(docTagged2, 'panelB-dataseries-1-series1-image');
nodeB = findTestById(docTagged2, 'panelB-dataseries-2-series2-image');
assert(~isempty(nodeA), 'missing tagged image A');
assert(~isempty(nodeB), 'missing tagged image B');
assert(~nodeA.isSameNode(nodeB), 'the two images were matched to the SAME svg element -- cross-assignment bug');
dA = char(nodeA.getAttribute('d')); dB = char(nodeB.getAttribute('d'));
numsA = str2double(regexp(dA, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match'));
numsB = str2double(regexp(dB, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match'));
ptsA = reshape(numsA,2,[])'; ptsB = reshape(numsB,2,[])';
% findobj (snapshotAxesStyle.m) does not guarantee creation order, so "series1" may correspond to
% either image -- just confirm the two matched boxes are disjoint along x (distinct XData ranges),
% regardless of which series-index landed on which.
disjoint = (max(ptsA(:,1)) < min(ptsB(:,1))) || (max(ptsB(:,1)) < min(ptsA(:,1)));
assert(disjoint, 'the two images'' matched boxes overlap along x -- expected disjoint XData ranges to stay distinguishable');
fprintf('Case 2: two images correctly matched to distinct series, no cross-assignment: PASS\n');

txt2 = fileread(taggedFile2);
ids2 = regexp(txt2, 'id="([^"]*)"', 'tokens');
ids2 = cellfun(@(c) c{1}, ids2, 'UniformOutput', false);
assert(numel(ids2) == numel(unique(ids2)), 'duplicate id found in two-image tagged output');
fprintf('Case 2: no duplicate ids: PASS\n');

% --- Case 3: an image dataseries AND a colorbar together in one axes -- confirm the colorbar's own
% gradient pattern is correctly excluded from image-matching candidacy and both get tagged correctly
% with no cross-contamination (this exact combination was avoided in test_colorbar.m's own fixture
% specifically because it was found to collide -- see that file's own header). ---
fig3 = buildImagePanel('heatmap-cb-series', [10 20 30 40 50], [3 13 23 33 43]);
ax3 = findobj(fig3, 'Type', 'axes');
ax3.InnerPosition = [0.15 0.15 0.55 0.7];   % narrower, to leave room for the colorbar
cb = colorbar(ax3);
cb.Label.String = 'intensity';
drawnow;

snap3 = snapshotAxesStyle(ax3);
rawFile3 = fullfile(outDir,'imgds3_raw.svg');
print(fig3, rawFile3, '-dsvg','-vector');
bakedFile3 = fullfile(outDir,'imgds3_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile3, bakedFile3));
identityRawFile3 = fullfile(outDir,'imgds3_identity_raw.svg');
dumpIdentitySvg(fig3, snap3, identityRawFile3);
identityBakedFile3 = fullfile(outDir,'imgds3_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile3, identityBakedFile3));
taggedFile3 = fullfile(outDir,'imgds3_tagged.svg');
stats3 = groupAndTagSvg(ax3, snap3, bakedFile3, taggedFile3, 'panelC', identityBakedFile3);
close(fig3);

fprintf('Case 3: stats.nDataSeries=%d (expect 1) nColorbarTicks=%d (expect >0)\n', stats3.nDataSeries, stats3.nColorbarTicks);
assert(stats3.nDataSeries == 1, 'expected exactly 1 dataseries leaf (the image) alongside the colorbar');
assert(stats3.nColorbarTicks > 0, 'colorbar ticks not identified when an image dataseries is also present');
docTagged3 = xmlread(taggedFile3);
imgNode3 = findTestById(docTagged3, 'panelC-dataseries-1-series1-image');
cbBoxNode3 = findTestById(docTagged3, 'panelC-colorbar-box');
assert(~isempty(imgNode3), 'missing tagged image dataseries leaf alongside colorbar');
assert(~isempty(cbBoxNode3), 'missing colorbar box alongside image dataseries');
assert(~imgNode3.isSameNode(cbBoxNode3), 'the image dataseries and the colorbar gradient box were matched to the SAME svg element -- cross-contamination bug');
fprintf('Case 3: image dataseries and colorbar coexist with no cross-contamination: PASS\n');

txt3 = fileread(taggedFile3);
ids3 = regexp(txt3, 'id="([^"]*)"', 'tokens');
ids3 = cellfun(@(c) c{1}, ids3, 'UniformOutput', false);
assert(numel(ids3) == numel(unique(ids3)), 'duplicate id found in image+colorbar tagged output');
fprintf('Case 3: no duplicate ids: PASS\n');

disp('IMAGE DATASERIES VALIDATION: PASS');

function node = findTestById(doc, id)
all = doc.getElementsByTagName('*');
node = [];
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
end
