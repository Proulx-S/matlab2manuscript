function [hexList, seriesIndexOf, roleCodeOf] = computeIdentityColors(snap)
% computeIdentityColors  THE single canonical mapping from snap index -> identity color, computed
% ONCE here and shared by dumpIdentitySvg.m (assigns these colors before export) and
% matchGraphicsToSvg.m (looks them up, decodes them back, and cross-checks the decode against this
% same function's own independently-recomputed expectation) -- so the two can never silently drift
% out of agreement with each other, and a caller accidentally matching against an identity SVG built
% from a DIFFERENT (stale/reordered) snap array gets caught rather than silently mismatched.
%
% Encodes (seriesIndex, roleCode, occurrence) per object (seriesRoleColorHex.m) rather than a bare
% sequential index: seriesIndex comes from assignSeriesIndices.m (Tag-based grouping, "pairing-by-
% identity" -- Seb's own ask 2026-08-29, see that file's own header for why Tag replaced DisplayName
% here), roleCode is 1 for a Line ('value') or 2 for a Patch ('conf'), and occurrence disambiguates
% the rare case of more than one object sharing the same (series,role) pair.
%
% hexList         cell array, one '#RRGGBB' string per snap(i)
% seriesIndexOf   numeric array, one series index per snap(i) (== assignSeriesIndices(snap))
% roleCodeOf      numeric array, one role code per snap(i) (1='value'/Line, 2='conf'/Patch)
seriesIndexOf = assignSeriesIndices(snap);
roleCodeOf = zeros(numel(snap),1);
hexList = cell(numel(snap),1);
occurrenceSeen = containers.Map('KeyType','char','ValueType','double');
for i = 1:numel(snap)
    roleCodeOf(i) = 1;
    if strcmp(snap(i).type,'patch'); roleCodeOf(i) = 2; end
    key = sprintf('%d-%d', seriesIndexOf(i), roleCodeOf(i));
    if ~isKey(occurrenceSeen, key); occurrenceSeen(key) = 0; end
    occurrenceSeen(key) = occurrenceSeen(key) + 1;
    hexList{i} = seriesRoleColorHex(seriesIndexOf(i), roleCodeOf(i), occurrenceSeen(key));
end
end
