function registry = dumpFontRegistry(ax, outFile)
% dumpFontRegistry  Capture the AUTHORITATIVE FontSize for every text-bearing role in a live axes,
% keyed by exact string content, so a post-export baking step can overwrite the SVG's own
% (confirmed, empirically, to be sub-point-rounded) font-size with the true source value instead of
% trusting the export's own arithmetic. Written as JSON: array of {content, fontSize, role}.
%
% Roles captured: title, xlabel, ylabel (real Text objects, own FontSize each), xticklabel/
% yticklabel (shared ruler FontSize, one entry per visible tick string).

entries = struct('content', {}, 'fontSize', {}, 'role', {});

if ~isempty(ax.Title.String)
    entries(end+1) = struct('content', char(ax.Title.String), 'fontSize', ax.Title.FontSize, 'role', 'title');
end
if ~isempty(ax.XLabel.String)
    entries(end+1) = struct('content', char(ax.XLabel.String), 'fontSize', ax.XLabel.FontSize, 'role', 'xlabel');
end
if ~isempty(ax.YLabel.String)
    entries(end+1) = struct('content', char(ax.YLabel.String), 'fontSize', ax.YLabel.FontSize, 'role', 'ylabel');
end

xtl = ax.XAxis.TickLabels;
for i = 1:numel(xtl)
    entries(end+1) = struct('content', char(xtl{i}), 'fontSize', ax.XAxis.FontSize, 'role', 'xticklabel'); %#ok<AGROW>
end
ytl = ax.YAxis.TickLabels;
for i = 1:numel(ytl)
    entries(end+1) = struct('content', char(ytl{i}), 'fontSize', ax.YAxis.FontSize, 'role', 'yticklabel'); %#ok<AGROW>
end

registry = entries;
if nargin >= 2 && ~isempty(outFile)
    fid = fopen(outFile, 'w');
    fwrite(fid, jsonencode(entries));
    fclose(fid);
end
end
