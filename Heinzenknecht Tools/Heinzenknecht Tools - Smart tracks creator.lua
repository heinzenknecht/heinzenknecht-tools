-- @description Heinzenknecht Tools - Smart Tracks Creator
-- @version 1.0
-- @author Guido Heinzenknecht
-- @link https://heinzenknecht.com/
-- @about
--   Replaces REAPER's default track creation behavior with folder-aware logic
--   optimized for asset organization workflows.
--
--   If no track is selected:
--   - a new folder track is created at the end of the project
--   - two child tracks are automatically created beneath it
--   - the folder is immediately collapsed
--
--   If a regular top-level track is selected:
--   - a new folder track is created below the selected track
--   - two child tracks are automatically created beneath it
--   - the folder is immediately collapsed
--
--   If a collapsed folder parent is selected:
--   - a new folder track is created after the entire folder block
--   - two child tracks are automatically created beneath it
--   - the folder is immediately collapsed
--
--   If an expanded folder parent is selected:
--   - a single child track is created directly inside the folder
--
--   If a child track is selected:
--   - a single track is created below the selected track
--
--   If the selected child track is the last track in its folder:
--   - a new child track is created within the same folder
--   - folder closing information is automatically transferred to preserve
--     the folder structure
--
--   Newly created folder tracks are created in a fully collapsed state.

local function getSelectedTrack()
    return reaper.GetSelectedTrack(0, 0)
end

local function getTrackIndex(tr)
    return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1
end

local function getFolderDepthDelta(tr)
    return math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH"))
end

local function getFolderCompactState(tr)
    return math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT"))
end

local function insertTrackAt(index)
    reaper.InsertTrackAtIndex(index, true)
    return reaper.GetTrack(0, index)
end

local function selectOnlyTrack(tr)
    if tr then
        reaper.SetOnlyTrackSelected(tr)
    end
end

local function createSingleTrackBelow(insertIndex)
    local newTrack = insertTrackAt(insertIndex)
    selectOnlyTrack(newTrack)
end

local function createSingleTrackBelowKeepingGroup(selectedTrack)
    local insertIndex = getTrackIndex(selectedTrack) + 1
    local originalDepth = getFolderDepthDelta(selectedTrack)

    local newTrack = insertTrackAt(insertIndex)

    -- If the selected track closes folder(s), move that closing depth
    -- to the new track so it stays in the same group.
    if originalDepth < 0 then
        reaper.SetMediaTrackInfo_Value(selectedTrack, "I_FOLDERDEPTH", 0)
        reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", originalDepth)
    end

    selectOnlyTrack(newTrack)
end

local function createCollapsedFolderBelow(insertIndex)
    reaper.InsertTrackAtIndex(insertIndex, true)
    reaper.InsertTrackAtIndex(insertIndex + 1, true)
    reaper.InsertTrackAtIndex(insertIndex + 2, true)

    local parent = reaper.GetTrack(0, insertIndex)
    local child1 = reaper.GetTrack(0, insertIndex + 1)
    local child2 = reaper.GetTrack(0, insertIndex + 2)

    -- Parent opens folder
    reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)

    -- First child remains a child
    reaper.SetMediaTrackInfo_Value(child1, "I_FOLDERDEPTH", 0)

    -- Last child closes folder
    reaper.SetMediaTrackInfo_Value(child2, "I_FOLDERDEPTH", -1)

    -- Fully collapsed
    reaper.SetMediaTrackInfo_Value(parent, "I_FOLDERCOMPACT", 2)

    selectOnlyTrack(parent)
end

local function findEndOfFolderBlock(folderParentTrack)
    local startIndex = getTrackIndex(folderParentTrack)
    local nesting = getFolderDepthDelta(folderParentTrack)

    if nesting <= 0 then
        return startIndex
    end

    local trackCount = reaper.CountTracks(0)
    local lastIndex = startIndex

    for i = startIndex + 1, trackCount - 1 do
        local tr = reaper.GetTrack(0, i)
        nesting = nesting + getFolderDepthDelta(tr)
        lastIndex = i

        if nesting <= 0 then
            break
        end
    end

    return lastIndex
end

reaper.Undo_BeginBlock2(0)
reaper.PreventUIRefresh(1)

local selectedTrack = getSelectedTrack()

if not selectedTrack then

    -- No selection -> folder at end
    createCollapsedFolderBelow(reaper.CountTracks(0))

else
    local parentTrack = reaper.GetParentTrack(selectedTrack)

    if parentTrack then

        -- Child track selected
        local folderDepth = getFolderDepthDelta(selectedTrack)

        if folderDepth < 0 then
            -- Last child in the group: keep the new track inside the same group
            createSingleTrackBelowKeepingGroup(selectedTrack)
        else
            -- Regular child: normal track below
            createSingleTrackBelow(getTrackIndex(selectedTrack) + 1)
        end

    else
        local folderDepth = getFolderDepthDelta(selectedTrack)
        local compactState = getFolderCompactState(selectedTrack)

        if folderDepth > 0 then

            -- Folder parent selected
            if compactState > 0 then
                -- Collapsed folder -> create sibling folder after block
                local insertIndex = findEndOfFolderBlock(selectedTrack) + 1
                createCollapsedFolderBelow(insertIndex)
            else
                -- Expanded folder -> create track inside folder
                createSingleTrackBelow(getTrackIndex(selectedTrack) + 1)
            end

        else
            -- Regular top-level track -> create folder below
            createCollapsedFolderBelow(getTrackIndex(selectedTrack) + 1)
        end
    end
end

reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock2(0, "Smart create track / collapsed folder", -1)