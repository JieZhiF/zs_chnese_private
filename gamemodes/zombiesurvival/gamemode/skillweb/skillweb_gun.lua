-- ============================================================
-- 技能树系统 - 枪械树（Gunnery Tree）（拆分自 registry.lua）
-- 内容：侧重装弹速度、拔枪速度、精准度的技能定义与本树技能的修饰符数值
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
-- 枪械树（Gunnery Tree）
-- 侧重装弹速度、拔枪速度、精准度
-- ============================================================

-- 扳机纪律 I-III
GM:AddSkill(SKILL_TRIGGER_DISCIPLINE1, ""..translate.Get("Skill_TriggerDiscipline1"), GOOD..""..translate.Get("Skill_TriggerDiscipline1_Good1").."\n"..GOOD..""..translate.Get("Skill_TriggerDiscipline1_Good2"),
    -5, 6, {SKILL_TRIGGER_DISCIPLINE2, SKILL_NONE}, TREE_GUNTREE)
GM:AddSkill(SKILL_TRIGGER_DISCIPLINE2, ""..translate.Get("Skill_TriggerDiscipline2"), GOOD..""..translate.Get("Skill_TriggerDiscipline2_Good1").."\n"..GOOD..""..translate.Get("Skill_TriggerDiscipline2_Good2"),
    -4, 3, {SKILL_TRIGGER_DISCIPLINE3, SKILL_D_PALSY, SKILL_EQUIPPED}, TREE_GUNTREE)
GM:AddSkill(SKILL_TRIGGER_DISCIPLINE3, ""..translate.Get("Skill_TriggerDiscipline3"), GOOD..""..translate.Get("Skill_TriggerDiscipline3_Good1").."\n"..GOOD..""..translate.Get("Skill_TriggerDiscipline3_Good2"),
    -3, 0, {SKILL_QUICKRELOAD, SKILL_QUICKDRAW, SKILL_WORTHINESS1, SKILL_EGOCENTRIC}, TREE_GUNTREE)

-- 麻痹（负面）/ 冷静
GM:AddSkill(SKILL_D_PALSY, ""..translate.Get("Skill_D_Palsy"), GOOD..""..translate.Get("Skill_D_Palsy_Good1").."\n"..GOOD..""..translate.Get("Skill_D_Palsy_Good2").."\n"..BAD..""..translate.Get("Skill_D_Palsy_Bad"),
    0, 4, {SKILL_LEVELHEADED}, TREE_GUNTREE)
GM:AddSkill(SKILL_LEVELHEADED, ""..translate.Get("Skill_LevelHeaded"), GOOD..""..translate.Get("Skill_LevelHeaded_Good"),
    -2, 2, {}, TREE_GUNTREE)

-- 快速拔枪 / 快换弹 / 灵巧之手
GM:AddSkill(SKILL_QUICKDRAW, ""..translate.Get("Skill_QuickDraw"), GOOD..""..translate.Get("Skill_QuickDraw_Good").."\n"..BAD..""..translate.Get("Skill_QuickDraw_Bad"),
    0, 1, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_QUICKRELOAD, ""..translate.Get("Skill_QuickReload"), GOOD..""..translate.Get("Skill_QuickReload_Good").."\n"..BAD..""..translate.Get("Skill_QuickReload_Bad"),
    -5, 1, {SKILL_SLEIGHTOFHAND}, TREE_GUNTREE)
GM:AddSkill(SKILL_SLEIGHTOFHAND, ""..translate.Get("Skill_SleightOfHand"), GOOD..""..translate.Get("Skill_SleightOfHand_Good").."\n"..BAD..""..translate.Get("Skill_SleightOfHand_Bad"),
    -5, -1, {}, TREE_GUNTREE)

-- 专注 I-III / 俄耳甫斯专注 / 深思
GM:AddSkill(SKILL_FOCUS, ""..translate.Get("Skill_Focus"), GOOD..""..translate.Get("Skill_Focus_Good").."\n"..BAD..""..translate.Get("Skill_Focus_Bad"),
    5, 6, {SKILL_NONE, SKILL_FOCUSII}, TREE_GUNTREE)
GM:AddSkill(SKILL_FOCUSII, ""..translate.Get("Skill_FocusII"), GOOD..""..translate.Get("Skill_FocusII_Good").."\n"..BAD..""..translate.Get("Skill_FocusII_Bad"),
    4, 3, {SKILL_FOCUSIII, SKILL_SCAVENGER, SKILL_D_PALSY, SKILL_PITCHER}, TREE_GUNTREE)
GM:AddSkill(SKILL_FOCUSIII, ""..translate.Get("Skill_FocusIII"), GOOD..""..translate.Get("Skill_FocusIII_Good").."\n"..BAD..""..translate.Get("Skill_FocusIII_Bad"),
    3, 0, {SKILL_EGOCENTRIC, SKILL_WOOISM, SKILL_ORPHICFOCUS, SKILL_SCOURER}, TREE_GUNTREE)
GM:AddSkill(SKILL_ORPHICFOCUS, ""..translate.Get("Skill_OrphicFocus"), GOOD..""..translate.Get("Skill_OrphicFocus_Good1").."\n"..GOOD..""..translate.Get("Skill_OrphicFocus_Good2").."\n"..BAD..""..translate.Get("Skill_OrphicFocus_Bad1").."\n"..BAD..""..translate.Get("Skill_OrphicFocus_Bad2"),
    5, -1, {SKILL_DELIBRATION}, TREE_GUNTREE)
GM:AddSkill(SKILL_DELIBRATION, ""..translate.Get("Skill_Delib"), GOOD..""..translate.Get("Skill_Delib_Good"),
    6, -3, {}, TREE_GUNTREE)

-- 冰冻瓦斯（解锁类）/ 软雷 / 以自我为中心 / 防爆 / 清道夫 / 投手
GM:AddSkill(SKILL_U_CRYGASGREN, ""..translate.Get("Skill_U_CryoGasGrenade"), GOOD..""..translate.Get("Skill_U_CryoGasGrenade_Good"),
    2, -3, {SKILL_EGOCENTRIC}, TREE_GUNTREE)
GM:AddSkill(SKILL_SOFTDET, ""..translate.Get("Skill_SoftDet"), GOOD..""..translate.Get("Skill_SoftDet_Good").."\n"..BAD..""..translate.Get("Skill_SoftDet_Bad"),
    0, -5, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_EGOCENTRIC, ""..translate.Get("Skill_Egocentric"), GOOD..""..translate.Get("Skill_Egocentric_Good").."\n"..BAD..""..translate.Get("Skill_Egocentric_Bad"),
    0, -1, {SKILL_BLASTPROOF}, TREE_GUNTREE)
GM:AddSkill(SKILL_BLASTPROOF, ""..translate.Get("Skill_BlastProof"), GOOD..""..translate.Get("Skill_BlastProof_Good").."\n"..BAD..""..translate.Get("Skill_BlastProof_Bad1").."\n"..BAD..""..translate.Get("Skill_BlastProof_Bad2"),
    0, -3, {SKILL_SOFTDET, SKILL_CANNONBALL, SKILL_CONEFFECT}, TREE_GUNTREE)
GM:AddSkill(SKILL_SCAVENGER, ""..translate.Get("Skill_Scavenger"), GOOD..""..translate.Get("Skill_Scavenger_Good"),
    7, 4, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_PITCHER, ""..translate.Get("Skill_Pitcher"), GOOD..""..translate.Get("Skill_Pitcher_Good"),
    6, 2, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_EQUIPPED, ""..translate.Get("Skill_Equipped"), GOOD..""..translate.Get("Skill_Equipped_Good"),
    -6, 2, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_WORTHINESS1, ""..translate.Get("Skill_Worthiness1"), GOOD..""..translate.Get("Skill_Worthiness1_Good").."\n"..BAD..""..translate.Get("Skill_Worthiness1_Bad"),
    -4, -3, {}, TREE_GUNTREE)

-- 炮弹 / 搜查者 / 锥形效应 / 吴主义 / 真·吴主义
GM:AddSkill(SKILL_CANNONBALL, ""..translate.Get("Skill_Cannonball"), GOOD..""..translate.Get("Skill_Cannonball_Good").."\n"..BAD..""..translate.Get("Skill_Cannonball_Bad"),
    -2, -3, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_SCOURER, ""..translate.Get("Skill_Scourer"), GOOD..""..translate.Get("Skill_Scourer_Good").."\n"..BAD..""..translate.Get("Skill_Scourer_Bad"),
    4, -3, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_CONEFFECT, ""..translate.Get("Skill_ConEffect"), GOOD..""..translate.Get("Skill_ConEffect_Good").."\n"..BAD..""..translate.Get("Skill_ConEffect_Bad"),
    2, -5, {}, TREE_GUNTREE)
GM:AddSkill(SKILL_WOOISM, ""..translate.Get("Skill_Wooism"), GOOD..""..translate.Get("Skill_Wooism_Good").."\n"..BAD..""..translate.Get("Skill_Wooism_Bad"),
    5, 1, {SKILL_TRUEWOOISM}, TREE_GUNTREE)
GM:AddSkill(SKILL_TRUEWOOISM, ""..translate.Get("Skill_TrueWooism"), GOOD..""..translate.Get("Skill_TrueWooism_Good").."\n"..BAD..""..translate.Get("Skill_TrueWooism_Bad"),
    7, 0, {}, TREE_GUNTREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

-- 专注 I-III：减散布、减换弹速度
GM:AddSkillModifier(SKILL_FOCUS, SKILLMOD_AIMSPREAD_MUL, -0.03)

GM:AddSkillModifier(SKILL_FOCUS, SKILLMOD_RELOADSPEED_MUL, -0.03)

GM:AddSkillModifier(SKILL_FOCUSII, SKILLMOD_AIMSPREAD_MUL, -0.04)

GM:AddSkillModifier(SKILL_FOCUSII, SKILLMOD_RELOADSPEED_MUL, -0.04)

GM:AddSkillModifier(SKILL_FOCUSIII, SKILLMOD_AIMSPREAD_MUL, -0.05)

GM:AddSkillModifier(SKILL_FOCUSIII, SKILLMOD_RELOADSPEED_MUL, -0.05)

-- 俄耳甫斯专注 / 深思
GM:AddSkillModifier(SKILL_ORPHICFOCUS, SKILLMOD_RELOADSPEED_MUL, -0.06)

GM:AddSkillModifier(SKILL_ORPHICFOCUS, SKILLMOD_AIMSPREAD_MUL, -0.02)

GM:AddSkillModifier(SKILL_DELIBRATION, SKILLMOD_AIMSPREAD_MUL, -0.01)

-- 吴主义
GM:AddSkillModifier(SKILL_WOOISM, SKILLMOD_IRONSIGHT_EFF_MUL, -0.25)

GM:AddSkillModifier(SKILL_EGOCENTRIC, SKILLMOD_SELF_DAMAGE_MUL, -0.35)

GM:AddSkillModifier(SKILL_EGOCENTRIC, SKILLMOD_HEALTH, -5)

GM:AddSkillModifier(SKILL_BLASTPROOF, SKILLMOD_SELF_DAMAGE_MUL, -0.45)

GM:AddSkillModifier(SKILL_BLASTPROOF, SKILLMOD_RELOADSPEED_MUL, -0.07)

GM:AddSkillModifier(SKILL_BLASTPROOF, SKILLMOD_DEPLOYSPEED_MUL, -0.12)

-- 快速拔枪 / 快换弹 / 灵巧之手
GM:AddSkillModifier(SKILL_QUICKDRAW, SKILLMOD_DEPLOYSPEED_MUL, 0.65)

GM:AddSkillModifier(SKILL_QUICKDRAW, SKILLMOD_RELOADSPEED_MUL, -0.15)

GM:AddSkillModifier(SKILL_QUICKRELOAD, SKILLMOD_RELOADSPEED_MUL, 0.10)

GM:AddSkillModifier(SKILL_QUICKRELOAD, SKILLMOD_DEPLOYSPEED_MUL, -0.25)

GM:AddSkillModifier(SKILL_SLEIGHTOFHAND, SKILLMOD_RELOADSPEED_MUL, 0.10)

GM:AddSkillModifier(SKILL_SLEIGHTOFHAND, SKILLMOD_AIMSPREAD_MUL, 0.05)

-- 扳机纪律 I-III
GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE1, SKILLMOD_RELOADSPEED_MUL, 0.02)

GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE1, SKILLMOD_DEPLOYSPEED_MUL, 0.02)

GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE2, SKILLMOD_RELOADSPEED_MUL, 0.03)

GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE2, SKILLMOD_DEPLOYSPEED_MUL, 0.03)

GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE3, SKILLMOD_RELOADSPEED_MUL, 0.04)

GM:AddSkillModifier(SKILL_TRIGGER_DISCIPLINE3, SKILLMOD_DEPLOYSPEED_MUL, 0.04)

-- 麻痹（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_PALSY, SKILLMOD_WORTH, 10)

GM:AddSkillModifier(SKILL_D_PALSY, SKILLMOD_RESUPPLY_DELAY_MUL, -0.03)

GM:AddSkillFunction(SKILL_D_PALSY, function(pl, active)
	pl.HasPalsy = active
end)

-- 吴主义（特殊函数）
GM:AddSkillFunction(SKILL_WOOISM, function(pl, active)
	pl.Wooism = active
end)

-- 俄耳甫斯专注（特殊函数）
GM:AddSkillFunction(SKILL_ORPHICFOCUS, function(pl, active)
	pl.Orphic = active
end)

-- 价值 I-IV
GM:AddSkillModifier(SKILL_WORTHINESS1, SKILLMOD_WORTH, 5)

-- 软雷 / 铁血 / 放血者 / 稳健步伐 / 无畏
GM:AddSkillModifier(SKILL_SOFTDET, SKILLMOD_EXP_DAMAGE_RADIUS, -0.10)

GM:AddSkillModifier(SKILL_SOFTDET, SKILLMOD_EXP_DAMAGE_TAKEN_MUL, -0.4)

GM:AddSkillModifier(SKILL_CANNONBALL, SKILLMOD_PROJ_SPEED, -0.25)

GM:AddSkillModifier(SKILL_CANNONBALL, SKILLMOD_PROJECTILE_DAMAGE_MUL, 0.03)

GM:AddSkillModifier(SKILL_CONEFFECT, SKILLMOD_EXP_DAMAGE_RADIUS, -0.2)

GM:AddSkillModifier(SKILL_CONEFFECT, SKILLMOD_EXP_DAMAGE_MUL, 0.05)

-- 搜查者（特殊函数）
GM:AddSkillFunction(SKILL_SCOURER, function(pl, active)
	pl.Scourer = active
end)

GM:AddSkillModifier(SKILL_LEVELHEADED, SKILLMOD_AIM_SHAKE_MUL, -0.05)

-- 真·吴主义（特殊函数）
GM:AddSkillFunction(SKILL_TRUEWOOISM, function(pl, active)
	pl.TrueWooism = active
end)

