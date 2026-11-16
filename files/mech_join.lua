-- mech_join.lua — 捕捉机械师加入瞬间 WRAM 槽位定位
-- 操作: 加载机械师加入前存档, 运行脚本, 按 F 开始, 触发机械师加入剧情, 按 F 停止
local DIR = "/tmp/opencode/mmgold"
os.execute("mkdir -p " .. DIR)
local logf = io.open(DIR .. "/mech_join.log", "w")
local function out(m)
  pcall(function() logf:write(m .. "\n") logf:flush() end)
  print(m)
end

local MEM = emu.memType.snesMemory
local frame = 0
local recording = false
local lastF = false
local writes = {}

-- 记录: 机械师加入前, 扫全 WRAM 角色区, 找出非零槽位
local function scan_slots(tag)
  out("=== " .. tag .. " 扫描角色区 ===")
  -- 扫描 $7E8000-$7E8400, 每 0xC0 一个槽位, 打印非零块
  for base = 0x7E8000, 0x7E8400, 0xC0 do
    local nonzero = {}
    for off = 0, 0xBF do
      local v = emu.read(base + off, MEM)
      if v ~= 0 then
        nonzero[#nonzero+1] = string.format("%02X", v)
      else
        nonzero[#nonzero+1] = "00"
      end
    end
    -- 只在有数据时打印
    local hasdata = false
    for i,v in ipairs(nonzero) do
      if v ~= "00" then hasdata = true end
    end
    if hasdata then
      out(string.format("  $%04X: %s", base & 0xFFFF, table.concat(nonzero, " ")))
    end
  end
  out("=== 扫描结束 ===")
end

local function onWrite(addr, value)
  if not recording then return end
  local st = emu.getState()
  writes[#writes+1] = {addr=addr, value=value, pc=st["cpu.pc"], k=st["cpu.k"], frame=frame}
end

-- 监控整个角色区
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x7E8000, 0x7E8500, emu.cpuType.snes, emu.memType.snesWorkRam)

emu.addEventCallback(function()
  frame = frame + 1
  local fDown = emu.isKeyPressed("F")
  if fDown and not lastF then
    recording = not recording
    if recording then
      out("=== [F] 开始监控 ===")
      writes = {}
      scan_slots("加入前")
    else
      out("=== [F] 停止监控 ===")
      scan_slots("加入后")
      out("写入记录条数: " .. #writes)
      -- 去重统计: 只显示出现过的地址
      local seen = {}
      local order = {}
      for i,w in ipairs(writes) do
        if not seen[w.addr] then seen[w.addr] = true; order[#order+1] = w.addr end
      end
      for _,a in ipairs(order) do
        out(string.format("  地址 $%06X 被写入, 示例: PC=$%02X:%04X f=%d", a, writes[1].k, writes[1].pc, writes[1].frame))
      end
      logf:close()
      out("=== 完成, 日志: " .. DIR .. "/mech_join.log ===")
    end
  end
  lastF = fDown
end, emu.eventType.endFrame)

out("=== mech_join.lua 已加载 ===")
out("加载机械师加入前存档, 按 F 开始, 触发剧情, 按 F 停止")