function [hex, rgb] = identityColorHex(idx)
% identityColorHex  The deliberately-arbitrary, guaranteed-unique color assigned to snapshotAxesStyle
% entry `idx` by dumpIdentitySvg.m's own identity-matching scheme: the index itself, encoded directly
% as a 24-bit RGB value (idx=1 -> #000001, idx=2 -> #000002, ... up to 16,777,215 -- vastly more than
% any real panel needs). Shared by dumpIdentitySvg.m (assigns it) and matchGraphicsToSvg.m (looks it
% up), so both sides always agree on the encoding.
%
% Exact hex STRING matching in the SVG markup itself has none of a rasterized image's antialiasing
% risk -- fill/stroke attribute VALUES are written as exact text, never blended -- so even
% adjacent-looking indices like #000001/#000002 are perfectly safe to rely on for exact matching.
%
% hex   e.g. '#000001' (as written into the SVG's fill/stroke attribute)
% rgb   [r g b] in [0,1], as MATLAB's own Color/FaceColor/EdgeColor properties expect
hex = sprintf('#%06x', idx);
rgb = [bitshift(idx,-16), mod(bitshift(idx,-8),256), mod(idx,256)] / 255;
end
