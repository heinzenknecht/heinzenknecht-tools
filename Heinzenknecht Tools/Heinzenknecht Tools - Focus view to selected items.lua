-- @description Heinzenknecht Tools - Focus view to selected items
-- @version 1.0
-- @author Guido Heinzenknecht
-- @link https://heinzenknecht.com/
-- @about
--   Zooms in horizontally to the selected items
--   Sets the playhead to right before the first item

local proj = 0
local itemCount = reaper.CountSelectedMediaItems(proj)

if itemCount == 0 then
  reaper.MB("No selected items.", "Focus selected items", 0)
  return
end

local minPos = math.huge
local maxEnd = -math.huge

for i = 0, itemCount - 1 do
  local item = reaper.GetSelectedMediaItem(proj, i)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local endPos = pos + len

  if pos < minPos then minPos = pos end
  if endPos > maxEnd then maxEnd = endPos end
end

local startTime = math.max(0, minPos - 1.0)
local endTime = maxEnd + 1.0

reaper.Undo_BeginBlock2(proj)
reaper.PreventUIRefresh(1)

-- Move playhead/edit cursor to the left edge without changing the view
reaper.SetEditCurPos2(proj, startTime, false, true)

-- Set the visible horizontal window explicitly
reaper.GetSet_ArrangeView2(proj, true, 0, 0, startTime, endTime)

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock2(proj, "Focus selected items horizontally", -1)