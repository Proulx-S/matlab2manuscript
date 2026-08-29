% NOTE: validates syncPanel.m (2026-08-29) -- the pillar-2 sync/insert operation. Covers: (1)
% first-time insertion at opts.defaultInnerPosition, and that a no-op resync recovers the same
% InnerPosition it just placed; (2) resync after a SIMULATED human edit (this environment has no real
% vector editor -- see syncPanel.m's own "KNOWN VALIDATION GAP" note) correctly recovers the new
% InnerPosition, including an aspect-ratio change, via an analytically-predicted expected value, not
% just "didn't error"; (3) two panels sharing one composed figure produce no id collisions, and
% resyncing one panel does not disturb the other's already-placed content; (4) a simulated rotation
% is detected and rejected rather than silently mishandled.
repoDir = fileparts(fileparts(mfilename('fullpath')));
addpath(repoDir);
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end

function ax = buildSyncTestPanel(fig)
ax = axes(fig);
ax.Units = 'normalized';
ax.PositionConstraint = 'innerposition';
ax.InnerPosition = [0.15 0.15 0.7 0.7];   % overwritten by syncPanel via innerPositionOverride
ax.Box = 'off';
plot(ax, 0:0.5:20, 5 + 0.3*sin(2*pi*(0:0.5:20)/5), 'Color',[0.9 0.7 0.1], 'LineWidth', 2);
ax.XLabel.String = 'time (s)';
ax.YLabel.String = 'signal';
drawnow;
end

function fig = newFig()
fig = figure('Visible','off');
fig.Units = 'centimeters'; fig.Position = [2 2 16 10];
end

function simulateExternalEdit(composedFile, panId, scaleXY, translateXY)
% Stands in for a human's edit in a vector editor: wraps `{panId}-root` in a NEW ancestor
% <g transform="translate(tx,ty) scale(sx,sy)">, the compound (non-matrix) transform-list form
% bakeTransforms.py's own matrix()-only parser can't handle (see resolveElementCTM.m's header) --
% deliberately exercising the general resolver, not the MATLAB-export-specific one.
doc = xmlread(composedFile);
docRoot = doc.getDocumentElement();
panelNode = findByIdLocal(docRoot, [panId '-root']);
assert(~isempty(panelNode), 'simulateExternalEdit: panel "%s" not found in %s', panId, composedFile);
parent = panelNode.getParentNode();
wrapper = doc.createElement('g');
wrapper.setAttribute('transform', sprintf('translate(%.10g,%.10g) scale(%.10g,%.10g)', ...
    translateXY(1), translateXY(2), scaleXY(1), scaleXY(2)));
parent.replaceChild(wrapper, panelNode);
wrapper.appendChild(panelNode);
xmlwrite(composedFile, doc);
end

function simulateRotation(composedFile, panId, angleDeg)
doc = xmlread(composedFile);
docRoot = doc.getDocumentElement();
panelNode = findByIdLocal(docRoot, [panId '-root']);
assert(~isempty(panelNode), 'simulateRotation: panel "%s" not found', panId);
parent = panelNode.getParentNode();
wrapper = doc.createElement('g');
wrapper.setAttribute('transform', sprintf('rotate(%.10g)', angleDeg));
parent.replaceChild(wrapper, panelNode);
wrapper.appendChild(panelNode);
xmlwrite(composedFile, doc);
end

function node = findByIdLocal(root, id)
node = [];
els = root.getElementsByTagName('*');
for i = 0:els.getLength()-1
    n = els.item(i);
    if n.hasAttribute('id') && strcmp(char(n.getAttribute('id')), id); node = n; return; end
end
end

function str = xmlNodeToString(node)
% Serializes JUST this one DOM node and its descendants (not the whole Document, unlike xmlwrite) --
% used to byte-compare one panel's own subtree before/after an unrelated panel's resync, which
% xmlwrite alone (whole-document only) can't isolate. NOTE: javax.xml.transform.Transformer with a
% DOMSource(node) does NOT do this in this environment -- confirmed empirically it serializes the
% node's entire OWNER DOCUMENT regardless of which node is passed (surprising, but real -- see this
% test file's own development notes/docs/findings.md). DOM Level 3 LSSerializer.writeToString(node)
% is correctly scoped to just the given node, so that's used instead.
domImpl = node.getOwnerDocument().getImplementation();
lsImpl = domImpl.getFeature('LS', '3.0');
serializer = lsImpl.createLSSerializer();
str = char(serializer.writeToString(node));
end

% ============================== (1) first-time insertion + no-op resync ==============================
composedFile = fullfile(outDir, 'synctest.svg');
if isfile(composedFile); delete(composedFile); end

fig1 = newFig(); ax1 = buildSyncTestPanel(fig1);
opts = struct('defaultInnerPosition', [0.1 0.1 0.35 0.35]);
result1 = syncPanel(ax1, outDir, 'synctest', 'A', opts);
close(fig1);
assert(isequal(result1.innerPosition, opts.defaultInnerPosition), 'first insertion should use opts.defaultInnerPosition exactly');
assert(isfile(composedFile), 'syncPanel did not create the composed file');
fprintf('first-time insertion: panel A placed at defaultInnerPosition\n');

fig1b = newFig(); ax1b = buildSyncTestPanel(fig1b);
result1b = syncPanel(ax1b, outDir, 'synctest', 'A', opts);
close(fig1b);
assert(max(abs(result1b.innerPosition - opts.defaultInnerPosition)) < 0.01, ...
    'a no-op resync (no edit made) should recover ~the same InnerPosition it just placed, got [%s]', num2str(result1b.innerPosition));
fprintf('no-op resync recovers the same InnerPosition (within tolerance): PASS\n');

% ============================== (2) resync after a simulated human edit ==============================
% Analytically predict the expected new InnerPosition rather than just checking "no error": confirms
% resolveElementCTM.m's transform-list composition and the box->InnerPosition inversion are both
% actually correct, not just plausible.
canvasSizePt = [8.5 11] * 72;   % US-Letter default
ip0 = opts.defaultInnerPosition;
x0 = ip0(1)*canvasSizePt(1); x1 = (ip0(1)+ip0(3))*canvasSizePt(1);
y1raw = canvasSizePt(2) - ip0(2)*canvasSizePt(2); y0raw = canvasSizePt(2) - (ip0(2)+ip0(4))*canvasSizePt(2);
scaleXY = [1.4 0.8]; translateXY = [50 30];   % deliberately anisotropic -- an aspect-ratio change
% transform="translate(tx,ty) scale(sx,sy)": combined = Translate ∘ Scale, so p' = (sx*x+tx, sy*y+ty)
x0n = scaleXY(1)*x0 + translateXY(1); x1n = scaleXY(1)*x1 + translateXY(1);
y0n = scaleXY(2)*y0raw + translateXY(2); y1n = scaleXY(2)*y1raw + translateXY(2);
expectedIP = [x0n/canvasSizePt(1), 1 - y1n/canvasSizePt(2), (x1n-x0n)/canvasSizePt(1), (y1n-y0n)/canvasSizePt(2)];

simulateExternalEdit(composedFile, 'A', scaleXY, translateXY);
fig1c = newFig(); ax1c = buildSyncTestPanel(fig1c);
result1c = syncPanel(ax1c, outDir, 'synctest', 'A', opts);
close(fig1c);
fprintf('simulated edit: expected InnerPosition=[%s], recovered=[%s]\n', num2str(expectedIP), num2str(result1c.innerPosition));
assert(max(abs(result1c.innerPosition - expectedIP)) < 0.005, ...
    'recovered InnerPosition after simulated edit does not match the analytically-predicted value');
fprintf('resync after simulated edit (including an aspect-ratio change) recovers the correct InnerPosition: PASS\n');

% ============================== (3) multi-panel independence ==============================
fig2 = newFig(); ax2 = buildSyncTestPanel(fig2);
optsB = struct('defaultInnerPosition', [0.55 0.55 0.35 0.35]);
resultB1 = syncPanel(ax2, outDir, 'synctest', 'B', optsB);
close(fig2);

docBefore = xmlread(composedFile);
txt = fileread(composedFile);
ids = regexp(txt, 'id="([^"]*)"', 'tokens');
ids = cellfun(@(c) c{1}, ids, 'UniformOutput', false);
assert(numel(ids) == numel(unique(ids)), 'duplicate id found across panels A and B in the composed file');
fprintf('two panels (A, B) share the composed file with no duplicate ids: PASS\n');

panelBNodeBefore = findByIdLocal(docBefore.getDocumentElement(), 'B-root');
panelBTextBefore = xmlNodeToString(panelBNodeBefore);

% Resync A again (another edit) -- B must be untouched.
simulateExternalEdit(composedFile, 'A', [1.1 1.1], [10 10]);
fig1d = newFig(); ax1d = buildSyncTestPanel(fig1d);
syncPanel(ax1d, outDir, 'synctest', 'A', opts);
close(fig1d);

docAfter = xmlread(composedFile);
panelBNodeAfter = findByIdLocal(docAfter.getDocumentElement(), 'B-root');
panelBTextAfter = xmlNodeToString(panelBNodeAfter);
assert(strcmp(panelBTextBefore, panelBTextAfter), 'resyncing panel A disturbed panel B''s already-placed content');
fprintf('resyncing panel A leaves panel B''s content byte-identical: PASS\n');

% ============================== (4) rotation rejection ==============================
simulateRotation(composedFile, 'B', 15);
fig2b = newFig(); ax2b = buildSyncTestPanel(fig2b);
threw = false;
try
    syncPanel(ax2b, outDir, 'synctest', 'B', optsB);
catch err
    threw = true;
    assert(strcmp(err.identifier, 'syncPanel:rotatedPanel'), 'expected syncPanel:rotatedPanel, got "%s": %s', err.identifier, err.message);
end
close(fig2b);
assert(threw, 'syncPanel should have rejected a rotated panel, but did not error');
fprintf('rotated panel correctly rejected: PASS\n');

% ============================== zero-arg call ==============================
defaultOpts = syncPanel();
assert(isstruct(defaultOpts) && isfield(defaultOpts,'defaultInnerPosition') ...
    && isequal(defaultOpts.defaultInnerPosition,[0.1 0.1 0.35 0.35]), ...
    'zero-arg call did not return a properly-populated default opts struct');
fprintf('zero-arg call returns default opts correctly\n');

disp('SYNC PANEL VALIDATION: PASS');
