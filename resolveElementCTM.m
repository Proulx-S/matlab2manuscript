function T = resolveElementCTM(node)
% resolveElementCTM  The net 2D affine transform (as [a b c d e f], SVG matrix() convention) mapping
% `node`'s own local coordinate space to the document root's coordinate space -- composed by walking
% `node`'s ancestor chain and multiplying every `transform` attribute found along the way.
%
% Built for syncPanel.m (2026-08-29): unlike bakeTransforms.py, which only ever has to handle
% MATLAB's own `-dsvg` export (confirmed to emit `transform="matrix(...)"` exclusively, nothing else
% -- see that file's own `MATRIX_RE.fullmatch`, which errors on anything else), a composed multi-
% panel figure may have been re-saved by an external vector editor, which can add compound,
% multi-function transform-list strings (`translate(...) scale(...) rotate(...)`) to a panel's
% wrapper group, or bake edits directly into raw coordinates with no transform attribute at all.
% This is a general SVG transform-list resolver, not a MATLAB-export-specific one -- do not merge it
% into/replace bakeTransforms.py's own parser, which is deliberately narrow for a different reason
% (documented there).
%
% Only matrix()/translate()/scale()/rotate() are supported (no skewX/skewY) -- this repo's own
% geometry never needs shear, the same stance bakeTransforms.py already takes for the same reason.
% A shear/skew transform, if ever encountered, errors loudly rather than being silently mishandled.
chain = {};
n = node;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute('transform')
        chain{end+1} = char(n.getAttribute('transform')); %#ok<AGROW>
    else
        chain{end+1} = '';
    end
    n = n.getParentNode();
end
% chain is [node, parent, grandparent, ..., topmost], innermost-first -- reverse so folding
% outermost-first yields T = T_topmost * ... * T_parent * T_node (parent transforms apply AFTER a
% node's own local transform, i.e. parent is "outer").
chain = fliplr(chain);
T = [1 0 0 1 0 0];
for i = 1:numel(chain)
    Ti = parseSvgTransformList(chain{i});
    T = composeAffine(T, Ti);
end
end

function T = parseSvgTransformList(str)
% One or more space-separated `func(args)` transforms, combined left-to-right per the SVG spec
% (leftmost is applied LAST, i.e. is the outermost of this list -- combined = F1*F2*F3*...).
T = [1 0 0 1 0 0];
if isempty(strtrim(str)); return; end
toks = regexp(str, '(\w+)\s*\(([^)]*)\)', 'tokens');
assert(~isempty(toks), 'resolveElementCTM:unparseableTransform', ...
    'could not parse transform="%s" as an SVG transform-list.', str);
for i = 1:numel(toks)
    name = toks{i}{1};
    nums = sscanf(strrep(toks{i}{2}, ',', ' '), '%f')';
    switch name
        case 'matrix'
            assert(numel(nums) == 6, 'resolveElementCTM:badMatrix', 'matrix() needs 6 args, got %d.', numel(nums));
            F = nums;
        case 'translate'
            tx = nums(1); ty = 0; if numel(nums) >= 2; ty = nums(2); end
            F = [1 0 0 1 tx ty];
        case 'scale'
            sx = nums(1); sy = sx; if numel(nums) >= 2; sy = nums(2); end
            F = [sx 0 0 sy 0 0];
        case 'rotate'
            ang = nums(1) * pi/180;
            R = [cos(ang) sin(ang) -sin(ang) cos(ang) 0 0];
            if numel(nums) >= 3
                cx = nums(2); cy = nums(3);
                F = composeAffine(composeAffine([1 0 0 1 cx cy], R), [1 0 0 1 -cx -cy]);
            else
                F = R;
            end
        otherwise
            error('resolveElementCTM:unsupportedTransform', ...
                'unsupported transform function "%s()" in "%s" (only matrix/translate/scale/rotate handled -- no shear, same stance as bakeTransforms.py).', name, str);
    end
    T = composeAffine(T, F);
end
end

function C = composeAffine(outer, inner)
% outer applied AFTER inner (outer ∘ inner) -- same convention/algebra as bakeTransforms.py's own
% `compose()`, duplicated here rather than shared because that file is Python and this is MATLAB.
oa=outer(1); ob=outer(2); oc=outer(3); od=outer(4); oe=outer(5); of=outer(6);
ia=inner(1); ib=inner(2); ic=inner(3); id_=inner(4); ie=inner(5); if_=inner(6);
a = oa*ia + oc*ib;
b = ob*ia + od*ib;
c = oa*ic + oc*id_;
d = ob*ic + od*id_;
e = oa*ie + oc*if_ + oe;
f = ob*ie + od*if_ + of;
C = [a b c d e f];
end
