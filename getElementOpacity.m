function op = getElementOpacity(node)
% getElementOpacity  Resolves an element's effective 'stroke-opacity' by walking up ancestors --
% MATLAB's -dsvg exporter puts style attributes on the enclosing <g>, not the leaf itself (same
% convention matchGraphicsToSvg.m's own attrOrParent relies on). Defaults to 1 (opaque) if never
% set, the correct SVG default. Shared by identifyAxisSpine.m (excluding gridlines, which are always
% drawn with a fractional opacity, from spine/tick candidacy) and groupAndTagSvg.m's own furniture
% identification (finding those same gridlines to group them).
op = 1;
n = node;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute('stroke-opacity')
        op = str2double(char(n.getAttribute('stroke-opacity')));
        return
    end
    n = n.getParentNode();
end
end
