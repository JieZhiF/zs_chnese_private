
---
-- @function SWEP:PreDrawViewModel
-- @description 在绘制视图模型之前调用。
--
function SWEP:PreDrawViewModel(vm)
	-- 如果设置了不显示视图模型，则将其完全透明化。
	if self.ShowViewModel == false then
		render.SetBlend(0)
	end
end

---
-- @function SWEP:PostDrawViewModel
-- @description 在绘制视图模型之后调用。
--
function SWEP:PostDrawViewModel(vm)
	-- 恢复渲染混合模式。
	if self.ShowViewModel == false then
		render.SetBlend(1)
	end

	-- 如果定义了 3D HUD 并且游戏模式允许绘制，则进行绘制。
	if self.HUD3DPos and GAMEMODE:ShouldDraw3DWeaponHUD() then
		local pos, ang = self:GetHUD3DPos(vm)
		if pos then
			self:Draw3DHUD(vm, pos, ang)
		end
	end
end

---
-- @function SWEP:GetHUD3DPos
-- @description 获取 3D HUD 在世界中的位置和角度。
--
function SWEP:GetHUD3DPos(vm)
	-- 查找指定的骨骼。
	local bone = vm:LookupBone(self.HUD3DBone)
	if not bone then return end

	-- 获取骨骼的矩阵信息（包含位置和角度）。
	local m = vm:GetBoneMatrix(bone)
	if not m then return end

	local pos, ang = m:GetTranslation(), m:GetAngles()

	-- 如果视图模型是翻转的，需要修正角度。
	if self.ViewModelFlip then
		ang.r = -ang.r
	end

	-- 应用位置和角度偏移。
	local offset = self.HUD3DPos
	local aoffset = self.HUD3DAng
	pos = pos + ang:Forward() * offset.x + ang:Right() * offset.y + ang:Up() * offset.z
	if aoffset.yaw ~= 0 then ang:RotateAroundAxis(ang:Up(), aoffset.yaw) end
	if aoffset.pitch ~= 0 then ang:RotateAroundAxis(ang:Right(), aoffset.pitch) end
	if aoffset.roll ~= 0 then ang:RotateAroundAxis(ang:Forward(), aoffset.roll) end

	return pos, ang
end

-- 定义 3D HUD 使用的颜色
local colBG = Color(16, 16, 16, 90)
local colRed = Color(220, 0, 0, 230)
local colYellow = Color(220, 220, 0, 230)
local colWhite = Color(220, 220, 220, 230)
local colAmmo = Color(255, 255, 255, 230)

---
-- @function GetAmmoColor
-- @description 根据当前弹药量返回一个动态颜色。
--
local function GetAmmoColor(clip, maxclip)
	if clip == 0 then
		colAmmo.r, colAmmo.g, colAmmo.b = 255, 0, 0
	else
		-- 弹药越少，颜色越偏向红色。
		local sat = clip / maxclip
		colAmmo.r = 255
		colAmmo.g = sat ^ 0.3 * 255
		colAmmo.b = sat * 255
	end
end

---
-- @function SWEP:GetDisplayAmmo
-- @description 计算用于显示的弹药数量，处理某些武器一次消耗多发子弹的情况。
--
function SWEP:GetDisplayAmmo(clip, backammo, maxclip)
	if self.RequiredClip ~= 1 then
		clip = math.floor(clip / self.RequiredClip)
		backammo = math.floor(backammo / self.RequiredClip)
		maxclip = math.ceil(maxclip / self.RequiredClip)
	end

	if self.AmmoUse then
		clip = math.floor(clip / self.AmmoUse)
		backammo = math.floor(backammo / self.AmmoUse)
		maxclip = math.ceil(maxclip / self.AmmoUse)
	end

	return clip, backammo, maxclip
end

---
-- @function SWEP:Draw3DHUD
-- @description 绘制附着在武器模型上的 3D HUD。
--
function SWEP:Draw3DHUD(vm, pos, ang)
	local wid, hei = 200, 240
	local x, y = wid * -0.6, hei * -0.5

	-- 获取弹药信息
	local clip = self:Clip1()
	local owner = self:GetOwner()
	local ammocount = owner:GetAmmoCount(self:GetPrimaryAmmoType())
	local maxclip = self.Primary.ClipSize
	local dclip, dbackammo, dmaxclip = self:GetDisplayAmmo(clip, ammocount, maxclip)
	--local auto = self.Primart.Automatic
	-- 开始 3D 空间中的 2D 绘制
	cam.Start3D2D(pos, ang, self.HUD3DScale / 2)
		-- 绘制背景
		draw.RoundedBoxEx(32, x, y, wid, hei, colBG, true, false, true, false)

		-- 绘制备弹量
		local displayspare = dmaxclip > 0 and self.Primary.DefaultClip ~= 99999
		if displayspare then
			-- 根据备弹量多少选择不同颜色
			local ammoColor = dbackammo == 0 and colRed or dbackammo <= dmaxclip and colYellow or colWhite
			draw.SimpleTextBlurry(dbackammo, dbackammo >= 1000 and "ZS3D2DFontSmall" or "ZS3D2DFont", x + wid * 0.5, y + hei * 0.65, ammoColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- 绘制当前弹匣弹量
		GetAmmoColor(dclip, dmaxclip) -- 获取动态颜色
		draw.SimpleTextBlurry(dclip, dclip >= 100 and "ZS3D2DFont" or "ZS3D2DFontBig", x + wid * 0.5, y + hei * (displayspare and 0.3 or 0.5), colAmmo, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if self.Primary.Automatic then
			draw.SimpleText("Auto","ZS3D2DFontSmall",x + wid * 0.5, y + hei * 0.88,color_white_alpha230,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		end
	cam.End3D2D()
end


---
-- @function SWEP:Draw2DHUD
-- @description 绘制屏幕右下角的 2D 武器信息 HUD。
-- 布局（参考目标截图，从左到右）：弹药图标 -> 大字体弹匣数字 -> 武器图标，
-- 小字体备弹数字垫在弹匣数字下方并与之重叠，主弹药（弹匣）浮在备弹上面。
-- 字体 ZSWeaponHUDClip / ZSWeaponHUDReserve 在 cl_init.lua GM:CreateScalingFonts 中创建。
--

-- 武器HUD颜色
local colClipNormal = Color(235, 235, 235, 245) -- 弹匣数字（白）
local colClipEmpty = Color(255, 70, 70, 255)    -- 弹匣打空时（红）
local colReserve = Color(125, 125, 125, 235)    -- 备弹数字（暗灰，垫底层）

local FONT_CLIP = "ZSWeaponHUDClip"       -- 大字体弹匣数字
local FONT_RESERVE = "ZSWeaponHUDReserve" -- 小字体备弹数字

-- 测量击杀图标的绘制尺寸：字体字形取原始尺寸（位图字体无法缩放），材质按比例缩入最大盒
local function MeasureKillicon(iconname, maxw, maxh)
	if not iconname then return 0, 0 end
	local data = killicon.Get(iconname)
	if not data then return 0, 0 end

	if killicon.GetFont(iconname) then
		surface.SetFont(data[1])
		return surface.GetTextSize(data[2])
	end

	local mat = Material(data[1])
	if not mat or mat:IsError() then return 0, 0 end

	local mw, mh = mat:Width(), mat:Height()
	if mw <= 0 or mh <= 0 then return maxw, maxh end
	local s = math.min(maxw / mw, maxh / mh)
	return mw * s, mh * s
end

-- 在指定位置（左上角）按测量好的尺寸绘制击杀图标
local function DrawKillicon(iconname, x, y, w, h)
	local data = killicon.Get(iconname)
	if not data then return end

	if killicon.GetFont(iconname) then
		surface.SetFont(data[1])
		surface.SetTextColor(data[3] or color_white)
		surface.SetTextPos(x, y)
		surface.DrawText(data[2])
		return
	end

	local mat = Material(data[1])
	if not mat or mat:IsError() then return end
	surface.SetMaterial(mat)
	surface.SetDrawColor(data[2] or color_white)
	surface.DrawTexturedRect(x, y, w, h)
end

function SWEP:Draw2DHUD()
	local owner = self:GetOwner()
	if not owner:IsValid() then return end

	local screenscale = BetterScreenScale()

	-- 获取弹药信息
	local clip = self:Clip1()
	local ammocount = owner:GetAmmoCount(self:GetPrimaryAmmoType())
	local maxclip = self:GetPrimaryClipSize()
	local dclip, dbackammo, dmaxclip = self:GetDisplayAmmo(clip, ammocount, maxclip)

	local hasclip = dmaxclip > 0
	-- 无限备弹（DefaultClip = 99999）的武器不显示备弹小字
	local displayspare = hasclip and not (self.Primary and self.Primary.DefaultClip == 99999)

	-- 大字体数字：有弹匣显示弹匣余量，否则显示备弹总量
	local bignum = hasclip and dclip or dbackammo

	-- 测量大字体弹匣数字
	surface.SetFont(FONT_CLIP)
	local bigw, bigh = surface.GetTextSize(tostring(bignum))

	-- 测量小字体备弹数字
	local sparew, spareh = 0, 0
	if displayspare then
		surface.SetFont(FONT_RESERVE)
		sparew, spareh = surface.GetTextSize(tostring(dbackammo))
	end

	-- 弹药图标：与 pworth 购物车相同的取法——用 SWEP 声明的 Primary.Ammo 小写后查 GM.AmmoIcons
	-- （不要用 game.GetAmmoName：客户端对自定义弹药不可靠，且武器声明的大小写不一，必须 lower）
	local ammoiconname
	local declaredammo = self.Primary and self.Primary.Ammo
	if declaredammo and declaredammo ~= "none" then
		ammoiconname = GAMEMODE.AmmoIcons[string.lower(declaredammo)] or nil
	end
	if ammoiconname and not killicon.Get(ammoiconname) then ammoiconname = nil end

	local ammoiconsize = 46 * screenscale
	local ammow, ammoh = MeasureKillicon(ammoiconname, ammoiconsize, ammoiconsize)

	-- 武器图标：当前武器的击杀图标
	local wepiconname = killicon.Get(self:GetClass()) and self:GetClass() or nil
	local wepw, weph = MeasureKillicon(wepiconname, 132 * screenscale, 60 * screenscale)

	-- 布局：整体锚定屏幕右下角，从右向左排布：武器图标 -> 弹匣数字 -> 弹药图标
	local gap = 10 * screenscale
	local rightmargin = 24 * screenscale
	local bottommargin = 44 * screenscale

	-- 备弹底边作为整组基线；主数字底边只上移少量（字体行高包含 ascent/descent 空隙），
	-- 保证主数字的墨迹压住备弹墨迹的上半部，形成截图中那样的重叠效果
	local overlap = displayspare and spareh * 0.15 or 0
	local baseline = ScrH() - bottommargin
	local bigbottom = baseline - overlap
	local bigcentery = bigbottom - bigh / 2

	local x = ScrW() - rightmargin
	local wepx, wepy = x - wepw, bigcentery - weph / 2
	local bigcenterx = wepx - gap - bigw / 2
	local bigleft = bigcenterx - bigw / 2
	local ammox, ammoy = bigleft - gap - ammow, bigcentery - ammoh / 2

	-- 1) 小字体备弹数字（先画，垫在底层），中心相对弹匣数字略微左偏
	if displayspare then
		draw.SimpleText(tostring(dbackammo), FONT_RESERVE, bigcenterx - bigw * 0.15, baseline, colReserve, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	end

	-- 2) 弹药图标
	if ammoiconname and ammow > 0 then
		DrawKillicon(ammoiconname, ammox, ammoy, ammow, ammoh)
	end

	-- 3) 大字体弹匣数字（后画，浮在备弹上面），打空时变红
	local colClip = hasclip and dclip == 0 and colClipEmpty or colClipNormal
	draw.SimpleText(tostring(bignum), FONT_CLIP, bigcenterx, bigbottom, colClip, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

	-- 4) 武器图标
	if wepiconname and wepw > 0 then
		DrawKillicon(wepiconname, wepx, wepy, wepw, weph)
	end
end

function SWEP:CooldownRingBinding()
    local finish = self:GetDTFloat(DT_WEAPON_BASE_FLOAT_RELOADEND)
    local now = CurTime()
    return math.max(0, finish - now)
end

function SWEP:CooldownRingMaximumBinding()
    local startTime = self:GetDTFloat(DT_WEAPON_BASE_FLOAT_RELOADSTART)
    local finishTime = self:GetDTFloat(DT_WEAPON_BASE_FLOAT_RELOADEND)
    return math.max(0, finishTime - startTime)
end

function SWEP:DrawCooldowns()
	if self:GetPrimaryAmmoCount() <= 0 then return end
	local cooldownIcon = self:GetCooldownIcon()
    local coneGap = self:GetCone() / 2
    local betterscale = BetterScreenScale()
    local remaining = self:CooldownRingBinding()
    local maximum = self:CooldownRingMaximumBinding()
    local ringSize = math.Clamp(CrosshairCoolPrimaryCircleSize, 0.5, 16) + coneGap
    local ringSpacing = math.Clamp(CrosshairCoolPrimaryCircleSize, 0, 16) + coneGap + self.CooldownExtraSize
    local ringColor = Color(255, 40, 40)
    local backgroundColor = Color(12, 12, 12, 30)

    if remaining > 0 and maximum > 0 and remaining ~= math.huge and maximum ~= math.huge then
        local centerX, centerY = ScrW() * 0.5, ScrH() * 0.5

        if CurTime() >= self:GetReloadStart() and CurTime() <= self:GetReloadFinish() then
            local innerRadius = (ringSpacing) * 10 * betterscale
            draw.HollowCircle(centerX, centerY, innerRadius, 2 * ringSize, 270, 270 + 360 * remaining / maximum, ringColor)
            draw.HollowCircle(centerX, centerY, innerRadius, 2 * ringSize, 270, 270 + 360, backgroundColor)
            draw.SimpleTextBlurry(math.Round(remaining, 1), "RemingtonNoiseless", centerX - innerRadius * 2, centerY,ringColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local iw, ih = cooldownIcon:Width(), cooldownIcon:Height()
            if iw == 0 or ih == 0 then iw, ih = 64, 64 end
            local pad = math.max(2, ringSize * 0.8)
            local iconMax = (innerRadius - pad) * 2
            local s = math.min(iconMax / iw, iconMax / ih)
            local w, h = math.floor(iw * s), math.floor(ih * s)
            local rotation = CurTime() * 90

            surface.SetMaterial(cooldownIcon)
            surface.SetDrawColor(ringColor)
            surface.DrawTexturedRectRotated(centerX, centerY, w, h, rotation)
        end
    end
end

---
-- @function SWEP:DrawHUD
-- @description 主 HUD 绘制函数，决定绘制哪些 HUD 元素。
--

function SWEP:DrawHUD()
	-- 根据游戏模式设置决定是否绘制 2D HUD
	if GAMEMODE:ShouldDraw2DWeaponHUD() then
		self:DrawCooldowns()
		self:Draw2DHUD()
	end
	if self:GetReloadFinish() > 0 then return end
	self:DrawWeaponCrosshair() -- 绘制准星（如果启用）


end

function SWEP:DrawWeaponSelection(x, y, w, h, alpha)
	self:BaseDrawWeaponSelection(x, y, w, h, alpha)
end
