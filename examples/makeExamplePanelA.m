% makeExamplePanelA  Concrete, on-disk example of every artifact this repo's pipeline currently
% produces for one PLAIN single-axes panel, for Seb to inspect directly:
%   panelA.fig          the original MATLAB figure (savefig)
%   panelA_raw.svg       straight print(-dsvg) export -- MATLAB's own transform="matrix(...)" intact
%   panelA.svg            bakeTransforms.py output -- transforms flattened into plain attributes
%   panelA_tagged.svg     groupAndTagSvg.m output -- real nested <g id=.../data-role=...> groups
%
% Also writes panelA_identity_raw.svg/panelA_identity.svg -- dumpIdentitySvg.m's own throwaway,
% identity-colored export (+ its own bake) used internally for robust data-series matching (see
% matchGraphicsToSvg.m). Not one of the four artifacts above; kept on disk only for inspecting the
% matching mechanism itself, never meant to be a real deliverable.
%
% Deliberately a hand-built plain axes, NOT plotVessels.m (2026-08-29 policy change, see
% docs/findings.md): plotVessels.m always hosts its axes inside a TiledChartLayout (even for one
% panel), and this repo has decided not to accommodate that for now -- adapting an arbitrary MATLAB
% figure down to a plain single-axes figure suitable for this pipeline is its own, later,
% independent step. Includes a confidence band (exercising the dataseries 'value'/'conf' sub-group
% split) and an ad hoc annotation (folded into furniture -- see groupAndTagSvg.m's own comment).
% Same synthetic panel used by test/test_group_tag.m.
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
% confidence band (Patch) FIRST, same DisplayName as the line below so groupAndTagSvg.m's own
% DisplayName-based pairing puts them in the same series' 'value'/'conf' sub-groups. Keep it
% default-visible (NOT HandleVisibility='off' -- that would also hide it from
% snapshotAxesStyle.m's own findobj(ax,'Type','patch') call, not just from legend()) and instead
% pass legend() an explicit handle list to keep it out of the legend without hiding it from findobj.
patchH = patch(ax, [x fliplr(x)], [y+0.15 fliplr(y-0.15)], [0.9 0.7 0.1], ...
    'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'signal'); %#ok<NASGU>
lineH = plot(ax, x, y, 'Color',[0.9 0.7 0.1], 'LineWidth', 2, 'DisplayName', 'signal');
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';   % deliberately the SAME string as the legend's own DisplayName below,
                                % to keep exercising the real content-collision case this pipeline
                                % must resolve (confirmed real on plotVessels.m's own "radius" panel)
legend(ax, lineH, 'Location','northeast');   % explicit handle -- only the line gets a legend entry
text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold');   % ad hoc annotation
drawnow;

snap = snapshotAxesStyle(ax);

figFile = fullfile(outDir,'panelA.fig');
savefig(fig, figFile);

rawFile = fullfile(outDir,'panelA_raw.svg');
print(fig, rawFile, '-dsvg','-vector');

bakedFile = fullfile(outDir,'panelA.svg');
system(sprintf('python3 %s %s %s', fullfile(fileparts(repoDir),'bakeTransforms.py'), rawFile, bakedFile));

% Identity-colored export (dumpIdentitySvg.m) + bake -- robust, collision-proof data-series matching
% (see matchGraphicsToSvg.m/docs/findings.md) instead of real-color fingerprinting.
identityRawFile = fullfile(outDir,'panelA_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'panelA_identity.svg');
system(sprintf('python3 %s %s %s', fullfile(fileparts(repoDir),'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'panelA_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, identityBakedFile); %#ok<NASGU>
close(fig);

fprintf('Wrote:\n  %s\n  %s\n  %s\n  %s\n', figFile, rawFile, bakedFile, taggedFile);
