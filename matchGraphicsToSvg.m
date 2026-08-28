function matches = matchGraphicsToSvg(snap, svgFile)
% matchGraphicsToSvg  Match each snapshotAxesStyle.m entry to its corresponding SVG element(s) in
% svgFile, by exact style fingerprint (stroke/fill hex, first) with a point-count tie-break for
% genuinely ambiguous cases (documented, not silently guessed). Prototype scope: polyline (Line)
% and path/polygon (Patch fill) candidates only -- the primitive types the simplest real case
% (plotVessels single-metric line panel) actually produces.
%
% Errors loudly (never silently guesses) on: zero candidates for a non-empty-style snapshot entry,
% or more than one candidate surviving both the color AND point-count filters (ambiguousMatch) --
% same "loud, not silent" discipline the prior engine's matchManuscriptFigureGeometricElement.m
% established, kept here since it proved the right call.
%
% matches(i): svgTag ('polyline'|'path'), points (Nx2, SVG-space), candidateCountBeforeTiebreak.

doc = xmlread(svgFile);
polylines = doc.getElementsByTagName('polyline');
paths = doc.getElementsByTagName('path');

matches = repmat(struct('svgTag','', 'points',[], 'candidateCountBeforeTiebreak',0), numel(snap), 1);

for i = 1:numel(snap)
    s = snap(i);
    if strcmp(s.type, 'line')
        if isempty(s.hex)
            continue   % no visible stroke -- nothing to match (e.g. a hidden helper line)
        end
        cands = findByStrokeHex(polylines, s.hex);
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
        cands = findByFillOrStrokeHex(paths, targetHex, isFillMatch);
        matches(i).svgTag = 'path';
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

    matches(i).points = parseGeometry(cands{1}, matches(i).svgTag);
    assert(size(matches(i).points,1) == s.nPts, 'matchGraphicsToSvg:unmatchedPointCount', ...
        ['object %d (type=%s, displayName=%s): the sole color-matching SVG %s has %d point(s), ' ...
         'live data has %d -- likely an axis-clip-boundary split (see file header); refusing to ' ...
         'return a partial match.'], ...
        i, s.type, s.displayName, matches(i).svgTag, size(matches(i).points,1), s.nPts);
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
end
end
