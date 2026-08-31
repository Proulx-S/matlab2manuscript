function stats = groupAndTagSvg(ax, snap, bakedSvgFile, taggedSvgFile, panId, identityBakedSvgFile)
% groupAndTagSvg  The grouping/tagging half of this repo's round-trip pipeline (README pillar 1):
% restructures an ALREADY-BAKED svg's DOM into real nested <g> containers -- full current hierarchy
% in docs/grouping-hierarchy.csv (an editable outline; edit it to propose a change). Top-level
% roles: furniture (figure/axes background, gridlines, AND any leftover/unclaimed element -- e.g. an
% ad hoc `text()` annotation -- folded in per Seb's own ask, see that section's own comment for the
% real paint-order tradeoff this involves), axis-spine (spine lines, per-tick mark+label pairs, axis
% labels), dataseries (each series split into its own 'value'/Line and 'conf'/error-band-Patch
% sub-group), legend (box, per-entry swatch+label), colorbar (box, outline, per-tick mark+label
% pairs, own label -- 2026-08-29, requires identityBakedSvgFile, see identifyColorbar.m). This gives
% a real SVG editor's own
% click-to-select/collapse behavior a usable hierarchy (select the whole axis-spine, or one tick's
% mark+label together, in one click) instead of 60+ flat, one-element-each groups at the document
% root.
%
% REVISED 2026-08-28 from this file's first version, which stamped `id`/`data-role`/`data-group`
% directly onto existing leaf elements without moving anything, reasoning that relocating nodes
% risked changing paint order. Seb's own feedback: that flat, attribute-only structure is useless in
% practice -- a real SVG editor's grouping/selection model is DOM nesting, not attribute values, so
% it required exactly as many clicks as no grouping at all. This version actually moves elements,
% verified NOT to change rendering by (1) inlining every relocated leaf's inherited presentation
% attributes (fill/stroke/font-*/etc, walked up from its original ancestor <g>) directly onto itself
% before moving it, so it never depends on whatever new ancestor it ends up under, and (2) anchoring
% each new top-level group at the document position of whichever of its members occurs EARLIEST in
% the original document, which preserves every group's paint order relative to untouched/other-group
% siblings exactly (empirically confirmed via rasterized pixel-diff against the un-grouped baked
% file, both in this file's own test and ad hoc verification during development -- see
% docs/findings.md).
%
% ax             live axes (NOT yet closed -- ax.Box/.InnerPosition/.Title/.XAxis etc. read live;
%                PositionConstraint='innerposition' required; Box='off' or 'on' both supported, see
%                identifyAxisSpine.m)
% snap           snapshotAxesStyle(ax), captured BEFORE export/close
% bakedSvgFile   path to the baked (bakeTransforms.py) SVG -- absolute coordinates required
% taggedSvgFile  output path (written via xmlwrite)
% panId          this panel's own id within whatever composed multi-panel figure it may end up in
%                (2026-08-29 -- see syncPanel.m). Every id this function generates is prefixed with
%                `{panId}-`, and the whole panel is wrapped in one outermost `<g id="{panId}-root"
%                data-panel="{panId}">` (reusing MATLAB's own single top-level `<g>` -- see
%                getRootGroup.m's own comment -- as that wrapper directly, rather than inserting a
%                redundant extra one) so multiple panels' tagged output can be merged into one
%                document with no id collisions (`data-role`/`data-group` VALUES are deliberately
%                left untouched -- those are meant to repeat identically across panels, e.g.
%                selecting every panel's own axis-spine at once is a real, intended cross-panel
%                operation). Safe as a blanket rename because nothing upstream of this function
%                (MATLAB's own -dsvg export, bakeTransforms.py) ever emits an `id` attribute of its
%                own to collide with -- confirmed empirically, 2026-08-29.
% identityBakedSvgFile  (optional) a baked (bakeTransforms.py) export of dumpIdentitySvg.m's own
%                identity-colored copy of the SAME figure/snap -- when given, data-series matching
%                uses identity-color cross-referencing (matchGraphicsToSvg.m) instead of real-color
%                fingerprinting, resolving the "two objects share a color and point count" ambiguity
%                that's otherwise genuinely unresolvable (see test_edge_cases.m Case B/D). Omit only
%                for quick/standalone use where that ambiguity isn't a concern -- the caller is
%                responsible for producing this file (dumpIdentitySvg.m + bake), mirroring how this
%                function never bakes bakedSvgFile itself either. ALSO REQUIRED (2026-08-29) if `ax`
%                has a live Colorbar -- identifyColorbar.m's own identification mechanism depends on
%                it entirely (no real-color fallback); omitting it when a Colorbar exists means the
%                colorbar's elements fall through to the "annotations" catch-all instead of being
%                properly tagged, not an error.
%
% stats: struct of counts (nDataSeries, nLegendEntries, nXTicks, nYTicks, nAxisLabels,
% nFurnitureGridlines, nAnnotations, nAnnotationFontSizeUnresolved, nColorbarTicks) so a caller can
% sanity-check nothing was silently skipped. Every text role EXCEPT annotations gets its font-size corrected from
% a live ax/legend property directly (no content-matching risk at all, since which property to read
% is already determined by the role itself); an annotation's font-size is corrected by content-
% matching against the small set of still-live ad hoc text() objects, and nAnnotationFontSizeUnresolved
% counts how many couldn't be resolved that way (kept at the baked/scaled, slightly-rounded value
% instead -- see docs/findings.md) rather than silently guessed.
%
% Known, deliberately out-of-scope gaps (tracked, not silently accepted -- see docs/findings.md):
% multi-legend/multi-axes figures out of scope. (`ax.Box='on'` used to error loudly rather than be
% mishandled -- RESOLVED 2026-08-29, see identifyAxisSpine.m: mirrored top/right spine lines and
% tick marks are now identified and tagged, though MATLAB never draws mirror-side tick LABELS, so
% there's no mirror counterpart to a tick's own label.) (A Line+error-band Patch used to be paired
% into one series by DisplayName equality only
% -- REVISED 2026-08-29, see assignSeriesIndices.m: now uses `Tag`, an explicit, non-display property
% meant for exactly this, since two unrelated series can legitimately/accidentally share a
% DisplayName.)

doc = xmlread(bakedSvgFile);
canvasSizePt = getCanvasSizeFromDoc(doc);
root = getRootGroup(doc);

% --- identification only below (read-only queries against the still-untouched doc; every node
% reference collected here stays valid after later mutation -- Java DOM objects don't invalidate
% when detached, only their position changes) ---
%
% Colorbar identified BEFORE data-series matching (moved up, 2026-08-30, from its previous position
% after matchGraphicsToSvg) -- its gradient box uses the EXACT SAME pattern-filled-closed-rect-<path>
% mechanism an Image dataseries' own box does (matchGraphicsToSvg.m's own image-matching strategy),
% so it's otherwise a real false-positive candidate for image matching -- confirmed real while
% building image-dataseries support this same day, see docs/findings.md. Excluded from
% matchGraphicsToSvg's own image-matching below via cbExcludeNodes, same discipline as the pre-
% existing colorbar-vs-legend-box exclusion just below.
if nargin >= 6 && ~isempty(identityBakedSvgFile)
    cbInfo = identifyColorbar(ax, doc, xmlread(identityBakedSvgFile));
else
    cbInfo = [];
end
cbExcludeRects = {};
cbExcludeText = {};
cbExcludeNodes = {};
if ~isempty(cbInfo)
    cbExcludeRects = {cbInfo.bboxPt};
    cbExcludeText = [cbInfo.tickLabelNodes(:)', {cbInfo.labelNode}];
    cbExcludeNodes = [{cbInfo.boxNode}, cbInfo.decorationNodes(:)'];
end
if nargin >= 6 && ~isempty(identityBakedSvgFile)
    matches = matchGraphicsToSvg(snap, doc, identityBakedSvgFile, canvasSizePt, cbExcludeNodes);
else
    matches = matchGraphicsToSvg(snap, doc, [], canvasSizePt, cbExcludeNodes);
end
spineInfo = identifyAxisSpine(ax, doc, canvasSizePt);
legInfo = identifyLegend(ax, snap, doc, spineInfo.expectedBoxPt, canvasSizePt, cbExcludeRects);
% cbExcludeText: a colorbar's own tick-label <text> can coincidentally share numeric CONTENT with an
% axis tick label (e.g. both showing "0"), and -- since the colorbar spans the box's full height --
% one of its tick labels can land within matchTickLabels' own generous "below/left of the box"
% geometric window purely by y-coordinate coincidence (confirmed real, 2026-08-29) -- excluded here
% the same way legend text already is (this function's own exclude-list discipline).
xLabelNodes = matchTickLabels(doc, ax.XAxis.TickLabels, spineInfo.xTickNodes, 'x', spineInfo.expectedBoxPt, cbExcludeText);
yLabelNodes = matchTickLabels(doc, ax.YAxis.TickLabels, spineInfo.yTickNodes, 'y', spineInfo.expectedBoxPt, cbExcludeText);
furn = identifyFurniture(doc, canvasSizePt, spineInfo.expectedBoxPt);

seriesIndexOf = assignSeriesIndices(snap);

% Axis title/xlabel/ylabel: content-only match, excluding whatever legend/tick-label matching above
% already claimed (this repo's own real test panel has a genuine collision -- its y-axis label and
% its legend entry both render the literal string "radius").
excludeText = {};
if ~isempty(legInfo)
    for ei = 1:numel(legInfo.entries); excludeText{end+1} = legInfo.entries(ei).textNode; end %#ok<AGROW>
end
excludeText = [excludeText, xLabelNodes(:)', yLabelNodes(:)'];
if ~isempty(cbInfo)
    excludeText = [excludeText, cbInfo.tickLabelNodes(:)', {cbInfo.labelNode}];
end
texts = doc.getElementsByTagName('text');
labelDefs = {'title',char(ax.Title.String); 'xlabel',char(ax.XLabel.String); 'ylabel',char(ax.YLabel.String)};
axisLabelNode = struct('title',[],'xlabel',[],'ylabel',[]);
for li = 1:size(labelDefs,1)
    role = labelDefs{li,1}; content = labelDefs{li,2};
    if isempty(content); continue; end
    node = findTextByContentExcluding(texts, content, excludeText);
    if ~isempty(node); axisLabelNode.(role) = node; end
end

% Catch-all "annotations": anything with real geometry/text that isn't claimed by any role above.
% xSpineTopNode/ySpineRightNode/xTickMirrorNodes/yTickMirrorNodes are [] / {} unless ax.Box='on'
% (identifyAxisSpine.m) -- harmless to always include, isNodeInList/earliestOriginalChild both treat
% an empty entry as a no-op.
claimed = [{spineInfo.xSpineNode, spineInfo.ySpineNode, spineInfo.xSpineTopNode, spineInfo.ySpineRightNode}, ...
    spineInfo.xTickNodes(:)', spineInfo.yTickNodes(:)', spineInfo.xTickMirrorNodes(:)', spineInfo.yTickMirrorNodes(:)', ...
    xLabelNodes(:)', yLabelNodes(:)', {axisLabelNode.title, axisLabelNode.xlabel, axisLabelNode.ylabel}, ...
    {furn.figureBgNode, furn.axesBgNode}, furn.gridlineNodes(:)'];
for i = 1:numel(snap)
    if ~isempty(matches(i).node); claimed{end+1} = matches(i).node; end %#ok<AGROW>
end
if ~isempty(legInfo)
    claimed = [claimed, legInfo.boxNodes(:)'];
    for ei = 1:numel(legInfo.entries)
        claimed{end+1} = legInfo.entries(ei).swatchNode; %#ok<AGROW>
        claimed{end+1} = legInfo.entries(ei).textNode; %#ok<AGROW>
    end
end
if ~isempty(cbInfo)
    claimed = [claimed, {cbInfo.boxNode, cbInfo.labelNode}, cbInfo.outlineNodes(:)', ...
        cbInfo.tickNodes(:)', cbInfo.tickLabelNodes(:)', cbInfo.decorationNodes(:)'];
end
annotationNodes = {};
for tagName = {'polyline','path','text','circle','image'}
    els = doc.getElementsByTagName(tagName{1});
    for k = 0:els.getLength()-1
        n = els.item(k);
        if isNodeInList(n, claimed); continue; end
        % A colorbar's (or, eventually, an image-dataseries') gradient/raster content is embedded
        % as an <image> child of a <pattern> DEFINITION, not a directly-rendered element -- a bare
        % getElementsByTagName('image') scan doesn't distinguish that from real content, so it was
        % otherwise wrongly caught here as a "leftover" annotation (confirmed real, 2026-08-29).
        if isDescendantOfTag(n, 'pattern'); continue; end
        annotationNodes{end+1} = n; %#ok<AGROW>
    end
end

% --- anchors: computed BEFORE any mutation, off the still-original document, so each new group's
% insertion point reflects whichever of its members occurs earliest in draw order ---
furnitureMembers = [{furn.figureBgNode, furn.axesBgNode}, furn.gridlineNodes(:)', annotationNodes(:)'];
spineMembers = [{spineInfo.xSpineNode, spineInfo.ySpineNode, spineInfo.xSpineTopNode, spineInfo.ySpineRightNode}, ...
    spineInfo.xTickNodes(:)', spineInfo.yTickNodes(:)', spineInfo.xTickMirrorNodes(:)', spineInfo.yTickMirrorNodes(:)', ...
    xLabelNodes(:)', yLabelNodes(:)', {axisLabelNode.title, axisLabelNode.xlabel, axisLabelNode.ylabel}];
dataMembers = {};
for i = 1:numel(snap)
    if ~isempty(matches(i).node); dataMembers{end+1} = matches(i).node; end %#ok<AGROW>
end
legendMembers = {};
if ~isempty(legInfo)
    legendMembers = legInfo.boxNodes(:)';
    for ei = 1:numel(legInfo.entries)
        legendMembers{end+1} = legInfo.entries(ei).swatchNode; %#ok<AGROW>
        legendMembers{end+1} = legInfo.entries(ei).textNode; %#ok<AGROW>
    end
end
colorbarMembers = {};
if ~isempty(cbInfo)
    colorbarMembers = [{cbInfo.boxNode, cbInfo.labelNode}, cbInfo.outlineNodes(:)', ...
        cbInfo.tickNodes(:)', cbInfo.tickLabelNodes(:)', cbInfo.decorationNodes(:)'];
end

anchorFurniture = earliestOriginalChild(root, furnitureMembers);
anchorSpine = earliestOriginalChild(root, spineMembers);
anchorData = earliestOriginalChild(root, dataMembers);
anchorColorbar = earliestOriginalChild(root, colorbarMembers);
anchorLegend = earliestOriginalChild(root, legendMembers);

stats = struct('nDataSeries',0, 'nLegendEntries',0, 'nXTicks',0, 'nYTicks',0, 'nAxisLabels',0, ...
    'nFurnitureGridlines',0, 'nAnnotations',0, 'nAnnotationFontSizeUnresolved',0, 'nColorbarTicks',0);

% --- furniture (+ annotations, folded in per Seb's own ask 2026-08-29) ---
if ~isempty(furn.figureBgNode) || ~isempty(furn.axesBgNode) || ~isempty(furn.gridlineNodes) || ~isempty(annotationNodes)
    furnitureG = newGroup(doc, 'furniture', 'furniture');
    insertAt(root, furnitureG, anchorFurniture);
    if ~isempty(furn.figureBgNode)
        relocateLeaf(furn.figureBgNode, furnitureG);
        tagLeaf(furn.figureBgNode, 'figure-background', 'figure-background');
    end
    if ~isempty(furn.axesBgNode)
        relocateLeaf(furn.axesBgNode, furnitureG);
        tagLeaf(furn.axesBgNode, 'axes-background', 'axes-background');
    end
    if ~isempty(furn.gridlineNodes)
        gridG = newGroup(doc, 'gridlines', 'gridlines');
        furnitureG.appendChild(gridG);
        for k = 1:numel(furn.gridlineNodes)
            relocateLeaf(furn.gridlineNodes{k}, gridG);
            tagLeaf(furn.gridlineNodes{k}, sprintf('gridline-%d',k), 'gridline');
        end
        stats.nFurnitureGridlines = numel(furn.gridlineNodes);
    end
    if ~isempty(annotationNodes)
        % Folded into furniture on Seb's own explicit ask -- this DOES physically relocate them
        % (dragging each one back to wherever furniture's own anchor is, typically the very front of
        % the document, since figure-background is almost always the earliest element overall), the
        % exact class of paint-order change this file's own design otherwise avoids for leftover
        % elements (they have no contiguity guarantee with each other OR with furniture -- see
        % docs/findings.md). Verified case-by-case via this file's own pixel-diff test rather than
        % assumed safe; if a real panel ever needs an annotation to render on TOP of data/spine/
        % legend (its most common real use, e.g. a corner label), folding it into furniture will
        % likely break that -- flag it if `test_group_tag.m`'s pixel-diff check ever catches this.
        annG = newGroup(doc, 'annotations', 'annotations');
        furnitureG.appendChild(annG);
        % Ad hoc text() objects still on the live axes (title/xlabel/ylabel excluded -- those are
        % already handled by name above, not by this catch-all) -- used to correct an annotation's
        % font-size the same way every other role's is corrected below, by CONTENT match against a
        % small, already-narrowed candidate set (mirrors identifyLegend.m's own content-matching
        % discipline). Left unresolved (baked/scaled fallback value kept, tracked in stats, not
        % silently guessed) if zero or more than one live text shares that exact content.
        adHocTextObjs = findall(ax, 'Type', 'text');
        knownLabelHandles = [ax.Title, ax.XLabel, ax.YLabel];
        adHocTextObjs = adHocTextObjs(~ismember(adHocTextObjs, knownLabelHandles));
        stats.nAnnotationFontSizeUnresolved = 0;
        for k = 1:numel(annotationNodes)
            node = annotationNodes{k};
            relocateLeaf(node, annG);
            id = char(node.getAttribute('id'));
            if isempty(id); id = sprintf('annotation-%d',k); end
            tagLeaf(node, id, 'annotation');
            if strcmp(char(node.getTagName()), 'text') && ~setAnnotationFontSizeFromLive(node, adHocTextObjs)
                stats.nAnnotationFontSizeUnresolved = stats.nAnnotationFontSizeUnresolved + 1;
            end
        end
        stats.nAnnotations = numel(annotationNodes);
    end
end

% --- axis spine (spine lines, per-tick mark+label pairs, axis labels) ---
spineG = newGroup(doc, 'axis-spine', 'axis-spine');
insertAt(root, spineG, anchorSpine);

linesG = newGroup(doc, 'axis-spine-lines', 'spine-lines');
spineG.appendChild(linesG);
relocateLeaf(spineInfo.xSpineNode, linesG); tagLeaf(spineInfo.xSpineNode, 'axis-spine-x', 'spine-line');
relocateLeaf(spineInfo.ySpineNode, linesG); tagLeaf(spineInfo.ySpineNode, 'axis-spine-y', 'spine-line');
% Mirror lines/ticks only exist when ax.Box='on' (identifyAxisSpine.m) -- MATLAB draws a second long
% line on the opposite side of each ruler, with its own set of tick marks but (confirmed empirically)
% never its own tick LABELS, so there's no mirror counterpart to xLabelNodes/yLabelNodes below.
if ~isempty(spineInfo.xSpineTopNode)
    relocateLeaf(spineInfo.xSpineTopNode, linesG);
    tagLeaf(spineInfo.xSpineTopNode, 'axis-spine-x-mirror', 'spine-line-mirror');
end
if ~isempty(spineInfo.ySpineRightNode)
    relocateLeaf(spineInfo.ySpineRightNode, linesG);
    tagLeaf(spineInfo.ySpineRightNode, 'axis-spine-y-mirror', 'spine-line-mirror');
end

ticksXG = newGroup(doc, 'axis-ticks-x', 'ticks'); ticksXG.setAttribute('data-axis','x');
spineG.appendChild(ticksXG);
for k = 1:numel(spineInfo.xTickNodes)
    tickG = newGroup(doc, sprintf('axis-tick-x-%d',k), 'tick');
    ticksXG.appendChild(tickG);
    relocateLeaf(spineInfo.xTickNodes{k}, tickG);
    tagLeaf(spineInfo.xTickNodes{k}, sprintf('axis-tick-x-%d-mark',k), 'tick-mark');
    if k <= numel(xLabelNodes) && ~isempty(xLabelNodes{k})
        relocateLeaf(xLabelNodes{k}, tickG);
        tagLeaf(xLabelNodes{k}, sprintf('axis-ticklabel-x-%d',k), 'tick-label');
        setFontSizeFromLive(xLabelNodes{k}, ax.XAxis.FontSize);
    end
end
stats.nXTicks = numel(spineInfo.xTickNodes);
if ~isempty(spineInfo.xTickMirrorNodes)
    ticksXMirrorG = newGroup(doc, 'axis-ticks-x-mirror', 'ticks-mirror'); ticksXMirrorG.setAttribute('data-axis','x');
    spineG.appendChild(ticksXMirrorG);
    for k = 1:numel(spineInfo.xTickMirrorNodes)
        relocateLeaf(spineInfo.xTickMirrorNodes{k}, ticksXMirrorG);
        tagLeaf(spineInfo.xTickMirrorNodes{k}, sprintf('axis-tick-x-mirror-%d',k), 'tick-mark-mirror');
    end
end

ticksYG = newGroup(doc, 'axis-ticks-y', 'ticks'); ticksYG.setAttribute('data-axis','y');
spineG.appendChild(ticksYG);
for k = 1:numel(spineInfo.yTickNodes)
    tickG = newGroup(doc, sprintf('axis-tick-y-%d',k), 'tick');
    ticksYG.appendChild(tickG);
    relocateLeaf(spineInfo.yTickNodes{k}, tickG);
    tagLeaf(spineInfo.yTickNodes{k}, sprintf('axis-tick-y-%d-mark',k), 'tick-mark');
    if k <= numel(yLabelNodes) && ~isempty(yLabelNodes{k})
        relocateLeaf(yLabelNodes{k}, tickG);
        tagLeaf(yLabelNodes{k}, sprintf('axis-ticklabel-y-%d',k), 'tick-label');
        setFontSizeFromLive(yLabelNodes{k}, ax.YAxis.FontSize);
    end
end
stats.nYTicks = numel(spineInfo.yTickNodes);
if ~isempty(spineInfo.yTickMirrorNodes)
    ticksYMirrorG = newGroup(doc, 'axis-ticks-y-mirror', 'ticks-mirror'); ticksYMirrorG.setAttribute('data-axis','y');
    spineG.appendChild(ticksYMirrorG);
    for k = 1:numel(spineInfo.yTickMirrorNodes)
        relocateLeaf(spineInfo.yTickMirrorNodes{k}, ticksYMirrorG);
        tagLeaf(spineInfo.yTickMirrorNodes{k}, sprintf('axis-tick-y-mirror-%d',k), 'tick-mark-mirror');
    end
end

labelsG = newGroup(doc, 'axis-labels', 'axis-labels');
spineG.appendChild(labelsG);
axisLabelFontSize = struct('title',ax.Title.FontSize, 'xlabel',ax.XLabel.FontSize, 'ylabel',ax.YLabel.FontSize);
for role = {'title','xlabel','ylabel'}
    node = axisLabelNode.(role{1});
    if isempty(node); continue; end
    relocateLeaf(node, labelsG);
    tagLeaf(node, ['axis-' role{1}], 'axis-label');
    setFontSizeFromLive(node, axisLabelFontSize.(role{1}));
    stats.nAxisLabels = stats.nAxisLabels + 1;
end

% --- data series (+ associated error, linked by shared Tag -- see assignSeriesIndices.m), each
% split into its own 'value' (the Line) and 'conf' (the confidence-interval/error-band Patch)
% sub-group -- per Seb's
% own ask 2026-08-29, docs/grouping-hierarchy.csv. ---
if ~isempty(dataMembers)
    dataG = newGroup(doc, 'dataseries', 'dataseries');
    insertAt(root, dataG, anchorData);
    seriesGroupOf = containers.Map('KeyType','double','ValueType','any');
    valueGroupOf = containers.Map('KeyType','double','ValueType','any');
    confGroupOf = containers.Map('KeyType','double','ValueType','any');

    % One shared slug per SERIES (not per snap(i)) -- since pairing is now by Tag, not DisplayName,
    % a series' own Patch member commonly has NO DisplayName at all (only the Line, which is what
    % appears in the legend, needs one). Using each member's OWN displayName independently would
    % otherwise give a series' Line and Patch leaves inconsistent ids (e.g. "...-signal-line" next
    % to "...-series1-fill") -- computed as a precompute pass so it's the same regardless of which
    % member happens to be processed first.
    seriesDisplayNameOf = containers.Map('KeyType','double','ValueType','char');
    for i = 1:numel(snap)
        if isempty(matches(i).node); continue; end
        si = seriesIndexOf(i);
        if ~isKey(seriesDisplayNameOf, si) && ~isempty(snap(i).displayName)
            seriesDisplayNameOf(si) = snap(i).displayName;
        end
    end

    for i = 1:numel(snap)
        if isempty(matches(i).node); continue; end
        si = seriesIndexOf(i);
        if isKey(seriesDisplayNameOf, si)
            dn = seriesDisplayNameOf(si);
        else
            dn = '';
        end
        slug = slugify(dn, sprintf('series%d',si));
        if ~isKey(seriesGroupOf, si)
            sg = newGroup(doc, sprintf('dataseries-%d-%s',si,slug), 'series');
            sg.setAttribute('data-series-index', num2str(si));
            if ~isempty(dn); sg.setAttribute('data-display-name', dn); end
            dataG.appendChild(sg);
            seriesGroupOf(si) = sg;
        end
        if strcmp(snap(i).type,'patch')
            role = 'dataseries-fill'; leafSuffix = '-fill'; subSuffix = '-conf'; subRole = 'dataseries-conf'; subMap = confGroupOf;
        elseif strcmp(snap(i).type,'image')
            % 2026-08-30: a heatmap/`image`/`imagesc` dataseries -- its own 'value' sub-group, same as
            % a Line, since there's no 'conf'/error-band counterpart concept for raster image content.
            role = 'dataseries-image'; leafSuffix = '-image'; subSuffix = '-value'; subRole = 'dataseries-value'; subMap = valueGroupOf;
        else
            role = 'dataseries-line'; leafSuffix = '-line'; subSuffix = '-value'; subRole = 'dataseries-value'; subMap = valueGroupOf;
        end
        if ~isKey(subMap, si)
            subG = newGroup(doc, sprintf('dataseries-%d-%s%s',si,slug,subSuffix), subRole);
            seriesGroupOf(si).appendChild(subG);
            subMap(si) = subG; %#ok<NASGU> -- subMap is a handle (containers.Map): this mutates
                                % valueGroupOf/confGroupOf directly, not a local copy
        end
        % leafSuffix is REQUIRED even for the common (line-only, no error-band) case -- without one,
        % a line-only series' leaf would get the exact same id as its own parent "series" group
        % (both "dataseries-<i>-<slug>"), an invalid duplicate id (confirmed real: caught by
        % inspecting this repo's own generated output, not by the tests -- findTestById's own
        % document-order search silently returned the GROUP instead of the intended leaf, since
        % getElementsByTagName('*') visits a parent before its children).
        relocateLeaf(matches(i).node, subMap(si));
        tagLeaf(matches(i).node, sprintf('dataseries-%d-%s%s',si,slug,leafSuffix), role);
        stats.nDataSeries = stats.nDataSeries + 1;
    end
end

% --- legend (box, per-entry swatch+label) ---
if ~isempty(legInfo)
    legendG = newGroup(doc, 'legend', 'legend');
    insertAt(root, legendG, anchorLegend);
    boxG = newGroup(doc, 'legend-box', 'legend-box');
    legendG.appendChild(boxG);
    for bi = 1:numel(legInfo.boxNodes)
        suffix = 'bg'; if bi > 1; suffix = 'border'; end
        relocateLeaf(legInfo.boxNodes{bi}, boxG);
        tagLeaf(legInfo.boxNodes{bi}, sprintf('legend-box-%s',suffix), sprintf('legend-box-%s',suffix));
    end
    % A MATLAB Legend has ONE FontSize shared by every entry (not per-entry) -- fetched directly
    % rather than via identifyLegend.m (which only returns node references, not the Legend object
    % itself) since ax is still live here.
    legObjs = findobj(ancestor(ax,'figure'), 'Type','legend');
    legendFontSize = [];
    if ~isempty(legObjs); legendFontSize = legObjs(1).FontSize; end
    for ei = 1:numel(legInfo.entries)
        e = legInfo.entries(ei);
        si = seriesIndexOf(e.snapIndex);
        entryG = newGroup(doc, sprintf('legend-entry-%d',si), 'legend-entry');
        entryG.setAttribute('data-series-index', num2str(si));
        legendG.appendChild(entryG);
        relocateLeaf(e.swatchNode, entryG); tagLeaf(e.swatchNode, sprintf('legend-swatch-%d',si), 'legend-swatch');
        relocateLeaf(e.textNode, entryG); tagLeaf(e.textNode, sprintf('legend-label-%d',si), 'legend-label');
        setFontSizeFromLive(e.textNode, legendFontSize);
        stats.nLegendEntries = stats.nLegendEntries + 1;
    end
end

% --- colorbar (box, outline, per-tick mark+label pairs, own label) -- 2026-08-29, see
% identifyColorbar.m's own header for the identity-color mechanism this depends on. ---
if ~isempty(cbInfo)
    cbG = newGroup(doc, 'colorbar', 'colorbar');
    insertAt(root, cbG, anchorColorbar);
    relocateLeaf(cbInfo.boxNode, cbG); tagLeaf(cbInfo.boxNode, 'colorbar-box', 'colorbar-box');
    outlineG = newGroup(doc, 'colorbar-outline', 'colorbar-outline');
    cbG.appendChild(outlineG);
    for oi = 1:numel(cbInfo.outlineNodes)
        relocateLeaf(cbInfo.outlineNodes{oi}, outlineG);
        tagLeaf(cbInfo.outlineNodes{oi}, sprintf('colorbar-outline-%d',oi), 'colorbar-outline-edge');
    end
    ticksG = newGroup(doc, 'colorbar-ticks', 'colorbar-ticks');
    cbG.appendChild(ticksG);
    for ti = 1:numel(cbInfo.tickNodes)
        tickG = newGroup(doc, sprintf('colorbar-tick-%d',ti), 'colorbar-tick');
        ticksG.appendChild(tickG);
        relocateLeaf(cbInfo.tickNodes{ti}, tickG);
        tagLeaf(cbInfo.tickNodes{ti}, sprintf('colorbar-tick-%d-mark',ti), 'colorbar-tick-mark');
        if ti <= numel(cbInfo.tickLabelNodes) && ~isempty(cbInfo.tickLabelNodes{ti})
            relocateLeaf(cbInfo.tickLabelNodes{ti}, tickG);
            tagLeaf(cbInfo.tickLabelNodes{ti}, sprintf('colorbar-ticklabel-%d',ti), 'colorbar-tick-label');
            setFontSizeFromLive(cbInfo.tickLabelNodes{ti}, ax.Colorbar.FontSize);
        end
    end
    stats.nColorbarTicks = numel(cbInfo.tickNodes);
    if ~isempty(cbInfo.decorationNodes)
        decG = newGroup(doc, 'colorbar-decoration', 'colorbar-decoration');
        cbG.appendChild(decG);
        for di = 1:numel(cbInfo.decorationNodes)
            relocateLeaf(cbInfo.decorationNodes{di}, decG);
            tagLeaf(cbInfo.decorationNodes{di}, sprintf('colorbar-decoration-%d',di), 'colorbar-decoration');
        end
    end
    if ~isempty(cbInfo.labelNode)
        relocateLeaf(cbInfo.labelNode, cbG);
        tagLeaf(cbInfo.labelNode, 'colorbar-label', 'colorbar-label');
        setFontSizeFromLive(cbInfo.labelNode, ax.Colorbar.Label.FontSize);
    end
end

pruneEmptyGroups(root);

% Blanket id-prefix pass MUST run before wrapping root as the panel's own id below -- root has no
% `id` yet at this point (getRootGroup.m never sets one), so it's untouched by this pass, then gets
% its own final id set directly afterward (prefixing it too would double it, e.g. "panelA-panelA-root").
prefixAllIds(root, panId);
root.setAttribute('id', [panId '-root']);
root.setAttribute('data-panel', panId);

xmlwrite(taggedSvgFile, doc);
end

function prefixAllIds(root, panId)
% Rewrites every id="..." already set within root's subtree to "{panId}-...", so this panel's
% output can share a document with other panels with no collision (see this file's own header).
els = root.getElementsByTagName('*');
for i = 0:els.getLength()-1
    n = els.item(i);
    if n.hasAttribute('id')
        n.setAttribute('id', [panId '-' char(n.getAttribute('id'))]);
    end
end
end

% ============================== identification helpers ==============================

function furn = identifyFurniture(doc, canvasSizePt, axesBoxPt)
% The figure-background rect (spans the whole canvas) and axes-background rect (spans the spine's
% own box, found via findClosedRectPaths.m -- shared with identifyLegend.m), plus every gridline
% polyline (excluded from identifyAxisSpine.m's own spine/tick candidacy by the SAME opacity signal
% -- gridlines are always drawn with a fractional stroke-opacity, confirmed in this repo's probe SVG).
% bgTol=1.5pt -- see identifyLegend.m's own identical constant/comment: the 72/ScreenPixelsPerInch
% rounding discrepancy scales with absolute canvas size and exceeds a 1pt tolerance on a US-Letter
% canvas (2026-08-29).
%
% Pattern-filled candidates are EXCLUDED here (2026-08-30) -- an image dataseries spanning the axes'
% FULL extent (a full-bleed heatmap, a very common real case) produces its own pattern-filled closed-
% rect <path> with the EXACT SAME bbox as the true (solid-fill) axes-background rect. Without this
% exclusion, whichever of the two happens to come LAST in document order silently overwrites the
% other as `furn.axesBgNode` (plain assignment, no uniqueness check) -- confirmed real building this
% same-day round: the true background rect fell through to "annotations" unclaimed, while the
% image's own rect got double-tagged (correctly recovered only because dataseries processing runs
% AFTER furniture and wins the final DOM position/attributes -- the axes-background rect itself was
% still silently lost). The true background always has a solid fill (ax.Color); an image's/
% colorbar's own referencing rect always has `fill="url(#...)"` -- never both real content.
bgTol = 1.5;
rects = findClosedRectPaths(doc);
furn.figureBgNode = [];
furn.axesBgNode = [];
for i = 1:numel(rects)
    if isPatternFilled(rects{i}.node); continue; end
    r = rects{i}.rect;
    if all(abs(r - [0 0 canvasSizePt(1) canvasSizePt(2)]) < bgTol)
        furn.figureBgNode = rects{i}.node;
    elseif all(abs(r - axesBoxPt) < bgTol)
        furn.axesBgNode = rects{i}.node;
    end
end
polylines = doc.getElementsByTagName('polyline');
furn.gridlineNodes = {};
for k = 0:polylines.getLength()-1
    node = polylines.item(k);
    if getElementOpacity(node) < 0.99
        furn.gridlineNodes{end+1} = node; %#ok<AGROW>
    end
end
end

function labelNodes = matchTickLabels(doc, tickLabelStrs, tickNodes, axisName, boxRect, excludeText)
% Candidate <text> nodes: content is one of the live tick label strings (ground truth, from
% ax.XAxis.TickLabels/ax.YAxis.TickLabels directly), AND positioned just outside the spine on the
% expected side (below for x,
% left for y) -- content alone risks a cross-axis collision, position alone has no exact distance to
% anchor a threshold against, so both are required; loudly refuses to pair if the resulting count
% doesn't match the tick marks.
%
% excludeText (optional, default {}): nodes to skip outright even if content+position both match --
% e.g. a colorbar's own tick labels, which can coincidentally share numeric content with an axis
% tick label AND land inside this function's own geometric window purely by coordinate coincidence
% (confirmed real, 2026-08-29 -- the colorbar spans the box's full height, so one of its tick
% labels landing within the "just below the box" window is a real, not hypothetical, collision).
if nargin < 6 || isempty(excludeText); excludeText = {}; end
texts = doc.getElementsByTagName('text');
cands = {};
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if isNodeInList(n, excludeText); continue; end
    content = strtrim(char(n.getTextContent()));
    if ~ismember(content, tickLabelStrs); continue; end
    x = str2double(char(n.getAttribute('x'))); y = str2double(char(n.getAttribute('y')));
    if axisName == 'x'
        inRange = y > boxRect(4) - 0.5 && y < boxRect(4) + 30;   % below the box, SVG y-down
        pos = x;
    else
        inRange = x < boxRect(1) + 0.5 && x > boxRect(1) - 30;   % left of the box
        pos = y;
    end
    if ~inRange; continue; end
    cands{end+1} = struct('node',n,'pos',pos); %#ok<AGROW>
end
assert(numel(cands) == numel(tickNodes), 'groupAndTagSvg:tickLabelCountMismatch', ...
    ['found %d %s-tick-label <text> candidate(s), expected %d (one per tick mark) -- refusing to ' ...
     'guess the pairing.'], numel(cands), axisName, numel(tickNodes));
[~, order] = sort(cellfun(@(c) c.pos, cands));
cands = cands(order);
labelNodes = cellfun(@(c) c.node, cands, 'UniformOutput', false);
end

function node = findTextByContentExcluding(texts, content, excludeList)
node = [];
for k = 0:texts.getLength()-1
    n = texts.item(k);
    if isNodeInList(n, excludeList); continue; end
    if strcmp(strtrim(char(n.getTextContent())), content)
        assert(isempty(node), 'groupAndTagSvg:ambiguousAxisLabel', ...
            'more than one <text> (outside already-claimed nodes) matches content "%s" -- cannot disambiguate.', content);
        node = n;
    end
end
end

function s = slugify(name, fallback)
if isempty(name); s = fallback; return; end
s = regexprep(lower(name), '[^a-z0-9]+', '-');
s = regexprep(s, '(^-+|-+$)', '');
if isempty(s); s = fallback; end
end

% ============================== DOM-surgery helpers ==============================

function g = getRootGroup(doc)
% MATLAB's -dsvg exporter wraps its entire drawing in exactly one top-level <g> (confirmed in this
% repo's own probe SVG) -- every semantic group this file builds is inserted as a sibling within it.
docRoot = doc.getDocumentElement();
kids = docRoot.getChildNodes();
g = [];
for i = 0:kids.getLength()-1
    c = kids.item(i);
    if c.getNodeType() == c.ELEMENT_NODE && strcmp(char(c.getTagName()),'g')
        assert(isempty(g), 'groupAndTagSvg:multipleRootGroups', ...
            'more than one top-level <g> found under <svg> -- unexpected MATLAB export structure.');
        g = c;
    end
end
assert(~isempty(g), 'groupAndTagSvg:noRootGroup', 'no top-level <g> found under <svg>.');
end

function g = newGroup(doc, id, role)
g = doc.createElement('g');
g.setAttribute('id', id);
g.setAttribute('data-role', role);
end

function insertAt(root, newG, anchor)
if ~isempty(anchor)
    root.insertBefore(newG, anchor);
else
    root.appendChild(newG);
end
end

function tagLeaf(node, id, role)
node.setAttribute('id', id);
node.setAttribute('data-role', role);
end

function setFontSizeFromLive(node, fontSize)
% setFontSizeFromLive  Overwrites node's own (baked, geometrically-scaled, slightly-rounded --
% bakeTransforms.py, docs/findings.md) font-size attribute with the authoritative LIVE value read
% directly from the corresponding ax/legend property -- no content-matching involved at all for the
% roles this is called for (title/xlabel/ylabel/tick-labels/legend-labels), since which property to
% read is already determined unambiguously by the role itself (REVISED 2026-08-29 from the previous
% content-keyed dumpFontRegistry.m/bakeTransforms.py mechanism -- see this file's own header).
if isempty(fontSize); return; end
node.setAttribute('font-size', sprintf('%.10g', fontSize));
end

function resolved = setAnnotationFontSizeFromLive(node, adHocTextObjs)
% setAnnotationFontSizeFromLive  Unlike setFontSizeFromLive's other callers, an annotation has no
% single ax/legend property to read -- it's whichever live ad hoc text() object shares its exact
% content, among a set already narrowed to "not title/xlabel/ylabel" (small, real content-matching
% risk, same discipline identifyLegend.m already uses for its own box-restricted matching). Leaves
% node's font-size untouched (the baked/scaled fallback stays) if zero or more than one candidate
% shares that content -- returns false so the caller can count it rather than silently guess.
resolved = false;
content = strtrim(char(node.getTextContent()));
if isempty(content) || isempty(adHocTextObjs); return; end
nMatches = 0; matchFontSize = [];
for i = 1:numel(adHocTextObjs)
    if strcmp(strtrim(char(adHocTextObjs(i).String)), content)
        nMatches = nMatches + 1;
        matchFontSize = adHocTextObjs(i).FontSize;
    end
end
if nMatches ~= 1; return; end
setFontSizeFromLive(node, matchFontSize);
resolved = true;
end

function relocateLeaf(node, newParent)
% Moves node into newParent, first inlining every inherited presentation attribute (fill/stroke/
% font-*/etc, walked up from node's CURRENT ancestor chain) directly onto node itself -- so its
% rendering never depends on whichever new (unstyled, id/data-role-only) semantic <g> it ends up
% nested under. MATLAB's own <text> elements already self-declare these directly (confirmed in this
% repo's own probe SVG) so this is a no-op for them; geometry primitives (polyline/path/circle) rely
% on their original style-batching wrapper <g> for most of it, so this matters there.
inlinePresentationAttrs(node);
oldParent = node.getParentNode();
oldParent.removeChild(node);
newParent.appendChild(node);
end

function inlinePresentationAttrs(node)
attrs = {'fill','fill-opacity','fill-rule','stroke','stroke-opacity','stroke-width', ...
    'stroke-linecap','stroke-linejoin','stroke-miterlimit','font-family','font-size', ...
    'font-weight','font-style','vector-effect'};
for i = 1:numel(attrs)
    a = attrs{i};
    if node.hasAttribute(a); continue; end
    v = attrFromAncestor(node, a);
    if ~isempty(v); node.setAttribute(a, v); end
end
end

function val = attrFromAncestor(node, attrName)
val = '';
n = node.getParentNode();
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.hasAttribute(attrName)
        val = char(n.getAttribute(attrName));
        return
    end
    n = n.getParentNode();
end
end

function tf = isPatternFilled(node)
% True if node's own (or inherited) fill references a <pattern> (an image/colorbar-gradient
% referencing rect) rather than a plain solid color -- see identifyFurniture's own caller comment.
val = '';
if node.hasAttribute('fill'); val = char(node.getAttribute('fill')); else; val = attrFromAncestor(node, 'fill'); end
tf = ~isempty(regexp(val, '^url\(#', 'once'));
end

function anchor = earliestOriginalChild(root, nodes)
% Whichever DIRECT CHILD of root contains (or equals) the earliest-in-document-order member of
% `nodes` -- used to insert a new semantic group at the position of its earliest original member,
% preserving paint order relative to every untouched/other-group sibling.
children = root.getChildNodes();
bestIdx = Inf; anchor = [];
for i = 0:children.getLength()-1
    child = children.item(i);
    if child.getNodeType() ~= child.ELEMENT_NODE; continue; end
    for k = 1:numel(nodes)
        if isempty(nodes{k}); continue; end
        if isSelfOrAncestor(child, nodes{k})
            if i < bestIdx; bestIdx = i; anchor = child; end
            break
        end
    end
end
end

function tf = isSelfOrAncestor(candidateAncestor, node)
n = node;
tf = false;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if n.isSameNode(candidateAncestor); tf = true; return; end
    n = n.getParentNode();
end
end

function tf = isDescendantOfTag(node, tagName)
n = node.getParentNode();
tf = false;
while ~isempty(n) && n.getNodeType() == n.ELEMENT_NODE
    if strcmp(char(n.getTagName()), tagName); tf = true; return; end
    n = n.getParentNode();
end
end

function tf = isNodeInList(node, list)
tf = false;
for i = 1:numel(list)
    if ~isempty(list{i}) && node.isSameNode(list{i}); tf = true; return; end
end
end

function pruneEmptyGroups(root)
% Removes any now-empty <g> left behind by relocateLeaf (an original MATLAB style-batching wrapper
% whose entire content was moved out) -- checked by ELEMENT children specifically, since Java DOM
% keeps insignificant whitespace as real Text child nodes that survive a leaf's removal.
kids = root.getChildNodes();
toRemove = {};
for i = 0:kids.getLength()-1
    c = kids.item(i);
    if c.getNodeType() == c.ELEMENT_NODE && strcmp(char(c.getTagName()),'g') && ~hasElementChildren(c)
        toRemove{end+1} = c; %#ok<AGROW>
    end
end
for i = 1:numel(toRemove)
    root.removeChild(toRemove{i});
end
end

function tf = hasElementChildren(node)
kids = node.getChildNodes();
tf = false;
for i = 0:kids.getLength()-1
    if kids.item(i).getNodeType() == kids.item(i).ELEMENT_NODE; tf = true; return; end
end
end
