% NOTE: validates colorbar support (2026-08-29) -- identifyColorbar.m/groupAndTagSvg.m's own
% "colorbar" top-level role (box, outline, per-tick mark+label pairs, own label), the copy-step's
% Colorbar decoupling/repositioning (runPillar1.m), and the pillar-2 round-trip (syncPanel.m)
% recovering a resize/aspect-ratio change and repositioning a decoupled colorbar to match. Uses only
% Line/Patch dataseries (NOT imagesc/image) -- image-type dataseries are an explicitly separate,
% not-yet-built round (docs/findings.md), and using imagesc here would immediately collide with
% this test's own colorbar identification (a data image renders via the exact same
% pattern-filled-rect mechanism the colorbar's own gradient does -- confirmed real while building
% this, see docs/findings.md's own note on this).
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

function fig = buildColorbarPanel()
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
ax.InnerPosition = [0.15 0.15 0.55 0.7];
hold(ax, 'on');

x = 0:0.5:20;
y = 5 + 0.3*sin(2*pi*x/5);
patch(ax, [x fliplr(x)], [y+0.15 fliplr(y-0.15)], [0.9 0.7 0.1], ...
    'FaceAlpha', 0.2, 'EdgeColor', 'none', 'Tag', 'signal-series');
lineH = plot(ax, x, y, 'Color',[0.9 0.7 0.1], 'LineWidth', 2, 'DisplayName', 'signal', 'Tag', 'signal-series');
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';
legend(ax, lineH, 'Location','northeast');
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold');
% colorbar attached regardless of what's plotted -- a colorbar just reflects the axes' current
% CLim/Colormap, no image/surface required (deliberately avoiding imagesc, see this file's header)
caxis(ax, [0 10]);
cb = colorbar(ax);
cb.Label.String = 'intensity';
ax.XAxis.FontSize = 9; ax.YAxis.FontSize = 11;
ax.XLabel.FontSize = 14; ax.YLabel.FontSize = 16;
cb.FontSize = 10; cb.Label.FontSize = 13;
drawnow;
end

% --- direct groupAndTagSvg.m validation (manual step-by-step pipeline, same discipline as
% test_group_tag.m) ---
fig = buildColorbarPanel();
ax = findobj(fig, 'Type', 'axes');
cbLive = ax.Colorbar;
nTicksExpected = numel(cbLive.Ticks);
cbFontSizeExpected = cbLive.FontSize;
cbLabelFontSizeExpected = cbLive.Label.FontSize;
snap = snapshotAxesStyle(ax);

rawFile = fullfile(outDir,'colorbar_raw.svg');
print(fig, rawFile, '-dsvg','-vector');
bakedFile = fullfile(outDir,'colorbar_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

identityRawFile = fullfile(outDir,'colorbar_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'colorbar_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'colorbar_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, 'panelCB', identityBakedFile);
close(fig);

fprintf('stats: nColorbarTicks=%d (expect %d) nDataSeries=%d nLegendEntries=%d nAnnotations=%d\n', ...
    stats.nColorbarTicks, nTicksExpected, stats.nDataSeries, stats.nLegendEntries, stats.nAnnotations);
assert(stats.nColorbarTicks == nTicksExpected, 'expected %d colorbar ticks', nTicksExpected);
assert(stats.nDataSeries == 2, 'expected 2 dataseries leaves (line+patch)');
assert(stats.nLegendEntries == 1, 'expected 1 legend entry');
assert(stats.nAnnotations == 1, 'expected exactly 1 annotation (the colorbar''s own pattern-embedded image must NOT be caught here -- see this file''s own header)');

docTagged = xmlread(taggedFile);
assert(~isempty(findTestById(docTagged,'panelCB-colorbar')), 'missing top-level colorbar group');
assert(~isempty(findTestById(docTagged,'panelCB-colorbar-box')), 'missing colorbar gradient box');
assert(~isempty(findTestById(docTagged,'panelCB-colorbar-label')), 'missing colorbar own label');
for ti = 1:nTicksExpected
    assert(~isempty(findTestById(docTagged, sprintf('panelCB-colorbar-tick-%d-mark',ti))), 'missing colorbar tick mark %d', ti);
    assert(~isempty(findTestById(docTagged, sprintf('panelCB-colorbar-ticklabel-%d',ti))), 'missing colorbar tick label %d', ti);
end
fprintf('colorbar box/outline/ticks/tick-labels/label all tagged\n');

% Font-size correction on the two new roles (direct property read, same discipline as every other
% role -- see groupAndTagSvg.m's own setFontSizeFromLive).
tickLabelNode = findTestById(docTagged, 'panelCB-colorbar-ticklabel-1');
labelNode = findTestById(docTagged, 'panelCB-colorbar-label');
assert(str2double(char(tickLabelNode.getAttribute('font-size'))) == cbFontSizeExpected, ...
    'colorbar tick label font-size not corrected to live cb.FontSize');
assert(str2double(char(labelNode.getAttribute('font-size'))) == cbLabelFontSizeExpected, ...
    'colorbar label font-size not corrected to live cb.Label.FontSize');
fprintf('colorbar font-size correction (tick labels + own label): PASS\n');

% No duplicate ids.
txt = fileread(taggedFile);
ids = regexp(txt, 'id="([^"]*)"', 'tokens');
ids = cellfun(@(c) c{1}, ids, 'UniformOutput', false);
assert(numel(ids) == numel(unique(ids)), 'duplicate id found in colorbar tagged output');
fprintf('no duplicate ids: PASS\n');

% Visual-regression check, same discipline as test_group_tag.m/test_box_on.m -- text stripped
% before rasterizing. A small, non-zero, precisely-diagnosed residual is EXPECTED here (NOT a bug):
% MATLAB draws a colorbar's own box-edge/ruler line duplicated several times, interleaved with the
% gradient box's own opaque fill; relocating every duplicate into one semantic group (rather than
% deleting the "redundant" earlier ones, which was tried and made this WORSE -- a stroke's own
% half-width bleeds slightly outside the gradient rect's exact edge, so an earlier duplicate is not
% actually fully hidden) reproduces the closest achievable match, a residual confined to sub-pixel
% antialiasing blending exactly along the colorbar's own edges (see docs/findings.md). Threshold set
% well above the observed ~1500/861696 (~0.17%) but far below any structural regression.
[hasRsvg,~] = system('which rsvg-convert');
[hasCompare,~] = system('which compare');
if hasRsvg == 0 && hasCompare == 0
    bakedNoTextFile = fullfile(outDir,'colorbar_baked_notext.svg');
    taggedNoTextFile = fullfile(outDir,'colorbar_tagged_notext.svg');
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), bakedFile, bakedNoTextFile));
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), taggedFile, taggedNoTextFile));
    bakedPng = fullfile(outDir,'colorbar_baked.png');
    taggedPng = fullfile(outDir,'colorbar_tagged.png');
    diffPng = fullfile(outDir,'colorbar_diff.png');
    system(sprintf('rsvg-convert -o %s %s', bakedPng, bakedNoTextFile));
    system(sprintf('rsvg-convert -o %s %s', taggedPng, taggedNoTextFile));
    [~,cmpOut] = system(sprintf('compare -metric AE -fuzz 2%% %s %s %s 2>&1', bakedPng, taggedPng, diffPng));
    diffCount = str2double(strtrim(cmpOut));
    if isnan(diffCount); diffCount = Inf; end
    fprintf('pixel-diff (baked vs. grouped/tagged rendering, text stripped, 2%% fuzz): %g differing pixels (known-residual budget: 5000)\n', diffCount);
    assert(diffCount < 5000, 'colorbar rendering changed unexpectedly: %g pixels differ (known-residual budget is 5000)', diffCount);
else
    warning('test_colorbar:noRasterTools', 'rsvg-convert/compare not found on PATH -- skipping the visual-regression pixel-diff check.');
end

% --- end-to-end through runPillar1.m: confirm the copy step's colorbar decoupling doesn't itself
% introduce any FURTHER difference beyond the manual pipeline above (same style comparison as
% test_run_pillar1.m's own byte-identical check, but text-stripped-pixel-diff since font-size
% correction + the known colorbar residual above both make byte-identity the wrong bar here). ---
fig2 = buildColorbarPanel();
ax2 = findobj(fig2, 'Type', 'axes');
result = runPillar1(ax2, outDir, 'figCB', 'panelCB', struct('keepIntermediates', true));
close(fig2);
fprintf('runPillar1 (colorbar-equipped panel): nColorbarTicks=%d\n', result.stats.nColorbarTicks);
% NOTE: cb.TicksMode='auto' recomputes a DIFFERENT "nice" tick count on the much larger US-Letter
% copy-step canvas than on this test's own small (16x10cm) source figure -- expected, not a bug (a
% bigger rendered colorbar comfortably fits more tick labels), so no exact count is asserted here --
% just that identification/tagging succeeded (a mismatch would have thrown inside groupAndTagSvg.m
% already, e.g. identifyColorbar:tickCountMismatch).
assert(result.stats.nColorbarTicks > 0, 'runPillar1 found no colorbar ticks at all');
txt2 = fileread(result.taggedFile);
ids2 = regexp(txt2, 'id="([^"]*)"', 'tokens');
ids2 = cellfun(@(c) c{1}, ids2, 'UniformOutput', false);
assert(numel(ids2) == numel(unique(ids2)), 'duplicate id found in runPillar1 colorbar output');
fprintf('runPillar1 end-to-end (colorbar-equipped panel): PASS\n');

% --- syncPanel.m round-trip: resize (including an aspect-ratio change) a colorbar-equipped panel
% via a simulated composed-SVG edit, confirm the colorbar repositions to track the new box --
% focused on the default 'eastoutside' location, per this round's own explicit scope. ---
syncOutDir = fullfile(outDir, 'colorbar_sync');
if exist(syncOutDir,'dir'); rmdir(syncOutDir,'s'); end
mkdir(syncOutDir);

fig3 = buildColorbarPanel();
ax3 = findobj(fig3, 'Type', 'axes');
r1 = syncPanel(ax3, syncOutDir, 'figS', 'panelS');
close(fig3);

doc = xmlread(r1.composedFile);
docRoot = doc.getDocumentElement();
els = docRoot.getElementsByTagName('*');
panelNode = [];
for k = 0:els.getLength()-1
    n = els.item(k);
    if strcmp(char(n.getAttribute('id')), 'panelS-root'); panelNode = n; end
end
assert(~isempty(panelNode), 'syncPanel did not place panelS-root into the composed file');
wrapper = doc.createElement('g');
wrapper.setAttribute('transform', 'translate(50,80) scale(1.4,0.8)');
parentNode = panelNode.getParentNode();
parentNode.removeChild(panelNode);
wrapper.appendChild(panelNode);
parentNode.appendChild(wrapper);
xmlwrite(r1.composedFile, doc);

fig4 = buildColorbarPanel();
ax4 = findobj(fig4, 'Type', 'axes');
r2 = syncPanel(ax4, syncOutDir, 'figS', 'panelS');
close(fig4);
fprintf('syncPanel innerPosition: first=%s -> after resize=%s\n', mat2str(r1.innerPosition,4), mat2str(r2.innerPosition,4));
assert(~isequal(r1.innerPosition, r2.innerPosition), 'resize was not recovered into a new InnerPosition');

docFinal = xmlread(r2.taggedFile);
spineXNode = findTestById(docFinal, 'panelS-axis-spine-x');
spineYNode = findTestById(docFinal, 'panelS-axis-spine-y');
cbBoxNode = findTestById(docFinal, 'panelS-colorbar-box');
assert(~isempty(cbBoxNode), 'colorbar box missing after resync');

spineXPts = sscanf(strrep(char(spineXNode.getAttribute('points')),',',' '), '%f');
spineXPts = reshape(spineXPts, 2, [])';
spineYPts = sscanf(strrep(char(spineYNode.getAttribute('points')),',',' '), '%f');
spineYPts = reshape(spineYPts, 2, [])';
boxRight = max(spineXPts(:,1));
boxYRange = [min(spineYPts(:,2)) max(spineYPts(:,2))];

d = char(cbBoxNode.getAttribute('d'));
nums = str2double(regexp(d, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match'));
cbPts = reshape(nums, 2, [])';
cbXRange = [min(cbPts(:,1)) max(cbPts(:,1))];
cbYRange = [min(cbPts(:,2)) max(cbPts(:,2))];

fprintf('box right edge=%.2f, colorbar x-range=[%.2f %.2f]\n', boxRight, cbXRange(1), cbXRange(2));
assert(cbXRange(1) > boxRight, 'colorbar did not stay to the right of the resized box');
assert(abs(cbYRange(1)-boxYRange(1)) < 2 && abs(cbYRange(2)-boxYRange(2)) < 2, ...
    'colorbar did not track the resized box''s new height (expected [%.2f %.2f], got [%.2f %.2f])', ...
    boxYRange(1), boxYRange(2), cbYRange(1), cbYRange(2));
fprintf('colorbar correctly repositioned to track the resized (aspect-ratio-changed) box: PASS\n');

disp('COLORBAR SUPPORT VALIDATION: PASS');

function node = findTestById(doc, id)
all = doc.getElementsByTagName('*');
node = [];
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
end
