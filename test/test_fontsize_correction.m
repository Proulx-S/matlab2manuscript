% NOTE: validates groupAndTagSvg.m's font-size correction (2026-08-29 -- REPLACES the previous
% dumpFontRegistry.m + bakeTransforms.py content-keyed registry mechanism, removed the same day: a
% flat content->fontSize dict is fundamentally ambiguous once more than title/xlabel/ylabel/
% tick-labels are covered, since two different ROLES can share identical text with genuinely
% different font sizes -- exercised directly below by giving the ylabel and the legend label the
% EXACT SAME content ("signal") but DIFFERENT font sizes, the precise case the old mechanism would
% have gotten wrong).
%
% Every role gets a DISTINCTIVE font size so a mix-up between any two is immediately obvious, and
% checked for an EXACT match (not "close to") against the live source value, since correction now
% reads that value directly rather than reconstructing it from a scaled/rounded export.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

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
ax.InnerPosition = [0.2 0.2 0.6 0.6];
ax.Box = 'off';
hold(ax, 'on');

x = 0:0.5:20;
y = 5 + 0.3*sin(2*pi*x/5);
lineH = plot(ax, x, y, 'Color',[0.9 0.7 0.1], 'LineWidth', 2, 'DisplayName', 'signal');
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';   % SAME content as the legend label below, DIFFERENT font size -- the
                                % exact collision case the old content-keyed registry got wrong
legend(ax, lineH, 'Location','northeast');
annotationH = text(ax, 0.02, 0.95, 'panel A', 'Units','normalized', 'FontWeight','bold'); %#ok<NASGU>

% Set AFTER plotting/legend (FontSize/FontSizeMode can silently reset to 'auto' on the first plot
% call on fresh axes, docs/findings.md) AND rulers-before-labels: setting ax.XAxis.FontSize/
% ax.YAxis.FontSize resets ax.XLabel.FontSizeMode/ax.YLabel.FontSizeMode back to 'auto' (confirmed
% real, a SEPARATE gotcha from the first-plot one -- caught by this test itself hitting it: an
% earlier version set labels before rulers and silently got XLabel=9.9 instead of 16, i.e.
% ax.XAxis.FontSize * ax.LabelFontSizeMultiplier's default 1.1, not a font-size-correction bug).
ax.XAxis.FontSize = 9;
ax.YAxis.FontSize = 11;
ax.XLabel.FontSize = 16;
ax.YLabel.FontSize = 22;
legObjs = findobj(fig, 'Type', 'legend');
legObjs.FontSize = 13;
annotationH.FontSize = 18;
drawnow;

snap = snapshotAxesStyle(ax);

rawFile = fullfile(outDir,'fontsize_raw.svg');
print(fig, rawFile, '-dsvg','-vector');
bakedFile = fullfile(outDir,'fontsize_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), rawFile, bakedFile));

identityRawFile = fullfile(outDir,'fontsize_identity_raw.svg');
dumpIdentitySvg(fig, snap, identityRawFile);
identityBakedFile = fullfile(outDir,'fontsize_identity_baked.svg');
system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), identityRawFile, identityBakedFile));

taggedFile = fullfile(outDir,'fontsize_tagged.svg');
stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, identityBakedFile);
close(fig);

fprintf('stats.nAnnotationFontSizeUnresolved = %d (expect 0)\n', stats.nAnnotationFontSizeUnresolved);
assert(stats.nAnnotationFontSizeUnresolved == 0, 'the "panel A" annotation font-size should have resolved cleanly (unique content)');

docTagged = xmlread(taggedFile);
checkFontSize(docTagged, 'axis-xlabel', 16, 'xlabel');
checkFontSize(docTagged, 'axis-ylabel', 22, 'ylabel (rotated -- also confirms font-size correction does not disturb the separately-baked rotate() transform)');
checkFontSize(docTagged, 'axis-ticklabel-x-1', 9, 'x tick label');
checkFontSize(docTagged, 'axis-ticklabel-y-1', 11, 'y tick label');
checkFontSize(docTagged, 'legend-label-1', 13, 'legend label');
checkFontSize(docTagged, 'annotation-1', 18, 'ad hoc annotation');

% The rotation itself must still be intact -- font-size correction runs on the ALREADY-baked SVG,
% touching only the font-size attribute, never the separately-baked rotate() transform.
ylabelNode = findTestById(docTagged, 'axis-ylabel');
transformAttr = char(ylabelNode.getAttribute('transform'));
assert(contains(transformAttr, 'rotate'), 'y-axis label lost its rotate() transform after font-size correction');
fprintf('y-axis label rotation preserved: %s\n', transformAttr);

disp('FONT-SIZE CORRECTION (role-based, not content-registry) VALIDATION: PASS');

function checkFontSize(doc, id, expected, label)
node = findTestById(doc, id);
assert(~isempty(node), 'could not find id="%s" (%s)', id, label);
actual = str2double(char(node.getAttribute('font-size')));
fprintf('%s (id=%s): font-size=%g (expect exactly %g)\n', label, id, actual, expected);
assert(abs(actual - expected) < 1e-6, '%s (id=%s): expected font-size %g, got %g', label, id, expected, actual);
end

function node = findTestById(doc, id)
all = doc.getElementsByTagName('*');
node = [];
for k = 0:all.getLength()-1
    n = all.item(k);
    if strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
end
