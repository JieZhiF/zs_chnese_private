-- ============================================================
-- 技能树系统 - 支援树 / 医疗树（Support/Medic Tree）（拆分自 registry.lua）
-- 内容：侧重医疗效率、治疗量的技能定义与本树技能的修饰符数值
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
-- 支援树 / 医疗树（Support/Medic Tree）
-- 侧重医疗效率、治疗量
-- ============================================================

-- 外科医生 I-IV
GM:AddSkill(SKILL_SURGEON1, ""..translate.Get("Skill_SURGEON1"), GOOD..""..translate.Get("Skill_SURGEON1_Good"),
																-4,			6,					{SKILL_NONE, SKILL_SURGEON2}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_SURGEON2, ""..translate.Get("Skill_SURGEON2"), GOOD..""..translate.Get("Skill_SURGEON2_Good"),
																-3,			3,					{SKILL_WORTHINESS4, SKILL_SURGEON3}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_SURGEON3, ""..translate.Get("Skill_SURGEON3"), GOOD..""..translate.Get("Skill_SURGEON3_Good"),
																-2,			0,					{SKILL_U_MEDICCLOUD, SKILL_D_FRAIL, SKILL_SURGEONIV}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_SURGEONIV, ""..translate.Get("Skill_SURGEONIV"), GOOD..""..translate.Get("Skill_SURGEONIV_Good"),
																-2,			-3,					{}, TREE_SUPPORTTREE)

-- 生物学 I-IV
GM:AddSkill(SKILL_BIOLOGYI, ""..translate.Get("Skill_BIOLOGYI"), GOOD..""..translate.Get("Skill_BIOLOGYI_Good"),
																4,			6,					{SKILL_NONE, SKILL_BIOLOGYII}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_BIOLOGYII, ""..translate.Get("Skill_BIOLOGYII"), GOOD..""..translate.Get("Skill_BIOLOGYII_Good"),
																3,			3,					{SKILL_BIOLOGYIII, SKILL_SMARTTARGETING}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_BIOLOGYIII, ""..translate.Get("Skill_BIOLOGYIII"), GOOD..""..translate.Get("Skill_BIOLOGYIII_Good"),
																2,			0,					{SKILL_U_MEDICCLOUD, SKILL_U_ANTITODESHOT, SKILL_BIOLOGYIV}, TREE_SUPPORTTREE)
GM:AddSkill(SKILL_BIOLOGYIV, ""..translate.Get("Skill_BIOLOGYIV"), GOOD..""..translate.Get("Skill_BIOLOGYIV_Good"),
																2,			-3,					{}, TREE_SUPPORTTREE)

-- 脆弱（负面）
GM:AddSkill(SKILL_D_FRAIL, ""..translate.Get("Skill_D_FRAIL"), GOOD..""..translate.Get("Skill_D_FRAIL_Good").."\n"..GOOD..""..translate.Get("Skill_D_FRAIL_Good2").."\n"..BAD..""..translate.Get("Skill_D_FRAIL_Bad"),
																-4,			-2,					{}, TREE_SUPPORTTREE)

-- 医疗云雾（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_MEDICCLOUD, ""..translate.Get("Skill_U_MEDICCLOUD"), GOOD..""..translate.Get("Skill_U_MEDICCLOUD_Good"),
																0,			-2,					{SKILL_OVERMEDIC}, TREE_SUPPORTTREE)
.AlwaysActive = true

-- 智能瞄准
GM:AddSkill(SKILL_SMARTTARGETING, ""..translate.Get("Skill_SMARTTARGETING"), GOOD..""..translate.Get("Skill_SMARTTARGETING_Good")..BAD..""..translate.Get("Skill_SMARTTARGETING_Bad")..BAD..""..translate.Get("Skill_SMARTTARGETING_Bad2"),
																0,			2,					{}, TREE_SUPPORTTREE)

-- 回收太阳
GM:AddSkill(SKILL_RECLAIMSOL, ""..translate.Get("Skill_RECLAIMSOL"), GOOD..""..translate.Get("Skill_RECLAIMSOL_Good")..BAD..""..translate.Get("Skill_RECLAIMSOL_Bad")..BAD..""..translate.Get("Skill_RECLAIMSOL_Bad2")..BAD..""..translate.Get("Skill_RECLAIMSOL_Bad3"),
																0,			4,					{SKILL_SMARTTARGETING}, TREE_SUPPORTTREE)

-- 力量射击（解锁类）
GM:AddSkill(SKILL_U_STRENGTHSHOT, ""..translate.Get("Skill_U_STRENGTHSHOT"), GOOD..""..translate.Get("Skill_U_STRENGTHSHOT_Good"),
																0,			0,					{SKILL_SMARTTARGETING}, TREE_SUPPORTTREE)

-- 价值 IV
GM:AddSkill(SKILL_WORTHINESS4, ""..translate.Get("Skill_WORTHINESS4"), GOOD..""..translate.Get("Skill_WORTHINESS4_Good")..BAD..""..translate.Get("Skill_WORTHINESS4_Bad"),
																-5,			2,					{}, TREE_SUPPORTTREE)

-- 解毒射击（解锁类）
GM:AddSkill(SKILL_U_ANTITODESHOT, ""..translate.Get("Skill_U_ANTITODESHOT"), GOOD..""..translate.Get("Skill_U_ANTITODESHOT_Good"),
																4,			-2,					{}, TREE_SUPPORTTREE)
--[[
-- 扩散
GM:AddSkill(SKILL_DISPERSION, ""..translate.Get("Skill_DISPERSION"), GOOD..""..translate.Get("Skill_DISPERSION_Good")..BAD..""..translate.Get("Skill_DISPERSION_Bad"),
																0,			-4,					{}, TREE_SUPPORTTREE)
																]]
--超量恢复
GM:AddSkill(SKILL_OVERMEDIC, "超量恢复", GOOD.."解锁超量恢复，可使HP超过上限".."\n"..BAD.."已经超过的不可再恢复", --其实这个不算BAD，只是提示
																0,			-4,					{}, TREE_SUPPORTTREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

-- 外科医生 I-IV：医疗冷却缩减
GM:AddSkillModifier(SKILL_SURGEON1, SKILLMOD_MEDKIT_COOLDOWN_MUL, -0.08)

GM:AddSkillModifier(SKILL_SURGEON2, SKILLMOD_MEDKIT_COOLDOWN_MUL, -0.09)

GM:AddSkillModifier(SKILL_SURGEON3, SKILLMOD_MEDKIT_COOLDOWN_MUL, -0.10)

GM:AddSkillModifier(SKILL_SURGEONIV, SKILLMOD_MEDKIT_COOLDOWN_MUL, -0.11)

-- 生物学 I-IV：医疗效果提升
GM:AddSkillModifier(SKILL_BIOLOGYI, SKILLMOD_MEDKIT_EFFECTIVENESS_MUL, 0.08)

GM:AddSkillModifier(SKILL_BIOLOGYII, SKILLMOD_MEDKIT_EFFECTIVENESS_MUL, 0.09)

GM:AddSkillModifier(SKILL_BIOLOGYIII, SKILLMOD_MEDKIT_EFFECTIVENESS_MUL, 0.1)

GM:AddSkillModifier(SKILL_BIOLOGYIV, SKILLMOD_MEDKIT_EFFECTIVENESS_MUL, 0.11)

GM:AddSkillModifier(SKILL_WORTHINESS4, SKILLMOD_WORTH, 5)

-- 智能瞄准 / 回收太阳
GM:AddSkillModifier(SKILL_SMARTTARGETING, SKILLMOD_MEDGUN_FIRE_DELAY_MUL, 0.25)

GM:AddSkillModifier(SKILL_SMARTTARGETING, SKILLMOD_MEDDART_EFFECTIVENESS_MUL, -0.1)

GM:AddSkillModifier(SKILL_RECLAIMSOL, SKILLMOD_MEDGUN_FIRE_DELAY_MUL, 0.5)

GM:AddSkillModifier(SKILL_RECLAIMSOL, SKILLMOD_MEDGUN_RELOAD_SPEED_MUL, -0.133)

-- 脆弱（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_FRAIL, SKILLMOD_WORTH, 20)

GM:AddSkillModifier(SKILL_D_FRAIL, SKILLMOD_POINTS, 5)

GM:AddSkillFunction(SKILL_D_FRAIL, function(pl, active)
	pl:SetDTBool(DT_PLAYER_BOOL_FRAIL, active)
end)

--[[
-- 扩散
GM:AddSkillModifier(SKILL_DISPERSION, SKILLMOD_CLOUD_RADIUS, 0.15)
GM:AddSkillModifier(SKILL_DISPERSION, SKILLMOD_CLOUD_TIME, -0.1)
]]

