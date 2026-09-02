--[[
	cl_namecards.lua - 名片系统（客户端）
	zs_namecard：我的名片（本地保存，变更时通过 net 上报服务器鉴权）
	zs_hide_namecards：屏蔽他人的名片（仅本地偏好）
	控制台输入 zs_namecard_check 可对整条链路做一键自检。
]]

local ipairs = ipairs
local file_Exists = file.Exists

-- 我的名片：本地保存（变更时主动上报服务器，不依赖 userinfo）
CreateClientConVar("zs_namecard", NAMECARD_NONE, true, false)
-- 屏蔽他人名片：仅本地偏好，不上传
CreateClientConVar("zs_hide_namecards", 0, true, false)

-- 材质缓存：ID -> IMaterial 或 false（加载失败，避免反复查找）
local matCache = {}

-- ============================================================
-- GM:GetNameCardMaterial - 获取名片材质（优先 .png，其次 .vmt），失败返回 nil
-- 直接尝试加载（不依赖 file.Exists，规避搜索路径差异）
-- ============================================================
function GM:GetNameCardMaterial(card)
	if not card then return nil end

	local cached = matCache[card.ID]
	if cached ~= nil then return cached or nil end

	local path = card.Material
	local mat = Material(path .. ".png")
	if mat:IsError() then
		mat = Material(path)
		if mat:IsError() then
			mat = false
		end
	end

	matCache[card.ID] = mat
	return mat or nil
end

-- ============================================================
-- GM:GetPlayerNameCardMaterial - 获取玩家名片的绘制用材质（遵守屏蔽设置）
-- ============================================================
function GM:GetPlayerNameCardMaterial(pl, ignoreBlock)
	local card = self:GetPlayerNameCard(pl, ignoreBlock)

	return self:GetNameCardMaterial(card)
end

-- ============================================================
-- GM:GetNameCardChoices - poptions 名片下拉框选项
-- 专属名片附加（专属）标记；本地预览不通过时额外提示（未解锁）
-- ============================================================
function GM:GetNameCardChoices()
	local choices = {
		{text = translate.Get("Option_NameCardNone"), value = NAMECARD_NONE}
	}

	local lp = LocalPlayer()
	for _, card in ipairs(self:GetSortedNameCards()) do
		local label = card.Name
		if card.Exclusive then
			label = label .. translate.Get("Option_NameCardExclusiveMark")
			if IsValid(lp) and not self:IsNameCardUsable(lp, card) then
				label = label .. translate.Get("Option_NameCardLockedSuffix")
			end
		end
		choices[#choices + 1] = {text = label, value = card.ID}
	end

	return choices
end

-- ============================================================
-- 上报名片选择（net 同步；userinfo 在部分环境下不可靠）
-- 进服时上报一次 + convar 变化时自动上报
-- ============================================================
local function SendNameCardToServer()
	local cvar = GetConVar("zs_namecard")
	if not cvar then return end

	local value = cvar:GetString()

	net.Start(NET_MSG.NAMECARD)
		net.WriteString(value)
	net.SendToServer()
end

hook.Add("InitPostEntity", "ZS_NameCards_ReportOnJoin", SendNameCardToServer)
cvars.AddChangeCallback("zs_namecard", SendNameCardToServer, "ZS_NameCards_Change")

-- ============================================================
-- zs_namecard_check - 名片系统一键自检（客户端控制台）
-- 依次检查：convar、注册表、材质文件、NWString 同步结果
-- ============================================================
concommand.Add("zs_namecard_check", function()
	print("========== [NameCards] 名片系统自检 ==========")

	local cvar = GetConVar("zs_namecard")
	local value = cvar and cvar:GetString() or "?（convar 不存在）"
	local hide = GetConVar("zs_hide_namecards")
	print("[1] zs_namecard = \"" .. value .. "\"   zs_hide_namecards = " .. (hide and tostring(hide:GetBool()) or "?"))

	local cards = GAMEMODE:GetSortedNameCards()
	local ids = {}
	for _, card in ipairs(cards) do
		ids[#ids + 1] = card.ID
	end
	print("[2] 已注册名片 " .. #cards .. " 张: " .. table.concat(ids, ", "))

	for _, card in ipairs(cards) do
		local hasPng = file_Exists("materials/" .. card.Material .. ".png", "GAME")
		local hasVmt = file_Exists("materials/" .. card.Material .. ".vmt", "GAME")
		local mat = GAMEMODE:GetNameCardMaterial(card)
		local usable = GAMEMODE:IsNameCardUsable(LocalPlayer(), card)
		print(string.format("    %-12s png=%-5s vmt=%-5s 材质=%-4s 使用权限=%s",
			card.ID, tostring(hasPng), tostring(hasVmt), mat and "OK" or "缺失", tostring(usable)))
	end

	local lp = LocalPlayer()
	if IsValid(lp) then
		print("[3] 我的 NWString zs_namecard = \"" .. lp:GetNWString("zs_namecard", "") .. "\"")
		print("[4] 排查提示：[1] 有值而 [3] 为空 => 服务器未收到/未通过同步（确认服务器已更新 gamemode 并重启回合）")
		print("               [3] 有值而计分板不显示 => 看上方材质加载日志，确认 png/vmt 是否加载成功")
	else
		print("[3] LocalPlayer 尚未就绪，进图后再试")
	end
	print("========== 自检结束 ==========")
end)
