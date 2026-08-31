function dumpIdentitySvg(fig, snap, outFile)
% dumpIdentitySvg  Exports a throwaway, identically-laid-out copy of fig with every
% snapshotAxesStyle.m object given a unique "identity color" (computeIdentityColors.m: encodes
% (seriesIndex, roleCode, occurrence), NOT just a bare sequential index -- see that file's own header
% for why) instead of its real color, so matchGraphicsToSvg.m can identify which exported SVG shape
% is which live MATLAB object -- AND which logical series/role it belongs to -- by EXACT color
% lookup, with zero possibility of collision even when two objects share the exact same REAL color (a
% genuine ambiguity the plain color-fingerprint approach cannot resolve on its own, see
% test_edge_cases.m Case B). The identity SVG is a disposable matching aid only, never meant to be
% shown to a user; real colors are ALWAYS restored before this function returns or throws, even if
% the error happens partway through recoloring.
%
% fig      the figure to export (snap's own objects must live on this figure's axes)
% snap     snapshotAxesStyle(ax) -- establishes the canonical index order computeIdentityColors.m
%          keys on; MUST be the exact same snap passed to matchGraphicsToSvg.m for the two sides to
%          agree
% outFile  where to write the identity SVG (same '-dsvg','-vector' export as the real one)
%
% Only Line/Patch objects (the same scope snapshotAxesStyle.m covers) are recolored. A Patch's
% FaceColor AND EdgeColor are both overridden when both are actually in use (unfilled or edgeless
% cases are left alone, matching snapshotAxesStyle.m's own "nothing to capture" convention) since
% either could be the color matchGraphicsToSvg.m ends up keying on for a given object.
%
% Image objects (2026-08-30) are deliberately NEVER recolored here -- a raster image's "color" is
% baked inside a compressed PNG blob, not a plain SVG attribute string, so the exact-hex-string trick
% this function relies on for Line/Patch doesn't transfer, and isn't needed anyway: an Image's own
% live XData/YData already fully determines its expected position (matchGraphicsToSvg.m matches it
% by direct geometric correlation instead, see snapshotAxesStyle.m's own computeImageExpectedFracBox).
%
% Colorbar support (2026-08-29): if `fig` has a live Colorbar, its `Color` property is ALSO
% temporarily overridden -- confirmed empirically to be the single property controlling its outline,
% tick marks, AND tick-label text all at once -- to colorbarIdentityColorHex.m's own reserved
% identity color (identifyColorbar.m looks it up the same way matchGraphicsToSvg.m looks up a
% series' own identity color: exact hex match in this throwaway export, then cross-referenced by
% geometry into the real one).

hexList = computeIdentityColors(snap);
restoreFns = {};
try
    for i = 1:numel(snap)
        h = snap(i).handle;
        rgb = sscanf(hexList{i}(2:end), '%2x')' / 255;
        if isa(h,'matlab.graphics.chart.primitive.Line')
            orig = h.Color;
            restoreFns{end+1} = @() set(h,'Color',orig); %#ok<AGROW>
            h.Color = rgb;
        elseif isa(h,'matlab.graphics.primitive.Image')
            continue   % never recolored -- see this file's own header
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
    cb = findobj(fig, 'Type', 'colorbar');
    if ~isempty(cb)
        cb = cb(1);
        origCbColor = cb.Color;
        restoreFns{end+1} = @() set(cb,'Color',origCbColor); %#ok<AGROW>
        cbIdHex = colorbarIdentityColorHex();
        cb.Color = sscanf(cbIdHex(2:end), '%2x')' / 255;
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
