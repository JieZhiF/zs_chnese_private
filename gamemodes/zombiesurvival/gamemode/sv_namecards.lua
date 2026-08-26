--[[
	sv_namecards.lua - 名片系统（服务端）
	客户端通过 zs_namecard 网络消息上报名片选择（userinfo 同步在部分环境下不可靠），
	服务端鉴权（专属名片走 CanUse）后用 NWString 广播给所有客户端。
	不合法的选择会被拒绝，并通过 CenterNotify 提示玩家。
	在服务器控制台输入 zs_namecard_debug 1 可开启调试输出。
]]

local IsValid = IsValid

-- 调试开关（服务器控制台）
CreateConVar("zs_namecard_debug", "0", FCVAR_ARCHIVE, "名片系统调试输出（服务端）")

local function DebugPrint(...)
	local cvar = GetConVar("zs_namecard_debug")
	if cvar and cvar:GetBool() then
		print("[NameCards][服务端]", ...)
	end
end

-- ============================================================
-- ApplyNameCard - 校验并应用玩家的名片选择
-- ============================================================
local function ApplyNameCard(pl, raw)
	if not IsValid(pl) then return end

	raw = tostring(raw or "")
	DebugPrint(pl:Name() .. " 上报名片: \"" .. raw .. "\"")

	local card = GAMEMODE:GetNameCard(raw)
	if card and not GAMEMODE:IsNameCardUsable(pl, card) then
		DebugPrint(pl:Name() .. " 无权使用 " .. card.ID .. "（专属名片校验未通过），已拒绝")
		pl:CenterNotify(COLOR_RED, translate.ClientGet(pl, "namecard_locked"))
		card = nil
	elseif not card and raw ~= "" and raw ~= NAMECARD_NONE then
		DebugPrint(pl:Name() .. " 上报了未知名片 ID: \"" .. raw .. "\"（未注册或已移除）")
	end

	local oldCard = GAMEMODE:GetNameCard(pl:GetNWString("zs_namecard", ""))
	local newID = card and card.ID or ""

	if newID ~= (oldCard and oldCard.ID or "") then
		pl:SetNWString("zs_namecard", newID)
		DebugPrint(pl:Name() .. " 名片同步完成 -> \"" .. (newID == "" and "无" or newID) .. "\"")
		gamemode.Call("PlayerNameCardChanged", pl, card, oldCard)
	end
end

-- 客户端上报名片选择
net.Receive(NET_MSG.NAMECARD, function(len, sender)
	if not IsValid(sender) or not sender:IsPlayer() then return end
	ApplyNameCard(sender, net:ReadString())
end)
