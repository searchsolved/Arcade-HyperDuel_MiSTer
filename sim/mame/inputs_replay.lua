-- Replays a tb_system +INPUTS file ("<frame> <p1p2hex> <systemhex>",
-- active low, held until the next line) into MAME's P1_P2 and SYSTEM
-- ports, so MAME and the core see the same choreography. Load after a tap:
--   -autoboot_script mame/tap_oki_play.lua with INPUTS=<file>
local path = os.getenv("INPUTS")
local rows = {}
for line in io.lines(path) do
  local f, a, b = line:match("^(%d+)%s+(%x+)%s+(%x+)")
  if f then rows[#rows + 1] = { tonumber(f), tonumber(a, 16), tonumber(b, 16) } end
end
local ports = manager.machine.ioport.ports
local function apply(port, value)
  for _, field in pairs(ports[port].fields) do
    if field.type_class ~= "config" and field.type_class ~= "dipswitch" then
      local pressed = (value & field.mask) == 0
      field:set_value(pressed and 1 or 0)
    end
  end
end
local idx, n = 1, 0
INPUT_REPLAY_KEEP = emu.add_machine_frame_notifier(function()
  n = n + 1
  while idx <= #rows and rows[idx][1] <= n do
    apply(":P1_P2", rows[idx][2]); apply(":SYSTEM", rows[idx][3])
    idx = idx + 1
  end
end)
