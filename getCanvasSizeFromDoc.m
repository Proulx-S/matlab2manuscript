function sz = getCanvasSizeFromDoc(doc)
% getCanvasSizeFromDoc  [width height] of an svg document's own viewBox, in its native coordinate
% units (SVG points, for a MATLAB -dsvg export) -- shared by identifyAxisSpine.m/identifyLegend.m/
% groupAndTagSvg.m so each doesn't re-derive it (and to keep the parse in exactly one place).
root = doc.getDocumentElement();
vb = char(root.getAttribute('viewBox'));
parts = sscanf(vb, '%f %f %f %f');
assert(numel(parts) == 4, 'getCanvasSizeFromDoc:badViewBox', 'could not parse viewBox="%s".', vb);
sz = [parts(3) parts(4)];
end
