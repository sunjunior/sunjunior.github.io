-- eagle_probe.lua: 增强版探针。
-- 1) $030B 上升沿 → 基地被炸:转储全 RAM 快照
-- 2) $05 写回调 → 值==$24 时转储快照+栈,定位是谁写出的标题画面
-- 3) 触发后逐帧记录状态变化(持续 6000 帧,含自然游戏结束→标题)
local DIR = "/tmp/opencode/tank"
local log = io.open(DIR .. "/eagle_probe.log", "w")
local MT = emu.memType.nesInternalRam
local f = 0
local tripped = false
local trip_frame = 0
local last030B = 0
local last_state = ""
local title_cont = 0
local last_title_write = -999

local function rd(a) return emu.read(a, MT) end
local function hex(x) return string.format("%02X", x) end
local function h16(x) return string.format("%04X", x) end

local function state()
  return string.format("f=%d 05=%02X 0A=%02X 0B=%02X 85=%02X 46=%02X 4B=%02X 4D=%02X 51=%02X 52=%02X 68=%02X 80=%02X 83=%02X 63=%02X 66=%02X 67=%02X 6D=%02X 7D=%02X 7E=%02X 0300=%02X 0304=%02X 0307=%02X 030B=%02X",
    f, rd(0x05), rd(0x0A), rd(0x0B), rd(0x85), rd(0x46), rd(0x4B), rd(0x4D),
    rd(0x51), rd(0x52), rd(0x68), rd(0x80), rd(0x83), rd(0x63), rd(0x66), rd(0x67),
    rd(0x6D), rd(0x7D), rd(0x7E), rd(0x0300), rd(0x0304), rd(0x0307), rd(0x030B))
end

local function dumpSnapshot(tag)
  log:write("--- SNAPSHOT [" .. tag .. "] " .. state() .. "\n")
  log:write("ZP:  ")
  for a = 0x00, 0xFF do log:write(string.format("%02X ", rd(a))) end
  log:write("\nSTK: ")
  for a = 0x100, 0x1FF do log:write(string.format("%02X ", rd(a))) end
  log:write("\nSND: ")
  for a = 0x0300, 0x030F do log:write(string.format("%02X ", rd(a))) end
  log:write("\n--- END SNAPSHOT\n")
  log:flush()
end

emu.addMemoryCallback(function(addr, val)
  if addr == 0x05 and val == 0x24 and (f - last_title_write) > 2 then
    last_title_write = f
    log:write("### [05=$24 WRITE] " .. state() .. "\n")
    dumpSnapshot("05WRITE")
  end
end, emu.callbackType.write, 0x05, 0x05)

log:write("eagle_probe ready (0x030B latch + $05=$24 writer probe)\n")
log:flush()

emu.addEventCallback(function()
  f = f + 1
  local b = rd(0x030B)
  if not tripped and b ~= 0 and last030B == 0 then
    tripped = true
    trip_frame = f
    log:write("=== [EAGLE-DESTROYED] " .. state() .. "\n")
    dumpSnapshot("TRIP")
  end
  last030B = b
  if tripped and (f - trip_frame) <= 6000 then
    local s = state()
    if s ~= last_state then
      log:write("[FRAME] " .. s .. "\n")
      log:flush()
      last_state = s
    end
    if rd(0x05) == 0x24 then
      title_cont = title_cont + 1
      if title_cont == 60 then
        log:write("*** [TITLE-SUSTAINED] " .. state() .. "\n")
        dumpSnapshot("TITLE60")
      end
    else
      title_cont = 0
    end
  end
end, emu.eventType.endFrame)
print("eagle_probe loaded")
