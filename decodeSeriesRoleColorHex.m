function [seriesIndex, roleCode, occurrence] = decodeSeriesRoleColorHex(hex)
% decodeSeriesRoleColorHex  Inverse of seriesRoleColorHex.m: recovers (seriesIndex, roleCode,
% occurrence) from a '#RRGGBB'-style identity color found in an SVG's fill/stroke attribute.
v = sscanf(hex(2:end), '%2x');
assert(numel(v) == 3, 'decodeSeriesRoleColorHex:badHex', 'expected a 6-hex-digit color, got "%s".', hex);
seriesIndex = v(1); roleCode = v(2); occurrence = v(3);
end
