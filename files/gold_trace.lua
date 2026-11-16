-- gold_trace.lua — 捕获 $7E:9100-$7E:9108 的所有写入(记录 PC), 定位"新游戏初始金币=0"的代码
--
-- 功能:
--   1) 写监控: 金币地址窗口 $7E:9100-$7E:9108, 值变化时记录 frame/addr/value/PC
--   2) 快照: 每 120 帧(约2秒)全量 WRAM+SRAM, 保留最近 200 份 (用于验证时间线)
--   3) 命令文件 /tmp/opencode/mmgold/cmd: reset / snapshot / mark <tag> / quit
--
-- 流程:
--   用户复位并重新开始新游戏, 初始化代码写入金币=0 时, 这里会记录该写入指令的 PC。
--   该 PC 就是要打补丁的位置 (改成 999999)。
local DIR = "/tmp/opencode/mmgold"
os.execute("mkdir -p " .. DIR)

local WRAM = emu.memType.snesWorkRam
local SRAM = emu.memType.snesSaveRam
local WRAM_SIZE = 0x20000
local SRAM_SIZE = 0x2000

local trace = io.open(DIR .. "/goldtrace.log", "a")
local function out(msg)
  if trace then pcall(function() trace:write(msg .. "\n") trace:flush() end) end
  print(msg)
end

local frame = 0
local seq = 0
local keep = 200
local autoInterval = 120
local lastAuto = 0

local function curGold()
  return emu.read(0x7E9102, emu.memType.snesMemory)
       + emu.read(0x7E9103, emu.memType.snesMemory) * 256
       + emu.read(0x7E9104, emu.memType.snesMemory) * 65536
       + emu.read(0x7E9105, emu.memType.snesMemory) * 16777216
end

-- ---- 写监控 (记录窗口内所有写入, 用于捕获零填充/复制等重复写) ----
local logCount = {}

local function onWrite(addr, value)
  if frame == 0 then return end
  logCount[addr] = (logCount[addr] or 0) + 1
  if logCount[addr] <= 200 then
    local st = emu.getState()
    out(string.format("[f=%06d] WRITE $%06X=$%02X  PC=$%02X:%04X  gold=%d", frame, addr, value, st["cpu.k"], st["cpu.pc"], curGold()))
  end
end

-- 注意: 必须用 snesWorkRam + 线性地址注册 (物理地址), 否则匹配失败
emu.addMemoryCallback(onWrite, emu.callbackType.write,
  0x9100, 0x9108, emu.cpuType.snes, emu.memType.snesWorkRam)

-- ---- 快照 ----
local function snapshot()
  local parts = {}
  local chunk = {}
  local n = 0
  for a = 0, WRAM_SIZE - 4, 4 do
    n = n + 1
    chunk[n] = string.pack("<I4", emu.read32(a, WRAM))
    if n >= 4096 then
      parts[#parts + 1] = table.concat(chunk)
      chunk = {}
      n = 0
    end
  end
  if n > 0 then parts[#parts + 1] = table.concat(chunk) end
  chunk = {}
  n = 0
  for a = 0, SRAM_SIZE - 4, 4 do
    n = n + 1
    chunk[n] = string.pack("<I4", emu.read32(a, SRAM))
    if n >= 4096 then
      parts[#parts + 1] = table.concat(chunk)
      chunk = {}
      n = 0
    end
  end
  if n > 0 then parts[#parts + 1] = table.concat(chunk) end
  return table.concat(parts)
end

local function saveSnapshot(tag)
  seq = seq + 1
  local name = tag and string.format("mark_%03d_%s.bin", seq, tag) or string.format("snap_%03d.bin", seq)
  local path = DIR .. "/" .. name
  local f = io.open(path, "wb")
  f:write(snapshot())
  f:close()
  out(string.format("[f=%d] saved %s (gold=%d)", frame, path, curGold()))
  return path
end

local function cleanup()
  local ok, f = pcall(io.popen, "ls -1t " .. DIR .. "/snap_*.bin 2>/dev/null | tail -n +" .. (keep + 1))
  if ok and f then
    for line in f:lines() do os.remove(line) end
    pcall(f.close, f)
  end
end

-- ---- 命令处理 ----
local CMD_FILE = DIR .. "/cmd"
local function processCommands()
  local f = io.open(CMD_FILE, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  os.remove(CMD_FILE)
  for line in string.gmatch(content, "[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "reset" then
      out("=== CMD RESET ===")
      local ok, err = pcall(emu.reset)
      if not ok then out("emu.reset failed: " .. tostring(err)) end
    elseif line == "snapshot" then
      out("=== CMD SNAPSHOT ===")
      saveSnapshot("cmd")
    elseif line:sub(1, 5) == "mark " then
      out("=== CMD MARK " .. line:sub(6) .. " ===")
      saveSnapshot(line:sub(6))
    elseif line == "quit" then
      out("=== CMD QUIT ===")
      emu.stop(0)
    else
      out("unknown cmd: " .. line)
    end
  end
end

emu.addEventCallback(function()
  frame = frame + 1

  if frame - lastAuto >= autoInterval then
    lastAuto = frame
    saveSnapshot()
    if frame % 600 == 0 then cleanup() end
  end

  processCommands()

  if frame == 1 then
    out("=== gold_trace started. 当前金币 = " .. curGold() .. " ===")
    out("=== 监控窗口 WRAM $9100-$9108 (线性). 命令文件: " .. CMD_FILE .. " (reset/snapshot/mark <tag>/quit) ===")
  end
end, emu.eventType.endFrame)
