-- ============================================================
-- 技能树系统 - 建造树 / 防御树（Building/Defence Tree）（拆分自 registry.lua）
-- 内容：侧重建造速度、炮塔、无人机的技能定义与本树技能的修饰符数值
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
-- 建造树 / 防御树（Building/Defence Tree）
-- 侧重建造速度、炮塔、无人机
-- ============================================================

-- 能手 I-VII
GM:AddSkill(SKILL_HANDY1, ""..translate.Get("Skill_Handy1"), GOOD..""..translate.Get("Skill_Handy1_Good"),
    -5, -6, {SKILL_NONE, SKILL_HANDY2}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDY2, ""..translate.Get("Skill_Handy2"), GOOD..""..translate.Get("Skill_Handy2_Good"),
    -5, -4, {SKILL_HANDY3, SKILL_U_BLASTTURRET, SKILL_LOADEDHULL}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDY3, ""..translate.Get("Skill_Handy3"), GOOD..""..translate.Get("Skill_Handy3_Good"),
    -5, -1, {SKILL_TAUT, SKILL_HAMMERDISCIPLINE, SKILL_D_NOODLEARMS, SKILL_HANDY4}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDY4, ""..translate.Get("Skill_Handy4"), GOOD..""..translate.Get("Skill_Handy4_Good"),
    -3, 1, {SKILL_HANDY5}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HANDY5, ""..translate.Get("Skill_Handy5"), GOOD..""..translate.Get("Skill_Handy5_Good"),
    -3, 3, {}, TREE_BUILDINGTREE)

-- 木工纪律 / 路障专家
GM:AddSkill(SKILL_HAMMERDISCIPLINE, ""..translate.Get("Skill_HammerDiscipline"), GOOD..""..translate.Get("Skill_HammerDiscipline_Good"),
    0, 1, {SKILL_BARRICADEEXPERT}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_BARRICADEEXPERT, ""..translate.Get("Skill_BarricadeExpert"), GOOD..""..translate.Get("Skill_BarricadeExpert_Good1").."\n"..GOOD..""..translate.Get("Skill_BarricadeExpert_Good2").."\n"..BAD..""..translate.Get("Skill_BarricadeExpert_Bad"),
    0, 3, {}, TREE_BUILDINGTREE)

-- 重载船体 / 强化船体 / 稳定船体 / 强化刀片 / 飞行员
GM:AddSkill(SKILL_LOADEDHULL, ""..translate.Get("Skill_LoadedHull"), GOOD..""..translate.Get("Skill_LoadedHull_Good").."\n"..BAD..""..translate.Get("Skill_LoadedHull_Bad"),
    -2, -4, {SKILL_REINFORCEDHULL, SKILL_REINFORCEDBLADES, SKILL_AVIATOR}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_REINFORCEDHULL, ""..translate.Get("Skill_ReinforcedHull"), GOOD..""..translate.Get("Skill_ReinforcedHull_Good").."\n"..BAD..""..translate.Get("Skill_ReinforcedHull_Bad1").."\n"..BAD..""..translate.Get("Skill_ReinforcedHull_Bad2"),
    -2, -2, {SKILL_STABLEHULL}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_STABLEHULL, ""..translate.Get("Skill_StableHull"), GOOD..""..translate.Get("Skill_StableHull_Good").."\n"..BAD..""..translate.Get("Skill_StableHull_Bad"),
    0, -3, {SKILL_U_DRONE}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_REINFORCEDBLADES, ""..translate.Get("Skill_ReinforcedBlades"), GOOD..""..translate.Get("Skill_ReinforcedBlades_Good").."\n"..BAD..""..translate.Get("Skill_ReinforcedBlades_Bad"),
    0, -5, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_AVIATOR, ""..translate.Get("Skill_Aviator"), GOOD..""..translate.Get("Skill_Aviator_Good").."\n"..BAD..""..translate.Get("Skill_Aviator_Bad"),
    -4, -2, {}, TREE_BUILDINGTREE)

-- 爆破炮塔（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_BLASTTURRET, ""..translate.Get("Skill_U_BlastTurret"), GOOD..""..translate.Get("Skill_U_BlastTurret_Good").."\n"..translate.Get("Skill_U_BlastTurret_Good2"),
    -8, -4, {SKILL_TURRETLOCK, SKILL_TWINVOLLEY, SKILL_TURRETOVERLOAD}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 炮塔锁定 / 双连射 / 炮塔过载 / 火箭炮塔
GM:AddSkill(SKILL_TURRETLOCK, ""..translate.Get("Skill_TurretLock"), GOOD..""..translate.Get("Skill_TurretLock_Good").."\n"..BAD..""..translate.Get("Skill_TurretLock_Bad"),
    -6, -2, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_TWINVOLLEY, ""..translate.Get("Skill_TwinVolley"), GOOD..""..translate.Get("Skill_TwinVolley_Good").."\n"..BAD..""..translate.Get("Skill_TwinVolley_Bad1").."\n"..BAD..""..translate.Get("Skill_TwinVolley_Bad2"),
    -10, -5, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_TURRETOVERLOAD, ""..translate.Get("Skill_TurretOverload"), GOOD..""..translate.Get("Skill_TurretOverload_Good").."\n"..BAD..""..translate.Get("Skill_TurretOverload_Bad"),
    -8, -2, {SKILL_INSTRUMENTS}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_U_ROCKETTURRET, ""..translate.Get("Skill_U_RocketTurret"), GOOD..""..translate.Get("Skill_U_RocketTurret_Good"),
    -8, 0, {SKILL_TURRETOVERLOAD}, TREE_BUILDINGTREE)

-- 无人机（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_DRONE, ""..translate.Get("Skill_U_Drone"), GOOD..""..translate.Get("Skill_U_Drone_Good"),
    2, -3, {SKILL_HAULMODULE, SKILL_U_ROLLERMINE}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 纳米云（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_NANITECLOUD, ""..translate.Get("Skill_U_NaniteCloud"), GOOD..""..translate.Get("Skill_U_NaniteCloud_Good"),
    3, 1, {SKILL_HAMMERDISCIPLINE}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 立场增幅器 / 技师 / 感应
GM:AddSkill(SKILL_FIELDAMP, ""..translate.Get("Skill_FieldAmp"), GOOD..""..translate.Get("Skill_FieldAmp_Good").."\n"..BAD..""..translate.Get("Skill_FieldAmp_Bad"),
    6, 4, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_TECHNICIAN, ""..translate.Get("Skill_Technician"), GOOD..""..translate.Get("Skill_Technician_Good").."\n"..GOOD..""..translate.Get("Skill_Technician_Good2"),
    4, 3, {}, TREE_BUILDINGTREE)

-- 滚雷（解锁类）/ 运输模块 / 洞察（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_ROLLERMINE, ""..translate.Get("Skill_U_Rollermine"), GOOD..""..translate.Get("Skill_U_Rollermine_Good"),
    3, -5, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_HAULMODULE, ""..translate.Get("Skill_HaulModule"), GOOD..""..translate.Get("Skill_HaulModule_Good"),
    2, -1, {SKILL_U_NANITECLOUD}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_INSIGHT, ""..translate.Get("Skill_Insight"), GOOD..""..translate.Get("Skill_Insight_Good1").."\n"..GOOD..""..translate.Get("Skill_Insight_Good2").."\n"..GOOD..""..translate.Get("Skill_Insight_Good3"),
    6, 0, {SKILL_U_NANITECLOUD, SKILL_U_ZAPPER_ARC, SKILL_LIGHTCONSTRUCT, SKILL_D_LATEBUYER}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 电弧连锁（解锁类，AlwaysActive）
GM:AddSkill(SKILL_U_ZAPPER_ARC, ""..translate.Get("Skill_U_ZapperArc"), GOOD..""..translate.Get("Skill_U_ZapperArc_Good"),
    6, 2, {SKILL_FIELDAMP, SKILL_TECHNICIAN}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 轻量构造 / 库存 / 敏锐 / 眼界 / 制造包（解锁类，AlwaysActive）
GM:AddSkill(SKILL_LIGHTCONSTRUCT, ""..translate.Get("Skill_LightConstruct"), GOOD..""..translate.Get("Skill_LightConstruct_Good").."\n"..BAD..""..translate.Get("Skill_LightConstruct_Bad"),
    8, -1, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_STOCKPILE, ""..translate.Get("Skill_Stockpile"), GOOD..""..translate.Get("Skill_Stockpile_Good").."\n"..BAD..""..translate.Get("Skill_Stockpile_Bad"),
    8, -3, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_ACUITY, ""..translate.Get("Skill_Acuity"), GOOD..""..translate.Get("Skill_Acuity_Good").."\n"..GOOD..""..translate.Get("Skill_Acuity_Good2").."\n"..GOOD..""..translate.Get("Skill_Acuity_Good3"),
    6, -3, {SKILL_INSIGHT, SKILL_STOCKPILE, SKILL_U_CRAFTINGPACK, SKILL_STOWAGE}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_VISION, ""..translate.Get("Skill_Vision"), GOOD..""..translate.Get("Skill_Vision_Good1").."\n"..GOOD..""..translate.Get("Skill_Vision_Good2"),
    6, -6, {SKILL_NONE, SKILL_ACUITY}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_U_CRAFTINGPACK, ""..translate.Get("Skill_U_CraftingPack"), GOOD..""..translate.Get("Skill_U_CraftingPack_Good1").."\n"..GOOD..""..translate.Get("Skill_U_CraftingPack_Good2").."\n"..GOOD..""..translate.Get("Skill_U_CraftingPack_Good3"),
    4, -1, {}, TREE_BUILDINGTREE)
.AlwaysActive = true

-- 晚买者（负面）/ 紧绷 / 面条手臂（负面）/ 乐器 / 储藏
GM:AddSkill(SKILL_D_LATEBUYER, ""..translate.Get("Skill_D_LateBuyer"), GOOD..""..translate.Get("Skill_D_LateBuyer_Good1").."\n"..GOOD..""..translate.Get("Skill_D_LateBuyer_Good2").."\n"..BAD..""..translate.Get("Skill_D_LateBuyer_Bad"),
    8, 1, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_TAUT, ""..translate.Get("Skill_Taut"), GOOD..""..translate.Get("Skill_Taut_Good").."\n"..BAD..""..translate.Get("Skill_Taut_Bad"),
    -5, 3, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_D_NOODLEARMS, ""..translate.Get("Skill_D_NoodleArms"), GOOD..""..translate.Get("Skill_D_NoodleArms_Good1").."\n"..GOOD..""..translate.Get("Skill_D_NoodleArms_Good2").."\n"..BAD..""..translate.Get("Skill_D_NoodleArms_Bad"),
    -7, 2, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_INSTRUMENTS, ""..translate.Get("Skill_Instruments"), GOOD..""..translate.Get("Skill_Instruments_Good"),
    -10, -3, {}, TREE_BUILDINGTREE)
GM:AddSkill(SKILL_STOWAGE, ""..translate.Get("Skill_Stowage"), GOOD..""..translate.Get("Skill_Stowage_Good").."\n"..BAD..""..translate.Get("Skill_Stowage_Bad"),
    4, -3, {}, TREE_BUILDINGTREE)

-- ============================================================
-- 本树技能的修饰符数值
-- GM:AddSkillModifier(技能ID, 修饰符类型, 数值)
-- 正数表示增益，负数表示减益；小于1的数值为倍率（如0.75表示75%）
-- ============================================================

-- 能手 I-VII+SP：修复速度
GM:AddSkillModifier(SKILL_HANDY1, SKILLMOD_REPAIRRATE_MUL, 0.04)

GM:AddSkillModifier(SKILL_HANDY2, SKILLMOD_REPAIRRATE_MUL, 0.05)

GM:AddSkillModifier(SKILL_HANDY3, SKILLMOD_REPAIRRATE_MUL, 0.06)

GM:AddSkillModifier(SKILL_HANDY4, SKILLMOD_REPAIRRATE_MUL, 0.07)

GM:AddSkillModifier(SKILL_HANDY5, SKILLMOD_REPAIRRATE_MUL, 0.08)

-- 木工纪律 / 路障专家
GM:AddSkillModifier(SKILL_HAMMERDISCIPLINE, SKILLMOD_HAMMER_SWING_DELAY_MUL, -0.2)

GM:AddSkillModifier(SKILL_BARRICADEEXPERT, SKILLMOD_HAMMER_SWING_DELAY_MUL, 0)

-- 面条手臂（负面，带特殊函数）
GM:AddSkillModifier(SKILL_D_NOODLEARMS, SKILLMOD_WORTH, 5)

GM:AddSkillModifier(SKILL_D_NOODLEARMS, SKILLMOD_SCRAP_START, 1)

GM:AddSkillFunction(SKILL_D_NOODLEARMS, function(pl, active)
	pl.NoObjectPickup = active
end)

-- 晚买者（负面）
GM:AddSkillModifier(SKILL_D_LATEBUYER, SKILLMOD_WORTH, 20)

GM:AddSkillModifier(SKILL_D_LATEBUYER, SKILLMOD_ARSENAL_DISCOUNT, -0.02)

-- 紧绷
GM:AddSkillFunction(SKILL_TAUT, function(pl, active)
	pl.BuffTaut = active
end)

-- 乐器 / 冷静 / 强壮 / 紧绷
GM:AddSkillModifier(SKILL_INSTRUMENTS, SKILLMOD_TURRET_RANGE_MUL, 0.05)

GM:AddSkillModifier(SKILL_TAUT, SKILLMOD_PROP_CARRY_SLOW_MUL, 0.4)

-- 炮塔过载 / 储藏
GM:AddSkillModifier(SKILL_TURRETOVERLOAD, SKILLMOD_TURRET_RANGE_MUL, -0.3)

GM:AddSkillModifier(SKILL_STOWAGE, SKILLMOD_RESUPPLY_DELAY_MUL, 0.15)

GM:AddSkillFunction(SKILL_STOWAGE, function(pl, active)
	pl.Stowage = active
end)

