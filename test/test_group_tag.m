% NOTE: this test deliberately validates groupAndTagSvg.m (+ identifyAxisSpine.m/identifyLegend.m)
% against a REAL plotting function (plotVessels.m) from a real consuming project (humanMouse), with
% a legend ON, so the DisplayName-content-collision case (this repo's own probe SVG has a legend
% entry AND a y-axis label that are both literally "radius") is actually exercised, not hypothetical.
% Adjust workDir if humanMouse lives elsewhere on this machine.
workDir = '/scratch/bass/projects/humanMouse';
addpath(genpath(fullfile(workDir,'vesselFit')));
addpath(genpath(fullfile(workDir,'humanVessel')));
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

t = (0:0.1:20)';
vessel = struct();
vessel.tsImMotionCorrected.gaussVascPhys.radius = 5 + 0.3*sin(2*pi*t/5)' + 0.02*randn(1,numel(t));
vessel.dt = 0.1;

fig = plotVessels(vessel, 'tsImMotionCorrected.gaussVascPhys.radius', struct('legendVerbose',1));
ax = findobj(fig,'Type','axes'); ax = ax(1);
fprintf('ax.Box=%s, ax.Title.String="%s", ax.XLabel.String="%s", ax.YLabel.String="%s"\n', ...
    ax.Box, char(ax.Title.String), char(ax.XLabel.String), char(ax.YLabel.String));

snap = snapshotAxesStyle(ax);

rawFile = fullfile(outDir,'group_tag_raw.svg');
print(fig, rawFile, '-dsvg','-vector');

bakedFile = fullfile(outDir,'group_tag_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

taggedFile = fullfile(outDir,'group_tag_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile);
close(fig);   % safe to close now -- groupAndTagSvg only needed the live ax/fig up to this point

fprintf('stats: nDataSeries=%d nLegendEntries=%d nXTicks=%d nYTicks=%d nAxisLabels=%d\n', ...
    stats.nDataSeries, stats.nLegendEntries, stats.nXTicks, stats.nYTicks, stats.nAxisLabels);

assert(stats.nDataSeries == 1, 'expected exactly 1 tagged data series');
assert(stats.nLegendEntries == 1, 'expected exactly 1 tagged legend entry');
assert(stats.nXTicks == 11, 'expected 11 x-ticks (0:2:20)');
assert(stats.nYTicks == 7, 'expected 7 y-ticks');
% ax.Title.String is empty for this real panel (the top text seen in this repo's own probe SVG is a
% separate whole-figure title/annotation, not ax.Title -- not this tool's concern yet) -- only
% xlabel+ylabel are real ax-level labels here.
assert(stats.nAxisLabels == 2, 'expected xlabel+ylabel tagged (2, ax.Title.String is empty for this panel)');

% --- element-count invariant: tagging must be PURELY additive (attributes only) -- same number of
% rendering-bearing elements before and after, nothing added/removed/duplicated.
docBaked = xmlread(bakedFile);
docTagged = xmlread(taggedFile);
for tag = {'polyline','path','text','circle'}
    nBaked = docBaked.getElementsByTagName(tag{1}).getLength();
    nTagged = docTagged.getElementsByTagName(tag{1}).getLength();
    assert(nBaked == nTagged, 'element count changed for <%s>: baked=%d tagged=%d', tag{1}, nBaked, nTagged);
    fprintf('<%s> count preserved: %d\n', tag{1}, nBaked);
end

% --- spot-check specific expected ids/attributes actually landed on the right elements ---
txt = fileread(taggedFile);
expectedIds = {'axis-spine-x','axis-spine-y','axis-xlabel','axis-ylabel', ...
    'axis-tick-x-1','axis-tick-x-11','axis-ticklabel-x-1','axis-ticklabel-x-11', ...
    'axis-tick-y-1','axis-tick-y-7','axis-ticklabel-y-1','axis-ticklabel-y-7', ...
    'legend-box-bg','legend-box-border','legend-swatch-1','legend-label-1'};
for i = 1:numel(expectedIds)
    found = ~isempty(regexp(txt, ['id="' regexptranslate('escape',expectedIds{i}) '"'], 'once'));
    assert(found, 'expected id="%s" not found in tagged SVG', expectedIds{i});
end
fprintf('all %d expected ids found\n', numel(expectedIds));

% dataseries id should embed the DisplayName slug ("radius")
found = ~isempty(regexp(txt, 'id="dataseries-1-radius"', 'once'));
assert(found, 'expected id="dataseries-1-radius" not found');

% the legend-label text and the ylabel text must be DIFFERENT nodes despite identical content
% ("radius" in both, confirmed in this repo's own probe.svg) -- if collapsed into the same match,
% one of axis-ylabel/legend-label-1 would be missing (already checked above) or attached to the
% WRONG element; cross-check by content+id co-occurring on distinct lines.
lines = strsplit(txt, newline);
ylabelLine = lines(~cellfun(@isempty, regexp(lines, 'id="axis-ylabel"', 'once')));
legendLabelLine = lines(~cellfun(@isempty, regexp(lines, 'id="legend-label-1"', 'once')));
assert(~isempty(ylabelLine) && ~isempty(legendLabelLine), 'could not locate the two "radius" text lines');
assert(~strcmp(ylabelLine{1}, legendLabelLine{1}), 'ylabel and legend-label collapsed onto the same line -- collision not resolved');
fprintf('ylabel/legend-label "radius" collision correctly resolved to distinct elements\n');

disp('GROUP/TAG VALIDATION: PASS');
