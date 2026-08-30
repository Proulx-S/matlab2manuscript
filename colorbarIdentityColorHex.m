function hex = colorbarIdentityColorHex()
% colorbarIdentityColorHex  THE single reserved identity color for a panel's colorbar outline/ticks/
% tick-labels (all driven by the one `cb.Color` property -- confirmed empirically, 2026-08-29), shared
% by dumpIdentitySvg.m (assigns it, temporarily, to `ax.Colorbar.Color` before the identity export) and
% identifyColorbar.m (looks it up). Reuses seriesRoleColorHex.m's own (seriesIndex,roleCode,occurrence)
% encoding with roleCode=3 -- a value real per-series data ALWAYS avoids (computeIdentityColors.m only
% ever assigns roleCode 1='value'/Line or 2='conf'/Patch) -- so this can never collide with a real
% series' own identity color regardless of how many series/occurrences exist. seriesIndex/occurrence
% are both fixed at 1 since at most one colorbar exists per axes (no per-series indexing needed).
hex = seriesRoleColorHex(1, 3, 1);
end
