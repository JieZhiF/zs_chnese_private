--[[
	sh_namecards.lua - 名片系统（共享）
	玩家可以在 F4 设置界面（poptions）中选择自己显示的名片，名片会以横幅形式
	绘制在 TAB 计分板的玩家行上，并在悬停信息卡中展示大图；
	客户端可以通过设置屏蔽他人的名片。

	名片材质统一放在 materials/namecards/ 文件夹（支持 .png / .vmt），
	文件名与名片 ID 一致，例如 namecards/default.png。

	对外接口（未来推出专属名片时使用）：
		GAMEMODE:AddNameCard{
			ID = "vip_gold",                 -- 必填，唯一 ID，同时是材质文件名
			Name = "尊享金卡",                -- 可选，显示名称（默认用 ID）
			Desc = "说明文字",                -- 可选，描述（供未来商店/预览界面使用）
			Material = "namecards/vip_gold", -- 可选，材质路径（默认 namecards/<ID>）
			SortOrder = 100,                 -- 可选，下拉框排序权重（越小越靠前）
			Exclusive = true,                -- 可选，专属名片（默认所有人可用）
			CanUse = function(pl)            -- 可选，专属名片持有校验（服务端鉴权 + 客户端预览共用）
				return pl:IsAdmin()
			end,
		}
	名片变更成功后服务端会触发 gamemode.Call("PlayerNameCardChanged", pl, newCard, oldCard)。
]]

local ipairs = ipairs
local pairs = pairs
local table_insert = table.insert
local table_sort = table.sort

-- 名片 convar 的“不使用”占位值
NAMECARD_NONE = "none"

GM.NameCards = {}        -- 注册顺序数组
GM.NameCardsByID = {}    -- ID -> 定义表
GM.NameCardsSorted = nil -- 排序缓存（注册新名片时置空）

-- ============================================================
-- GM:AddNameCard - 名片注册接口
-- 用法见文件头注释；重复 ID 会拒绝注册并提示
-- ============================================================
function GM:AddNameCard(card)
	if not istable(card) or not isstring(card.ID) or card.ID == "" then
		ErrorNoHalt("[NameCards] 注册名片必须提供非空的 ID 字符串！\n")
		return
	end

	if self.NameCardsByID[card.ID] then
		ErrorNoHalt("[NameCards] 名片 ID 重复，注册被拒绝：" .. card.ID .. "\n")
		return self.NameCardsByID[card.ID]
	end

	card.Name = card.Name or card.ID
	card.Material = card.Material or ("namecards/" .. card.ID)
	card.SortOrder = card.SortOrder or (#self.NameCards + 1)
	card.Exclusive = card.Exclusive == true

	self.NameCardsByID[card.ID] = card
	table_insert(self.NameCards, card)
	self.NameCardsSorted = nil

	return card
end

-- ============================================================
-- GM:GetNameCard - 按 ID 获取名片定义
-- ============================================================
function GM:GetNameCard(id)
	if not id or id == "" or id == NAMECARD_NONE then return nil end
	return self.NameCardsByID[id]
end

-- ============================================================
-- GM:GetSortedNameCards - 排序后的名片列表（下拉框用）
-- ============================================================
function GM:GetSortedNameCards()
	if not self.NameCardsSorted then
		local sorted = {}
		for _, card in pairs(self.NameCards) do
			table_insert(sorted, card)
		end
		table_sort(sorted, function(a, b)
			if a.SortOrder ~= b.SortOrder then return a.SortOrder < b.SortOrder end
			return a.ID < b.ID
		end)
		self.NameCardsSorted = sorted
	end
	return self.NameCardsSorted
end

-- ============================================================
-- GM:IsNameCardUsable - 名片持有校验
-- 普通名片所有人可用；专属名片必须通过 CanUse 回调
-- ============================================================
function GM:IsNameCardUsable(pl, card)
	if not card then return false end
	if not card.Exclusive then return true end
	if isfunction(card.CanUse) then
		local ok, result = pcall(card.CanUse, pl)
		return ok and result == true
	end
	return false
end

-- ============================================================
-- GM:GetPlayerNameCard - 获取玩家当前佩戴的名片定义
-- 客户端默认遵守“屏蔽他人名片”设置（ignoreBlock 为 true 时跳过检查）
-- ============================================================
function GM:GetPlayerNameCard(pl, ignoreBlock)
	if not IsValid(pl) then return nil end

	local card = self:GetNameCard(pl:GetNWString("zs_namecard", ""))
	if not card then return nil end

	if CLIENT and not ignoreBlock and pl ~= LocalPlayer() then
		local hide = GetConVar("zs_hide_namecards")
		if hide and hide:GetBool() then return nil end
	end

	return card
end

-- ============================================================
-- 默认名片注册
-- 材质文件位于 materials/namecards/<ID>.png（或 .vmt），
-- 当前为程序生成的占位图，直接替换同名文件即可换成正式美术。
-- ============================================================
GM:AddNameCard{ID = "default", Name = "零号档案", SortOrder = 10, Desc = "幸存者的基础身份档案。"}
GM:AddNameCard{ID = "crimson", Name = "猩红浪潮", SortOrder = 11, Desc = "浸染血色的作战记录。"}
GM:AddNameCard{ID = "verdant", Name = "翠绿庇护", SortOrder = 12, Desc = "庇护所发放的通行凭证。"}
GM:AddNameCard{ID = "midnight", Name = "午夜协议", SortOrder = 13, Desc = "只在深夜行动的暗号。"}
GM:AddNameCard{ID = "amber", Name = "落日余晖", SortOrder = 14, Desc = "黄昏撤离时留下的纪念。"}
GM:AddNameCard{ID = "frost", Name = "极地霜华", SortOrder = 15, Desc = "寒霜凝结成的徽记。"}

-- 专属名片示例：演示 Exclusive + CanUse 接口，未来可替换为更复杂的鉴权逻辑
GM:AddNameCard{
	ID = "commander",
	Name = "指挥官",
	Desc = "示例专属名片：仅管理员可用。",
	SortOrder = 90,
	Exclusive = true,
	CanUse = function(pl)
		return IsValid(pl) and pl:IsAdmin()
	end
}
