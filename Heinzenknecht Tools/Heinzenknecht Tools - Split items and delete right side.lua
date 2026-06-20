-- @description Heinzenknecht Tools - Split items and delete right side
-- @version 1.0
-- @author Guido Heinzenknecht
-- @link https://heinzenknecht.com/
-- @about
--   Split selected item at edit cursor
--   Delete the right side
--   Add a 0.1s fade-in to the remaining right side.

local FADE_LEN = 0.1

local cursor_pos = reaper.GetCursorPosition()

-- Collect selected items first so deleting items does not affect iteration.
local items = {}
local item_count = reaper.CountSelectedMediaItems(0)

for i = 0, item_count - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  if item then
    items[#items + 1] = item
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, item in ipairs(items) do
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_pos + item_len

  -- Only split items that actually contain the edit cursor.
  if cursor_pos > item_pos and cursor_pos < item_end then
    local right_item = reaper.SplitMediaItem(item, cursor_pos)
    if right_item then
      local tr = reaper.GetMediaItemTrack(item)
      reaper.DeleteTrackMediaItem(tr, right_item) -- remove right side
      reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", FADE_LEN)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Split selected items, delete right side, add fade-out", -1)