function matches = matchGraphicsToSvg(snap, svgFile, identitySvgFile, canvasSizePt, excludeNodes)
% matchGraphicsToSvg  Match each snapshotAxesStyle.m entry to its corresponding SVG element(s) in
% svgFile. Two matching strategies:
%
% (1) REAL-COLOR fingerprint (used when identitySvgFile is omitted, the original strategy): exact
%     style fingerprint (stroke/fill hex) with a point-count tie-break for genuinely ambiguous cases.
%     Errors loudly (never silently guesses) on: zero candidates for a non-empty-style snapshot
%     entry, or more than one candidate surviving both the color AND point-count filters
%     (ambiguousMatch) -- e.g. two Lines that happen to share both the same real color AND the same
%     point count are genuinely unresolvable this way (confirmed real -- see test_edge_cases.m Case
%     B) -- same "loud, not silent" discipline the prior engine's
%     matchManuscriptFigureGeometricElement.m established, kept here since it proved the right call.
%
% (2) IDENTITY-COLOR cross-reference (used when identitySvgFile IS given -- see dumpIdentitySvg.m):
%     look up each object's own shape in a THROWAWAY identity-colored export by its unique,
%     collision-proof identity color (computeIdentityColors.m -- encodes (seriesIndex, roleCode,
%     occurrence), not just a bare index, so the SAME Tag-based pairing key groupAndTagSvg.m's
%     'value'/'conf' sub-grouping uses is baked into the identity export too), then find the shape
%     with that EXACT SAME geometry in the real svgFile (geometry is identical between the two
%     exports since only color differs) -- so the real SVG's own colors never need to be unique at
%     all. This is strictly more robust than (1): it resolves the Case B ambiguity above outright,
%     since identity colors can never collide by construction. `groupAndTagSvg.m` always uses this
%     path; (1) is kept only for backward compatibility / standalone use without an identity export.
%
% matches(i): svgTag ('polyline'|'path'), points (Nx2, SVG-space), node (the matched Java DOM
% element itself -- kept live against the SAME doc used to build these matches, so a caller doing
% further DOM surgery, e.g. groupAndTagSvg.m's tagging pass, can setAttribute() on it directly
% instead of re-deriving it from points/geometry), candidateCountBeforeTiebreak.
%
% Accepts either a file path (opens its own xmlread doc) or an already-open org.w3c.dom.Document for
% BOTH svgFile and identitySvgFile -- pass an already-open doc for svgFile when a caller
% (groupAndTagSvg.m) needs matches(i).node to stay valid against a doc it will go on to mutate and
% serialize itself.
%
% (3) IMAGE geometric correlation (2026-08-30, snap(i).type=='image' -- a heatmap/`image`/`imagesc`
%     dataseries): NEVER uses either color-based strategy above -- a raster image's "color" is baked
%     inside a compressed PNG blob, not a plain SVG attribute string, so exact-hex-string matching
%     doesn't transfer, and isn't needed anyway: each Image's own live XData/YData already fully
%     determines its expected box (snapshotAxesStyle.m's own computeImageExpectedFracBox), so there's
%     no color ambiguity to resolve the way there is for Line/Patch. `canvasSizePt` (REQUIRED when
%     any snap(i).type=='image') scales that normalized-fraction box into SVG points, mirroring
%     identifyAxisSpine.m's own two-stage approach.
%
%     Mechanism (confirmed empirically before writing this, 2026-08-30): an `<image>` element's OWN
%     x/y/width/height attributes are ALWAYS in a local pattern-TILE coordinate frame (typically
%     x="0" y="0"), never the real canvas position, for ANY image content (not colorbar-specific, as
%     the previous round's own comment assumed) -- MATLAB wraps every embedded raster in a `<pattern>`
%     (in `<defs>`), and the actual canvas placement lives entirely on whichever OTHER element paints
%     with `fill="url(#patternId)"` -- confirmed to always be a plain closed-rect <path>, the exact
%     same 5-point M-L-L-L-L shape findClosedRectPaths.m already parses for figure/axes-background/
%     legend-box/colorbar-gradient (identifyColorbar.m already established and documents this same
%     "the pattern itself is irrelevant to placement" mechanism for the colorbar's own gradient box).
%     So: every closed-rect <path> whose fill (own or inherited, attrOrParent) references a pattern
%     is a placement candidate, bbox-matched against each Image's expected box within this repo's
%     usual ~1.5pt tolerance -- no <pattern>/<image> parsing needed for placement at all. Zero or
%     multiple matches errors loudly (same "refuse to guess" posture as strategies (1)/(2) above)
%     rather than silently guessing.

if nargin < 5; excludeNodes = {}; end

if ischar(svgFile) || isstring(svgFile)
    doc = xmlread(svgFile);
else
    doc = svgFile;
end
polylines = doc.getElementsByTagName('polyline');
paths = doc.getElementsByTagName('path');

useIdentity = nargin >= 3 && ~isempty(identitySvgFile);
if useIdentity
    if ischar(identitySvgFile) || isstring(identitySvgFile)
        identityDoc = xmlread(identitySvgFile);
    else
        identityDoc = identitySvgFile;
    end
    identityPolylines = identityDoc.getElementsByTagName('polyline');
    identityPaths = identityDoc.getElementsByTagName('path');
    % computeIdentityColors.m encodes (seriesIndex, roleCode, occurrence) per object -- the SAME
    % Tag-based pairing key assignSeriesIndices.m/groupAndTagSvg.m use for 'value'/'conf' grouping
    % (Seb's own ask 2026-08-29, "pairing-by-identity": Tag replaces the previous DisplayName-based
    % key, see assignSeriesIndices.m's own header for why) -- computed ONCE here, shared by
    % dumpIdentitySvg.m (which assigned these exact colors before export) so the two can never
    % silently disagree.
    identityHexList = computeIdentityColors(snap);
end

matches = repmat(struct('svgTag','', 'points',[], 'node',[], 'candidateCountBeforeTiebreak',0), numel(snap), 1);

for i = 1:numel(snap)
    s = snap(i);
    if strcmp(s.type, 'image')
        assert(nargin >= 4 && ~isempty(canvasSizePt), 'matchGraphicsToSvg:missingCanvasSize', ...
            'object %d is an Image dataseries -- canvasSizePt is required to match it (see this file''s own header).', i);
        matches(i) = matchImageToSvg(s, doc, canvasSizePt, excludeNodes, i);
        continue
    end
    if strcmp(s.type, 'line')
        if isempty(s.hex)
            continue   % no visible stroke -- nothing to match (e.g. a hidden helper line)
        end
        matches(i).svgTag = 'polyline';
    else
        % Patch: prefer fill hex (this project's own CI-band/patch usage is always a filled
        % region), fall back to stroke hex if unfilled.
        targetHex = s.fillHex;
        isFillMatch = true;
        if isempty(targetHex)
            targetHex = s.hex;
            isFillMatch = false;
        end
        if isempty(targetHex)
            continue
        end
        matches(i).svgTag = 'path';
    end

    if useIdentity
        idHex = identityHexList{i};
        if strcmp(s.type,'line')
            idCands = findByStrokeHex(identityPolylines, idHex);
        else
            idCands = findByFillOrStrokeHex(identityPaths, idHex, isFillMatch);
        end
        matches(i).candidateCountBeforeTiebreak = numel(idCands);
        assert(~isempty(idCands), 'matchGraphicsToSvg:noMatch', ...
            'object %d (type=%s, displayName=%s): no identity-svg %s candidate with identity color %s found.', ...
            i, s.type, s.displayName, matches(i).svgTag, idHex);

        % Unlike the real-color path, MORE THAN ONE identity-color candidate can ONLY mean this
        % object's own shape was split into multiple fragments (an axis-clip-boundary split --
        % confirmed real, see test_edge_cases.m Case C) -- identity colors are unique per OBJECT by
        % construction, so a second candidate can never belong to a DIFFERENT object the way a real-
        % color collision could. Point-count tie-break still applies (fragment reassembly remains a
        % deliberate, documented non-goal -- see below).
        if numel(idCands) > 1
            idCands = filterByPointCount(idCands, s.nPts, matches(i).svgTag);
        end
        assert(numel(idCands) == 1, 'matchGraphicsToSvg:ambiguousMatch', ...
            ['object %d (type=%s, displayName=%s): %d identity-colored candidates found -- this can ' ...
             'only mean an axis-clip-boundary split (identity colors can''t collide across objects), ' ...
             'and point-count tie-break could not resolve which fragment is the whole curve.'], ...
            i, s.type, s.displayName, numel(idCands));

        targetPts = parseGeometry(idCands{1}, matches(i).svgTag);
        assert(size(targetPts,1) == s.nPts, 'matchGraphicsToSvg:unmatchedPointCount', ...
            ['object %d (type=%s, displayName=%s): the identity-matched %s has %d point(s), live data ' ...
             'has %d -- likely an axis-clip-boundary split; refusing to return a partial match.'], ...
            i, s.type, s.displayName, matches(i).svgTag, size(targetPts,1), s.nPts);

        % Cross-reference into the REAL svg by geometry -- identical between the two exports since
        % only color differs, so the real svg's own colors are never consulted here at all.
        if strcmp(matches(i).svgTag,'polyline'); realNodeList = polylines; else; realNodeList = paths; end
        realCands = findByGeometry(realNodeList, matches(i).svgTag, targetPts);
        assert(~isempty(realCands), 'matchGraphicsToSvg:noGeometryMatch', ...
            'object %d (type=%s, displayName=%s): identity-matched geometry not found in the real SVG -- did the two exports diverge?', ...
            i, s.type, s.displayName);
        assert(numel(realCands) == 1, 'matchGraphicsToSvg:ambiguousGeometryMatch', ...
            'object %d (type=%s, displayName=%s): %d shapes in the real SVG share the identity-matched geometry exactly -- cannot disambiguate.', ...
            i, s.type, s.displayName, numel(realCands));
        matches(i).node = realCands{1};
        matches(i).points = targetPts;
        continue
    end

    % --- real-color fingerprint path (no identity SVG supplied) ---
    if strcmp(s.type,'line')
        cands = findByStrokeHex(polylines, s.hex);
    else
        cands = findByFillOrStrokeHex(paths, targetHex, isFillMatch);
    end

    matches(i).candidateCountBeforeTiebreak = numel(cands);
    assert(~isempty(cands), 'matchGraphicsToSvg:noMatch', ...
        'object %d (type=%s, displayName=%s): no SVG %s candidate with matching color found.', ...
        i, s.type, s.displayName, matches(i).svgTag);

    % Point-count check applies EVEN with a single color candidate -- MATLAB's own vector export
    % can split one Line into multiple SVG polylines when its data crosses the axis clip boundary
    % (confirmed real, reproducible gap -- see test_edge_cases.m Case C), so "exactly one candidate
    % survived the color filter" does NOT by itself mean "this candidate is the whole curve." A
    % single split fragment sharing this object's color would otherwise pass silently with the
    % wrong point count -- checked here instead, so it fails loudly (unmatchedPointCount) rather
    % than returning a truncated match. Reassembling split fragments is a real, known follow-up
    % (the prior engine attempted and reverted a fragment-concatenation fix as half-working) --
    % deliberately NOT attempted here; this prototype's job is to fail loudly on it, not silently
    % succeed with partial data.
    if numel(cands) > 1
        cands = filterByPointCount(cands, s.nPts, matches(i).svgTag);
    end
    assert(numel(cands) == 1, 'matchGraphicsToSvg:ambiguousMatch', ...
        ['object %d (type=%s, displayName=%s): %d candidates share this color and point count -- ' ...
         'cannot disambiguate with this prototype''s current signal set.'], ...
        i, s.type, s.displayName, numel(cands));

    matches(i).node = cands{1};
    matches(i).points = parseGeometry(cands{1}, matches(i).svgTag);
    assert(size(matches(i).points,1) == s.nPts, 'matchGraphicsToSvg:unmatchedPointCount', ...
        ['object %d (type=%s, displayName=%s): the sole color-matching SVG %s has %d point(s), ' ...
         'live data has %d -- likely an axis-clip-boundary split (see file header); refusing to ' ...
         'return a partial match.'], ...
        i, s.type, s.displayName, matches(i).svgTag, size(matches(i).points,1), s.nPts);
end
end

function m = matchImageToSvg(s, doc, canvasSizePt, excludeNodes, snapIdx)
% matchImageToSvg  See this file's own header, strategy (3). Converts s.expectedFracBox (normalized
% figure fraction, MATLAB-space bottom-left origin -- snapshotAxesStyle.m) to SVG points the same way
% identifyAxisSpine.m's own expectedBoxPt does, then bbox-matches every pattern-filled closed-rect
% <path> in doc against it. excludeNodes (e.g. a colorbar's own boxNode/decorationNodes, see
% groupAndTagSvg.m's own caller comment) skips candidates already claimed elsewhere -- a colorbar's
% gradient box uses this EXACT SAME pattern-filled-rect mechanism, confirmed a real false-positive
% risk while building this (2026-08-30), not just a theoretical one.
W = canvasSizePt(1); H = canvasSizePt(2);
fb = s.expectedFracBox;
x0 = fb(1)*W; x1 = fb(3)*W;
yBottomMatlab = fb(2)*H; yTopMatlab = fb(4)*H;
y0 = H - yTopMatlab; y1 = H - yBottomMatlab;
expectedBoxPt = [x0 y0 x1 y1];

tol = 1.5;   % same tolerance family as identifyAxisSpine.m/identifyLegend.m (72/ScreenPixelsPerInch rounding)
rects = findClosedRectPaths(doc);
cands = {};
for ri = 1:numel(rects)
    if isNodeInList(rects{ri}.node, excludeNodes); continue; end
    fillVal = attrOrParent(rects{ri}.node, 'fill');
    if isempty(regexp(fillVal, '^url\(#', 'once')); continue; end
    if all(abs(rects{ri}.rect - expectedBoxPt) < tol)
        cands{end+1} = rects{ri}.node; %#ok<AGROW>
    end
end
m = struct('svgTag','path', 'points',[], 'node',[], 'candidateCountBeforeTiebreak',numel(cands));
assert(~isempty(cands), 'matchGraphicsToSvg:noImageCandidate', ...
    'object %d (type=image, tag=%s): no pattern-filled closed-rect <path> found near the expected box [%.2f %.2f %.2f %.2f] -- did baking/export change?', ...
    snapIdx, s.tag, expectedBoxPt);
assert(numel(cands) == 1, 'matchGraphicsToSvg:ambiguousImageMatch', ...
    'object %d (type=image, tag=%s): %d pattern-filled closed-rect <path> candidates match the expected box -- cannot disambiguate.', ...
    snapIdx, s.tag, numel(cands));
m.node = cands{1};
end

function tf = isNodeInList(node, list)
tf = false;
for i = 1:numel(list)
    if ~isempty(list{i}) && node.isSameNode(list{i}); tf = true; return; end
end
end

function cands = findByStrokeHex(nodeList, hex)
cands = {};
for k = 0:nodeList.getLength()-1
    node = nodeList.item(k);
    stroke = attrOrParent(node, 'stroke');
    if strcmpi(stroke, hex)
        cands{end+1} = node; %#ok<AGROW>
    end
end
end

function cands = findByFillOrStrokeHex(nodeList, hex, isFillMatch)
cands = {};
attrName = 'fill';
if ~isFillMatch; attrName = 'stroke'; end
for k = 0:nodeList.getLength()-1
    node = nodeList.item(k);
    val = attrOrParent(node, attrName);
    if strcmpi(val, hex)
        cands{end+1} = node; %#ok<AGROW>
    end
end
end

function cands = findByGeometry(nodeList, svgTag, targetPts)
cands = {};
for k = 0:nodeList.getLength()-1
    node = nodeList.item(k);
    pts = parseGeometry(node, svgTag);
    if isequal(size(pts), size(targetPts)) && all(abs(pts(:) - targetPts(:)) < 1e-6)
        cands{end+1} = node; %#ok<AGROW>
    end
end
end

function val = attrOrParent(node, attrName)
% MATLAB's -dsvg exporter puts paint attributes on the enclosing <g>, not the leaf element itself
% (confirmed empirically -- see snapshotAxesStyle.m's own header) -- check the node first, then walk
% up parents until found or the document root is reached.
val = '';
n = node;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute(attrName)
        val = char(n.getAttribute(attrName));
        return
    end
    n = n.getParentNode();
end
end

function cands = filterByPointCount(cands, nPts, svgTag)
keep = {};
for i = 1:numel(cands)
    pts = parseGeometry(cands{i}, svgTag);
    if size(pts,1) == nPts
        keep{end+1} = cands{i}; %#ok<AGROW>
    end
end
cands = keep;
end

function pts = parseGeometry(node, svgTag)
if strcmp(svgTag, 'polyline')
    str = char(node.getAttribute('points'));
    vals = sscanf(str, '%f,%f');
    pts = reshape(vals, 2, [])';
else
    str = char(node.getAttribute('d'));
    nums = regexp(str, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match');
    vals = str2double(nums);
    pts = reshape(vals, 2, [])';
    % A closed patch path (MATLAB's own -dsvg exporter closes a filled polygon by explicitly
    % repeating its first vertex as its own last vertex, not via a separate 'Z' command -- confirmed
    % real: a genuine 83-vs-82 off-by-one against live nPts otherwise, first hit validating a real
    % confidence-band Patch end-to-end) -- drop that repeated closing vertex so the point count
    % matches live data exactly, not "live data + 1".
    if size(pts,1) > 1 && all(abs(pts(1,:) - pts(end,:)) < 1e-6)
        pts = pts(1:end-1,:);
    end
end
end
