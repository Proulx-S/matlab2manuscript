% NOTE: validates dumpFontRegistry.m + bakeTransforms.py's rotation handling against a REAL
% rotated-text case (plotVessels.m's own y-axis label) from a real consuming project (humanMouse).
% Adjust workDir if humanMouse lives elsewhere on this machine.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));
repoDir = fileparts(fileparts(mfilename('fullpath')));
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct());
ax = findobj(fig,'Type','axes'); ax = ax(1);
ax.YLabel.FontSize = 17;   % deliberately distinctive, unrounded-looking value
ax.FontSize = 12;
drawnow;

registryFile = fullfile(outDir, 'font_registry.json');
addpath(repoDir);
dumpFontRegistry(ax, registryFile);
fprintf('YLabel string = "%s", FontSize = %g\n', ax.YLabel.String, ax.YLabel.FontSize);

svgFile = fullfile(outDir, 'rotation_test.svg');
print(fig, svgFile, '-dsvg', '-vector');
close(fig);

system(sprintf('python3 %s %s %s %s', fullfile(repoDir,'bakeTransforms.py'), svgFile, ...
    fullfile(outDir,'rotation_test_baked.svg'), registryFile));
disp('DONE MATLAB SIDE');
