function rects = findClosedRectPaths(doc)
% findClosedRectPaths  Every axis-aligned closed-rectangle <path> in doc -- a MATLAB-exported one
% serializes (post-bake) as "M x0,y0 L x1,y0 L x1,y1 L x0,y1 L x0,y0" (5 point commands, first==last,
% axis-aligned edges). Shared by identifyLegend.m (legend box) and groupAndTagSvg.m's own furniture
% identification (figure/axes background rects) -- extracted here rather than duplicated, since both
% need the exact same pattern match.
%
% rects{i}: struct('node', the Java DOM <path> element, 'rect', [x0 y0 x1 y1]).
paths = doc.getElementsByTagName('path');
rects = {};
for k = 0:paths.getLength()-1
    node = paths.item(k);
    d = char(node.getAttribute('d'));
    nums = regexp(d, '[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?', 'match');
    vals = str2double(nums);
    if numel(vals) ~= 10; continue; end
    pts = reshape(vals, 2, [])';
    if any(abs(pts(1,:) - pts(5,:)) > 1e-6); continue; end
    xs = pts(1:4,1); ys = pts(1:4,2);
    isAxisAligned = numel(unique(round(xs,4))) == 2 && numel(unique(round(ys,4))) == 2;
    if ~isAxisAligned; continue; end
    rects{end+1} = struct('node',node,'rect',[min(xs) min(ys) max(xs) max(ys)]); %#ok<AGROW>
end
end
