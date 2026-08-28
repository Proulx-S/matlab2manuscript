% NOTE: identifies a real rotated-text case (plotVessels.m's own vessel-ID corner label) against a
% real consuming project (humanMouse). Adjust workDir if humanMouse lives elsewhere on this machine.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));

t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct());
ax = findobj(fig,'Type','axes'); ax = ax(1);
ax.YLabel.FontSize = 17;
ax.FontSize = 12;
drawnow;

allText = findall(fig, 'Type', 'text');
fprintf('Found %d Type=text objects:\n', numel(allText));
for i = 1:numel(allText)
    t_ = allText(i);
    fprintf('  [%d] String="%s" Parent=%s Rotation=%g Position=%s\n', ...
        i, char(t_.String), class(t_.Parent), t_.Rotation, mat2str(t_.Position,4));
end

% Check XAxis/YAxis Exponent (scientific-notation multiplier indicator)
fprintf('ax.YAxis.Exponent = %g, ax.YAxis.ExponentMode=%s\n', ax.YAxis.Exponent, ax.YAxis.ExponentMode);
fprintf('ax.XAxis.Exponent = %g\n', ax.XAxis.Exponent);
close(fig);
disp('DONE');
