-- OKI M6295 command/status tap (jt6295 busy-start and stop-byte patches,
-- docs/ACCURACY.md 3.7). Logs every sub-CPU write to and read from the OKI
-- port with the frame number, and for each phrase start (the second byte
-- of a play command) whether the selected voices were already busy in MAME
-- at that instant (MAME ignores those starts, okim6295.cpp L281-284).
--
-- Usage (hyprduel; magerror: OKI_BASE=0x800004 and the magerror set):
--   TAP_OUT=<file> TAP_FRAMES=3600 mame hyprduel -rompath ../roms \
--     -video none -sound none -nothrottle -autoboot_script mame/tap_oki.lua
--
-- Output CSV lines:
--   W,<frame>,<byte>,<emu seconds>   command byte written
--   R,<frame>,<status>               status read by the game
--   S,<frame>,<phrase>,<chmask>,<busy_before>   phrase start request

local outpath = os.getenv("TAP_OUT") or "build/mame/oki_tap.csv"
local total_frames = tonumber(os.getenv("TAP_FRAMES") or "3600")
local base = tonumber(os.getenv("OKI_BASE") or "0x400004")

local sub = manager.machine.devices[":sub"].spaces["program"]
local oki = manager.machine.devices[":oki"]
local fh = io.open(outpath, "w")
local frame_now = 0
local pending = -1

-- voice playing flags from the device's save items (reading the port from
-- inside a tap hangs MAME). The stream is brought up to date by the write
-- handler itself, after this tap runs, so a voice that ended since the last
-- stream update can still read as playing: an upper bound on busy starts.
local playing = {}
for name, idx in pairs(oki.items) do
  local v = name:match("^(%d)/m_voice%[voicenum%]%.m_playing$")
  if v then playing[tonumber(v)] = emu.item(idx) end
end
local function status_now()
  local v = 0
  for i = 0, 3 do
    if playing[i] and playing[i]:read(0) ~= 0 then v = v | (1 << i) end
  end
  return v
end

local wtap = sub:install_write_tap(base, base + 1, "oki_wtap",
  function(offset, data, mask)
    local b
    if (mask & 0x00ff) ~= 0 then b = data & 0xff else b = (data >> 8) & 0xff end
    fh:write(string.format("W,%d,%02x,%.9f\n", frame_now, b, manager.machine.time:as_double()))
    if pending >= 0 then
      local busy = status_now() & 0x0f
      fh:write(string.format("S,%d,%02x,%x,%x\n", frame_now, pending, (b >> 4) & 0x0f, busy))
      pending = -1
    elseif (b & 0x80) ~= 0 then
      pending = b & 0x7f
    end
  end)

local rtap = sub:install_read_tap(base, base + 1, "oki_rtap",
  function(offset, data, mask)
    local v
    if (mask & 0x00ff) ~= 0 then v = data & 0xff else v = (data >> 8) & 0xff end
    fh:write(string.format("R,%d,%02x\n", frame_now, v))
    return data
  end)

-- keep the subscriptions referenced from a global, or the garbage collector
-- removes them once this chunk returns
OKI_TAP_KEEP = { wtap, rtap }
OKI_TAP_KEEP[3] = emu.add_machine_frame_notifier(function()
  frame_now = frame_now + 1
  if frame_now >= total_frames then
    fh:close()
    manager.machine:exit()
  end
end)
