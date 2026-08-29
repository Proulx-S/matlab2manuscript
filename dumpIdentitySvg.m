function dumpIdentitySvg(fig, snap, outFile)
% dumpIdentitySvg  Exports a throwaway, identically-laid-out copy of fig with every
% snapshotAxesStyle.m object given a unique "identity color" (identityColorHex.m: index i ->
% #000000+i) instead of its real color, so matchGraphicsToSvg.m can identify which exported SVG
% shape is which live MATLAB object by EXACT color lookup, with zero possibility of collision --
% even when two objects share the exact same REAL color, a genuine ambiguity the plain color-
% fingerprint approach cannot resolve on its own (see test_edge_cases.m Case B). The identity SVG is
% a disposable matching aid only, never meant to be shown to a user; real colors are ALWAYS restored
% before this function returns or throws, even if the error happens partway through recoloring.
%
% fig      the figure to export (snap's own objects must live on this figure's axes)
% snap     snapshotAxesStyle(ax) -- establishes the canonical index order identityColorHex.m keys on;
%          MUST be the exact same snap passed to matchGraphicsToSvg.m for the two sides to agree
% outFile  where to write the identity SVG (same '-dsvg','-vector' export as the real one)
%
% Only Line/Patch objects (the same scope snapshotAxesStyle.m covers) are recolored. A Patch's
% FaceColor AND EdgeColor are both overridden when both are actually in use (unfilled or edgeless
% cases are left alone, matching snapshotAxesStyle.m's own "nothing to capture" convention) since
% either could be the color matchGraphicsToSvg.m ends up keying on for a given object.

restoreFns = {};
try
    for i = 1:numel(snap)
        h = snap(i).handle;
        [~, rgb] = identityColorHex(i);
        if isa(h,'matlab.graphics.chart.primitive.Line')
            orig = h.Color;
            restoreFns{end+1} = @() set(h,'Color',orig); %#ok<AGROW>
            h.Color = rgb;
        else
            if ~(ischar(h.FaceColor) && strcmp(h.FaceColor,'none'))
                orig = h.FaceColor;
                restoreFns{end+1} = @() set(h,'FaceColor',orig); %#ok<AGROW>
                h.FaceColor = rgb;
            end
            if ~strcmp(h.EdgeColor,'none') && ~ischar(h.EdgeColor)
                orig = h.EdgeColor;
                restoreFns{end+1} = @() set(h,'EdgeColor',orig); %#ok<AGROW>
                h.EdgeColor = rgb;
            end
        end
    end
    drawnow;
    print(fig, outFile, '-dsvg', '-vector');
catch ME
    restoreAllColors(restoreFns);
    rethrow(ME);
end
restoreAllColors(restoreFns);
end

function restoreAllColors(restoreFns)
for i = 1:numel(restoreFns)
    restoreFns{i}();
end
end
