% NOTE: validates assignSeriesIndices.m's Tag-based series pairing (2026-08-29, "pairing-by-
% identity" -- Seb's own ask) against BOTH failure modes the previous DisplayName-based scheme was
% genuinely vulnerable to:
%   (1) two UNRELATED objects that happen to (legitimately or accidentally) share a DisplayName must
%       NOT be merged into one series just because their display strings match.
%   (2) two objects DELIBERATELY meant to pair (a Line + its own confidence-band Patch) must still
%       be recognized as one series even when the Patch has no DisplayName at all (the normal case
%       now that pairing no longer depends on it).
addpath(fullfile(fileparts(fileparts(mfilename('fullpath')))));

% Case 1: same DisplayName, different Tag -- must NOT pair.
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
plot(ax, 1:10, sin(1:10), 'Color',[0.2 0.6 0.9], 'DisplayName','signal', 'Tag','A');
plot(ax, 1:10, cos(1:10), 'Color',[0.8 0.2 0.2], 'DisplayName','signal', 'Tag','B');
snap = snapshotAxesStyle(ax);
close(fig);
idx = assignSeriesIndices(snap);
assert(isequal(idx,[1;2]), ...
    'Case 1: two objects with the SAME DisplayName but DIFFERENT Tags were wrongly merged into one series -- Tag-based pairing not working.');
fprintf('Case 1 (same DisplayName, different Tag): PASS -- correctly kept as separate series\n');

% Case 2: same Tag, no DisplayName on the Patch -- MUST pair (the normal confidence-band case).
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
patch(ax, [1 2 2 1], [0 0 1 1], [0.5 0.5 0.5], 'Tag','pair1');   % deliberately NO DisplayName
plot(ax, 1:10, sin(1:10), 'Color',[0.2 0.6 0.9], 'DisplayName','signal', 'Tag','pair1');
snap2 = snapshotAxesStyle(ax);
close(fig);
idx2 = assignSeriesIndices(snap2);
assert(isequal(idx2,[1;1]), ...
    'Case 2: two objects sharing a Tag (one with no DisplayName at all) were NOT merged into one series.');
fprintf('Case 2 (shared Tag, patch has no DisplayName): PASS -- correctly paired\n');

% Case 3: no Tag set at all on either -- must NOT accidentally pair via the empty-string fallback
% (mirrors the same fallback discipline the old DisplayName-keyed version had for an unset DisplayName).
fig = figure('Visible','off'); ax = axes(fig); hold(ax,'on');
plot(ax, 1:10, sin(1:10), 'Color',[0.2 0.6 0.9]);
plot(ax, 1:10, cos(1:10), 'Color',[0.8 0.2 0.2]);
snap3 = snapshotAxesStyle(ax);
close(fig);
idx3 = assignSeriesIndices(snap3);
assert(isequal(idx3,[1;2]), ...
    'Case 3: two untagged objects were wrongly merged via an empty-Tag collision.');
fprintf('Case 3 (no Tag on either): PASS -- correctly kept as separate series (no accidental empty-key merge)\n');

disp('PAIRING-BY-IDENTITY (Tag) VALIDATION: PASS');
