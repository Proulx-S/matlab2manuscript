% NOTE: validates TiledChartLayout support (2026-08-29, via runPillar1.m's copy step -- copyobj
% detaches the axes from its TiledChartLayout parent cleanly, so the previous "TiledChartLayout is
% out of scope" restriction no longer applies to anything routed through runPillar1.m; see
% docs/findings.md). Builds the SAME synthetic panel content as test_run_pillar1.m's
% buildTestPanel(), once hosted in a tiledlayout and once plain, and checks: runPillar1.m succeeds on
% both with no errors, produces IDENTICAL stats, and a text-stripped pixel-diff of 0 -- proving the
% tiled origin has no effect on the final output once routed through the copy step.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

function ax = buildContent(ax)
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
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold', 'FontSize', 18);
drawnow;
end

% --- TILED axes: PositionConstraint/InnerPosition cannot be set directly on a tiled axes (MATLAB
% silently refuses with a warning) -- runPillar1.m's copy step only ever needs to READ whatever
% InnerPosition the tile auto-computed and re-impose it on the (detached) copy, so content is built
% first and the resulting auto InnerPosition captured afterward, deliberately not forced beforehand. ---
figT = figure('Visible','off');
figT.Units = 'centimeters'; figT.Position = [2 2 16 10];
tl = tiledlayout(figT, 1, 1);
axT = nexttile(tl);
buildContent(axT);
tiledInnerPosition = axT.InnerPosition;
fprintf('pre-copy: class(axT.Parent)=%s InnerPosition=[%s]\n', class(axT.Parent), num2str(tiledInnerPosition));

resultT = runPillar1(axT, outDir, 'tiledtest', 'tiled');
close(figT);
fprintf('TILED stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d nAnnotationFontSizeUnresolved=%d\n', ...
    resultT.stats.nDataSeries, resultT.stats.nLegendEntries, resultT.stats.nXTicks, resultT.stats.nYTicks, ...
    resultT.stats.nAnnotationFontSizeUnresolved);

% --- PLAIN axes (reference), SAME InnerPosition the tile auto-computed -- a tiled axes and a plain
% axes have DIFFERENT default auto-margins, so this must be forced explicitly for a fair
% apples-to-apples comparison (only the origin -- tiled vs. plain -- should differ, not the geometry) ---
figP = figure('Visible','off');
figP.Units = 'centimeters'; figP.Position = [2 2 16 10];
axP = axes(figP);
axP.Units = 'normalized';
axP.PositionConstraint = 'innerposition';
axP.InnerPosition = tiledInnerPosition;
buildContent(axP);

resultP = runPillar1(axP, outDir, 'tiledtest', 'plain');
close(figP);
fprintf('PLAIN stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d nAnnotationFontSizeUnresolved=%d\n', ...
    resultP.stats.nDataSeries, resultP.stats.nLegendEntries, resultP.stats.nXTicks, resultP.stats.nYTicks, ...
    resultP.stats.nAnnotationFontSizeUnresolved);

assert(isequal(resultT.stats, resultP.stats), 'TILED vs PLAIN stats differ');
fprintf('stats identical between TILED and PLAIN origin: PASS\n');

stripScript = fullfile(repoDir, 'test', 'stripTextForDiff.py');
tNoText = fullfile(outDir, 'tiledtest_tiled_tagged_notext.svg');
pNoText = fullfile(outDir, 'tiledtest_plain_tagged_notext.svg');
system(sprintf('python3 %s %s %s', stripScript, resultT.taggedFile, tNoText));
system(sprintf('python3 %s %s %s', stripScript, resultP.taggedFile, pNoText));
tPng = fullfile(outDir, 'tiledtest_tiled.png');
pPng = fullfile(outDir, 'tiledtest_plain.png');
system(sprintf('rsvg-convert -o %s %s', tPng, tNoText));
system(sprintf('rsvg-convert -o %s %s', pPng, pNoText));
diffPng = fullfile(outDir, 'tiledtest_diff.png');
[~, out] = system(sprintf('compare -metric AE -fuzz 2%% %s %s %s 2>&1', tPng, pPng, diffPng));
nDiff = str2double(regexp(out, '[\d.]+', 'match', 'once'));
fprintf('pixel-diff (TILED vs PLAIN, text stripped, 2%% fuzz): %g differing pixels\n', nDiff);
assert(nDiff == 0, 'TILED vs PLAIN tagged output differs visually (text stripped)');

disp('TILEDLAYOUT SUPPORT VALIDATION: PASS');
