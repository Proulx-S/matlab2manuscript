function [hex, rgb] = seriesRoleColorHex(seriesIndex, roleCode, occurrence)
% seriesRoleColorHex  Encodes (seriesIndex, roleCode, occurrence) directly as a 24-bit identity
% color -- #<seriesIndex><roleCode><occurrence>, one byte each (1-255) -- so decoding a shape's
% identity color (decodeSeriesRoleColorHex.m) recovers not just "which exact object" but its series/
% role too, without any DisplayName-string matching. roleCode: 1='value' (the Line), 2='conf' (the
% Patch/error-band). occurrence disambiguates the rare case of more than one object sharing the
% exact same (series,role) pair (e.g. two confidence bands on one series) -- normally 1.
%
% Exact hex STRING matching in SVG markup has none of a rasterized image's antialiasing risk (fill/
% stroke attribute VALUES are written as exact text, never blended) -- safe even for adjacent byte
% values, unlike a rasterized "color picking" buffer would be.
%
% hex   e.g. '#01020a' (seriesIndex=1, roleCode=2/'conf', occurrence=10)
% rgb   [r g b] in [0,1], as MATLAB's own Color/FaceColor/EdgeColor properties expect
assert(seriesIndex>=1 && seriesIndex<=255 && roleCode>=1 && roleCode<=255 && occurrence>=1 && occurrence<=255, ...
    'seriesRoleColorHex:outOfRange', ...
    'seriesIndex/roleCode/occurrence must each be in [1,255] (got %d,%d,%d).', seriesIndex, roleCode, occurrence);
hex = sprintf('#%02x%02x%02x', seriesIndex, roleCode, occurrence);
rgb = [seriesIndex, roleCode, occurrence] / 255;
end
