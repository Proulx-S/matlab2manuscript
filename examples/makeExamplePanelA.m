% makeExamplePanelA  Concrete, on-disk example of every artifact this repo's pipeline currently
% produces for one panel (real plotVessels.m data, legend on), for Seb to inspect directly:
%   panelA.fig          the original MATLAB figure (savefig)
%   panelA_raw.svg       straight print(-dsvg) export -- MATLAB's own transform="matrix(...)" intact
%   panelA.svg            bakeTransforms.py output -- transforms flattened into plain attributes
%   panelA_tagged.svg     groupAndTagSvg.m output -- id/data-role/data-group stamped on top of the
%                         baked file (not explicitly asked for by name, generated anyway since it's
%                         this session's actual deliverable)
%
% figure1.svg (a composed multi-panel figure with this panel inserted as a layer) is NOT produced --
% that's pillar 2 (the mm-based resize round-trip / panel-insertion step), not yet built. See
% docs/findings.md and README.md's Status section.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));
repoDir = fileparts(mfilename('fullpath'));
addpath(fileparts(repoDir));
outDir = repoDir;

t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct('legendVerbose',1));
ax = findobj(fig,'Type','axes'); ax = ax(1);
% plotVessels.m ALWAYS hosts its axes inside a tiledlayout (even for a single panel, confirmed via
% class(ax.Parent)=='matlab.graphics.layout.TiledChartLayout') -- PositionConstraint cannot be set
% for a tiled axes at all (see identifyAxisSpine.m's own comment for the full story).
snap = snapshotAxesStyle(ax);

figFile = fullfile(outDir,'panelA.fig');
savefig(fig, figFile);

rawFile = fullfile(outDir,'panelA_raw.svg');
print(fig, rawFile, '-dsvg','-vector');

bakedFile = fullfile(outDir,'panelA.svg');
system(sprintf('python3 %s %s %s', fullfile(fileparts(repoDir),'bakeTransforms.py'), rawFile, bakedFile));

taggedFile = fullfile(outDir,'panelA_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile); %#ok<NASGU>
close(fig);

fprintf('Wrote:\n  %s\n  %s\n  %s\n  %s\n', figFile, rawFile, bakedFile, taggedFile);
