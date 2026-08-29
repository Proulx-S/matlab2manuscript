% makeExamplePanelA  Concrete, on-disk example of every artifact this repo's pillar-1 pipeline
% currently produces for one PLAIN single-axes panel, for Seb to inspect directly. Runs the whole
% pipeline through the single-function wrapper (runPillar1.m, 2026-08-29) with
% opts.keepIntermediates=true, rather than calling each pipeline step by hand -- this IS the intended
% way to run pillar 1 now, and using it here doubles as a live example of doing so:
%   panelA.fig                the original MATLAB figure (savefig -- NOT part of runPillar1.m itself)
%   panelA_raw.svg             straight print(-dsvg) export -- MATLAB's own transform="matrix(...)"
%   panelA.svg                 bakeTransforms.py output -- transforms flattened into plain attributes
%   panelA_identity_raw.svg    dumpIdentitySvg.m's own throwaway, identity-colored export
%   panelA_identity.svg        the identity export, baked -- used internally for robust data-series
%                              matching (matchGraphicsToSvg.m); not a real deliverable on its own
%   panelA_tagged.svg          groupAndTagSvg.m output -- real nested <g id=.../data-role=...> groups
%
% Deliberately a hand-built plain axes, NOT plotVessels.m (2026-08-29 policy change, see
% docs/findings.md): plotVessels.m always hosts its axes inside a TiledChartLayout (even for one
% panel), and this repo has decided not to accommodate that for now -- adapting an arbitrary MATLAB
% figure down to a plain single-axes figure suitable for this pipeline is its own, later,
% independent step. Includes a confidence band (exercising the dataseries 'value'/'conf' sub-group
% split, paired by Tag not DisplayName) and an ad hoc annotation (folded into furniture -- see
% groupAndTagSvg.m's own comment). Same synthetic panel used by test/test_group_tag.m.
%
% figure1.svg (a composed multi-panel figure with this panel inserted as a layer) is NOT produced --
% that's pillar 2 (the mm-based resize round-trip / panel-insertion step), not yet built. See
% docs/findings.md and README.md's Status section.
repoDir = fileparts(mfilename('fullpath'));
addpath(fileparts(repoDir));
outDir = repoDir;

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
% patch NO DisplayName at all, to demonstrate pairing survives without one. Keep it default-visible
% (NOT HandleVisibility='off' -- that would also hide it from snapshotAxesStyle.m's own
% findobj(ax,'Type','patch') call, not just from legend()) and instead pass legend() an explicit
% handle list to keep it out of the legend without hiding it from findobj.
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

figFile = fullfile(outDir,'panelA.fig');
savefig(fig, figFile);

result = runPillar1(ax, outDir, 'panelA', struct('keepIntermediates', true));
close(fig);

fprintf('Wrote:\n  %s\n  %s\n  %s\n  %s\n  %s\n  %s\n', figFile, ...
    fullfile(outDir,'panelA_raw.svg'), fullfile(outDir,'panelA.svg'), ...
    fullfile(outDir,'panelA_identity_raw.svg'), fullfile(outDir,'panelA_identity.svg'), ...
    result.taggedFile);
