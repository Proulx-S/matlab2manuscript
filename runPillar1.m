function result = runPillar1(ax, outDir, figId, panId, opts)
% runPillar1  Runs this repo's ENTIRE pillar-1 pipeline (grouping/tagging) end to end for one plain
% single-axes panel: copy -> snapshot -> raw export -> bake -> identity export -> identity bake ->
% group/tag -- producing just the final tagged SVG, `<figId>_<panId>_tagged.svg`. The four
% intermediate files this needs along the way (`<figId>_<panId>_raw.svg`, `<figId>_<panId>.svg`
% baked, `<figId>_<panId>_identity_raw.svg`, `<figId>_<panId>_identity.svg` baked-identity) are
% DELETED once no longer needed by default -- set `opts.keepIntermediates=true` to keep them instead.
%
% COPY STEP (2026-08-29): before anything else, `ax` is `copyobj`'d into a brand-new figure built on
% a fixed standard canvas (default US Letter portrait, `opts.canvasSize`) -- the caller's own `ax`/
% figure is NEVER touched, mutated, or closed; every export/bake/tag step downstream runs against
% the COPY. This exists so every panel this tool ever produces shares one physical coordinate system
% (the eventual composed multi-panel figure will use the SAME standard canvas -- see docs/findings.md,
% "pillar 2" design notes), and so absolute font-size/line-width fidelity depends only on the target
% canvas size, never on whatever size the caller's own raw figure happened to be. `figId`/`panId` are
% now compulsory for exactly this reason: they name the copy figure/output stem, not the caller's
% original figure.
%
% A useful side effect of copying: `ax` may now come from a TiledChartLayout (e.g. plotVessels.m's
% own axes) -- `copyobj` detaches it cleanly into a plain axes on the copy figure, which is why
% TiledChartLayout-hosted axes are supported as of this same change (previously out of scope, see
% docs/findings.md).
%
% Call with NO arguments to see this help and get a fully-populated default opts struct (required
% fields included as empty placeholders) -- the Bass-wide convention for a new user-facing function.
%
% ax        live axes (NOT yet closed, and NEVER modified -- the copy step reads it, never writes to
%           it). Box='off' or 'on' both supported (identifyAxisSpine.m). ax.Units must be
%           'normalized' (so ax.InnerPosition is read as a portable fraction, not a size tied to the
%           caller's own figure). TiledChartLayout-hosted axes ARE supported (see above).
% outDir    directory to write `<figId>_<panId>_tagged.svg` (and, if opts.keepIntermediates, the four
%           intermediate files) into
% figId     compulsory id for the eventual composed multi-panel figure this panel belongs to (used
%           here only for the output filename stem -- embedding figId/panId into every tagged
%           element's own id, for safe multi-panel composition, is a DELIBERATELY DEFERRED later
%           step, not yet implemented -- see docs/findings.md)
% panId     compulsory id for this panel within that figure (same file-naming role as figId above)
% opts.keepIntermediates  (default false) keep the 4 intermediate SVG files instead of deleting them
% opts.pythonExe          (default 'python3') interpreter used to invoke bakeTransforms.py
% opts.canvasUnits        (default 'inches') units for opts.canvasSize
% opts.canvasSize         (default [8.5 11], US Letter portrait) the copy figure's fixed [width
%                         height] canvas size, in opts.canvasUnits
%
% result.taggedFile   full path to the final tagged SVG (always kept, regardless of opts)
% result.stats        groupAndTagSvg.m's own per-role counts struct

if nargin == 0
    fprintf(['runPillar1  Runs this repo''s entire pillar-1 pipeline (grouping/tagging) end to end\n' ...
        'for one plain single-axes panel: copy -> snapshot -> raw export -> bake -> identity export ->\n' ...
        'identity bake -> group/tag -- producing just the final tagged SVG. `ax` is first copied\n' ...
        '(copyobj) into a fresh figure on a fixed standard canvas (default US Letter) -- the caller''s\n' ...
        'own figure/ax is never touched. Intermediate files are deleted by default\n' ...
        '(opts.keepIntermediates=true keeps them).\n\n' ...
        'ax        live axes (NOT yet closed, never modified) -- Box=''off''/''on'' both supported,\n' ...
        '          ax.Units must be ''normalized''; TiledChartLayout-hosted axes ARE supported\n' ...
        'outDir    directory to write outputs into\n' ...
        'figId     compulsory id for the eventual composed multi-panel figure (naming only for now)\n' ...
        'panId     compulsory id for this panel (naming only for now)\n' ...
        'opts.keepIntermediates  (default false) keep the 4 intermediate SVG files\n' ...
        'opts.pythonExe          (default ''python3'')\n' ...
        'opts.canvasUnits        (default ''inches'')\n' ...
        'opts.canvasSize         (default [8.5 11], US Letter portrait)\n\n' ...
        'Returns result.taggedFile (path) and result.stats (groupAndTagSvg.m''s own counts).\n']);
    result = struct('ax',[], 'outDir','', 'figId','', 'panId','', 'keepIntermediates',false, ...
        'pythonExe','python3', 'canvasUnits','inches', 'canvasSize',[8.5 11]);
    return
end

if nargin < 5 || isempty(opts); opts = struct(); end
if ~isfield(opts,'keepIntermediates'); opts.keepIntermediates = false; end
if ~isfield(opts,'pythonExe'); opts.pythonExe = 'python3'; end
if ~isfield(opts,'canvasUnits'); opts.canvasUnits = 'inches'; end
if ~isfield(opts,'canvasSize'); opts.canvasSize = [8.5 11]; end

assert(strcmp(ax.Units,'normalized'), 'runPillar1:wrongUnits', ...
    'ax.Units must be ''normalized'' (so ax.InnerPosition is a portable fraction) -- got ''%s''.', ax.Units);

repoDir = fileparts(mfilename('fullpath'));
bakeScript = fullfile(repoDir, 'bakeTransforms.py');
baseName = sprintf('%s_%s', figId, panId);

[fig2, ax2] = copyAxesToStandardCanvas(ax, opts.canvasUnits, opts.canvasSize);
cleanupFig2 = onCleanup(@() close(fig2));

rawFile           = fullfile(outDir, [baseName '_raw.svg']);
bakedFile         = fullfile(outDir, [baseName '.svg']);
identityRawFile   = fullfile(outDir, [baseName '_identity_raw.svg']);
identityBakedFile = fullfile(outDir, [baseName '_identity.svg']);
taggedFile        = fullfile(outDir, [baseName '_tagged.svg']);

snap = snapshotAxesStyle(ax2);

print(fig2, rawFile, '-dsvg', '-vector');
runBake(opts.pythonExe, bakeScript, rawFile, bakedFile);

dumpIdentitySvg(fig2, snap, identityRawFile);
runBake(opts.pythonExe, bakeScript, identityRawFile, identityBakedFile);

stats = groupAndTagSvg(ax2, snap, bakedFile, taggedFile, identityBakedFile);

if ~opts.keepIntermediates
    delete(rawFile);
    delete(bakedFile);
    delete(identityRawFile);
    delete(identityBakedFile);
end

result.taggedFile = taggedFile;
result.stats = stats;
end

function [fig2, ax2] = copyAxesToStandardCanvas(ax, canvasUnits, canvasSize)
% Copies `ax` (and its Legend, if any) into a fresh figure sized to the fixed standard canvas,
% re-establishing everything `copyobj` is known to drop or reset (2026-08-29 empirical findings):
%   - copying `ax` alone silently DROPS its Legend -- must copy [ax, ax.Legend] together.
%   - `axis square`/`axis image` (PlotBoxAspectRatioMode/DataAspectRatioMode='manual') survive the
%     copy and keep constraining the copy's drawn box even though InnerPosition itself is untouched
%     by them -- resetting both Modes to 'auto' after the copy, then re-setting InnerPosition,
%     restores the full undistorted box (confirmed empirically, no third property needed).
%   - XAxis/YAxis/XLabel/YLabel FontSize are silently reset to auto-mode defaults by `copyobj`,
%     regardless of the source's mode/value -- must be re-applied explicitly post-copy, RULERS
%     BEFORE LABELS (same ordering rule as the XAxis.FontSize -> XLabel.FontSizeMode reset gotcha
%     already documented in docs/findings.md, since XAxis/YAxis FontSize resets XLabel/YLabel's own
%     FontSizeMode back to auto if set afterward).
% This also detaches `ax` from a TiledChartLayout parent cleanly, if that's what it was hosted in.
origInnerPosition = ax.InnerPosition;
origXAxisFS  = ax.XAxis.FontSize;
origYAxisFS  = ax.YAxis.FontSize;
origXLabelFS = ax.XLabel.FontSize;
origYLabelFS = ax.YLabel.FontSize;

fig2 = figure('Visible','off');
fig2.Units = canvasUnits;
fig2.Position = [1 1 canvasSize];
fig2.PaperUnits = canvasUnits;
fig2.PaperSize = canvasSize;
fig2.PaperPositionMode = 'manual';
fig2.PaperPosition = [0 0 canvasSize];

if ~isempty(ax.Legend)
    copied = copyobj([ax, ax.Legend], fig2);
    ax2 = copied(1);
else
    ax2 = copyobj(ax, fig2);
end

ax2.Units = 'normalized';
ax2.PositionConstraint = 'innerposition';
ax2.PlotBoxAspectRatioMode = 'auto';
ax2.DataAspectRatioMode = 'auto';
ax2.InnerPosition = origInnerPosition;
ax2.XAxis.FontSize = origXAxisFS;
ax2.YAxis.FontSize = origYAxisFS;
ax2.XLabel.FontSize = origXLabelFS;
ax2.YLabel.FontSize = origYLabelFS;
drawnow;
end

function runBake(pythonExe, script, infile, outfile)
[status, cmdout] = system(sprintf('%s %s %s %s', pythonExe, script, infile, outfile));
assert(status == 0, 'runPillar1:bakeFailed', 'bakeTransforms.py failed on %s:\n%s', infile, cmdout);
end
