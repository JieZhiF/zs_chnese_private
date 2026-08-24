-- ============================================================================
-- cl_sway.lua - 视模型摇摆（ARC9 移植 · 重构版）
-- 基准：arc9_weapon_base/lua/weapons/arc9_base/cl_sway.lua 现行版，数学公式
--       逐项照搬不做改动；ZS 侧反复改动堆积出的旧速度侧倾系统已整体删除
--       （见 cl_viewmodel.lua / shared.lua / sh_init.lua 的同步清理）。
--
-- [符号映射] ARC9 → 本文件
--   GetViewModelInertia              → ApplyMouseSway 惯性变体（默认）
--   GetViewModelSway                 → ApplyMouseSway 经典变体（MouseSwayInertia=false）
--   DarsuBob（bobstyle=3）           → ApplyARC9Bob
--
-- [刻意剔除的 ARC9 遗留]（多轮历史修改的产物，ZS 无对应机制，不再移植）
--   FesiugBob/ArcticBob/ArcticBreadBob/ArcticBreadDarsuBob（bobstyle 备选变体）
--   SprintVerticalOffset（作者自注"实现有误、仅为旧枪保留"的冲刺补偿段）
--   GetMidAirBob / GetViewModelLeftRight（ARC9 消费端已注释停用）
--   arc9_vm_bobstyle 控制台变量、Customize 菜单耦合、Peeking/Sliding 第三方钩子、
--   freeaim 模块的 InertiaDiff（仅服务弹道偏移与自定义菜单，polyarms 无武器启用；
--   移植保持纯视觉，不改弹道）
--
-- [每枪参数]（shared.lua 有默认值，逐枪覆盖；参考 PolyArms 武器包调法）
--   MouseSway          false 关闭鼠标摇摆
--   MouseSwayMult      鼠标摇摆总强度倍率
--   MouseSwayInertia   false 切经典位移变体（默认惯性：仅旋转、回中快、无拖尾）
--   BobWalkMult / BobSprintMult      走路 / 奔跑摆动倍率
--   BobSettingsMove    六元幅度表 {x, y, z, pitch, yaw, roll}
--   BobSettingsSpeed   六元节奏表（同序）
--   PolyArms 参考预设——步枪 {1.25,1,1.5,1.25,-3.5,0.95}；冲锋枪 {1.2,-0.8,1.3,0.6,1.5,1.2}；
--   手枪/喷子 {0.85,-0.45,0.5,0.9,-1.5,1.15}；Speed 表通用约 {0.9,1,0.92,1,1,0.75}
--
-- [帧守卫契约] CalcViewModelView 在 PIP 等多 pass 渲染下单帧可多次调用：
--   全部逐帧平滑状态经 FrameNumber 闸门每渲染帧只推进一次，变换每次调用照常叠加，
--   否则多 pass 下状态加速推进产生位姿分裂（表现为转视角残影）。
--   本系统是唯一摆动来源：入口处清零引擎 SwayScale/BobScale 防双重叠加
--   （GMod 对未声明的 SWEP 默认尺度也是 1，清零不可省略）。
--
-- 消费点：cl_viewmodel.lua CalcViewModelView 第 3 步（步摆）/ 第 7.3 步（鼠标摇摆）
-- ============================================================================

-- 鼠标摇摆的文件级平滑状态（单本地玩家视角，文件级共享安全）
local lasteyeang = Angle()
local smootheyeang = Angle()
local smoothswayroll = 0

-- 步摆的文件级平滑状态
local notonground = 0
local smoothsidemove = 0
local smoothjumpmove = 0

-- [帧守卫] 每子系统独立闸门：两函数同帧先后被调用，不能共用一个帧号
local swayframe = 0
local bobframe = 0

-- 绕指定点旋转位姿（ARC9 RotateAroundPoint2 的本地等价实现）
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

	-- [帧守卫] 平滑状态每渲染帧只推进一次
	local frame = FrameNumber()
	local newframe = frame ~= swayframe
	if newframe then swayframe = frame end

	if self.MouseSwayInertia ~= false then
		--------------------------------------------------------------
		-- 惯性变体（默认）：视角差 → 惯性角逼近 → 轴旋转（ARC9 原式）
		--------------------------------------------------------------
		local d = 1 - eased
		local eyeangg = self:GetOwner():EyeAngles()

		local vsi = self.ViewModelSwayInertia
		if not isangle(vsi) then
			vsi = Angle()
			self.ViewModelSwayInertia = vsi
		end

		if newframe then
			local diff = (eyeangg - (self.ViewModelLastEyeAng or eyeangg)) / 4
			diff.p = math.Clamp(diff.p, -1, 1)
			diff.y = math.Clamp(diff.y, -1, 1)

			vsi.p = math.ApproachAngle(vsi.p, diff.p, vsi.p / 10 * ft / 0.5)
			vsi.y = math.ApproachAngle(vsi.y, diff.y, vsi.y / 10 * ft / 0.5)
			self.ViewModelLastEyeAng = eyeangg
		end

		ang:RotateAroundAxis(ang:Up(), vsi.y * 12 * d * mult)
		ang:RotateAroundAxis(ang:Right(), -vsi.p * 12 * d * mult)
	else
		--------------------------------------------------------------
		-- 经典变体：平滑视角增量 → 位移 + 绕视轴原点整体旋转（ARC9 原式）
		-- sightmult 的 1/ft 项用于高帧率/低帧率下保持偏移量一致
		--------------------------------------------------------------
		if newframe then
			smootheyeang = LerpAngle(math.Clamp(ft * 24, 0.075, 1), smootheyeang, EyeAngles() - lasteyeang)
			lasteyeang = EyeAngles()

			smoothswayroll = Lerp(math.Clamp(ft * 24, 0.075, 1), smoothswayroll, smootheyeang.y)

			smootheyeang.p = math.Clamp(smootheyeang.p * 0.95, -10, 10)
			smootheyeang.y = math.Clamp(smootheyeang.y * 0.9, -4, 4)
			smootheyeang.r = math.Clamp(smoothswayroll * (0.5 + math.Clamp(ft * 64, 0, 4)), -2, 2)
		end

		local sightmult = (0.5 + math.Clamp(1 / ft / 100, 0, 5)) * Lerp(eased, 1, 0.25) * mult

		pos:Add(ang:Up() * smootheyeang.p * 0.075 * sightmult)
		pos:Add(ang:Right() * smootheyeang.y * -0.1 * sightmult)

		pos, ang = RotateAroundPoint(pos, ang, vector_origin, vector_origin, smootheyeang * sightmult)
	end

	return pos, ang
end

-- 与 ARC9 相同的默认六元表：{x, y, z, pitch, yaw, roll}
local defbobsettings = {0.5, 0.25, 1, 0.75, 2, 0.875}
local defbobsettings2 = {1, 0.75, 1, 1, 1, 0.75}

function SWEP:ApplyARC9Bob(pos, ang, eased)
	local owner = self:GetOwner()

	-- [引擎摆动清零] 本系统是唯一摆动来源：引擎自带 bob/sway（含未声明时的
	-- 默认尺度 1）必须屏蔽，否则双重叠加
	self.SwayScale = 0
	self.BobScale = 0

	local ft = RealFrameTime()
	if ft <= 0 or ft > 0.1 then return pos, ang end

	local velocityangle = owner:GetVelocity()
	local sprinting = owner.IsSprinting and owner:IsSprinting() or false

	local sharedmult = sprinting and (self.BobSprintMult or 1) or (self.BobWalkMult or 1)
	local velocity = math.Clamp(velocityangle:Length(), 0, 350)

	-- [帧守卫]
	local frame = FrameNumber()
	local newframe = frame ~= bobframe
	if newframe then bobframe = frame end

	if newframe then
		self.ViewModelBobVelocity = math.Approach(self.ViewModelBobVelocity or 0, velocity, ft * 10000)
	end
	local d = math.Clamp((self.ViewModelBobVelocity or 0) / 350, 0, 0.75)

	if newframe then
		notonground = math.Approach(notonground, owner:OnGround() and 0 or 1, ft / 0.1)

		-- 跳跃上升/下坠的指数化惯性（ARC9 "crazy math" 原式照搬）
		local jumpmove = math.Clamp(
			math.ease.InExpo(math.Clamp(velocityangle.z, -350, 0) / -350) * 25
			+ math.ease.InExpo(math.Clamp(velocityangle.z, 0, 350) / 350) * -60,
			-5, 3.5) * (1.5 - eased)
		smoothjumpmove = Lerp(math.Clamp(ft * 8, 0, 1), smoothjumpmove, jumpmove)

		-- 横移分量：速度在视线右方向上的投影归一化
		local sidemove = (velocityangle:Dot(owner:EyeAngles():Right()) / owner:GetMaxSpeed()) * 4 * (1.5 - eased)
		smoothsidemove = Lerp(math.Clamp(ft * 8, 0, 1), smoothsidemove, sidemove)
	end

	local steprate = Lerp(d, 1, 2.5)
	steprate = Lerp(notonground, steprate, 0.5)

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
