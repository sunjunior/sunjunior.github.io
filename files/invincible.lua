-- Invincible: 无敌测试脚本
-- 原理: 死亡重生后游戏会把 $89 (无敌/护盾计时器) 置 3 再递减。
--       每帧把 $89 写回 3, 让游戏认为玩家一直处于重生无敌状态。
-- 开关: 按 P1 的 Select 按钮 (你绑定的是 Q 键) 切换 开/关。
-- 验证: 开启后让敌人子弹打你, 应不再扣生命 ($51 不变, 坦克不爆炸)。

local MT = emu.memType.nesInternalRam
local function rd(a) return emu.read(a, MT) end
local function wr(a, v) emu.write(a, v, MT) end

local SHIELD_ADDR = 0x89
local SHIELD_VAL = 3
local SEL_BIT = 0x04

local on = true
local lastSel = false

print("=== Invincible 已启动: 每帧写 $89=" .. SHIELD_VAL .. " (无敌) ===")
print("按 P1 Select (你绑定的 Q 键) 切换开关; 当前: 开启")

emu.addEventCallback(function()
  local cur06 = rd(0x06)
  local selDown = ((rd(0x08) & SEL_BIT) ~= 0) or ((cur06 & SEL_BIT) ~= 0 and not lastSel)
  if selDown then
    on = not on
    print("无敌: " .. (on and "开启" or "关闭"))
  end
  lastSel = (cur06 & SEL_BIT) ~= 0

  if on then
    wr(SHIELD_ADDR, SHIELD_VAL)
  end
end, emu.eventType.startFrame)
