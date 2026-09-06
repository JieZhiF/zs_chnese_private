-- ============================================================
-- 技能树系统 - 注册表核心（拆分自 registry.lua）
-- 内容：全局数据表（Skills / SkillModifiers / SkillFunctions /
--       SkillModifierFunctions）、技能注册API、六大技能树常量
-- 加载顺序：由 registry.lua 最先加载
-- ============================================================

-- GM 全局仅在技能树加载阶段可用，此处捕获为 local 以便后续使用
local GM = GM or GAMEMODE

-- ============================================================
-- 技能树系统 - 技能注册表
-- 定义所有技能、技能修饰符、技能函数、树常量、
-- 技能ID常量、修饰符ID常量，以及各技能的增益/减益数值
-- ============================================================

-- ============================================================
-- 全局技能数据表
--   Skills[] — 所有技能定义（名称、描述、连接、位置、树归属）
--   SkillModifiers[] — 各技能对应的修饰符及数值
--   SkillFunctions[] — 各技能对应的特殊函数列表
--   SkillModifierFunctions[] — 各修饰符ID对应的处理函数
-- ============================================================
GM.Skills = {}
GM.SkillModifiers = {}
GM.SkillFunctions = {}
GM.SkillModifierFunctions = {}

-- ============================================================
-- 注册新技能
-- @param id 技能ID
-- @param name 技能名称（空字符串表示禁用该技能）
-- @param description 技能描述（仅客户端使用）
-- @param x, y 在技能树网格中的位置（仅客户端）
-- @param connections 相邻技能ID列表
-- @param tree 所属技能树（TREE_* 常量）
-- @return skill 技能表
-- ============================================================
function GM:AddSkill(id, name, description, x, y, connections, tree)
	local skill = {Connections = table.ToAssoc(connections or {})}

	if CLIENT then
		skill.x = x
		skill.y = y

		-- TODO: 基于修饰符动态生成技能描述

		skill.Description = description
	end

	-- 名称为空则该技能被禁用（占位用）
	if #name == 0 then
		name = "Skill "..id
		skill.Disabled = true
	end

	skill.Name = name
	skill.Tree = tree

	self.Skills[id] = skill

	return skill
end

-- ============================================================
-- 注册饰品（Trinket）技能
-- @param name 饰品名称
-- @param swepaffix 武器后缀
-- @param pairedweapon 是否配对武器
-- @param veles 保留参数
-- @param weles 掉落物品列表
-- @param tier 品质等级
-- @param description 描述
-- @param status 状态实体名
-- @param stocks 库存
-- @return skillId, dataTab
-- ============================================================
function GM:AddTrinket(name, swepaffix, pairedweapon, veles, weles, tier, description, status, stocks)
	local skill = {Connections = {}}

	skill.Name = name
	skill.Trinket = swepaffix
	skill.Status = status

	local datatab = {PrintName = name, DroppedEles = weles, Tier = tier, Description = description, Status = status, Stocks = stocks}

	if pairedweapon then
		skill.PairedWeapon = "weapon_zs_t_" .. swepaffix
	end

	self.ZSInventoryItemData["trinket_" .. swepaffix] = datatab
	self.Skills[#self.Skills + 1] = skill

	return #self.Skills, self.ZSInventoryItemData["trinket_" .. swepaffix]
end

-- ============================================================
-- 通过饰品名称查找对应的技能ID
-- ============================================================
function GM:GetTrinketSkillID(trinketname)
	for skillid, skill in pairs(self.Skills) do
		if skill.Trinket and skill.Trinket == trinketname then
			return skillid
		end
	end
end

-- ============================================================
-- 为指定技能添加修饰符数值
-- 同类型修饰符的数值会累加
-- ============================================================
function GM:AddSkillModifier(skillid, modifier, amount)
	self.SkillModifiers[skillid] = self.SkillModifiers[skillid] or {}
	self.SkillModifiers[skillid][modifier] = (self.SkillModifiers[skillid][modifier] or 0) + amount
end

-- ============================================================
-- 为指定技能添加特殊函数
-- 技能激活/停用时调用
-- ============================================================
function GM:AddSkillFunction(skillid, func)
	self.SkillFunctions[skillid] = self.SkillFunctions[skillid] or {}
	table.insert(self.SkillFunctions[skillid], func)
end

-- ============================================================
-- 注册修饰符处理函数
-- @param modid 修饰符ID
-- @param func 处理函数(pl, amount)
-- ============================================================
function GM:SetSkillModifierFunction(modid, func)
	self.SkillModifierFunctions[modid] = func
end

-- ============================================================
-- 创建通用修饰符函数
-- 将 amount + 1.0 限制在 [0, 1000] 后赋给 pl[modifiername]
-- ============================================================
function GM:MkGenericMod(modifiername)
	return function(pl, amount) pl[modifiername] = math.Clamp(amount + 1.0, 0.0, 1000.0) end
end

-- ============================================================
-- 技能树类型常量（用于屏幕上的位置排列）
-- ============================================================
TREE_HEALTHTREE = 1
TREE_SPEEDTREE = 2
TREE_SUPPORTTREE = 3
TREE_BUILDINGTREE = 4
TREE_MELEETREE = 5
TREE_GUNTREE = 6

