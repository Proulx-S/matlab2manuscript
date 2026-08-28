% NOTE: this test deliberately validates matchGraphicsToSvg.m against a REAL plotting function
% (plotVessels.m) from a real consuming project (humanMouse), not synthetic data -- see this
% repo's README for why. Adjust workDir if humanMouse lives elsewhere on this machine.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));
addpath(fileparts(fileparts(mfilename('fullpath'))));

outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct());
ax = findobj(fig,'Type','axes'); ax = ax(1);

% Capture ground truth BEFORE export/close.
snap = snapshotAxesStyle(ax);
fprintf('Captured %d data-bearing object(s): ', numel(snap));
for i=1:numel(snap); fprintf('[%s hex=%s nPts=%d] ', snap(i).type, snap(i).hex, snap(i).nPts); end
fprintf('\n');

svgFile = fullfile(outDir, 'match_test.svg');
print(fig, svgFile, '-dsvg', '-vector');
liveXData = snap(1).handle.XData;
liveYData = snap(1).handle.YData;
close(fig);

matches = matchGraphicsToSvg(snap, svgFile);

for i = 1:numel(matches)
    fprintf('object %d -> matched %s with %d points (candidates before tiebreak: %d)\n', ...
        i, matches(i).svgTag, size(matches(i).points,1), matches(i).candidateCountBeforeTiebreak);
end

% Sanity check: does the matched SVG polyline's own point count equal the live data's point count?
assert(size(matches(1).points,1) == numel(liveXData), 'point count mismatch');

% Cross-check SHAPE (not just count): correlation between live data and the matched SVG geometry's
% own y-coordinates should be strongly negative (SVG y is flipped vs. data y) and near -1/+1 in
% magnitude, confirming this is really the SAME curve, not a coincidentally-same-length furniture
% polyline that happens to share this color (shouldn't be possible here since furniture is white/
% black, but worth checking as a genuine independent validation, not just trusting the color match).
svgY = matches(1).points(:,2);
r = corrcoef(liveYData(:), svgY(:));
fprintf('correlation between live YData and matched SVG y-coords: %.6f (expect near -1)\n', r(1,2));
assert(r(1,2) < -0.99, 'shape cross-check failed -- matched element does not look like the real data');

disp('PROTOTYPE VALIDATION: PASS');
