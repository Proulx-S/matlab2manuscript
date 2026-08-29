function result = runPillar1(ax, outDir, baseName, opts)
% runPillar1  Runs this repo's ENTIRE pillar-1 pipeline (grouping/tagging, README) end to end for one
% plain single-axes panel: snapshot -> raw export -> bake -> identity export -> identity bake ->
% group/tag -- producing just the final tagged SVG, `<baseName>_tagged.svg`. The four intermediate
% files this needs along the way (`<baseName>_raw.svg`, `<baseName>.svg` baked, `<baseName>_
% identity_raw.svg`, `<baseName>_identity.svg` baked-identity) are DELETED once no longer needed by
% default -- set `opts.keepIntermediates=true` to keep them instead (this is exactly the naming
% convention `examples/makeExamplePanelA.m` already uses by hand).
%
% Call with NO arguments to see this help and get a fully-populated default opts struct (required
% fields included as empty placeholders) -- the Bass-wide convention for a new user-facing function.
%
% ax        live axes (NOT yet closed -- stays open when this function returns, same as
%           groupAndTagSvg.m itself; the caller decides when to close it). Box='off' or 'on' both
%           supported (identifyAxisSpine.m); PositionConstraint='innerposition' required.
%           TiledChartLayout-hosted axes (e.g. plotVessels.m output) are NOT supported -- see
%           docs/findings.md.
% outDir    directory to write `<baseName>_tagged.svg` (and, if opts.keepIntermediates, the four
%           intermediate files) into
% baseName  filename stem, e.g. 'panelA' -> panelA_raw.svg / panelA.svg / panelA_tagged.svg / ...
% opts.keepIntermediates  (default false) keep the 4 intermediate SVG files instead of deleting them
% opts.pythonExe          (default 'python3') interpreter used to invoke bakeTransforms.py
%
% result.taggedFile   full path to the final tagged SVG (always kept, regardless of opts)
% result.stats        groupAndTagSvg.m's own per-role counts struct

if nargin == 0
    fprintf(['runPillar1  Runs this repo''s entire pillar-1 pipeline (grouping/tagging) end to end\n' ...
        'for one plain single-axes panel: snapshot -> raw export -> bake -> identity export ->\n' ...
        'identity bake -> group/tag -- producing just the final tagged SVG. Intermediate files are\n' ...
        'deleted by default (opts.keepIntermediates=true keeps them).\n\n' ...
        'ax        live axes (NOT yet closed) -- Box=''off''/''on'' both supported, \n' ...
        '          PositionConstraint=''innerposition'' required; TiledChartLayout NOT supported\n' ...
        'outDir    directory to write outputs into\n' ...
        'baseName  filename stem, e.g. ''panelA'' -> panelA_raw.svg / panelA.svg / panelA_tagged.svg\n' ...
        'opts.keepIntermediates  (default false) keep the 4 intermediate SVG files\n' ...
        'opts.pythonExe          (default ''python3'')\n\n' ...
        'Returns result.taggedFile (path) and result.stats (groupAndTagSvg.m''s own counts).\n']);
    result = struct('ax',[], 'outDir','', 'baseName','', 'keepIntermediates',false, 'pythonExe','python3');
    return
end

if nargin < 4 || isempty(opts); opts = struct(); end
if ~isfield(opts,'keepIntermediates'); opts.keepIntermediates = false; end
if ~isfield(opts,'pythonExe'); opts.pythonExe = 'python3'; end

repoDir = fileparts(mfilename('fullpath'));
bakeScript = fullfile(repoDir, 'bakeTransforms.py');
fig = ancestor(ax, 'figure');

rawFile           = fullfile(outDir, [baseName '_raw.svg']);
bakedFile         = fullfile(outDir, [baseName '.svg']);
identityRawFile   = fullfile(outDir, [baseName '_identity_raw.svg']);
identityBakedFile = fullfile(outDir, [baseName '_identity.svg']);
taggedFile        = fullfile(outDir, [baseName '_tagged.svg']);

snap = snapshotAxesStyle(ax);

print(fig, rawFile, '-dsvg', '-vector');
runBake(opts.pythonExe, bakeScript, rawFile, bakedFile);

dumpIdentitySvg(fig, snap, identityRawFile);
runBake(opts.pythonExe, bakeScript, identityRawFile, identityBakedFile);

stats = groupAndTagSvg(ax, snap, bakedFile, taggedFile, identityBakedFile);

if ~opts.keepIntermediates
    delete(rawFile);
    delete(bakedFile);
    delete(identityRawFile);
    delete(identityBakedFile);
end

result.taggedFile = taggedFile;
result.stats = stats;
end

function runBake(pythonExe, script, infile, outfile)
[status, cmdout] = system(sprintf('%s %s %s %s', pythonExe, script, infile, outfile));
assert(status == 0, 'runPillar1:bakeFailed', 'bakeTransforms.py failed on %s:\n%s', infile, cmdout);
end
