-- eagle_watch.lua: GUI 实战验证用看门狗。
-- 检测 $030B(老鹰被摧毁的专属音效锁存,仅在 $E6B4 写入)上升沿。
-- 触发后逐帧记录关键状态,并自动标记:
--   [MENU-REACHED]  当 $05==$24(标题画面文本)且 $85==$01 附近 → 回到菜单
--   [CONTINUE-SEEN] 当 $68 重新变为 $80($C388 下一关开始) → 走继续路径
local DIR = "/tmp/opencode/tank"
local log = io.open(DIR .. "/eagle_watch.log", "w")
local f = 0
local tripped = false
local trip_frame = 0
local last030B = 0
local saw_continue = false
local saw_menu = false

local function read(x) return emu.read(x, emu.memType.nesInternalRam) end
local function hex(x) return string.format("%02X", x) end

local function state(extra)
  return string.format("f=%d 68=%02X 0A=%02X 0B=%02X 05=%02X 85=%02X 46=%02X 4B=%02X 51=%02X 52=%02X 6D=%02X 0300=%02X 0307=%02X %s",
    f, read(0x68), read(0x0A), read(0x0B), read(0x05), read(0x85), read(0x46), read(0x4B),
    read(0x51), read(0x52), read(0x6D), read(0x0300), read(0x0307), extra or "")
end

local function dumpStack()
  local s = {}
  for i = 0x100, 0x1FF do s[#s+1] = string.format("%02X", read(i)) end
  log:write("STACK: " .. table.concat(s, " ") .. "\n")
  log:flush()
end

log:write("watchdog ready (0x030B latch)\n")
log:flush()

emu.addEventCallback(function()
  f = f + 1
  local b = read(0x030B)
  if not tripped and b ~= 0 and last030B == 0 then
    tripped = true
    trip_frame = f
    log:write("=== [EAGLE-DESTROYED] 030B=" .. hex(b) .. " " .. state() .. "\n")
    dumpStack()
    log:flush()
  end
  last030B = b
  if tripped then
    -- 标记路径
    if not saw_continue and read(0x68) == 0x80 then
      saw_continue = true
      log:write("*** [CONTINUE-SEEN] 68=$80 " .. state() .. "\n")
    end
    if not saw_menu and read(0x05) == 0x24 and read(0x85) == 0x01 and (f - trip_frame) > 60 then
      saw_menu = true
      log:write("*** [MENU-REACHED] 05=$24 85=$01 " .. state() .. "\n")
    end
    if f - trip_frame <= 1500 then
      log:write("[FRAME] " .. state() .. "\n")
      log:flush()
    elseif saw_continue or saw_menu then
      log:write("--- done: continue=" .. tostring(saw_continue) .. " menu=" .. tostring(saw_menu) .. " @f=" .. f .. "\n")
      log:flush()
      -- 保留 GUI 正常使用,不强制停止
    end
  end
end, emu.eventType.endFrame)
print("eagle_watch loaded (GUI watch mode)")
