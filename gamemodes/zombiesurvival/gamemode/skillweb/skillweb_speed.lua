-- ============================================================
-- 技能树系统 - 速度树（Speed Tree）（拆分自 registry.lua）
-- 内容：侧重移动速度、跳跃、灵活性的技能定义与本树技能的修饰符数值
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
-- 速度树（Speed Tree）
-- 侧重移动速度、跳跃、灵活性
-- ============================================================

-- 速度 I-V
GM:AddSkill(SKILL_SPEED1, ""..translate.Get("Skill_Speed1"), GOOD..""..translate.Get("Skill_Speed1_Good").."\n"..BAD..""..translate.Get("Skill_Speed1_Bad"),
																-4,			6,					{SKILL_NONE, SKILL_SPEED2}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_SPEED2, ""..translate.Get("Skill_Speed2"), GOOD..""..translate.Get("Skill_Speed2_Good").."\n"..BAD..""..translate.Get("Skill_Speed2_Bad"),
																-4,			4,					{SKILL_SPEED3, SKILL_PHASER, SKILL_SPEED2, SKILL_U_CORRUPTEDFRAGMENT}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_SPEED3, ""..translate.Get("Skill_Speed3"), GOOD..""..translate.Get("Skill_Speed3_Good").."\n"..BAD..""..translate.Get("Skill_Speed3_Bad"),
																-4,			2,					{SKILL_SPEED4}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_SPEED4, ""..translate.Get("Skill_Speed4"), GOOD..""..translate.Get("Skill_Speed4_Good").."\n"..BAD..""..translate.Get("Skill_Speed4_Bad"),
																-4,			0,					{SKILL_SPEED5, SKILL_SAFEFALL}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_SPEED5, ""..translate.Get("Skill_Speed5"), GOOD..""..translate.Get("Skill_Speed5_Good").."\n"..BAD..""..translate.Get("Skill_Speed5_Bad"),
																-4,			-2,					{SKILL_ULTRANIMBLE, SKILL_BACKPEDDLER, SKILL_MOTIONI, SKILL_CARDIOTONIC, SKILL_UNBOUND}, TREE_SPEEDTREE)

-- 敏捷 I-III
GM:AddSkill(SKILL_AGILEI, ""..translate.Get("Skill_AgileI"), GOOD..""..translate.Get("Skill_AgileI_Good").."\n"..BAD..""..translate.Get("Skill_AgileI_Bad"),
																4, 6, {SKILL_NONE, SKILL_AGILEII}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_AGILEII, ""..translate.Get("Skill_AgileII"), GOOD..""..translate.Get("Skill_AgileII_Good").."\n"..BAD..""..translate.Get("Skill_AgileII_Bad"),
																4, 2, {SKILL_AGILEIII, SKILL_WORTHINESS3}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_AGILEIII, ""..translate.Get("Skill_AgileIII"), GOOD..""..translate.Get("Skill_AgileIII_Good").."\n"..BAD..""..translate.Get("Skill_AgileIII_Bad"),
																4, -2, {SKILL_SAFEFALL, SKILL_ULTRANIMBLE, SKILL_SURESTEP, SKILL_INTREPID}, TREE_SPEEDTREE)

-- 迟缓（负面技能）
GM:AddSkill(SKILL_D_SLOW, ""..translate.Get("Skill_D_Slow"), GOOD..""..translate.Get("Skill_D_Slow_Good1").."\n"..GOOD..""..translate.Get("Skill_D_Slow_Good2").."\n"..BAD..""..translate.Get("Skill_D_Slow_Bad"),
																0, -4, {}, TREE_SPEEDTREE)

-- 动态 I-III
GM:AddSkill(SKILL_MOTIONI, ""..translate.Get("Skill_MotionI"), GOOD..""..translate.Get("Skill_MotionI_Good"),
																-2, -2, {SKILL_MOTIONII}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_MOTIONII, ""..translate.Get("Skill_MotionII"), GOOD..""..translate.Get("Skill_MotionII_Good"),
																-1, -1, {SKILL_MOTIONIII}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_MOTIONIII, ""..translate.Get("Skill_MotionIII"), GOOD..""..translate.Get("Skill_MotionIII_Good"),
																0, -2, {SKILL_D_SLOW}, TREE_SPEEDTREE)

-- 后退者
GM:AddSkill(SKILL_BACKPEDDLER, ""..translate.Get("Skill_Backpeddler"), GOOD..""..translate.Get("Skill_Backpeddler_Good").."\n"..BAD..""..translate.Get("Skill_Backpeddler_Bad1").."\n"..BAD..""..translate.Get("Skill_Backpeddler_Bad2"),
																-6, 0, {}, TREE_SPEEDTREE)

-- 相位
GM:AddSkill(SKILL_PHASER, ""..translate.Get("Skill_Phaser"), GOOD..""..translate.Get("Skill_Phaser_Good").."\n"..BAD..""..translate.Get("Skill_Phaser_Bad"),
																-1, 4, {SKILL_D_WIDELOAD, SKILL_DRIFT}, TREE_SPEEDTREE)

-- 漂移
GM:AddSkill(SKILL_DRIFT, ""..translate.Get("Skill_Drift"), GOOD..""..translate.Get("Skill_Drift_Good"),
																1, 3, {SKILL_WARP}, TREE_SPEEDTREE)

-- 曲速
GM:AddSkill(SKILL_WARP, ""..translate.Get("Skill_Warp"), GOOD..""..translate.Get("Skill_Warp_Good"),
																2, 2, {}, TREE_SPEEDTREE)

-- 安全坠落
GM:AddSkill(SKILL_SAFEFALL, ""..translate.Get("Skill_SafeFall"), GOOD..""..translate.Get("Skill_SafeFall_Good1").."\n"..GOOD..""..translate.Get("Skill_SafeFall_Good2").."\n"..BAD..""..translate.Get("Skill_SafeFall_Bad"),
	0, 0, {}, TREE_SPEEDTREE)

-- 宽载（负面）
GM:AddSkill(SKILL_D_WIDELOAD, ""..translate.Get("Skill_D_WideLoad"), GOOD..""..translate.Get("Skill_D_WideLoad_Good1").."\n"..GOOD..""..translate.Get("Skill_D_WideLoad_Good2").."\n"..BAD..""..translate.Get("Skill_D_WideLoad_Bad"),
	1, 1, {}, TREE_SPEEDTREE)

-- 腐蚀碎片（解锁类）
GM:AddSkill(SKILL_U_CORRUPTEDFRAGMENT, ""..translate.Get("Skill_U_CorruptedFragment"), GOOD..""..translate.Get("Skill_U_CorruptedFragment_Good"),
	-2, 2, {}, TREE_SPEEDTREE)

-- 超灵活
GM:AddSkill(SKILL_ULTRANIMBLE, ""..translate.Get("Skill_UltraNimble"), GOOD..""..translate.Get("Skill_UltraNimble_Good").."\n"..BAD..""..translate.Get("Skill_UltraNimble_Bad"),
	0, -6, {}, TREE_SPEEDTREE)

-- 价值 III / 稳健步伐 / 无畏 / 强壮 / 强心剂 / 无拘
GM:AddSkill(SKILL_WORTHINESS3, ""..translate.Get("Skill_Worthiness3"), GOOD..""..translate.Get("Skill_Worthiness3_Good").."\n"..BAD..""..translate.Get("Skill_Worthiness3_Bad"),
	6, 2, {}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_SURESTEP, ""..translate.Get("Skill_SureStep"), GOOD..""..translate.Get("Skill_SureStep_Good").."\n"..BAD..""..translate.Get("Skill_SureStep_Bad"),
	6, 0, {}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_INTREPID, ""..translate.Get("Skill_Intrepid"), GOOD..""..translate.Get("Skill_Intrepid_Good").."\n"..BAD..""..translate.Get("Skill_Intrepid_Bad"),
	6, -4, {SKILL_ROBUST}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_ROBUST, ""..translate.Get("Skill_Robust"), GOOD..""..translate.Get("Skill_Robust_Good"),
	6, -2, {}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_CARDIOTONIC, ""..translate.Get("Skill_Cardiotonic"), GOOD..""..translate.Get("Skill_Cardiotonic_Good1").."\n"..BAD..""..translate.Get("Skill_Cardiotonic_Bad1").."\n"..BAD..""..translate.Get("Skill_Cardiotonic_Bad2").."\n"..translate.Get("Skill_Cardiotonic_Good2"),
    -6, -4, {}, TREE_SPEEDTREE)
GM:AddSkill(SKILL_UNBOUND, ""..translate.Get("Skill_Unbound"), GOOD..""..translate.Get("Skill_Unbound_Good").."\n"..BAD..""..translate.Get("Skill_Unbound_Bad"),
    -4, -4, {}, TREE_SPEEDTREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

GM:AddSkillModifier(SKILL_SPEED1, SKILLMOD_SPEED, 0.75)

GM:AddSkillModifier(SKILL_SPEED1, SKILLMOD_HEALTH, -1)

GM:AddSkillModifier(SKILL_SPEED2, SKILLMOD_SPEED, 1.5)

GM:AddSkillModifier(SKILL_SPEED2, SKILLMOD_HEALTH, -2)

GM:AddSkillModifier(SKILL_SPEED3, SKILLMOD_SPEED, 3)

GM:AddSkillModifier(SKILL_SPEED3, SKILLMOD_HEALTH, -4)

GM:AddSkillModifier(SKILL_SPEED4, SKILLMOD_SPEED, 4.5)

GM:AddSkillModifier(SKILL_SPEED4, SKILLMOD_HEALTH, -6)

GM:AddSkillModifier(SKILL_SPEED5, SKILLMOD_SPEED, 5.25)

GM:AddSkillModifier(SKILL_SPEED5, SKILLMOD_HEALTH, -7)

-- 动态 I-III
GM:AddSkillModifier(SKILL_MOTIONI, SKILLMOD_SPEED, 0.75)

GM:AddSkillModifier(SKILL_MOTIONII, SKILLMOD_SPEED, 0.75)

GM:AddSkillModifier(SKILL_MOTIONIII, SKILLMOD_SPEED, 0.75)

GM:AddSkillModifier(SKILL_ULTRANIMBLE, SKILLMOD_HEALTH, -10)

GM:AddSkillModifier(SKILL_ULTRANIMBLE, SKILLMOD_SPEED, 15)

-- 迟缓（负面）
GM:AddSkillModifier(SKILL_D_SLOW, SKILLMOD_WORTH, 15)

GM:AddSkillModifier(SKILL_D_SLOW, SKILLMOD_ENDWAVE_POINTS, 1)

GM:AddSkillModifier(SKILL_D_SLOW, SKILLMOD_SPEED, -33.75)

-- 相位 / 漂移 / 曲速
GM:AddSkillModifier(SKILL_PHASER, SKILLMOD_BARRICADE_PHASE_SPEED_MUL, 0.15)

GM:AddSkillModifier(SKILL_PHASER, SKILLMOD_SIGIL_TELEPORT_MUL, 0.15)

GM:AddSkillModifier(SKILL_DRIFT, SKILLMOD_BARRICADE_PHASE_SPEED_MUL, 0.05)

GM:AddSkillModifier(SKILL_WARP, SKILLMOD_SIGIL_TELEPORT_MUL, -0.05)

-- 安全坠落
GM:AddSkillModifier(SKILL_SAFEFALL, SKILLMOD_FALLDAMAGE_DAMAGE_MUL, -0.4)

GM:AddSkillModifier(SKILL_SAFEFALL, SKILLMOD_FALLDAMAGE_RECOVERY_MUL, -0.5)

GM:AddSkillModifier(SKILL_SAFEFALL, SKILLMOD_FALLDAMAGE_SLOWDOWN_MUL, 0.4)

-- 后退者（带特殊函数）
GM:AddSkillModifier(SKILL_BACKPEDDLER, SKILLMOD_SPEED, -7)

GM:AddSkillFunction(SKILL_BACKPEDDLER, function(pl, active)
	pl.NoBWSpeedPenalty = active
end)

-- 宽载（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_WIDELOAD, SKILLMOD_WORTH, 20)

GM:AddSkillModifier(SKILL_D_WIDELOAD, SKILLMOD_RESUPPLY_DELAY_MUL, -0.05)

GM:AddSkillFunction(SKILL_D_WIDELOAD, function(pl, active)
	pl.NoGhosting = active
end)

GM:AddSkillModifier(SKILL_WORTHINESS3, SKILLMOD_WORTH, 5)

-- 敏捷 I-III
GM:AddSkillModifier(SKILL_AGILEI, SKILLMOD_JUMPPOWER_MUL, 0.04)

GM:AddSkillModifier(SKILL_AGILEI, SKILLMOD_SPEED, -2)

GM:AddSkillModifier(SKILL_AGILEII, SKILLMOD_JUMPPOWER_MUL, 0.05)

GM:AddSkillModifier(SKILL_AGILEII, SKILLMOD_SPEED, -3)

GM:AddSkillModifier(SKILL_AGILEIII, SKILLMOD_JUMPPOWER_MUL, 0.06)

GM:AddSkillModifier(SKILL_AGILEIII, SKILLMOD_SPEED, -4)

GM:AddSkillModifier(SKILL_SURESTEP, SKILLMOD_SPEED, -4)

GM:AddSkillModifier(SKILL_SURESTEP, SKILLMOD_SLOW_EFF_TAKEN_MUL, -0.35)

GM:AddSkillModifier(SKILL_INTREPID, SKILLMOD_SPEED, -4)

GM:AddSkillModifier(SKILL_INTREPID, SKILLMOD_LOW_HEALTH_SLOW_MUL, -0.35)

GM:AddSkillModifier(SKILL_UNBOUND, SKILLMOD_SPEED, -4)

GM:AddSkillModifier(SKILL_CARDIOTONIC, SKILLMOD_SPEED, -12)

GM:AddSkillModifier(SKILL_CARDIOTONIC, SKILLMOD_BLOODARMOR_DMG_REDUCTION, -0.2)

GM:AddSkillModifier(SKILL_ROBUST, SKILLMOD_WEAPON_WEIGHT_SLOW_MUL, -0.06)

