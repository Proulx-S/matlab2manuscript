% NOTE: validates identifyAxisSpine.m/groupAndTagSvg.m's ax.Box='on' support (2026-08-29, previously
% errored loudly rather than being mishandled). Confirmed empirically before building this: Box='on'
% draws a SECOND long spine line on the opposite side of each ruler (top mirrors bottom, right
% mirrors left), bundled with a full set of mirrored tick marks in the SAME <g> as the primary
% side's -- but MATLAB never draws tick LABELS on the mirror side, only marks.
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
ax.Box = 'on';   % the whole point of this test
hold(ax, 'on');

x = 0:0.5:20;
y = 5 + 0.3*sin(2*pi*x/5);
lineH = plot(ax, x, y, 'Color',[0.9 0.7 0.1], 'LineWidth', 2, 'DisplayName', 'signal');
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';
legend(ax, lineH, 'Location','northeast');
drawnow;
nXTicksExpected = numel(ax.XAxis.TickLabels);
nYTicksExpected = numel(ax.YAxis.TickLabels);

snap = snapshotAxesStyle(ax);

rawFile = fullfile(outDir,'box_on_raw.svg');
print(fig, rawFile, '-dsvg','-vector');
bakedFile = fullfile(outDir,'box_on_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

identityRawFile = fullfile(outDir,'box_on_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'box_on_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'box_on_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, identityBakedFile);
close(fig);

fprintf('stats: nXTicks=%d nYTicks=%d\n', stats.nXTicks, stats.nYTicks);
assert(stats.nXTicks == nXTicksExpected, 'expected %d primary x-ticks', nXTicksExpected);
assert(stats.nYTicks == nYTicksExpected, 'expected %d primary y-ticks', nYTicksExpected);

docTagged = xmlread(taggedFile);
assert(~isempty(findTestById(docTagged,'axis-spine-x')), 'missing primary x spine');
assert(~isempty(findTestById(docTagged,'axis-spine-y')), 'missing primary y spine');
assert(~isempty(findTestById(docTagged,'axis-spine-x-mirror')), 'missing mirror x spine (Box=on)');
assert(~isempty(findTestById(docTagged,'axis-spine-y-mirror')), 'missing mirror y spine (Box=on)');
fprintf('primary + mirror spine lines both tagged\n');

nMirrorXTicks = countIdsWithPrefix(docTagged, 'axis-tick-x-mirror-');
nMirrorYTicks = countIdsWithPrefix(docTagged, 'axis-tick-y-mirror-');
fprintf('mirror x-ticks tagged: %d (expect %d), mirror y-ticks tagged: %d (expect %d)\n', ...
    nMirrorXTicks, nXTicksExpected, nMirrorYTicks, nYTicksExpected);
assert(nMirrorXTicks == nXTicksExpected, 'expected %d mirror x-ticks tagged', nXTicksExpected);
assert(nMirrorYTicks == nYTicksExpected, 'expected %d mirror y-ticks tagged', nYTicksExpected);

% Mirror ticks must NOT have a tick-label counterpart -- MATLAB never draws one (confirmed real).
mirrorTickLabelCount = countIdsWithPrefix(docTagged, 'axis-ticklabel-x-mirror-') + countIdsWithPrefix(docTagged, 'axis-ticklabel-y-mirror-');
assert(mirrorTickLabelCount == 0, 'unexpectedly found a mirror tick LABEL -- MATLAB should never draw one');

% Element-count invariant + no duplicate ids, same discipline as test_group_tag.m.
docBaked = xmlread(bakedFile);
for tag = {'polyline','path','text','circle'}
    nBaked = docBaked.getElementsByTagName(tag{1}).getLength();
    nTagged = docTagged.getElementsByTagName(tag{1}).getLength();
    assert(nBaked == nTagged, 'element count changed for <%s>: baked=%d tagged=%d', tag{1}, nBaked, nTagged);
end
txt = fileread(taggedFile);
ids = regexp(txt, 'id="([^"]*)"', 'tokens');
ids = cellfun(@(c) c{1}, ids, 'UniformOutput', false);
assert(numel(ids) == numel(unique(ids)), 'duplicate id found in Box=on tagged output');
fprintf('element-count invariant + no duplicate ids: PASS\n');

% Visual-regression check, same discipline as test_group_tag.m -- text stripped before rasterizing
% (stripTextForDiff.py): font-size correction is a real, intentional visual change, unrelated to
% grouping, so baked-vs-tagged is no longer 0-diff for text specifically (see that file's own note).
[hasRsvg,~] = system('which rsvg-convert');
[hasCompare,~] = system('which compare');
if hasRsvg == 0 && hasCompare == 0
    bakedNoTextFile = fullfile(outDir,'box_on_baked_notext.svg');
    taggedNoTextFile = fullfile(outDir,'box_on_tagged_notext.svg');
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), bakedFile, bakedNoTextFile));
    system(sprintf('python3 %s %s %s', fullfile(repoDir,'test','stripTextForDiff.py'), taggedFile, taggedNoTextFile));
    bakedPng = fullfile(outDir,'box_on_baked.png');
    taggedPng = fullfile(outDir,'box_on_tagged.png');
    diffPng = fullfile(outDir,'box_on_diff.png');
    system(sprintf('rsvg-convert -o %s %s', bakedPng, bakedNoTextFile));
    system(sprintf('rsvg-convert -o %s %s', taggedPng, taggedNoTextFile));
    [~,cmpOut] = system(sprintf('compare -metric AE -fuzz 2%% %s %s %s 2>&1', bakedPng, taggedPng, diffPng));
    diffCount = str2double(strtrim(cmpOut));
    if isnan(diffCount); diffCount = Inf; end
    fprintf('pixel-diff (baked vs. grouped/tagged rendering, text stripped, 2%% fuzz): %g differing pixels\n', diffCount);
    assert(diffCount == 0, 'rendering changed after grouping/tagging Box=on panel: %g pixels differ', diffCount);
else
    warning('test_box_on:noRasterTools', 'rsvg-convert/compare not found on PATH -- skipping the visual-regression pixel-diff check.');
end

disp('BOX=ON VALIDATION: PASS');

function node = findTestById(doc, id)
all = doc.getElementsByTagName('*');
node = [];
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
end

function n = countIdsWithPrefix(doc, idPrefix)
all = doc.getElementsByTagName('*');
n = 0;
for k = 0:all.getLength()-1
    id = char(all.item(k).getAttribute('id'));
    if startsWith(id, idPrefix); n = n + 1; end
end
end
