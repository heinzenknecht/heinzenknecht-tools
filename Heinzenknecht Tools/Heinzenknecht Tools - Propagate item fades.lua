-- @description Heinzenknecht Tools - Propagate item fades
-- @version 1.0
-- @author Guido Heinzenknecht
-- @link https://heinzenknecht.com/
-- @about
--  Copy/paste fades
--  Select one item first and run the action to copy, then several items to apply the same fades
--  1 selected item   -> COPY
--  2+ selected items -> PASTE

local EXT_SECTION = "FADE_PITCH_ENV_CLIPBOARD_V4"
local PITCH_TOGGLE_CMD = 41612 -- Take: Toggle take pitch envelope

local function q(s)
  return string.format("%q", s or "")
end

local function unq(s)
  if not s or s == "" then return "" end
  local fn = load("return " .. s)
  if not fn then return "" end
  local ok, res = pcall(fn)
  if not ok or type(res) ~= "string" then return "" end
  return res
end

local function split_lines(s)
  local t = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    t[#t + 1] = line
  end
  return t
end

local function save_clip(data)
  local packed = table.concat({
    string.format("%.17g", data.fadein_len),
    string.format("%.17g", data.fadeout_len),
    string.format("%.17g", data.fadein_shape),
    string.format("%.17g", data.fadeout_shape),
    string.format("%.17g", data.fadein_dir),
    string.format("%.17g", data.fadeout_dir),
    q(data.pitch_chunk),
  }, "\n")

  reaper.SetExtState(EXT_SECTION, "data", packed, false)
end

local function load_clip()
  local raw = reaper.GetExtState(EXT_SECTION, "data")
  if raw == "" then return nil end

  local lines = split_lines(raw)
  if #lines < 7 then return nil end

  local nums = {}
  for i = 1, 6 do
    nums[i] = tonumber(lines[i])
    if nums[i] == nil then return nil end
  end

  return {
    fadein_len   = nums[1],
    fadeout_len  = nums[2],
    fadein_shape = nums[3],
    fadeout_shape= nums[4],
    fadein_dir   = nums[5],
    fadeout_dir  = nums[6],
    pitch_chunk  = unq(lines[7]),
  }
end

local function get_active_take_pitch_chunk(item)
  local take = reaper.GetActiveTake(item)
  if not take then return "" end

  local env = reaper.GetTakeEnvelopeByName(take, "Pitch")
  if not env then return "" end

  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok or chunk == "" then return "" end
  return chunk
end

local function copy_from_item(item)
  return {
    fadein_len   = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
    fadeout_len  = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
    fadein_shape = reaper.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"),
    fadeout_shape= reaper.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"),
    fadein_dir   = reaper.GetMediaItemInfo_Value(item, "D_FADEINDIR"),
    fadeout_dir  = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTDIR"),
    pitch_chunk  = get_active_take_pitch_chunk(item),
  }
end

local function select_only_item(proj, item)
  reaper.SelectAllMediaItems(proj, false)
  reaper.SetMediaItemSelected(item, true)
end

local function ensure_pitch_env(item, proj)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end

  local env = reaper.GetTakeEnvelopeByName(take, "Pitch")
  if env then return env end

  select_only_item(proj, item)
  reaper.Main_OnCommand(PITCH_TOGGLE_CMD, 0)

  take = reaper.GetActiveTake(item)
  if not take then return nil end
  return reaper.GetTakeEnvelopeByName(take, "Pitch")
end

local function apply_to_item(item, proj, data)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN",   data.fadein_len)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN",  data.fadeout_len)
  reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", data.fadein_shape)
  reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE",data.fadeout_shape)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINDIR",   data.fadein_dir)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTDIR",  data.fadeout_dir)

  if data.pitch_chunk and data.pitch_chunk ~= "" then
    local env = ensure_pitch_env(item, proj)
    if env then
      reaper.SetEnvelopeStateChunk(env, data.pitch_chunk, false)
    end
  end

  reaper.UpdateItemInProject(item)
end

local proj = 0
local count = reaper.CountSelectedMediaItems(proj)

if count == 0 then
  reaper.MB("No items selected.", "Fade clipboard", 0)
  return
end

if count == 1 then
  local item = reaper.GetSelectedMediaItem(proj, 0)
  if not item then return end

  save_clip(copy_from_item(item))
  return
end

local data = load_clip()
if not data then
  reaper.MB("No copied fade/envelope data.\nSelect one item first to copy it.", "Fade clipboard", 0)
  return
end

local items = {}
for i = 0, count - 1 do
  local item = reaper.GetSelectedMediaItem(proj, i)
  if item then
    items[#items + 1] = item
  end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

for _, item in ipairs(items) do
  apply_to_item(item, proj, data)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Copy/paste item fades and take pitch envelope", -1)

-- Restore original selection if we changed it while creating pitch envelopes
reaper.SelectAllMediaItems(proj, false)
for _, item in ipairs(items) do
  reaper.SetMediaItemSelected(item, true)
end