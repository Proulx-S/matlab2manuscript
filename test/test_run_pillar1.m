% NOTE: validates runPillar1.m (2026-08-29, revised same day for the copy-step change) -- the
% single-function wrapper around this repo's own pillar-1 pipeline (copy -> bake -> identity
% export/bake -> group/tag). Checks: (1) its output is IDENTICAL to the manual step-by-step pipeline
% (now including the copy step itself -- see manualCopyStep() below) test_group_tag.m/
% examples/makeExamplePanelA.m already validate by hand; (2) intermediate files are deleted by
% default; (3) opts.keepIntermediates=true keeps them; (4) figId/panId are compulsory and name the
% output stem; (5) opts.canvasUnits/opts.canvasSize override the US-Letter default.
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
ax.XAxis.FontSize = 9;
ax.YAxis.FontSize = 11;
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';
ax.XLabel.FontSize = 16;
ax.YLabel.FontSize = 22;
legend(ax, lineH, 'Location','northeast');
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold');
drawnow;
end

function [fig2, ax2] = manualCopyStep(ax, canvasUnits, canvasSize)
% Manually reproduces runPillar1.m's own internal copyAxesToStandardCanvas() step, so the byte-
% identical comparison below actually compares "runPillar1.m" against "everything it does, done by
% hand" -- including the copy -- not just the post-copy pipeline stages (which would silently stop
% being a meaningful ground-truth comparison once the copy step was introduced).
origInnerPosition = ax.InnerPosition;
origXAxisFS = ax.XAxis.FontSize;
origYAxisFS = ax.YAxis.FontSize;
origXLabelFS = ax.XLabel.FontSize;
origYLabelFS = ax.YLabel.FontSize;

fig2 = figure('Visible','off');
fig2.Units = canvasUnits;
fig2.Position = [1 1 canvasSize];
fig2.PaperUnits = canvasUnits;
fig2.PaperSize = canvasSize;
fig2.PaperPositionMode = 'manual';
fig2.PaperPosition = [0 0 canvasSize];

if ~isempty(ax.Legend)
    copied = copyobj([ax, ax.Legend], fig2);
    ax2 = copied(1);
else
    ax2 = copyobj(ax, fig2);
end
ax2.Units = 'normalized';
ax2.PositionConstraint = 'innerposition';
ax2.PlotBoxAspectRatioMode = 'auto';
ax2.DataAspectRatioMode = 'auto';
ax2.InnerPosition = origInnerPosition;
ax2.XAxis.FontSize = origXAxisFS;
ax2.YAxis.FontSize = origYAxisFS;
ax2.XLabel.FontSize = origXLabelFS;
ax2.YLabel.FontSize = origYLabelFS;
drawnow;
end

% --- default call: intermediates deleted ---
fig1 = buildTestPanel();
ax1 = findobj(fig1, 'Type', 'axes');
result = runPillar1(ax1, outDir, 'wraptest', 'panelA');
close(fig1);

fprintf('runPillar1 stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d\n', ...
    result.stats.nDataSeries, result.stats.nLegendEntries, result.stats.nXTicks, result.stats.nYTicks);
assert(strcmp(result.taggedFile, fullfile(outDir,'wraptest_panelA_tagged.svg')), 'unexpected taggedFile path');
assert(isfile(result.taggedFile), 'runPillar1 did not produce the tagged SVG');

intermediates = {fullfile(outDir,'wraptest_panelA_raw.svg'), fullfile(outDir,'wraptest_panelA.svg'), ...
    fullfile(outDir,'wraptest_panelA_identity_raw.svg'), fullfile(outDir,'wraptest_panelA_identity.svg')};
for i = 1:numel(intermediates)
    assert(~isfile(intermediates{i}), 'intermediate file %s was NOT cleaned up (default opts)', intermediates{i});
end
fprintf('default call: intermediates correctly deleted, tagged SVG kept\n');

% --- opts.keepIntermediates=true ---
fig2 = buildTestPanel();
ax2 = findobj(fig2, 'Type', 'axes');
result2 = runPillar1(ax2, outDir, 'wraptest', 'kept', struct('keepIntermediates', true));
close(fig2);
intermediates2 = {fullfile(outDir,'wraptest_kept_raw.svg'), fullfile(outDir,'wraptest_kept.svg'), ...
    fullfile(outDir,'wraptest_kept_identity_raw.svg'), fullfile(outDir,'wraptest_kept_identity.svg')};
for i = 1:numel(intermediates2)
    assert(isfile(intermediates2{i}), 'intermediate file %s should have been kept (keepIntermediates=true)', intermediates2{i});
end
fprintf('opts.keepIntermediates=true: all 4 intermediates correctly kept\n');

% --- opts.canvasUnits/opts.canvasSize override the US-Letter default ---
fig2b = buildTestPanel();
ax2b = findobj(fig2b, 'Type', 'axes');
result2b = runPillar1(ax2b, outDir, 'wraptest', 'customcanvas', ...
    struct('keepIntermediates', true, 'canvasUnits', 'centimeters', 'canvasSize', [20 15]));
close(fig2b);
raw = fileread(fullfile(outDir, 'wraptest_customcanvas_raw.svg'));
svgTag = regexp(raw, '<svg width="([\d.]+)mm" height="([\d.]+)mm"', 'tokens', 'once');
assert(~isempty(svgTag), 'could not parse <svg width=.../height=...> from wraptest_customcanvas_raw.svg');
canvasWmm = str2double(svgTag{1}); canvasHmm = str2double(svgTag{2});
% tolerance: same 72/ScreenPixelsPerInch rounding discrepancy documented elsewhere in this repo
% (docs/findings.md) means the declared mm size is not bit-exact to the requested 200mm x 150mm.
assert(abs(canvasWmm - 200) < 1 && abs(canvasHmm - 150) < 1, ...
    'opts.canvasUnits/canvasSize override did not take effect (expected ~200mm x ~150mm canvas, got %.3fmm x %.3fmm)', ...
    canvasWmm, canvasHmm);
fprintf('opts.canvasUnits/opts.canvasSize override: PASS (%.3fmm x %.3fmm canvas confirmed)\n', canvasWmm, canvasHmm);

% --- runPillar1's output must be BYTE-IDENTICAL to the manual step-by-step pipeline, INCLUDING the
% copy step ---
fig3 = buildTestPanel();
ax3 = findobj(fig3, 'Type', 'axes');
[manualFig2, manualAx2] = manualCopyStep(ax3, 'inches', [8.5 11]);
snap3 = snapshotAxesStyle(manualAx2);
manualRaw = fullfile(outDir,'wraptest_manual_raw.svg');
print(manualFig2, manualRaw, '-dsvg','-vector');
manualBaked = fullfile(outDir,'wraptest_manual.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), manualRaw, manualBaked));
manualIdRaw = fullfile(outDir,'wraptest_manual_identity_raw.svg');
dumpIdentitySvg(manualFig2, snap3, manualIdRaw);
manualIdBaked = fullfile(outDir,'wraptest_manual_identity.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), manualIdRaw, manualIdBaked));
manualTagged = fullfile(outDir,'wraptest_manual_tagged.svg');
manualStats = groupAndTagSvg(manualAx2, snap3, manualBaked, manualTagged, manualIdBaked);
close(manualFig2);
close(fig3);

wrapText = fileread(result.taggedFile);
manualText = fileread(manualTagged);
assert(strcmp(wrapText, manualText), 'runPillar1.m''s output differs from the manual step-by-step pipeline (including the copy step) -- byte-for-byte comparison failed');
fprintf('runPillar1.m output is byte-identical to the manual step-by-step pipeline (copy step included)\n');
assert(isequal(result.stats, manualStats), 'runPillar1.m''s stats differ from the manual pipeline''s');

% --- zero-arg call: self-populating default opts (Bass-wide convention) ---
defaultOpts = runPillar1();
assert(isstruct(defaultOpts) && isfield(defaultOpts,'keepIntermediates') && defaultOpts.keepIntermediates == false ...
    && isfield(defaultOpts,'canvasUnits') && strcmp(defaultOpts.canvasUnits,'inches') ...
    && isfield(defaultOpts,'canvasSize') && isequal(defaultOpts.canvasSize,[8.5 11]), ...
    'zero-arg call did not return a properly-populated default opts struct');
fprintf('zero-arg call returns default opts correctly (including US-Letter canvas default)\n');

disp('RUN PILLAR1 WRAPPER VALIDATION: PASS');
