% NOTE: validates runPillar1.m (2026-08-29) -- the single-function wrapper around this repo's own
% pillar-1 pipeline (bake -> identity export/bake -> group/tag). Checks: (1) its output is IDENTICAL
% to the manual step-by-step pipeline test_group_tag.m/examples/makeExamplePanelA.m already validate
% by hand; (2) intermediate files are deleted by default; (3) opts.keepIntermediates=true keeps them,
% using the exact naming convention examples/makeExamplePanelA.m already established by hand.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

function fig = buildTestPanel()
% Same synthetic panel test_group_tag.m/examples/makeExamplePanelA.m use, factored out here so both
% the manual pipeline and runPillar1.m below run against byte-identical live data.
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
drawnow;
end

% --- default call: intermediates deleted ---
fig1 = buildTestPanel();
ax1 = findobj(fig1, 'Type', 'axes');
result = runPillar1(ax1, outDir, 'wraptest');
close(fig1);

fprintf('runPillar1 stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d\n', ...
    result.stats.nDataSeries, result.stats.nLegendEntries, result.stats.nXTicks, result.stats.nYTicks);
assert(strcmp(result.taggedFile, fullfile(outDir,'wraptest_tagged.svg')), 'unexpected taggedFile path');
assert(isfile(result.taggedFile), 'runPillar1 did not produce the tagged SVG');

intermediates = {fullfile(outDir,'wraptest_raw.svg'), fullfile(outDir,'wraptest.svg'), ...
    fullfile(outDir,'wraptest_identity_raw.svg'), fullfile(outDir,'wraptest_identity.svg')};
for i = 1:numel(intermediates)
    assert(~isfile(intermediates{i}), 'intermediate file %s was NOT cleaned up (default opts)', intermediates{i});
end
fprintf('default call: intermediates correctly deleted, tagged SVG kept\n');

% --- opts.keepIntermediates=true ---
fig2 = buildTestPanel();
ax2 = findobj(fig2, 'Type', 'axes');
result2 = runPillar1(ax2, outDir, 'wraptest_kept', struct('keepIntermediates', true));
close(fig2);
intermediates2 = {fullfile(outDir,'wraptest_kept_raw.svg'), fullfile(outDir,'wraptest_kept.svg'), ...
    fullfile(outDir,'wraptest_kept_identity_raw.svg'), fullfile(outDir,'wraptest_kept_identity.svg')};
for i = 1:numel(intermediates2)
    assert(isfile(intermediates2{i}), 'intermediate file %s should have been kept (keepIntermediates=true)', intermediates2{i});
end
fprintf('opts.keepIntermediates=true: all 4 intermediates correctly kept\n');

% --- runPillar1's output must be BYTE-IDENTICAL to the manual step-by-step pipeline ---
fig3 = buildTestPanel();
ax3 = findobj(fig3, 'Type', 'axes');
snap3 = snapshotAxesStyle(ax3);
manualRaw = fullfile(outDir,'wraptest_manual_raw.svg');
print(fig3, manualRaw, '-dsvg','-vector');
manualBaked = fullfile(outDir,'wraptest_manual.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), manualRaw, manualBaked));
manualIdRaw = fullfile(outDir,'wraptest_manual_identity_raw.svg');
dumpIdentitySvg(fig3, snap3, manualIdRaw);
manualIdBaked = fullfile(outDir,'wraptest_manual_identity.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), manualIdRaw, manualIdBaked));
manualTagged = fullfile(outDir,'wraptest_manual_tagged.svg');
manualStats = groupAndTagSvg(ax3, snap3, manualBaked, manualTagged, manualIdBaked);
close(fig3);

wrapText = fileread(result.taggedFile);
manualText = fileread(manualTagged);
assert(strcmp(wrapText, manualText), 'runPillar1.m''s output differs from the manual step-by-step pipeline -- byte-for-byte comparison failed');
fprintf('runPillar1.m output is byte-identical to the manual step-by-step pipeline\n');
assert(isequal(result.stats, manualStats), 'runPillar1.m''s stats differ from the manual pipeline''s');

% --- zero-arg call: self-populating default opts (Bass-wide convention) ---
defaultOpts = runPillar1();
assert(isstruct(defaultOpts) && isfield(defaultOpts,'keepIntermediates') && defaultOpts.keepIntermediates == false, ...
    'zero-arg call did not return a properly-populated default opts struct');
fprintf('zero-arg call returns default opts correctly\n');

disp('RUN PILLAR1 WRAPPER VALIDATION: PASS');
