-- ============================================================
-- 技能树系统 - 中文汉化版新增技能（拆分自 registry.lua）
-- 内容：自定义扩展技能（战斗者SP系列、能手VI/VII、熟练于心、
--       连携作战等）的定义与数值，以及被注释禁用的扩展技能占位
-- ============================================================

-- GM 全局仅在技能树加载阶段可用，此处捕获为 local 以便后续使用
local GM = GM or GAMEMODE

-- ============================================================
-- 技能描述颜色标记
-- ^ 后跟颜色ID，用于描述文本中的着色
-- ============================================================
local GOOD = "^"..COLORID_GREEN
local BAD = "^"..COLORID_RED

-- ============================================================
-- 以下为中文汉化版新增技能（自定义扩展内容）
-- ============================================================

-- 路障专家 SP01
GM:AddSkill(SKILL_BARRICADEEXPERT_SP01, "熟练于心", GOOD.."+12% 木工锤挥动速度",
																0,			5,					{SKILL_BARRICADEEXPERT}, TREE_BUILDINGTREE)

-- 能手 VI / VII / 巧夺天工
GM:AddSkill(SKILL_HANDY6, "能手 VI", GOOD.."+9% repair rate",
																-3,			5,					{SKILL_HANDY5}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDY7, "能手 VII", GOOD.."+10% repair rate",
																-4,			5,					{SKILL_HANDY6}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDYSP_01, "巧夺天工", GOOD.."+15% repair rate",
																-5,			5,					{SKILL_HANDY7}, TREE_BUILDINGTREE)

-- 战斗者 SP01-SP07（磨炼系列 / 锐不可当 / 重斩）
GM:AddSkill(SKILL_BATTLERSP01, "磨炼 I", GOOD.."+2 初始菜单点数",
																0,			7,					{SKILL_LASTSTAND}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP02, "磨炼 II", GOOD.."+2 初始菜单点数",
																1,			7,					{SKILL_BATTLERSP01}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP03, "磨炼 III", GOOD.."+2 初始菜单点数",
																2,			7,					{SKILL_BATTLERSP02}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP04, "锐不可当", GOOD.."+10% 近战伤害",
																3,			7,					{SKILL_BATTLERSP03}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP05, "磨炼 IV", GOOD.."+2 初始菜单点数",
																4,			7,					{SKILL_BATTLERSP04}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP06, "磨炼 V", GOOD.."+2 初始菜单点数\n"..GOOD.."+5% 近战范围",
																5,			7,					{SKILL_BATTLERSP05}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLERSP07, "重斩", GOOD.."+20% 近战伤害\n"..BAD.."+8% 近战攻击延迟",
																6,			7,					{SKILL_BATTLERSP06}, TREE_MELEETREE)
--[[
-- 究极天赋：良缘的庇佑
GM:AddSkill(SKILL_BATTLERSP_114514, "究极天赋：良缘的庇佑", GOOD.."近战攻击时追加30%伤害\n"..GOOD.."空中攻击时.攻速增加300%且会每次攻击会滞留一段时间\n"..GOOD.."势不可挡:霸体",
																3,			9,					{SKILL_BATTLERSP07}, TREE_MELEETREE)

-- 基头四 / 海虎爆破钳 / 次男道（拳击扩展）
GM:AddSkill(SKILL_COMBOKNUCKLESP01, "基头四", GOOD.."-5% 拳头攻击间隔\n"..GOOD.."+4 最大生命值\nY~M~C~A一轮强劲的音乐响起.唏 YOUNG MAN!.站在你门前的是！四个穿着很少布的大只佬!\n咸湿的眼神~淫贱的笑意~讨人厌的动作!",
																8,			-4,					{SKILL_COMBOKNUCKLE}, TREE_MELEETREE)
GM:AddSkill(SKILL_COMBOKNUCKLESP02, "海虎爆破钳", GOOD.."-5% 拳头攻击间隔\n"..GOOD.."+15% 拳头伤害\n让我找找秘密武器~",
																9,			-4,					{SKILL_COMBOKNUCKLESP01}, TREE_MELEETREE)
GM:AddSkill(SKILL_COMBOKNUCKLESP03, "次男道", GOOD.."-8% 拳头攻击间隔\n"..GOOD.."+20% 拳头伤害\n二十万匹力量！",
																10,			-4,					{SKILL_COMBOKNUCKLESP02}, TREE_MELEETREE)
]]
-- 连携作战
GM:AddSkill(SKILL_FIELDAMPSP01,"连携作战", GOOD.."-10% 电塔与维修立场攻击延迟\n"..GOOD.."+10% 电塔和维修立场攻击范围\n"..BAD.."-12 移动速度\n血肉苦痛，机械飞升！",
																7,			4,					{SKILL_FIELDAMP}, TREE_BUILDINGTREE)

-- ============================================================
-- 中文汉化版新增技能的修饰符数值
-- ============================================================
-- ============================================================
-- 以下是中文汉化版新增技能修饰符
-- ============================================================

-- 磨炼 I-V：初始菜单点数
GM:AddSkillModifier(SKILL_BATTLERSP01, SKILLMOD_WORTH, 2)
GM:AddSkillModifier(SKILL_BATTLERSP02, SKILLMOD_WORTH, 2)
GM:AddSkillModifier(SKILL_BATTLERSP03, SKILLMOD_WORTH, 2)
GM:AddSkillModifier(SKILL_BATTLERSP05, SKILLMOD_WORTH, 2)
GM:AddSkillModifier(SKILL_BATTLERSP06, SKILLMOD_WORTH, 2)

-- 锐不可当：近战伤害 +10%
GM:AddSkillModifier(SKILL_BATTLERSP04, SKILLMOD_MELEE_DAMAGE_MUL, 0.1)

-- 磨炼 V：近战范围 +5%
GM:AddSkillModifier(SKILL_BATTLERSP06, SKILLMOD_MELEE_RANGE_MUL, 0.05)

-- 重斩：近战伤害 +20%，近战攻击延迟 +8%
GM:AddSkillModifier(SKILL_BATTLERSP07, SKILLMOD_MELEE_DAMAGE_MUL, 0.2)
GM:AddSkillModifier(SKILL_BATTLERSP07, SKILLMOD_MELEE_SWING_DELAY_MUL, 0.08)

-- 究极天赋：良缘的庇佑：近战伤害 +30%
GM:AddSkillModifier(SKILL_BATTLERSP_114514, SKILLMOD_MELEE_DAMAGE_MUL, 0.3)

-- 熟练于心：木工锤挥动速度 -12%
GM:AddSkillModifier(SKILL_BARRICADEEXPERT_SP01, SKILLMOD_HAMMER_SWING_DELAY_MUL, -0.12)

-- 能手 VI / VII / 巧夺天工：修复速度
GM:AddSkillModifier(SKILL_HANDY6, SKILLMOD_REPAIRRATE_MUL, 0.09)
GM:AddSkillModifier(SKILL_HANDY7, SKILLMOD_REPAIRRATE_MUL, 0.1)
GM:AddSkillModifier(SKILL_HANDYSP_01, SKILLMOD_REPAIRRATE_MUL, 0.15)

-- 基头四：拳头攻击间隔 -5%，生命 +4
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP01, SKILLMOD_UNARMED_SWING_DELAY_MUL, -0.05)
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP01, SKILLMOD_HEALTH, 4)

-- 海虎爆破钳：拳头攻击间隔 -5%，拳头伤害 +15%
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP02, SKILLMOD_UNARMED_SWING_DELAY_MUL, -0.05)
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP02, SKILLMOD_UNARMED_DAMAGE_MUL, 0.15)

-- 次男道：拳头攻击间隔 -8%，拳头伤害 +20%
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP03, SKILLMOD_UNARMED_SWING_DELAY_MUL, -0.08)
GM:AddSkillModifier(SKILL_COMBOKNUCKLESP03, SKILLMOD_UNARMED_DAMAGE_MUL, 0.2)

-- 连携作战：速度 -12
GM:AddSkillModifier(SKILL_FIELDAMPSP01, SKILLMOD_SPEED, -12)

