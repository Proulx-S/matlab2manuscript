repoDir = fileparts(fileparts(mfilename('fullpath')));
outDir = fullfile(fileparts(mfilename('fullpath')), 'out');
if ~exist(outDir,'dir'); mkdir(outDir); end
MM_PER_PT = 25.4/72;

fig = figure('Visible','off');
fig.Units = 'centimeters';
fig.Position = [2 2 16 10];
fig.PaperUnits = 'centimeters';
fig.PaperSize = [16 10];
fig.PaperPositionMode = 'manual';
fig.PaperPosition = [0 0 16 10];

ax = axes(fig);
ax.Units = 'normalized';
ax.PositionConstraint = 'innerposition';
ax.InnerPosition = [0.2 0.2 0.5 0.5];   % RAW, no manual correction
hold(ax,'on');
plot(ax, 1:10, sin(1:10), 'LineWidth', 2);        % RAW LineWidth
plot(ax, 5, 5, 'o', 'MarkerSize', 12, 'MarkerFaceColor',[0.9 0.1 0.1], 'MarkerEdgeColor','none', 'LineStyle','none');  % RAW MarkerSize
ax.FontSize = 14;   % RAW FontSize, set AFTER plotting (avoids the reset-on-first-plot gotcha)
drawnow;

svgFile = fullfile(outDir, 'final_raw.svg');
print(fig, svgFile, '-dsvg','-vector');
close(fig);

system(sprintf('python3 %s %s %s', fullfile(repoDir,'bakeTransforms.py'), svgFile, fullfile(outDir,'final_baked.svg')));

bakedFile = fullfile(outDir,'final_baked.svg');
txt = fileread(bakedFile);
vb = regexp(txt, 'viewBox="0 0 ([0-9.]+) ([0-9.]+)"', 'tokens', 'once');
canvasW = str2double(vb{1});

doc = xmlread(bakedFile);

fprintf('=== POSITION ===\n');
polylines = doc.getElementsByTagName('polyline');
for kk=0:polylines.getLength()-1
    node = polylines.item(kk);
    pts = sscanf(char(node.getAttribute('points')),'%f,%f');
    pts = reshape(pts,2,[])';
    if size(pts,1)==2
        dx = abs(diff(pts(:,1))); dy = abs(diff(pts(:,2)));
        if dx > 20 && dy < 1
            fprintf('BOTTOM spine RAW attr frac=[%.5f %.5f] (target [0.2 0.7], NO transform math needed now)\n', ...
                min(pts(:,1))/canvasW, max(pts(:,1))/canvasW);
        end
    end
end

fprintf('=== LINEWIDTH ===\n');
sw = regexp(txt, 'stroke-width="([0-9.]+)"', 'tokens');
sw = cellfun(@(c) str2double(c{1}), sw);
fprintf('stroke-width values present: %s (target data line = 2, raw no correction)\n', mat2str(unique(sw),6));

fprintf('=== FONTSIZE (real <text> elements only) ===\n');
textNodes = doc.getElementsByTagName('text');
fsSet = [];
for kk=0:textNodes.getLength()-1
    node = textNodes.item(kk);
    if node.hasAttribute('font-size')
        fsSet(end+1) = str2double(char(node.getAttribute('font-size'))); %#ok<AGROW>
    end
end
fprintf('<text> font-size values: %s (target=14, raw no correction)\n', mat2str(unique(fsSet),6));

fprintf('=== MARKERSIZE ===\n');
circles = doc.getElementsByTagName('circle');
for kk=0:circles.getLength()-1
    node = circles.item(kk);
    r = str2double(char(node.getAttribute('r')));
    fprintf('circle radius (RAW attr, post-bake) = %.6g pt = %.6g mm (target MarkerSize=12 -> radius=6pt=%.6gmm)\n', ...
        r, r*MM_PER_PT, 6*MM_PER_PT);
end
disp('DONE');
