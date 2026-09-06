-- ============================================================
-- 技能树系统 - 近战树（Melee Tree）（拆分自 registry.lua）
-- 内容：侧重近战伤害、攻速、拳击的技能定义与本树技能的修饰符数值
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
-- 近战树（Melee Tree）
-- 侧重近战伤害、攻速、拳击
-- ============================================================

-- 价值 II
GM:AddSkill(SKILL_WORTHINESS2, ""..translate.Get("Skill_Worthiness2"), GOOD..""..translate.Get("Skill_Worthiness2_Good").."\n"..BAD..""..translate.Get("Skill_Worthiness2_Bad"),
    4, 0, {}, TREE_MELEETREE)

-- 战斗者 I-V
GM:AddSkill(SKILL_BATTLER1, ""..translate.Get("Skill_Battler1"), GOOD..""..translate.Get("Skill_Battler1_Good"),
    -6, -6, {SKILL_BATTLER2, SKILL_NONE}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLER2, ""..translate.Get("Skill_Battler2"), GOOD..""..translate.Get("Skill_Battler2_Good"),
    -6, -4, {SKILL_BATTLER3, SKILL_LIGHTWEIGHT}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLER3, ""..translate.Get("Skill_Battler3"), GOOD..""..translate.Get("Skill_Battler3_Good"),
    -4, -2, {SKILL_BATTLER4, SKILL_LANKY}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLER4, ""..translate.Get("Skill_Battler4"), GOOD..""..translate.Get("Skill_Battler4_Good"),
    -2, 0, {SKILL_BATTLER5, SKILL_MASTERCHEF, SKILL_D_CLUMSY}, TREE_MELEETREE)
GM:AddSkill(SKILL_BATTLER5, ""..translate.Get("Skill_Battler5"), GOOD..""..translate.Get("Skill_Battler5_Good"),
    0, 2, {SKILL_GLASSWEAPONS, SKILL_BLOODLUST}, TREE_MELEETREE)

-- 最后一战 / 玻璃武器 / 笨拙（负面）
GM:AddSkill(SKILL_LASTSTAND, ""..translate.Get("Skill_LastStand"), GOOD..""..translate.Get("Skill_LastStand_Good").."\n"..BAD..""..translate.Get("Skill_LastStand_Bad"),
    0, 6, {}, TREE_MELEETREE)
GM:AddSkill(SKILL_GLASSWEAPONS, ""..translate.Get("Skill_GlassWeapons"), GOOD..""..translate.Get("Skill_GlassWeapons_Good").."\n"..BAD..""..translate.Get("Skill_GlassWeapons_Bad"),
    2, 4, {}, TREE_MELEETREE)
GM:AddSkill(SKILL_D_CLUMSY, ""..translate.Get("Skill_D_Clumsy"), GOOD..""..translate.Get("Skill_D_Clumsy_Good").."\n"..BAD..""..translate.Get("Skill_D_Clumsy_Bad"),
    -2, 2, {}, TREE_MELEETREE)

-- 廉价拳套 / 暴击拳套 / 拳击大师 / 连击拳套
GM:AddSkill(SKILL_CHEAPKNUCKLE, ""..translate.Get("Skill_CheapKnuclle"), GOOD..""..translate.Get("Skill_CheapKnuclle_Good").."\n"..BAD..""..translate.Get("Skill_CheapKnuclle_Bad"),
    4, -2, {SKILL_HEAVYSTRIKES, SKILL_WORTHINESS2}, TREE_MELEETREE)
GM:AddSkill(SKILL_CRITICALKNUCKLE, ""..translate.Get("Skill_CriticalKnuclle"), GOOD..""..translate.Get("Skill_CriticalKnuclle_Good").."\n"..BAD..""..translate.Get("Skill_CriticalKnuclle_Bad"),
    6, -2, {SKILL_BRASH}, TREE_MELEETREE)
GM:AddSkill(SKILL_KNUCKLEMASTER, ""..translate.Get("Skill_KnuckleMaster"), GOOD..""..translate.Get("Skill_KnuckleMaster_Good1").."\n"..GOOD..""..translate.Get("Skill_KnuckleMaster_Good2").."\n"..BAD..""..translate.Get("Skill_KnuckleMaster_Bad"),
    6, -6, {SKILL_NONE, SKILL_COMBOKNUCKLE}, TREE_MELEETREE)
GM:AddSkill(SKILL_COMBOKNUCKLE, ""..translate.Get("Skill_ComboKnuckle"), GOOD..""..translate.Get("Skill_ComboKnuckle_Good").."\n"..BAD..""..translate.Get("Skill_ComboKnuckle_Bad"),
    6, -4, {SKILL_CHEAPKNUCKLE, SKILL_CRITICALKNUCKLE}, TREE_MELEETREE)

-- 重击 / 长矛手 / 瘦长 I-II / 大厨 / 轻量级 / 嗜血 / 鲁莽
GM:AddSkill(SKILL_HEAVYSTRIKES, ""..translate.Get("Skill_HeavyStrikes"), GOOD..""..translate.Get("Skill_HeavyStrikes_Good").."\n"..BAD..""..translate.Get("Skill_HeavyStrikes_Bad1").."\n"..BAD..""..translate.Get("Skill_HeavyStrikes_Bad2"),
    2, 0, {SKILL_BATTLER5, SKILL_JOUSTER}, TREE_MELEETREE)
GM:AddSkill(SKILL_JOUSTER, ""..translate.Get("Skill_Jouster"), GOOD..""..translate.Get("Skill_Jouster_Good").."\n"..BAD..""..translate.Get("Skill_Jouster_Bad"),
    2, 2, {}, TREE_MELEETREE)
GM:AddSkill(SKILL_LANKY, ""..translate.Get("Skill_LankyI"), GOOD..""..translate.Get("Skill_LankyI_Good").."\n"..BAD..""..translate.Get("Skill_LankyI_Bad"),
    -4, 0, {SKILL_LANKYII}, TREE_MELEETREE)
GM:AddSkill(SKILL_LANKYII, ""..translate.Get("Skill_LankyII"), GOOD..""..translate.Get("Skill_LankyII_Good").."\n"..BAD..""..translate.Get("Skill_LankyII_Bad"),
    -4, 2, {}, TREE_MELEETREE)
GM:AddSkill(SKILL_MASTERCHEF, ""..translate.Get("Skill_MasterChef"), GOOD..""..translate.Get("Skill_MasterChef_Good").."\n"..BAD..""..translate.Get("Skill_MasterChef_Bad"),
    0, -3, {SKILL_BATTLER4}, TREE_MELEETREE)
GM:AddSkill(SKILL_LIGHTWEIGHT, ""..translate.Get("Skill_Lightweight"), GOOD..""..translate.Get("Skill_Lightweight_Good").."\n"..BAD..""..translate.Get("Skill_Lightweight_Bad"),
    -6, -2, {}, TREE_MELEETREE)
GM:AddSkill(SKILL_BLOODLUST, ""..translate.Get("Skill_Bloodlust"), ""..translate.Get("Skill_Bloodlust_Description").."\n"..GOOD..""..translate.Get("Skill_Bloodlust_Good").."\n"..BAD..""..translate.Get("Skill_Bloodlust_Bad"),
    -2, 4, {SKILL_LASTSTAND}, TREE_MELEETREE)
GM:AddSkill(SKILL_BRASH, ""..translate.Get("Skill_Brash"), GOOD..""..translate.Get("Skill_Brash_Good").."\n"..BAD..""..translate.Get("Skill_Brash_Bad"),
    6, 0, {}, TREE_MELEETREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

-- 战斗者 I-V：近战伤害
GM:AddSkillModifier(SKILL_BATTLER1, SKILLMOD_MELEE_DAMAGE_MUL, 0.04)

GM:AddSkillModifier(SKILL_BATTLER2, SKILLMOD_MELEE_DAMAGE_MUL, 0.05)

GM:AddSkillModifier(SKILL_BATTLER3, SKILLMOD_MELEE_DAMAGE_MUL, 0.05)

GM:AddSkillModifier(SKILL_BATTLER4, SKILLMOD_MELEE_DAMAGE_MUL, 0.06)

GM:AddSkillModifier(SKILL_BATTLER5, SKILLMOD_MELEE_DAMAGE_MUL, 0.07)

-- 长矛手：伤害+击退-
GM:AddSkillModifier(SKILL_JOUSTER, SKILLMOD_MELEE_DAMAGE_MUL, 0.1)

GM:AddSkillModifier(SKILL_JOUSTER, SKILLMOD_MELEE_KNOCKBACK_MUL, -1.0)

-- 笨拙（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_CLUMSY, SKILLMOD_WORTH, 20)

GM:AddSkillModifier(SKILL_D_CLUMSY, SKILLMOD_POINTS, 5)

GM:AddSkillFunction(SKILL_D_CLUMSY, function(pl, active)
	pl.IsClumsy = active
end)

GM:AddSkillModifier(SKILL_WORTHINESS2, SKILLMOD_WORTH, 5)

-- 拳击大师 / 暴击拳套
GM:AddSkillModifier(SKILL_KNUCKLEMASTER, SKILLMOD_UNARMED_SWING_DELAY_MUL, 0.35)

GM:AddSkillModifier(SKILL_KNUCKLEMASTER, SKILLMOD_UNARMED_DAMAGE_MUL, 0.75)

GM:AddSkillModifier(SKILL_CRITICALKNUCKLE, SKILLMOD_UNARMED_DAMAGE_MUL, -0.25)

GM:AddSkillModifier(SKILL_CRITICALKNUCKLE, SKILLMOD_UNARMED_SWING_DELAY_MUL, 0.25)

-- 瘦长 I-II
GM:AddSkillModifier(SKILL_LANKY, SKILLMOD_MELEE_DAMAGE_MUL, -0.15)

GM:AddSkillModifier(SKILL_LANKY, SKILLMOD_MELEE_RANGE_MUL, 0.1)

GM:AddSkillModifier(SKILL_LANKYII, SKILLMOD_MELEE_DAMAGE_MUL, -0.15)

GM:AddSkillModifier(SKILL_LANKYII, SKILLMOD_MELEE_RANGE_MUL, 0.1)

-- 大厨 / 轻量级
GM:AddSkillModifier(SKILL_MASTERCHEF, SKILLMOD_MELEE_DAMAGE_MUL, -0.10)

GM:AddSkillModifier(SKILL_LIGHTWEIGHT, SKILLMOD_MELEE_DAMAGE_MUL, -0.2)

GM:AddSkillModifier(SKILL_CHEAPKNUCKLE, SKILLMOD_MELEE_RANGE_MUL, -0.1)

GM:AddSkillModifier(SKILL_HEAVYSTRIKES, SKILLMOD_MELEE_KNOCKBACK_MUL, 1)

-- 鲁莽
GM:AddSkillModifier(SKILL_BRASH, SKILLMOD_MELEE_SWING_DELAY_MUL, -0.16)

GM:AddSkillModifier(SKILL_BRASH, SKILLMOD_MELEE_MOVEMENTSPEED_ON_KILL, -15)

