addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

% Case A: two lines, SAME color, DIFFERENT point counts -- must disambiguate via nPts tie-break.
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
plot(ax, 1:10, sin(1:10), 'Color',[0.2 0.6 0.9], 'LineWidth',2);
plot(ax, 1:30, cos(1:30)*0.5, 'Color',[0.2 0.6 0.9], 'LineWidth',2);
snap = snapshotAxesStyle(ax);
svgFile = fullfile(outDir,'edgeA.svg');
print(fig, svgFile, '-dsvg', '-vector');
xd1 = snap(1).handle.XData; xd2 = snap(2).handle.XData;
close(fig);
matches = matchGraphicsToSvg(snap, svgFile);
assert(size(matches(1).points,1) == numel(xd1) && size(matches(2).points,1) == numel(xd2), ...
    'Case A: point-count tiebreak failed to correctly assign each object');
fprintf('Case A (same color, different nPts): PASS -- correctly disambiguated by point count\n');

% Case B: two lines, SAME color AND SAME point count -- must error loudly (ambiguousMatch), not
% silently guess.
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
plot(ax, 1:10, sin(1:10), 'Color',[0.7 0.2 0.4], 'LineWidth',2);
plot(ax, 1:10, cos(1:10), 'Color',[0.7 0.2 0.4], 'LineWidth',2);
snap = snapshotAxesStyle(ax);
svgFile = fullfile(outDir,'edgeB.svg');
print(fig, svgFile, '-dsvg', '-vector');
close(fig);
threw = false;
try
    matchGraphicsToSvg(snap, svgFile);
catch e
    threw = strcmp(e.identifier, 'matchGraphicsToSvg:ambiguousMatch');
end
assert(threw, 'Case B: expected a loud ambiguousMatch error, got none (or the wrong one)');
fprintf('Case B (same color, same nPts): PASS -- correctly refused to guess (ambiguousMatch)\n');

% Case C: axis-clip-boundary split (the documented known-gap in the OLD engine) -- a line whose
% data crosses the visible xlim so MATLAB's exporter may split it into multiple polyline siblings.
% Check whether this prototype's simple point-count tiebreak survives that case, or inherits the
% same gap.
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
xx = 1:100; yy = sin(xx/5);
plot(ax, xx, yy, 'Color',[0.1 0.8 0.3], 'LineWidth',2);
xlim(ax, [20 80]);   % forces a real clip -- data extends past the visible range on both sides
snap = snapshotAxesStyle(ax);
svgFile = fullfile(outDir,'edgeC.svg');
print(fig, svgFile, '-dsvg', '-vector');
close(fig);
try
    m = matchGraphicsToSvg(snap, svgFile);
    fprintf('Case C (axis-clip split): matched %d point(s) vs. live %d -- %s\n', ...
        size(m(1).points,1), numel(xx), tern(size(m(1).points,1)==numel(xx),'EXACT MATCH','MISMATCH (expected -- known gap)'));
catch e
    fprintf('Case C (axis-clip split): threw %s -- %s\n', e.identifier, e.message);
end

function s = tern(cond,a,b)
if cond; s=a; else; s=b; end
end
