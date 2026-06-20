-- @description Heinzenknecht Tools - Align items for asset creation
-- @version 1.0
-- @author Guido Heinzenknecht
-- @link https://heinzenknecht.com/
-- @about
--   Aligns selected items into a structured layout for asset creation workflows.
--
--   If all selected units are on a single track, the script behaves as a
--   standard sequential arranger:
--   - units are ordered by their timeline position
--   - each unit is placed immediately after the previous one
--   - a 500 ms gap is inserted between units
--
--   If selected units span multiple tracks, units are grouped according to
--   their order on each track:
--   - the first unit on every track starts at the same time
--   - each subsequent group starts after the longest unit in the previous
--     group plus a 500 ms gap
--   - if a track contains fewer units than others, the remaining tracks
--     continue following the same grouping logic
--
--   REAPER item groups are treated as single units:
--   - all selected items sharing the same I_GROUPID are moved together
--   - the unit duration is calculated from the earliest start position to
--     the latest end position within the group

local GAP_SECONDS = 0.5

local function getTrackNumber(track)
    return math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
end

local function getUnitKey(item)
    local groupId = math.floor(reaper.GetMediaItemInfo_Value(item, "I_GROUPID") or 0)
    if groupId > 0 then
        return "G" .. tostring(groupId)
    end
    return "I" .. tostring(item)
end

local function collectUnits()
    local itemCount = reaper.CountSelectedMediaItems(0)
    local unitMap = {}

    for i = 0, itemCount - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItemTrack(item)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local key = getUnitKey(item)

        local unit = unitMap[key]
        if not unit then
            unit = {
                key = key,
                items = {},
                startPos = pos,
                endPos = pos + len,
                track = track,
                trackNum = getTrackNumber(track)
            }
            unitMap[key] = unit
        end

        unit.items[#unit.items + 1] = {
            item = item,
            pos = pos,
            len = len,
            track = track
        }

        if pos < unit.startPos then
            unit.startPos = pos
        end

        local itemEnd = pos + len
        if itemEnd > unit.endPos then
            unit.endPos = itemEnd
        end

        local tn = getTrackNumber(track)
        if tn < unit.trackNum then
            unit.trackNum = tn
            unit.track = track
        end
    end

    local units = {}
    for _, unit in pairs(unitMap) do
        unit.len = unit.endPos - unit.startPos
        units[#units + 1] = unit
    end

    return units
end

local function moveUnitTo(unit, targetPos)
    local delta = targetPos - unit.startPos
    for _, entry in ipairs(unit.items) do
        reaper.SetMediaItemInfo_Value(entry.item, "D_POSITION", entry.pos + delta)
    end
end

local function sortUnitsByPosition(a, b)
    if a.startPos == b.startPos then
        return a.trackNum < b.trackNum
    end
    return a.startPos < b.startPos
end

local function arrangeSingleTrack(units)
    table.sort(units, sortUnitsByPosition)

    local currentPos = units[1].startPos
    for _, unit in ipairs(units) do
        moveUnitTo(unit, currentPos)
        currentPos = currentPos + unit.len + GAP_SECONDS
    end
end

local function arrangeMultiTrack(units)
    local trackMap = {}
    local trackOrder = {}

    for _, unit in ipairs(units) do
        if not trackMap[unit.track] then
            trackMap[unit.track] = {}
            trackOrder[#trackOrder + 1] = unit.track
        end
        trackMap[unit.track][#trackMap[unit.track] + 1] = unit
    end

    table.sort(trackOrder, function(a, b)
        return getTrackNumber(a) < getTrackNumber(b)
    end)

    for _, track in ipairs(trackOrder) do
        table.sort(trackMap[track], sortUnitsByPosition)
    end

    local startPos = nil
    local maxGroups = 0

    for _, track in ipairs(trackOrder) do
        local list = trackMap[track]
        if #list > 0 then
            if not startPos or list[1].startPos < startPos then
                startPos = list[1].startPos
            end
            if #list > maxGroups then
                maxGroups = #list
            end
        end
    end

    if not startPos then
        return
    end

    local currentPos = startPos

    for groupIndex = 1, maxGroups do
        local groupUnits = {}
        local groupLen = 0

        for _, track in ipairs(trackOrder) do
            local unit = trackMap[track][groupIndex]
            if unit then
                groupUnits[#groupUnits + 1] = unit
                if unit.len > groupLen then
                    groupLen = unit.len
                end
            end
        end

        for _, unit in ipairs(groupUnits) do
            moveUnitTo(unit, currentPos)
        end

        currentPos = currentPos + groupLen + GAP_SECONDS
    end
end

local units = collectUnits()

if #units < 2 then
    reaper.ShowMessageBox("Select at least 2 items, or 2 grouped items treated as one unit.", "Error", 0)
    return
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local trackSet = {}
for _, unit in ipairs(units) do
    trackSet[unit.track] = true
end

local trackCount = 0
for _ in pairs(trackSet) do
    trackCount = trackCount + 1
end

if trackCount == 1 then
    arrangeSingleTrack(units)
else
    arrangeMultiTrack(units)
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Arrange selected items with 500ms gap, grouped items as single units", -1)