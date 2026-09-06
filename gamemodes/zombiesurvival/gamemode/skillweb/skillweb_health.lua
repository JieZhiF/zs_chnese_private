-- ============================================================
-- 技能树系统 - 生命树（Health Tree）（拆分自 registry.lua）
-- 内容：侧重生命值、血甲、恢复的技能定义与本树技能的修饰符数值
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
-- 生命树（Health Tree）
-- 侧重生命值、血甲、恢复
-- ============================================================

-- 坚毅 I-V：生命与速度的取舍
GM:AddSkill(SKILL_STOIC1, ""..translate.Get("Skill_Stoic1"), GOOD..""..translate.Get("Skill_Stoic1_Good").."\n"..BAD..""..translate.Get("Skill_Stoic1_Bad"),
																-4,			-6,					{SKILL_NONE, SKILL_STOIC2}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_STOIC2, ""..translate.Get("Skill_Stoic2"), GOOD..""..translate.Get("Skill_Stoic2_Good").."\n"..BAD..""..translate.Get("Skill_Stoic2_Bad"),
																-4,			-4,					{SKILL_STOIC3, SKILL_VITALITY1, SKILL_REGENERATOR}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_STOIC3, ""..translate.Get("Skill_Stoic3"), GOOD..""..translate.Get("Skill_Stoic3_Good").."\n"..BAD..""..translate.Get("Skill_Stoic3_Bad"),
																-3,			-2,					{SKILL_STOIC4}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_STOIC4, ""..translate.Get("Skill_Stoic4"), GOOD..""..translate.Get("Skill_Stoic4_Good").."\n"..BAD..""..translate.Get("Skill_Stoic4_Bad"),
																-3,			0,					{SKILL_STOIC5}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_STOIC5, ""..translate.Get("Skill_Stoic5"), GOOD..""..translate.Get("Skill_Stoic5_Good").."\n"..BAD..""..translate.Get("Skill_Stoic5_Bad"),
																-3,			2,					{SKILL_BLOODARMOR, SKILL_TANKER}, TREE_HEALTHTREE)

-- 血友病：正面+负面加成
GM:AddSkill(SKILL_D_HEMOPHILIA, ""..translate.Get("Skill_D_Hemophilia"), GOOD..""..translate.Get("Skill_D_Hemophilia_Good1").."\n"..GOOD..""..translate.Get("Skill_D_Hemophilia_Good2").."\n"..BAD..""..translate.Get("Skill_D_Hemophilia_Bad"),
																4,			2,					{}, TREE_HEALTHTREE)

-- 暴食：食物恢复但付出代价
GM:AddSkill(SKILL_GLUTTON, ""..translate.Get("Skill_Glutton"), GOOD..""..translate.Get("Skill_Glutton_Good1").."\n"..""..GOOD..translate.Get("Skill_Glutton_Good2").."\n"..BAD..""..translate.Get("Skill_Glutton_Bad1").."\n"..BAD..""..translate.Get("Skill_Glutton_Bad2"),
																3,			-2,					{SKILL_GOURMET, SKILL_BLOODARMOR}, TREE_HEALTHTREE)

-- 有备无患
GM:AddSkill(SKILL_PREPAREDNESS, ""..translate.Get("Skill_Preparedness"), GOOD..""..translate.Get("Skill_Preparedness_Good"),
																4,			-6,					{SKILL_NONE}, TREE_HEALTHTREE)

-- 美食家：食物效率提升
GM:AddSkill(SKILL_GOURMET, ""..translate.Get("Skill_Gourmet"), GOOD..""..translate.Get("Skill_Gourmet_Good").."\n"..BAD..""..translate.Get("Skill_Gourmet_Bad"),
																4,			-4,					{SKILL_PREPAREDNESS, SKILL_VITALITY1}, TREE_HEALTHTREE)

-- 止血：血甲转换
GM:AddSkill(SKILL_HAEMOSTASIS, ""..translate.Get("Skill_Haemostasis"), GOOD..""..translate.Get("Skill_Haemostasis_Good").."\n"..BAD..""..translate.Get("Skill_Haemostasis_Bad").."\n"..BAD..""..translate.Get("Skill_Haemostasis_Bad2"),
																4,			6,					{}, TREE_HEALTHTREE)

-- 放血者：血甲增益
GM:AddSkill(SKILL_BLOODLETTER, ""..translate.Get("Skill_Bloodletter"), GOOD..""..translate.Get("Skill_Bloodletter_Good").."\n"..BAD..""..translate.Get("Skill_Bloodletter_Bad"),
																0,			4,					{SKILL_ANTIGEN}, TREE_HEALTHTREE)

-- 再生者
GM:AddSkill(SKILL_REGENERATOR, ""..translate.Get("Skill_Regenerator")		, GOOD..""..translate.Get("Skill_Regenerator_Good").."\n"..BAD..""..translate.Get("Skill_Regenerator_Bad"),	
																-5,			-2,					{}, TREE_HEALTHTREE)

-- 血甲
GM:AddSkill(SKILL_BLOODARMOR, ""..translate.Get("Skill_BloodArmor"), GOOD..""..translate.Get("Skill_BloodArmor_Good1").."\n"..GOOD..""..translate.Get("Skill_BloodArmor_Good2").."\n"..GOOD..""..translate.Get("Skill_BloodArmor_Good3").."\n"..BAD..""..translate.Get("Skill_BloodArmor_Bad"),
																2,			2,					{SKILL_IRONBLOOD, SKILL_BLOODLETTER, SKILL_D_HEMOPHILIA}, TREE_HEALTHTREE)

-- 铁血
GM:AddSkill(SKILL_IRONBLOOD, ""..translate.Get("Skill_IronBlood"), GOOD..""..translate.Get("Skill_IronBlood_Good1").."\n"..GOOD..""..translate.Get("Skill_IronBlood_Good2").."\n"..BAD..""..translate.Get("Skill_IronBlood_Bad"),
																2,			4,					{SKILL_HAEMOSTASIS, SKILL_CIRCULATION}, TREE_HEALTHTREE)

-- 虚弱（负面技能）
GM:AddSkill(SKILL_D_WEAKNESS, ""..translate.Get("Skill_D_Weakness"), GOOD..""..translate.Get("Skill_D_Weakness_Good1").."\n"..GOOD..""..translate.Get("Skill_D_Weakness_Good2").."\n"..GOOD..""..translate.Get("Skill_D_Weakness_Good3"),
																1,			-1,					{}, TREE_HEALTHTREE)

-- 活力 I-III
GM:AddSkill(SKILL_VITALITY1, ""..translate.Get("Skill_Vitality1"), GOOD..""..translate.Get("Skill_Vitality1_Good"),
																0,			-4,					{SKILL_VITALITY2}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_VITALITY2, ""..translate.Get("Skill_Vitality2")	, GOOD..""..translate.Get("Skill_Vitality2_Good"),
																0,			-2,					{SKILL_VITALITY3}, TREE_HEALTHTREE)
GM:AddSkill(SKILL_VITALITY3, ""..translate.Get("Skill_Vitality3")	, GOOD..""..translate.Get("Skill_Vitality3_Good"),
																0,			-0,					{SKILL_D_WEAKNESS}, TREE_HEALTHTREE)

-- 坦克
GM:AddSkill(SKILL_TANKER, ""..translate.Get("Skill_Tanker"), GOOD..""..translate.Get("Skill_Tanker_Good").."\n"..BAD..""..translate.Get("Skill_Tanker_Bad"),
																-5,			 4,					{}, TREE_HEALTHTREE)

-- 觅食者
GM:AddSkill(SKILL_FORAGER, ""..translate.Get("Skill_Forager"), GOOD..""..translate.Get("Skill_Forager_Good").."\n"..BAD..""..translate.Get("Skill_Forager_Bad"),
																5, 			-2,					{SKILL_GOURMET}, TREE_HEALTHTREE)

-- 糖分爆发
GM:AddSkill(SKILL_SUGARRUSH, ""..translate.Get("Skill_SugarRush"), GOOD..""..translate.Get("Skill_SugarRush_Good").."\n"..BAD..""..translate.Get("Skill_SugarRush_Bad"),
																4,			 0,					{SKILL_GOURMET}, TREE_HEALTHTREE)

-- 循环系统
GM:AddSkill(SKILL_CIRCULATION, ""..translate.Get("Skill_Circulation"), GOOD..""..translate.Get("Skill_Circulation_Good"),
																4, 			4, 					{SKILL_SANGUINE}, TREE_HEALTHTREE)

-- 乐观（多血质）
GM:AddSkill(SKILL_SANGUINE, ""..translate.Get("Skill_Sanguine"), GOOD..""..translate.Get("Skill_Sanguine_Good").."\n"..GOOD..""..translate.Get("Skill_Sanguine_Good2").."\n"..GOOD..""..translate.Get("Skill_Sanguine_Good3"),
																6,		 	2,					{}, TREE_HEALTHTREE)

-- 抗原
GM:AddSkill(SKILL_ANTIGEN, ""..translate.Get("Skill_Antigen"), GOOD..""..translate.Get("Skill_Antigen_Good").."\n"..BAD..""..translate.Get("Skill_Antigen_Bad"),
																-2, 		4, 					{}, TREE_HEALTHTREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

GM:AddSkillModifier(SKILL_STOIC1, SKILLMOD_HEALTH, 1)

GM:AddSkillModifier(SKILL_STOIC1, SKILLMOD_SPEED, -0.75)

GM:AddSkillModifier(SKILL_STOIC2, SKILLMOD_HEALTH, 2)

GM:AddSkillModifier(SKILL_STOIC2, SKILLMOD_SPEED, -1.5)

GM:AddSkillModifier(SKILL_STOIC3, SKILLMOD_HEALTH, 4)

GM:AddSkillModifier(SKILL_STOIC3, SKILLMOD_SPEED, -3)

GM:AddSkillModifier(SKILL_STOIC4, SKILLMOD_HEALTH, 6)

GM:AddSkillModifier(SKILL_STOIC4, SKILLMOD_SPEED, -4.5)

GM:AddSkillModifier(SKILL_STOIC5, SKILLMOD_HEALTH, 7)

GM:AddSkillModifier(SKILL_STOIC5, SKILLMOD_SPEED, -5.25)

-- 活力 I-III
GM:AddSkillModifier(SKILL_VITALITY1, SKILLMOD_HEALTH, 1)

GM:AddSkillModifier(SKILL_VITALITY2, SKILLMOD_HEALTH, 1)

GM:AddSkillModifier(SKILL_VITALITY3, SKILLMOD_HEALTH, 1)

GM:AddSkillModifier(SKILL_GLUTTON, SKILLMOD_HEALTH, -5)

GM:AddSkillModifier(SKILL_TANKER, SKILLMOD_HEALTH, 20)

GM:AddSkillModifier(SKILL_TANKER, SKILLMOD_SPEED, -7.5)

-- 美食家 / 糖分爆发
GM:AddSkillModifier(SKILL_GOURMET, SKILLMOD_FOODEATTIME_MUL, 0.5)

GM:AddSkillModifier(SKILL_GOURMET, SKILLMOD_FOODRECOVERY_MUL, 1.0)

GM:AddSkillModifier(SKILL_SUGARRUSH, SKILLMOD_FOODRECOVERY_MUL, -0.35)

-- 血友病（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_HEMOPHILIA, SKILLMOD_WORTH, 10)

GM:AddSkillModifier(SKILL_D_HEMOPHILIA, SKILLMOD_SCRAP_START, 3)

GM:AddSkillFunction(SKILL_D_HEMOPHILIA, function(pl, active)
	pl.HasHemophilia = active
end)

-- 血甲
GM:AddSkillModifier(SKILL_BLOODARMOR, SKILLMOD_HEALTH, -13)

-- 止血：血甲减伤减益
GM:AddSkillModifier(SKILL_HAEMOSTASIS, SKILLMOD_BLOODARMOR_DMG_REDUCTION, -0.25)

-- 再生者
GM:AddSkillModifier(SKILL_REGENERATOR, SKILLMOD_HEALTH, -6)

-- 虚弱（负面）
GM:AddSkillModifier(SKILL_D_WEAKNESS, SKILLMOD_WORTH, 15)

GM:AddSkillModifier(SKILL_D_WEAKNESS, SKILLMOD_ENDWAVE_POINTS, 1)

GM:AddSkillModifier(SKILL_D_WEAKNESS, SKILLMOD_ARSENAL_DISCOUNT, -0.02)

GM:AddSkillModifier(SKILL_IRONBLOOD, SKILLMOD_BLOODARMOR_DMG_REDUCTION, 0.25)

GM:AddSkillModifier(SKILL_IRONBLOOD, SKILLMOD_BLOODARMOR_MUL, -0.5)

GM:AddSkillModifier(SKILL_BLOODLETTER, SKILLMOD_BLOODARMOR_GAIN_MUL, 1)

GM:AddSkillModifier(SKILL_CIRCULATION, SKILLMOD_BLOODARMOR, 1)

GM:AddSkillModifier(SKILL_SANGUINE, SKILLMOD_BLOODARMOR, 5)

GM:AddSkillModifier(SKILL_SANGUINE, SKILLMOD_HEALTH, 5)

GM:AddSkillModifier(SKILL_SANGUINE, SKILLMOD_WEAPON_WEIGHT_SLOW_MUL, -0.08)

-- 抗原
GM:AddSkillModifier(SKILL_ANTIGEN, SKILLMOD_BLOODARMOR_DMG_REDUCTION, 0.05)

GM:AddSkillModifier(SKILL_ANTIGEN, SKILLMOD_HEALTH, -3)

