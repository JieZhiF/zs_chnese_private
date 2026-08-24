-- ============================================================================
-- cl_sway.lua - 鼠标摇摆（移植自 ARC9 arc9_base/cl_sway.lua）
-- 视角转动时枪身以平滑滞后跟随，产生武器惯性质感。两种变体：
--   经典（默认）：平滑视角增量 → 位移偏移 + 绕视轴原点整体旋转
--                （对应 ARC9 GetViewModelSway，剔除其冲刺/自定义菜单耦合段）
--   惯性（MouseSwayInertia=true）：逐帧视角差 → ApproachAngle 惯性角，
--                仅做轴旋转无位移，回中更快（对应 ARC9 GetViewModelInertia）
-- 开镜时幅度按进度衰减；总强度乘 SWEP.MouseSwayMult；MouseSway=false 整体关闭。
-- 消费点：cl_viewmodel.lua CalcViewModelView 第 7.3 步
-- ============================================================================

-- 经典变体的文件级平滑状态（单本地玩家视角，全局共享安全）。
-- [帧守卫] CalcViewModelView 在 PIP/反射等多 pass 下一帧可多次调用，
-- 平滑状态若随调用次数推进会产生位姿分裂（表现为转视角残影）
local lasteyeang = Angle()
local smootheyeang = Angle()
local smoothswayroll = 0
local lastswayframe = 0

local function RotateAroundPoint(pos, ang, center, offset, rot)
	local mat = Matrix()
	mat:Translate(pos)
	mat:Rotate(ang)
	mat:Translate(center)
	mat:Rotate(rot)
	mat:Translate(offset)
	mat:Translate(-center)
	return mat:GetTranslation(), mat:GetAngles()
end

function SWEP:ApplyMouseSway(pos, ang, eased)
	local ft = RealFrameTime()
	if ft <= 0 or ft > 0.1 then return pos, ang end

	local mult = self.MouseSwayMult or 1

	-- [默认惯性] ARC9 现代版默认走惯性变体（增量÷4 钳幅、快速回中、无拖尾）；
	-- 经典变体滞后大，快速甩视角时枪身拖尾明显（MouseSwayInertia=false 显式启用）
	if self.MouseSwayInertia ~= false then
		--------------------------------------------------------------
		-- 惯性变体：视角差 → 惯性角逼近 → 轴旋转（ARC9 原式照搬）
		--------------------------------------------------------------
		local eyeangg = self:GetOwner():EyeAngles()
		local d = 1 - eased

		local diff = (eyeangg - (self.ViewModelLastEyeAng or eyeangg)) / 4
		diff.p = math.Clamp(diff.p, -1, 1)
		diff.y = math.Clamp(diff.y, -1, 1)

		-- 实例化副本后再改写，避免污染类级共享默认值
		local vsi = self.ViewModelSwayInertia
		if not isangle(vsi) then vsi = Angle() end
		vsi.p = math.ApproachAngle(vsi.p, diff.p, vsi.p / 10 * ft / 0.5)
		vsi.y = math.ApproachAngle(vsi.y, diff.y, vsi.y / 10 * ft / 0.5)
		self.ViewModelSwayInertia = vsi
		self.ViewModelLastEyeAng = eyeangg

		ang:RotateAroundAxis(ang:Up(), vsi.y * 12 * d * mult)
		ang:RotateAroundAxis(ang:Right(), -vsi.p * 12 * d * mult)
	else
		--------------------------------------------------------------
		-- 经典变体：平滑视角增量 → 位移 + 整体旋转（ARC9 原式照搬）
		-- sightmult 的 1/ft 项用于高帧率/低帧率下保持偏移量一致
		--------------------------------------------------------------
		local sightmult = (0.5 + math.Clamp(1 / ft / 100, 0, 5)) * Lerp(eased, 1, 0.25) * mult

		-- [帧守卫] 平滑状态每帧只推进一次（多 pass 渲染防位姿分裂）
		local frame = FrameNumber()
		if frame ~= lastswayframe then
			lastswayframe = frame
			smootheyeang = LerpAngle(math.Clamp(ft * 24, 0.075, 1), smootheyeang, EyeAngles() - lasteyeang)
			lasteyeang = EyeAngles()

			smoothswayroll = Lerp(math.Clamp(ft * 24, 0.075, 1), smoothswayroll, smootheyeang.y)

			smootheyeang.p = math.Clamp(smootheyeang.p * 0.95, -10, 10)
			smootheyeang.y = math.Clamp(smootheyeang.y * 0.9, -4, 4)
			smootheyeang.r = math.Clamp(smoothswayroll * (0.5 + math.Clamp(ft * 64, 0, 4)), -2, 2)
		end

		pos:Add(ang:Up() * smootheyeang.p * 0.075 * sightmult)
		pos:Add(ang:Right() * smootheyeang.y * -0.1 * sightmult)

		pos, ang = RotateAroundPoint(pos, ang, vector_origin, vector_origin, smootheyeang * sightmult)
	end

	return pos, ang
end

-- ============================================================================
-- 移动摇摆（移植自 ARC9 DarsuBob 步行循环）
-- 六轴正弦步行节奏（位置 x/y/z + 姿态 p/y/r）+ 跳跃/落地惯性 + 横移倾斜 +
-- 下蹲节奏变化；开镜时整体衰减。逐枪可通过 BobSettingsMove/Speed 六元表微调。
-- 替换旧版速度侧倾/前倾实现（UseARC9Bob=false 可回退）。
-- 消费点：cl_viewmodel.lua CalcViewModelView 第 3 步
-- ============================================================================

local notonground = 0
local smoothsidemove = 0
local smoothjumpmove = 0

-- 与 ARC9 相同的默认六元表：{x, y, z, pitch, yaw, roll}
local defbobsettings = {0.5, 0.25, 1, 0.75, 2, 0.875}
local defbobsettings2 = {1, 0.75, 1, 1, 1, 0.75}

function SWEP:ApplyARC9Bob(pos, ang, eased)
	local owner = self:GetOwner()
	local ft = RealFrameTime()

	local velocityangle = owner:GetVelocity()
	local sprinting = owner.IsSprinting and owner:IsSprinting() or false

	local sharedmult = sprinting and (self.BobSprintMult or 1) or (self.BobWalkMult or 1)
	local velocity = math.Clamp(velocityangle:Length(), 0, 350)

	self.ViewModelBobVelocity = math.Approach(self.ViewModelBobVelocity or 0, velocity, ft * 10000)
	local d = math.Clamp((self.ViewModelBobVelocity or 0) / 350, 0, 0.75)

	notonground = math.Approach(notonground, owner:OnGround() and 0 or 1, ft / 0.1)
	local steprate = Lerp(d, 1, 2.5)
	steprate = Lerp(notonground, steprate, 0.5)

	-- 跳跃上升/下坠的指数化惯性（"crazy math" 原式照搬）
	local jumpmove = math.Clamp(
		math.ease.InExpo(math.Clamp(velocityangle.z, -350, 0) / -350) * 25
		+ math.ease.InExpo(math.Clamp(velocityangle.z, 0, 350) / 350) * -60,
		-5, 3.5) * (1.5 - eased)
	smoothjumpmove = Lerp(math.Clamp(ft * 8, 0, 1), smoothjumpmove, jumpmove)

	if IsFirstTimePredicted() or game.SinglePlayer() then
		self.BobCT = (self.BobCT or 0) + (ft * steprate)
	end

	d = d * Lerp(eased, 1.4, 0.8) -- 开镜衰减摆幅
	local d2 = math.ease.InQuart(d)
	local d3 = math.ease.InQuad(d) * 0.6
	local speedmult = 1.4
	local speedmultang = 1.45

	local settings = self.BobSettingsMove or defbobsettings
	local settings2 = self.BobSettingsSpeed or defbobsettings2
	local xm, ym, zm, pm, yym, rm = settings[1], settings[2], settings[3], settings[4], settings[5], settings[6]
	local xms, yms, zms, pms, yyms, rms = settings2[1], settings2[2], settings2[3], settings2[4], settings2[5], settings2[6]

	-- 横移分量：速度在视线右方向上的投影归一化
	local sidemove = (velocityangle:Dot(owner:EyeAngles():Right()) / owner:GetMaxSpeed()) * 4 * (1.5 - eased)
	smoothsidemove = Lerp(math.Clamp(ft * 8, 0, 1), smoothsidemove, sidemove)

	local crouchmult = (owner:Crouching() and not sprinting) and 2.5 * (1.3 - eased) or 1
	local ct = self.BobCT or 0

	---- 位置三轴 ----
	pos:Sub(ang:Right() *    math.sin(speedmult * ct * 5 * xms) * d2 * 0.5  * Lerp(sprinting and 1 or 0, 1, 0.05) * xm * sharedmult)
	pos:Sub(ang:Up() *       math.cos(speedmult * ct * 7 * yms) * d  * 0.05 * (crouchmult * crouchmult * crouchmult) * Lerp(sprinting and 1 or 0, 1, 0.3) * ym * sharedmult)
	pos:Sub(ang:Forward() *  math.sin(speedmult * ct * 4 * zms) * d2 * 0.75 * crouchmult * zm * sharedmult)

	---- 姿态三轴 ----
	ang:RotateAroundAxis(ang:Right(),   math.sin(speedmultang * ct * 5.5 * pms + 0.3) * d3 * 2.25 * pm * sharedmult + smoothjumpmove)
	ang:RotateAroundAxis(ang:Up(),      math.cos(speedmultang * ct * 3.3 * yyms)      * d3 * 1   * Lerp(sprinting and 1 or 0, 1, 0.1) * yym * sharedmult)
	ang:RotateAroundAxis(ang:Forward(), math.sin(speedmultang * ct * 6 * rms)         * d3 * 4.5 * crouchmult * rm * sharedmult + smoothsidemove)

	return pos, ang
end
