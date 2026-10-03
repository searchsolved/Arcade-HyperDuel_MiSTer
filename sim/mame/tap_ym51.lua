-- YM2151 write/status tap for Hyper Duel (docs/ACCURACY.md 3.7), same
-- format as tb_system +YM51LOG:
--   W,<frame>,<a0>,<byte>   write (a0 = 0 address, 1 data)
--   R,<frame>,<status>      status byte the game read
-- Usage: YM_OUT=<file> TAP_FRAMES=<n> [INPUTS=<file>] mame hyprduel ...
--   -autoboot_script mame/tap_ym51.lua   (add inputs with tap_ym51_play.lua)
local outpath = os.getenv("YM_OUT") or "build/mame/ym51.csv"
local total_frames = tonumber(os.getenv("TAP_FRAMES") or "1800")
local sub = manager.machine.devices[":sub"].spaces["program"]
local fh = io.open(outpath, "w")
local frame_now = 0
local w = sub:install_write_tap(0x400000, 0x400003, "ym51w", function(o, d, m)
  fh:write(string.format("W,%d,%d,%02x\n", frame_now, (o >> 1) & 1, d & 0xff))
end)
local r = sub:install_read_tap(0x400000, 0x400003, "ym51r", function(o, d, m)
  fh:write(string.format("R,%d,%02x\n", frame_now, d & 0xff))
  return d
end)
YM51_KEEP = { w, r }
YM51_KEEP[3] = emu.add_machine_frame_notifier(function()
  frame_now = frame_now + 1
  if frame_now >= total_frames then fh:close(); manager.machine:exit() end
end)
