function snap = snapshotAxesStyle(ax)
% snapshotAxesStyle  Capture a per-object STYLE RECIPE for every data-bearing graphics object in a
% live axes, BEFORE export/close -- the ground truth half of a style-fingerprint match against that
% axes' own exported SVG (see matchGraphicsToSvg.m). Deliberately narrow: Line and Patch only (the
% simplest-case scope), color/style attributes only (no geometry) -- geometry/position stays a
% fallback disambiguator for a later, harder-case pass, not needed here.
%
% Each entry's .hex/.fillHex is computed the SAME way MATLAB's own -dsvg exporter apparently does
% (round(channel*255), zero-padded 2-digit hex) -- confirmed by direct empirical round-trip test
% against a real exported SVG (round(Color*255) == the SVG's own stroke="#..." hex, byte for byte),
% NOT assumed from any documented color-space rule.
%
% snap(i) fields: handle, type ('line'|'patch'), hex (stroke color, [] for a Line with
% LineStyle='none'), fillHex ([] unless a Patch/filled), lineStyle, faceAlpha, edgeAlpha,
% displayName, tag, nPts (numel(XData) -- a cheap geometric tie-breaker for same-style candidates).

lines_ = findobj(ax, 'Type', 'line');
patches_ = findobj(ax, 'Type', 'patch');
objs = [lines_(:); patches_(:)];

snap = repmat(struct('handle',[], 'type','', 'hex','', 'fillHex','', 'lineStyle','', ...
    'faceAlpha',[], 'edgeAlpha',[], 'displayName','', 'tag','', 'nPts',0), numel(objs), 1);

for i = 1:numel(objs)
    h = objs(i);
    snap(i).handle = h;
    snap(i).displayName = h.DisplayName;
    snap(i).tag = h.Tag;
    if isa(h,'matlab.graphics.chart.primitive.Line')
        snap(i).type = 'line';
        snap(i).nPts = numel(h.XData);
        snap(i).lineStyle = h.LineStyle;
        if ~strcmp(h.LineStyle,'none') || ~strcmp(h.Marker,'none')
            snap(i).hex = rgbToHex(h.Color);
        end
    else
        snap(i).type = 'patch';
        snap(i).nPts = numel(h.XData);
        snap(i).lineStyle = h.LineStyle;
        if ~strcmp(h.EdgeColor,'none') && ~(ischar(h.EdgeColor))
            snap(i).hex = rgbToHex(h.EdgeColor);
        end
        if ~(ischar(h.FaceColor) && strcmp(h.FaceColor,'none'))
            fc = h.FaceColor;
            if ischar(fc); fc = matlabColorToRGB(fc); end
            snap(i).fillHex = rgbToHex(fc);
        end
        snap(i).faceAlpha = h.FaceAlpha;
        snap(i).edgeAlpha = h.EdgeAlpha;
    end
end
end

function hex = rgbToHex(rgb)
if ischar(rgb); rgb = matlabColorToRGB(rgb); end
hex = sprintf('#%02x%02x%02x', round(rgb(1)*255), round(rgb(2)*255), round(rgb(3)*255));
end

function rgb = matlabColorToRGB(c)
switch c
    case 'r'; rgb = [1 0 0];
    case 'g'; rgb = [0 1 0];
    case 'b'; rgb = [0 0 1];
    case 'k'; rgb = [0 0 0];
    case 'w'; rgb = [1 1 1];
    case 'y'; rgb = [1 1 0];
    case 'm'; rgb = [1 0 1];
    case 'c'; rgb = [0 1 1];
    otherwise
        error('snapshotAxesStyle:unknownColorChar', 'unrecognized MATLAB color char: %s', c);
end
end
