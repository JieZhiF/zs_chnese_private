-- ============================================================================
-- DAmmoBar - 底部弹药横栏（SUNRUST 风格复刻，共识 v5.3）
-- 12 类弹药槽：方形图标框（近黑深槽底）+ 三位数量 + （有货时）丢弃/给予小按钮
-- 由主面板 ZSInventoryPanel 以 vgui.Create("ZSAmmoBar", self) 创建并 Dock Bottom
-- 点击图标切换 zs_resupplyammotype；丢弃/给予走 zsdropammo / zsgiveammo
-- 布局比例以 SUNRUST 靶子图（2560x1440 实测）为准：栏高 100 基值、槽框 ~56 基值、
-- 数量行位于框下（17 级字体），有货时主题色渐变更明显。
-- ============================================================================
-- 区域地图（VGUI 结构索引：区域/位置/作用/常改）
--
-- [区域] 常量与主题色
-- [位置] 文件头部局部表（AMMO_ORDER / THEME_COLORS）
-- [作用] 槽位顺序、每类弹药的主题色、渐变贴图与公共颜色
-- [常改] 12 色主题表、槽位顺序
--
-- [区域] 根面板
-- [位置] PANEL:Init / PANEL:PerformLayout / PANEL:Paint（ZSAmmoBar）
-- [作用] Dock Bottom 横栏：12 槽均分布局、深色栏底（仅上侧两角圆角）
-- [常改] 栏高 BAR_TALL、栏底配色、圆角半径
--
-- [区域] 12 槽渲染
-- [位置] SLOT:Init / SLOT:SetAmmoKey / SLOT:UpdateCount / SLOT:Paint（ZSAmmoSlot）
-- [作用] 每槽方形图标框（近黑深槽底）+ 主题色描边 + 向下渐变（有货加浓）+ killicon 弹药图标（缺图标画占位块）
-- [常改] 图标框边距、描边粗细、渐变透明度、图标兜底画法
--
-- [区域] 选中态描边
-- [位置] SLOT:Paint（MySelf.ResupplyChoice 判断段）
-- [作用] 当前补给选中的槽位外圈加画一圈同主题色空心描边
-- [常改] 外圈间隔、描边宽度
--
-- [区域] 数量两段着色
-- [位置] SLOT:Paint（数量三位段）
-- [作用] %03d 三位数量分两段着色：前导零暗灰、有效位亮白；数量为 0 时整串暗灰
-- [常改] 前导零/有效位/空数量颜色、字体（ZSInvAmmoCount 本文件懒创建）
--
-- [区域] 丢弃/给予小按钮
-- [位置] SLOT:PerformLayout / SLOT:Paint / SLOT:OnMousePressed
-- [作用] 数量 > 0 时在数量下方并排绘制绿色小按钮（box 图标 = 丢弃 / user_go 图标 = 给予），点击发 zsdropammo / zsgiveammo
-- [常改] 按钮尺寸与命中矩形、按钮图标路径、指令名
--
-- [区域] tooltip
-- [位置] PANEL:PaintOver
-- [作用] 悬停槽位上方自绘提示框（弹药名 + 持有量），clamp 在栏内
-- [常改] 提示底色、内边距、字体
--
-- [区域] 0.5s 刷新
-- [位置] PANEL:Think
-- [作用] 每 0.5s 轮询 MySelf:GetAmmoCount 回填 12 槽数量
-- [常改] RefreshTime 间隔
-- ============================================================================

local PANEL = {}

-- 性能局部化（仓库惯例）
local math = math
local string = string
local ipairs = ipairs
local RealTime = RealTime
local draw = draw
local surface = surface
local vgui = vgui

-- 槽位顺序表：与 GM.AmmoIcons 注册顺序一致（sh_globals.lua）
local AMMO_ORDER = { "pistol", "smg1", "ar2", "battery", "buckshot", "357", "xbowbolt", "gaussenergy", "pulse", "impactmine", "chemical", "scrap" }

-- SUNRUST 风格主题色，可调（与 AMMO_ORDER 一一对应）
local THEME_COLORS = {
	pistol = Color(176, 176, 186),		-- 手枪：灰
	smg1 = Color(255, 158, 64),			-- 冲锋枪：橙
	ar2 = Color(198, 168, 96),			-- 突击步枪：土黄
	battery = Color(104, 214, 118),		-- 医疗能量：绿
	buckshot = Color(192, 92, 62),		-- 霰弹：红棕
	["357"] = Color(146, 208, 150),		-- 步枪：绿
	xbowbolt = Color(140, 176, 132),	-- 弩箭：灰绿
	gaussenergy = Color(240, 216, 92),	-- 钉子：黄
	pulse = Color(146, 128, 240),		-- 脉冲：蓝紫
	impactmine = Color(230, 84, 84),	-- 爆炸物：红
	chemical = Color(238, 148, 64),		-- 化学品：橙
	scrap = Color(152, 152, 158),		-- 废料：灰
}

-- 向下渐变贴图（图标框下方主题色→透明）
local texGradientDown = surface.GetTextureID("gui/gradient_down")

-- 公共颜色（深色风格：槽底近黑、栏底加深，对齐靶子图）
local colBarBG = Color(8, 8, 10, 238)			-- 横栏底色
local colFrameBG = Color(8, 8, 9, 250)			-- 图标框深色底（近黑实心）
local colFrameBGHover = Color(28, 28, 30, 250)	-- 悬停时图标框底色
local colLeadZero = Color(112, 112, 112)		-- 数量前导零
local colValidDigit = Color(245, 245, 245)		-- 数量有效位
local colEmptyDigit = Color(98, 98, 98)			-- 数量为 0 时整串
local colBtnBG = Color(36, 80, 44, 215)			-- 小按钮底（绿色调）
local colBtnBGHover = Color(64, 130, 74, 230)	-- 小按钮悬停底
local colBtnArrow = Color(198, 240, 205, 235)	-- 小按钮箭头
local colTipBG = Color(6, 6, 8, 235)			-- 自绘提示底
local colTipText = Color(225, 225, 225)			-- 自绘提示文字

-- 字体
-- 数量字体：本文件懒创建（Harmony 加粗 17 级，对齐靶子图框下数量字号）
local FONT_COUNT = "ZSInvAmmoCount"
local FONT_TIP = "ZSHUDFontSmallest"

local AmmoCountFontReady = false
local function EnsureAmmoCountFont()
	if AmmoCountFontReady then return end
	AmmoCountFontReady = true
	surface.CreateFont(FONT_COUNT, {font = "Harmony OS Sans SC", size = math.ceil(17 * BetterScreenScale()), weight = 650, extended = true, antialias = true})
end

-- 获取给予目标索引：优先用面板「选择附近人类」选中的队友（SelectedGiveTarget），
-- 其次 ALT 按下时面对的锁定目标（HumanMenuLockOn），都没有则 0（服务端面前检测）
local function GetTargetEntIndex()
	if GAMEMODE.InventoryPanel and GAMEMODE.InventoryPanel.SelectedGiveTarget then
		local idx = GAMEMODE.InventoryPanel.SelectedGiveTarget
		local target = Entity(idx)
		if IsValid(target) and target:IsPlayer() and target:Alive() then
			return idx
		end
	end

	return GAMEMODE.HumanMenuLockOn and GAMEMODE.HumanMenuLockOn:IsValid() and GAMEMODE.HumanMenuLockOn:EntIndex() or 0
end

-- 点是否在矩形内（矩形为 {x, y, w, h}）
local function InRect(x, y, r)
	return x >= r.x and y >= r.y and x <= r.x + r.w and y <= r.y + r.h
end

-- 点是否在矩形内（矩形为 {x, y, w, h}）
local function InRect(x, y, r)
	return x >= r.x and y >= r.y and x <= r.x + r.w and y <= r.y + r.h
end

-- ============================================================================
-- 弹药槽（ZSAmmoSlot）：纯 Paint 手绘子控件，无子面板
-- ============================================================================

local SLOT = {}

function SLOT:Init()
	self.AmmoKey = "pistol"
	self.Count = 0
	self:SetMouseInputEnabled(true)
end

-- 绑定弹药类型与主题色
function SLOT:SetAmmoKey(key)
	self.AmmoKey = key
	self.ThemeColor = THEME_COLORS[key] or color_white
end

-- 轮询回填数量（由横栏 Think 调用）
function SLOT:UpdateCount(count)
	self.Count = count
end

-- 计算图标框 / 数量行 / 两枚小按钮的命中矩形
function SLOT:PerformLayout()
	local scale = BetterScreenScale()
	local w, h = self:GetSize()

	-- 方形图标框：水平居中，顶部留边（栏加高后框约 56 基值，对齐靶子图槽框比例）
	local boxsize = math.min(w - 16 * scale, h - 44 * scale)
	self.IconRect = { x = (w - boxsize) * 0.5, y = 8 * scale, w = boxsize, h = boxsize }

	-- 数量行：紧贴图标框下方（高度压缩，给下方按钮行留位）
	self.CountY = self.IconRect.y + boxsize + 4 * scale
	self.CountH = math.max(h - self.CountY - 24 * scale, 12 * scale)

	-- 两枚小按钮：数量行下方并排居中（SUNRUST 布局；仅数量 > 0 时绘制并可点）
	local btn = math.min(12 * scale, self.CountH)
	local by = self.CountY + self.CountH + 1 * scale
	self.DropRect = { x = w * 0.5 - btn - 2 * scale, y = by, w = btn, h = btn }
	self.GiveRect = { x = w * 0.5 + 2 * scale, y = by, w = btn, h = btn }
end

function SLOT:Paint()
	local scale = BetterScreenScale()
	local w = self:GetWide()
	local theme = self.ThemeColor or color_white
	local count = self.Count or 0
	local hasammo = count > 0
	local icon = self.IconRect
	if not icon then return end

	-- 向下渐变底：图标框下方画主题色→透明；有货时加浓更明显，无弹药时保留淡渐变
	local gradalpha = hasammo and 200 or 45
	surface.SetTexture(texGradientDown)
	surface.SetDrawColor(theme.r, theme.g, theme.b, gradalpha)
	surface.DrawTexturedRect(icon.x, icon.y + icon.h, icon.w, self:GetTall() - (icon.y + icon.h))

	-- 图标框：深色底 + 主题色描边（1-2px）
	local cursorX, cursorY = self:CursorPos()
	local hovered = InRect(cursorX, cursorY, icon)
	draw.RoundedBox(2, icon.x, icon.y, icon.w, icon.h, hovered and colFrameBGHover or colFrameBG)
	local outline = math.max(1, math.floor(scale))
	surface.SetDrawColor(theme.r, theme.g, theme.b, 255)
	surface.DrawOutlinedRect(icon.x, icon.y, icon.w, icon.h, outline)

	-- 选中态：外圈再画一圈同主题色空心描边（2px，间隔 2px），仅当前选中类
	if MySelf and MySelf.ResupplyChoice == self.AmmoKey then
		surface.SetDrawColor(theme.r, theme.g, theme.b, 255)
		surface.DrawOutlinedRect(icon.x - 4 * scale, icon.y - 4 * scale, icon.w + 8 * scale, icon.h + 8 * scale, math.max(2, math.floor(2 * scale)))
	end

	-- 弹药图标：与全库一致的取法——killicon.Get(GM.AmmoIcons[key]) 得 {材质路径, 染色}
	local iconname = GAMEMODE.AmmoIcons and GAMEMODE.AmmoIcons[self.AmmoKey]
	local drawn = false
	if iconname then
		local ki = killicon.Get(iconname)
		if ki and ki[1] then
			local mat = Material(ki[1])
			if mat and not mat:IsError() then
				local mw, mh = mat:Width(), mat:Height()
				if mw > 0 and mh > 0 then
					-- 等比缩入图标框（留 1/8 内边距）
					local inset = icon.w * 0.125
					local maxw, maxh = icon.w - inset * 2, icon.h - inset * 2
					local s = math.min(maxw / mw, maxh / mh)
					local icw, ich = mw * s, mh * s
					local col = ki[2] or color_white
					surface.SetMaterial(mat)
					surface.SetDrawColor(col.r, col.g, col.b, hasammo and 255 or 140)
					surface.DrawTexturedRect(icon.x + (icon.w - icw) * 0.5, icon.y + (icon.h - ich) * 0.5, icw, ich)
					drawn = true
				end
			end
		end
	end
	-- 图标缺失时的占位块（主题色小方块）
	if not drawn then
		local ph = icon.w * 0.4
		surface.SetDrawColor(theme.r, theme.g, theme.b, hasammo and 200 or 90)
		surface.DrawRect(icon.x + (icon.w - ph) * 0.5, icon.y + (icon.h - ph) * 0.5, ph, ph)
	end

	-- 数量三位：分两段着色（前导零暗灰，有效位白；为 0 时整串暗灰）
	local text = string.format("%03d", math.max(count, 0))
	surface.SetFont(FONT_COUNT)
	local cx = w * 0.5
	local cy = self.CountY + self.CountH * 0.5
	if hasammo then
		local sig = tostring(count)
		local leadn = #text - #sig
		local prefix = leadn > 0 and string.sub(text, 1, leadn) or ""
		local pw = surface.GetTextSize(prefix)
		local sw = surface.GetTextSize(sig)
		local startx = cx - (pw + sw) * 0.5
		if prefix ~= "" then
			draw.SimpleText(prefix, FONT_COUNT, startx, cy, colLeadZero, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(sig, FONT_COUNT, startx + pw, cy, colValidDigit, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	else
		draw.SimpleText(text, FONT_COUNT, cx, cy, colEmptyDigit, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- 数量 > 0：绘制两枚绿色调小按钮（原版 icon16 图标：box = 丢弃 / user_go = 给予）
	if hasammo then
		local hmx, hmy = self:CursorPos()
		for _, info in ipairs({ { self.DropRect, "icon16/box.png" }, { self.GiveRect, "icon16/user_go.png" } }) do
			local r, matname = info[1], info[2]
			if r then
				local hot = InRect(hmx, hmy, r)
				draw.RoundedBox(2, r.x, r.y, r.w, r.h, hot and colBtnBGHover or colBtnBG)
				local mat = Material(matname)
				if mat and not mat:IsError() then
					surface.SetMaterial(mat)
					surface.SetDrawColor(colBtnArrow.r, colBtnArrow.g, colBtnArrow.b, colBtnArrow.a)
					surface.DrawTexturedRect(r.x + 1, r.y + 1, r.w - 2, r.h - 2)
				end
			end
		end
	end
end

function SLOT:OnMousePressed(mousecode)
	if mousecode ~= MOUSE_LEFT then return end
	-- 空槽不可点
	if not IsValid(MySelf) or (self.Count or 0) <= 0 then return end

	local mx, my = self:CursorPos()
	-- 小按钮优先于图标切换
	if self.GiveRect and InRect(mx, my, self.GiveRect) then
		RunConsoleCommand("zsgiveammo", self.AmmoKey, GetTargetEntIndex())
		return
	end
	if self.DropRect and InRect(mx, my, self.DropRect) then
		RunConsoleCommand("zsdropammo", self.AmmoKey)
		return
	end
	-- 点击图标：切换补给选择（再点取消，回 default）
	if self.IconRect and InRect(mx, my, self.IconRect) then
		-- 与 sh_options.lua 白名单一致才允许选中（防御）
		if GAMEMODE.AmmoResupply and not GAMEMODE.AmmoResupply[self.AmmoKey] then return end
		if MySelf.ResupplyChoice == self.AmmoKey then
			MySelf.ResupplyChoice = nil
			RunConsoleCommand("zs_resupplyammotype", "default")
		else
			MySelf.ResupplyChoice = self.AmmoKey
			RunConsoleCommand("zs_resupplyammotype", self.AmmoKey)
		end
	end
end

vgui.Register("ZSAmmoSlot", SLOT, "Panel")

-- ============================================================================
-- 底部横栏（ZSAmmoBar）
-- ============================================================================

-- 面板尺寸：高约 BetterScreenScale() * 100（靶子图实测栏高 155px@1440p）
local BAR_TALL = 100
-- 刷新间隔（秒），照 dammocounter 的 RealTime 节流写法
PANEL.NextRefresh = 0
PANEL.RefreshTime = 0.5

function PANEL:Init()
	EnsureAmmoCountFont()
	self:SetTall(BAR_TALL * BetterScreenScale())
	self:SetMouseInputEnabled(true)

	-- 按 AMMO_ORDER 顺序创建 12 个槽
	self.Slots = {}
	for _, key in ipairs(AMMO_ORDER) do
		local slot = vgui.Create("ZSAmmoSlot", self)
		slot:SetAmmoKey(key)
		self.Slots[#self.Slots + 1] = slot
	end
end

-- 槽宽均分：整栏宽 / 12
function PANEL:PerformLayout()
	local w, h = self:GetSize()
	local slotw = w / #AMMO_ORDER
	for i, slot in ipairs(self.Slots) do
		slot:SetPos(math.floor((i - 1) * slotw), 0)
		slot:SetSize(math.ceil(slotw), h)
	end
end

-- 每 0.5s 轮询本地玩家各类弹药持有量
function PANEL:Think()
	if RealTime() >= self.NextRefresh then
		self.NextRefresh = RealTime() + self.RefreshTime
		if IsValid(MySelf) then
			for _, slot in ipairs(self.Slots) do
				slot:UpdateCount(MySelf:GetAmmoCount(slot.AmmoKey))
			end
		end
	end
end

-- 深色栏底（Dock Bottom：仅上侧两角圆角），子槽在其上绘制
function PANEL:Paint(w, h)
	draw.RoundedBoxEx(6 * BetterScreenScale(), 0, 0, w, h, colBarBG, true, true, false, false)
	return true
end

-- PaintOver：画在所有子槽之上的自绘悬停提示（名称 + 持有量）
function PANEL:PaintOver(w, h)
	local mx, my = self:CursorPos()
	if mx < 0 or my < 0 or mx >= w or my >= h then return end

	local scale = BetterScreenScale()
	local slotw = w / #AMMO_ORDER
	local idx = math.Clamp(math.floor(mx / slotw) + 1, 1, #AMMO_ORDER)
	local slot = self.Slots[idx]
	if not slot then return end

	local name = GAMEMODE.AmmoNames and GAMEMODE.AmmoNames[slot.AmmoKey] or slot.AmmoKey
	local text = name .. " ×" .. tostring(slot.Count or 0)
	-- 已选择给予目标时在提示中标注
	local targetidx = GetTargetEntIndex()
	if targetidx > 0 then
		local target = Entity(targetidx)
		if IsValid(target) and target:IsPlayer() then
			text = text .. "  → " .. target:Nick()
		end
	end
	surface.SetFont(FONT_TIP)
	local tw, th = surface.GetTextSize(text)
	local pad = 6 * scale
	local boxw, boxh = tw + pad * 2, th + pad
	local bx = math.Clamp(idx * slotw - boxw * 0.5, 2, w - boxw - 2)
	local by = 2
	draw.RoundedBox(4, bx, by, boxw, boxh, colTipBG)
	draw.SimpleText(text, FONT_TIP, bx + boxw * 0.5, by + boxh * 0.5, colTipText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("ZSAmmoBar", PANEL, "Panel")
