function idx = assignSeriesIndices(snap)
% assignSeriesIndices  Groups snapshotAxesStyle.m entries into logical "series" -- e.g. a Line and
% its own confidence-band Patch -- for groupAndTagSvg.m's own 'value'/'conf' sub-grouping
% (docs/grouping-hierarchy.csv). idx(i) is a 1-indexed series number; two entries share one iff they
% share the same non-empty `Tag`.
%
% REVISED 2026-08-29 (Seb's own ask, "pairing-by-identity"): previously keyed on `DisplayName`
% instead of `Tag`. DisplayName is meant for what a human reads in the legend -- two UNRELATED
% series can legitimately (or accidentally) share one, silently merging them into one series that
% were never meant to be linked. `Tag` is the MATLAB property meant for exactly this kind of
% internal/programmatic identification, not display, so an accidental collision is far less likely
% and the intent is explicit. DisplayName is still used (correctly) elsewhere for what it's actually
% for -- identifyLegend.m matches legend text by DisplayName because that's literally the string a
% human sees there; this file's own grouping decision is a different question entirely.
%
% An entry with an empty Tag gets its own standalone series (no accidental grouping via shared-empty-
% string collision) -- same "ungrouped by default" fallback the DisplayName-keyed version used.
%
% This is a PURE function of `snap` (no SVG/color involvement) -- also called by
% computeIdentityColors.m so dumpIdentitySvg.m's identity-color assignment and groupAndTagSvg.m's
% own grouping decision are always guaranteed to agree, computed from the exact same live data.
idx = zeros(numel(snap),1);
keyToIdx = containers.Map('KeyType','char','ValueType','double');
nextIdx = 0;
for i = 1:numel(snap)
    key = snap(i).tag;
    if isempty(key); key = sprintf('__untagged_%d__', i); end
    if ~isKey(keyToIdx, key)
        nextIdx = nextIdx + 1;
        keyToIdx(key) = nextIdx;
    end
    idx(i) = keyToIdx(key);
end
end
