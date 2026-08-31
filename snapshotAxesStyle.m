function snap = snapshotAxesStyle(ax)
% snapshotAxesStyle  Capture a per-object STYLE RECIPE for every data-bearing graphics object in a
% live axes, BEFORE export/close -- the ground truth half of a style-fingerprint match against that
% axes' own exported SVG (see matchGraphicsToSvg.m). Line, Patch, and Image (2026-08-30 -- a heatmap/
% `image`/`imagesc` dataseries, see below) -- color/style attributes only for Line/Patch (no
% geometry -- geometry/position stays a fallback disambiguator for a later, harder-case pass, not
% needed there); Image is matched entirely by GEOMETRY instead, never color (see below).
%
% Each entry's .hex/.fillHex is computed the SAME way MATLAB's own -dsvg exporter apparently does
% (round(channel*255), zero-padded 2-digit hex) -- confirmed by direct empirical round-trip test
% against a real exported SVG (round(Color*255) == the SVG's own stroke="#..." hex, byte for byte),
% NOT assumed from any documented color-space rule.
%
% Image objects (2026-08-30): have a `Tag` property but NO `DisplayName` property at all (confirmed
% empirically -- accessing `.DisplayName` on one throws) -- `displayName` is set to '' directly
% rather than read, so downstream id-slug computation (groupAndTagSvg.m) falls back to its already-
% established "no DisplayName" convention with no special-casing needed there. Never recolored for
% identity-matching (dumpIdentitySvg.m) and never matched by color (matchGraphicsToSvg.m) -- a raster
% image's "color" would be baked inside a compressed PNG blob, not a plain SVG attribute string, so
% the same exact-hex-string trick that resolves Line/Patch color collisions doesn't transfer. Instead
% `expectedFracBox` is precomputed here (while `ax` is still live) -- the image's own data-space
% extent (XData/YData, padded half a pixel per edge -- MATLAB only ever uses the FIRST/LAST elements
% of XData/YData regardless of vector length, confirmed empirically) converted through ax.XLim/YLim/
% XDir/YDir/InnerPosition into a normalized-figure-fraction box (MATLAB-space, bottom-left origin) --
% matchGraphicsToSvg.m only needs to scale this by the canvas's own physical size to get final SVG
% points, mirroring identifyAxisSpine.m's own two-stage normalized-fraction -> canvas-points approach.
% There is no color ambiguity to resolve here the way there is for Line/Patch: each Image's own live
% XData/YData already fully determines its expected box, so direct geometric correlation is not just
% simpler but strictly sufficient.
%
% snap(i) fields: handle, type ('line'|'patch'|'image'), hex (stroke color, [] for a Line with
% LineStyle='none'), fillHex ([] unless a Patch/filled), lineStyle, faceAlpha, edgeAlpha,
% displayName, tag, nPts (numel(XData) -- a cheap geometric tie-breaker for same-style candidates;
% unused/0 for an Image), expectedFracBox ([xMin yMin xMax yMax], normalized figure fraction,
% MATLAB-space -- [] unless type='image').

lines_ = findobj(ax, 'Type', 'line');
patches_ = findobj(ax, 'Type', 'patch');
images_ = findobj(ax, 'Type', 'image');
objs = [lines_(:); patches_(:); images_(:)];

snap = repmat(struct('handle',[], 'type','', 'hex','', 'fillHex','', 'lineStyle','', ...
    'faceAlpha',[], 'edgeAlpha',[], 'displayName','', 'tag','', 'nPts',0, 'expectedFracBox',[]), ...
    numel(objs), 1);

for i = 1:numel(objs)
    h = objs(i);
    snap(i).handle = h;
    if isa(h,'matlab.graphics.chart.primitive.Line')
        snap(i).type = 'line';
        snap(i).displayName = h.DisplayName;
        snap(i).tag = h.Tag;
        snap(i).nPts = numel(h.XData);
        snap(i).lineStyle = h.LineStyle;
        if ~strcmp(h.LineStyle,'none') || ~strcmp(h.Marker,'none')
            snap(i).hex = rgbToHex(h.Color);
        end
    elseif isa(h,'matlab.graphics.primitive.Image')
        snap(i).type = 'image';
        snap(i).displayName = '';   % Image has no DisplayName property at all -- never read it
        snap(i).tag = h.Tag;
        snap(i).expectedFracBox = computeImageExpectedFracBox(ax, h);
    else
        snap(i).type = 'patch';
        snap(i).displayName = h.DisplayName;
        snap(i).tag = h.Tag;
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

function fracBox = computeImageExpectedFracBox(ax, h)
% computeImageExpectedFracBox  [xMin yMin xMax yMax], normalized FIGURE fraction (MATLAB-space,
% bottom-left origin, i.e. already including ax.InnerPosition's own offset+scale -- the same
% convention identifyAxisSpine.m's own expectedBoxPt computation starts from before its own final
% canvas-points scaling step).
%
% Formula confirmed empirically (2026-08-30) against a real baked SVG's own referencing-path
% geometry, exact match: XData/YData only ever use their FIRST and LAST elements regardless of
% vector length; the rendered extent is HALF A PIXEL WIDER on each side than those two values
% (dx = (XData(end)-XData(1))/(nCols-1), and the image spans [XData(1)-dx/2, XData(end)+dx/2] -- a
% single-column/row image (nCols==1 or nRows==1, dx undefined) defaults to dx=1, MATLAB's own
% implicit single-pixel data-unit width, confirmed empirically: image(ax,[5 5],[1 3],C) with a
% 1-column CData produces ax.XLim=[4.5 5.5], i.e. exactly a 1-unit-wide default pixel.
ip = ax.InnerPosition;
xlo = ax.XLim(1); xhi = ax.XLim(2);
ylo = ax.YLim(1); yhi = ax.YLim(2);
nCols = size(h.CData,2); nRows = size(h.CData,1);
xFirst = h.XData(1); xLast = h.XData(end);
yFirst = h.YData(1); yLast = h.YData(end);
if nCols > 1; dx = (xLast-xFirst)/(nCols-1); else; dx = 1; end
if nRows > 1; dy = (yLast-yFirst)/(nRows-1); else; dy = 1; end
xEdge1 = xFirst - dx/2; xEdge2 = xLast + dx/2;
yEdge1 = yFirst - dy/2; yEdge2 = yLast + dy/2;
imgXMin = min(xEdge1,xEdge2); imgXMax = max(xEdge1,xEdge2);
imgYMin = min(yEdge1,yEdge2); imgYMax = max(yEdge1,yEdge2);

if strcmp(ax.XDir,'normal')
    xFracMin = (imgXMin-xlo)/(xhi-xlo);
    xFracMax = (imgXMax-xlo)/(xhi-xlo);
else
    xFracMin = (xhi-imgXMax)/(xhi-xlo);
    xFracMax = (xhi-imgXMin)/(xhi-xlo);
end
yFracOfMin = yFracOf(imgYMin, ylo, yhi, ax.YDir);
yFracOfMax = yFracOf(imgYMax, ylo, yhi, ax.YDir);
yFracBottom = min(yFracOfMin, yFracOfMax);
yFracTop = max(yFracOfMin, yFracOfMax);

xAbsMin = ip(1) + xFracMin*ip(3);
xAbsMax = ip(1) + xFracMax*ip(3);
yAbsMin = ip(2) + yFracBottom*ip(4);
yAbsMax = ip(2) + yFracTop*ip(4);
fracBox = [xAbsMin yAbsMin xAbsMax yAbsMax];
end

function f = yFracOf(y, lo, hi, yDir)
if strcmp(yDir,'normal')
    f = (y-lo)/(hi-lo);
else
    f = (hi-y)/(hi-lo);
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
