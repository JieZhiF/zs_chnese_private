-- cl_viewmodel.lua

-- [弹簧字段类型守卫] 防御运行时外部污染（实测出现过字段被写成非数学类型导致
-- :Length 报错刷屏）：类型不符时自动重置并一次性打印污染详情供溯源
local isvector, isangle = isvector, isangle

-- [Angle 无 Length 方法] GMod 角度元表不含 Length/LengthSqr（ARC9 原版以
-- angleLengthSqr 自行计算且弹簧状态存 Vector）；主层旋转状态在本文件中
-- 为 Angle，长度一律走此函数，禁止改回 :Length()
local function AngLen(a)
	return math.sqrt(a.p * a.p + a.y * a.y + a.r * a.r)
end

local function GuardField(wep, key, isok, maker)
	local v = wep[key]
	if v == nil or isok(v) then return v or maker() end

	if not wep.m_RecoilFieldWarned then
		wep.m_RecoilFieldWarned = true
		local keys = {}
		if istable(v) then
			for k in pairs(v) do
				keys[#keys + 1] = tostring(k)
				if #keys >= 6 then break end
			end
		end
		ErrorNoHalt(string.format(
			"[ZS Recoil] %s 的 %s 字段被外部污染(type=%s, keys=[%s])，已自动重置——请将本行反馈给开发者定位污染源\n",
			wep:GetClass(), key, type(v), table.concat(keys, " ")))
	end
	return maker()
end

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

-- ==== [ARC9 移植 · vmposition "funny" 弧线插值] ====
-- 入瞄路径不是直线匀速：位移三轴各用不同缓动错峰到位，叠加 sin(π·进度)
-- 中段鼓包沿预设弧线矢量绕行；角度轴有独立滚转弧线。ARC9 开镜"丝滑绕行"
-- 手感的来源，常数与曲线族逐字对应其 cl_vmposition.lua。
local ease_local = math.ease
local math_sin_l = math.sin
local PI_L = 3.1415926

local FUNNY_VEC_IN = Vector(-1.9, 2, 1.95)   -- 入镜中段弧线终点（t=a² 渐达）
local FUNNY_VEC_OUT = Vector(1, 1, -0.8)     -- 出镜中段弧线（恒定形状）

local function ArcLerpVector(a, v1, v2, mode)
	local dx, dy, dz = v2.x - v1.x, v2.y - v1.y, v2.z - v1.z

	local a1, a2, a3, mid, mid2
	if mode then
		a1 = ease_local.OutExpo(a)
		a2 = ease_local.InOutBack(a)
		a3 = ease_local.OutQuad(a)
		mid = math_sin_l(PI_L * ease_local.OutSine(a))
		mid2 = math_sin_l(PI_L * ease_local.OutCubic(a * a))
	else
		a1 = ease_local.InQuad(a)
		a2 = ease_local.InSine(a)
		a3 = ease_local.InSine(a)
		mid = math_sin_l(PI_L * ease_local.InOutQuad(a))
		mid2 = math_sin_l(PI_L * ease_local.InSine(a))
	end

	local yayx, yayy, yayz
	if mode then
		local t = a * a
		yayx = Lerp(t, FUNNY_VEC_OUT.x, FUNNY_VEC_IN.x)
		yayy = Lerp(t, FUNNY_VEC_OUT.y, FUNNY_VEC_IN.y)
		yayz = Lerp(t, FUNNY_VEC_OUT.z, FUNNY_VEC_IN.z)
	else
		yayx, yayy, yayz = FUNNY_VEC_OUT.x, FUNNY_VEC_OUT.y, FUNNY_VEC_OUT.z
	end

	return Vector(
		v1.x + yayx * mid + a1 * dx,
		v1.y + yayy * mid + a2 * dy,
		v1.z + yayz * mid2 + a3 * dz)
end

-- 入镜弧线角（ARC9 funnyangleIn×0.85）/ 出镜弧线角（funnyangleOut×0.85）
local ARC_ANG_ENTER_P, ARC_ANG_ENTER_Y, ARC_ANG_ENTER_R = -2.55, -1.7, 6.8
local ARC_ANG_EXIT_P, ARC_ANG_EXIT_Y, ARC_ANG_EXIT_R = 1.4875, -1.7, -5.95

local function ArcLerpAngle(a, target, mode)
	local arc
	if mode then
		arc = math_sin_l(PI_L * ease_local.OutSine(a))
	else
		arc = math_sin_l(PI_L * ease_local.InOutQuad(a))
	end

	-- 起点恒为 angle_zero：分量即角差（ARC9 AngleDifference(x,0) 同义）
	return Angle(
		a * target.p + (mode and ARC_ANG_ENTER_P or ARC_ANG_EXIT_P) * arc,
		a * target.y + (mode and ARC_ANG_ENTER_Y or ARC_ANG_EXIT_Y) * arc,
		a * target.r + (mode and ARC_ANG_ENTER_R or ARC_ANG_EXIT_R) * arc)
end
function SWEP:ThinkVisualRecoil()
    local ft = RealFrameTime()
    if ft == 0 or ft > 0.1 then return end

    -- [ARC9 移植 · ThinkVisualRecoil]
    -- 时间步限制在 5~20ms：大帧不按原步长积分，防止低帧率弹簧发散
    ft = math.Clamp(ft, 0.005, 0.02)

    -- MAGIC 限幅：帧率自适应收紧；>90ms 视为极端卡顿钳到 0.1
    local magic
    if ft > 0.09 then magic = 0.1 else magic = math.min(210, 210 / (ft / 0.015)) end

    -- 主层弹簧三参数（ARC9 VisualRecoilDampingConst/SpringMagnitude/SpringPunchDamping）
    local k = self.VisualRecoilDampingConst or 120
    local m = self.VisualRecoilSpringMagnitude or 1
    local d = self.VisualRecoilSpringPunchDamping or 6

    -- 主层状态（合并态：含微抖层贡献，与 ARC9 netvar 语义一致）
    local vpa = GuardField(self, "VisRecoilPos", isvector, Vector)
    local vpv = GuardField(self, "VisRecoilVel", isvector, Vector)
    local vpc = GuardField(self, "VisRecoilAcc", isvector, Vector)

    -- 主层平移：速度 Verlet（位置半步 + 拖曳/回复加速度 + 加速度平均推进速度）
    vpa = vpa + vpv * ft + vpc * ft * ft * 0.5
    local vpdrag = -(vpv * vpv:Length() * 0.5)
    local vplen = math.max(vpa:Length(), 0.0001)
    local vpreturn = (-vpa * vpa:Length() * k) + (-vpa / vplen * m) + (-vpv * d)
    local nvpc = vpdrag + vpreturn
    vpv = vpv + ((vpc + nvpc) * (ft * 0.5))
    for i = 1, 3 do
        vpa[i] = math.Clamp(vpa[i], -magic, magic)
        vpv[i] = math.Clamp(vpv[i], -magic, magic)
        nvpc[i] = math.Clamp(nvpc[i], -magic, magic)
    end

    -- 主层旋转：同一套 Verlet
    local vaa = GuardField(self, "VisRecoilAng", isangle, Angle)
    local vav = GuardField(self, "VisRecoilAngVel", isangle, Angle)
    local vac = GuardField(self, "VisRecoilAngAcc", isangle, Angle)

    vaa = vaa + vav * ft + vac * ft * ft * 0.5
    local vdrag = -(vav * AngLen(vav) * 0.5)
    local valen = math.max(AngLen(vaa), 0.0001)
    local vreturn = (-vaa * AngLen(vaa) * k) + (-vaa / valen * m) + (-vav * d)
    local nvac = vdrag + vreturn
    vav = vav + ((vac + nvac) * (ft * 0.5))
    for i = 1, 3 do
        vaa[i] = math.Clamp(vaa[i], -magic, magic)
        vav[i] = math.Clamp(vav[i], -magic, magic)
        nvac[i] = math.Clamp(nvac[i], -magic, magic)
    end

    -- 微抖层（ARC9 SubtleVisualRecoil）：独立高频小弹簧，开火后 0.75s 内活跃
    local vpa2 = GuardField(self, "SubVisRecoilPos", isvector, Vector)
    local vpv2 = GuardField(self, "SubVisRecoilVel", isvector, Vector)
    local vpc2 = GuardField(self, "SubVisRecoilAcc", isvector, Vector)
    local vaa2 = GuardField(self, "SubVisRecoilAng", isvector, Vector)
    local vav2 = GuardField(self, "SubVisRecoilAngVel", isvector, Vector)
    local vac2 = GuardField(self, "SubVisRecoilAngAcc", isvector, Vector)

    if self.SubtleVisualRecoil ~= false and (CurTime() - (self.last_shot_time or 0)) < 0.75 then
        local k2 = 150 * (self.SubtleVisualRecoilSpeed or 1)
        local m2 = 0.3
        local d2 = 2.8

        -- [延迟补偿] 高 ping 降低刚度阻尼比，避免预测回滚放大抖动（ARC9 原式）
        if not game.SinglePlayer() then
            local lp = LocalPlayer()
            if IsValid(lp) then
                local ping = lp:Ping()
                if game.IsDedicated() then ping = ping + 5 end
                if ping > 9 then
                    -- 保持不变（ARC9 原样）
                else
                    k2 = k2 * 15
                    d2 = d2 * 10
                end
            end
        end

        vpa2 = vpa2 + vpv2 * ft + vpc2 * ft * ft * 0.5
        local vpdrag2 = -(vpv2 * vpv2:Length() * 0.5)
        local vplen2 = math.max(vpa2:Length(), 0.0001)
        local vpreturn2 = (-vpa2 * vpa2:Length() * k2) + (-vpa2 / vplen2 * m2) + (-vpv2 * d2)
        vpc2 = vpdrag2 + vpreturn2
        vpv2 = vpv2 + vpc2 * (ft * 0.5)
        for i = 1, 3 do
            vpa2[i] = math.Clamp(vpa2[i], -magic, magic)
            vpv2[i] = math.Clamp(vpv2[i], -magic, magic)
            vpc2[i] = math.Clamp(vpc2[i], -magic, magic)
        end

        vaa2 = vaa2 + vav2 * ft + vac2 * ft * ft * 0.5
        local vdrag2 = -(vav2 * vav2:Length() * 0.5)
        local valen2 = math.max(vaa2:Length(), 0.0001)
        local vreturn2 = (-vaa2 * vaa2:Length() * k2) + (-vaa2 / valen2 * m2) + (-vav2 * d2)
        vac2 = vdrag2 + vreturn2
        vav2 = vav2 + vac2 * (ft * 0.5)

        vaa2.x = vaa2.x * 0.25 -- 俯仰微抖衰减（ARC9 原式）
        for i = 1, 3 do
            vaa2[i] = math.Clamp(vaa2[i], -magic, magic)
            vav2[i] = math.Clamp(vav2[i], -magic, magic)
            vac2[i] = math.Clamp(vac2[i], -magic, magic)
        end
    end

    -- 合并写入（渲染消费合并值；分层状态保留供下帧积分，ARC9 同构）
    self.VisRecoilPos = vpa + vpa2
    self.VisRecoilVel = vpv + vpv2
    self.VisRecoilAcc = nvpc + vpc2

    self.VisRecoilAng = Angle(vaa.p + vaa2.x, vaa.y + vaa2.y, vaa.r + vaa2.z)
    self.VisRecoilAngVel = Angle(vav.p + vav2.x, vav.y + vav2.y, vav.r + vav2.z)
    self.VisRecoilAngAcc = Angle(nvac.p + vac2.x, nvac.y + vac2.y, nvac.r + vac2.z)

    self.SubVisRecoilPos = vpa2
    self.SubVisRecoilVel = vpv2
    self.SubVisRecoilAcc = vpc2
    self.SubVisRecoilAng = vaa2
    self.SubVisRecoilAngVel = vav2
    self.SubVisRecoilAngAcc = vac2
end

-- ==== DoSubtleVisualRecoil - 微抖层注入（ARC9 DoSubtleVisualRecoil 移植） ====
-- 主层管"枪身上跳"，本层管高频细碎抖动：方向表取样（均匀随机常出近零值）+
-- 连射越久方向越稳定（funnynumber 随 RecoilAmount 衰减）+ ping 幅度补偿。
function SWEP:DoSubtleVisualRecoil()
    if SERVER or not CLIENT then return end
    -- [开关契约] false 必须同时切断注入与积分（ThinkVisualRecoil 侧）：
    -- 只关积分的话注入量会逐发累积成永久偏移
    if self.SubtleVisualRecoil == false then return end

    local mult = (self.SubtleVisualRecoil or 1) * 0.75
    if not self:GetIronsights() then mult = mult * (self.SubtleVisualRecoilHipFire or 2) end

    local funnynumber = 1.3 - math.min(self.RecoilAmount or 0, 4.5) / 4.5

    if not game.SinglePlayer() then
        local lp = LocalPlayer()
        if IsValid(lp) then
            local ping = lp:Ping()
            if game.IsDedicated() then ping = ping + 5 end
            if ping > 9 then
                mult = mult * math.Clamp(0.5 - ping * 0.004, 0.25, 0.5)
            end
        end
    end

    self.SubVisRecoilPos = (self.SubVisRecoilPos or Vector(0, 0, 0)) + Vector(math.Rand(-0.05, 0.03), -1.0, math.Rand(-0.06, 0.03)) * mult

    local upp = ({0.1, 0.125, 0.15, 0.175, 0.2})[math.random(5)]
    local dirs = ({-1.35, -1.25, -1.125, -1, -0.75, -0.75, 0.75, 0.75, 1, 1.125, 1.25, 1.35})[math.random(12)]

    self.SubVisRecoilAng = (self.SubVisRecoilAng or Vector(0, 0, 0))
        + Vector(upp, 0, (self.SubtleVisualRecoilDirection or 0) * funnynumber + dirs) * mult
end

local ghostlerp = 0

function SWEP:CalcViewModelView(vm, oldpos, oldang, pos, ang)
    local owner = self:GetOwner()
    if not IsValid(owner) then return pos, ang end

    -- [物理计算] 确保物理逻辑在渲染前更新
    if self.ThinkVisualRecoil then self:ThinkVisualRecoil() end

    -- 1. 基础 VM 修正 (Offset)
    if self.VMAng and self.VMPos then
        ang:RotateAroundAxis(ang:Right(), self.VMAng.p)
        ang:RotateAroundAxis(ang:Up(), self.VMAng.y)
        ang:RotateAroundAxis(ang:Forward(), self.VMAng.r)
        pos = pos + (ang:Right() * self.VMPos.x) + (ang:Forward() * self.VMPos.y) + (ang:Up() * self.VMPos.z)
    end

	-- 2. 机械瞄准过渡 (Iron Sights) —— ARC9 风格：双端共享的平滑进度 + 缓动曲线
	self.CurrentIronPos = self.CurrentIronPos or Vector(0, 0, 0)
	self.CurrentIronAng = self.CurrentIronAng or Angle(0, 0, 0)

	-- [过渡进度 · 双轨] ARC9 vmposition 同构：
	--   sd_raw —— 原始线性进度：位移弧线插值与 sights 姿态参数消费（工厂动画期望线性驱动）
	--   sd_ease —— 双缓动混合（保留过冲）：开镜 OutBack/InOutSine、收镜 InOutQuad/InQuad，
	--             角度弧线插值消费；过冲被 ARC9 式弧线吸收，不外泄到 FOV
	--   eased  —— 钳制版标量：晃动/呼吸/步伐衰减等层消费
	local delta = self.GetIronsightDelta and self:GetIronsightDelta() or 0
	local entering = (delta > 0 and self:GetIronsights()) and true or false
	local sd_raw = delta
	local sd_ease = 0
	if delta > 0 then
		if entering then
			sd_ease = Lerp(0.25, math.ease.OutBack(delta), math.ease.InOutSine(delta))
		else
			sd_ease = Lerp(0.7, math.ease.InOutQuad(delta), math.ease.InQuad(delta))
		end
	end
	local eased = math.Clamp(sd_ease, 0, 1)

	-- [开镜视模型 FOV · ARC9 GetViewModelFOV 移植] IronSights.ViewModelFOV 声明时生效，
	-- 写回引擎原生每帧读取的 SWEP.ViewModelFOV（自绘投影管线已移除，动态写回是该
	-- 字段唯一可行接法）。与 ARC9 一致的三层结构：
	--   1) 专用指数逼近状态 m_nSmoothVMFOV（步长 max(diff/ADS时长, diff, 1)*ft*2）：
	--      大差距快追、小差距缓收，不再借用姿势层带 OutBack 过冲的 eased
	--      （旧版过冲会泄漏进 FOV，表现为开镜瞬间冲过头再弹回）；
	--   2) 独立缓动轴：开镜 Lerp(0.21, OutBack, InOutSine) / 收镜 Lerp(0.65, InOutSine, InOutBack)，
	--      与 ARC9 逐字对应，微过冲只落在 FOV 自身弹性里；
	--   3) 基础值只缓存一次，防止把上帧插值结果当基准造成逐帧漂移。
	-- 未声明 ViewModelFOV 字段的武器完全不受影响
	local iron_fov = istable(self.IronSights) and tonumber(self.IronSights.ViewModelFOV) or nil
	if iron_fov and iron_fov > 0 then
		if not self.m_nBaseVMFOV then
			self.m_nBaseVMFOV = self.ViewModelFOV or 60
		end

		local vm_target = iron_fov
		self.m_nSmoothVMFOV = self.m_nSmoothVMFOV or self.m_nBaseVMFOV
		local vdiff = math.abs(vm_target - self.m_nSmoothVMFOV)
		if vdiff > 0 then
			self.m_nSmoothVMFOV = math.Approach(self.m_nSmoothVMFOV, vm_target,
				math.max(vdiff / (self.AimDownSightsTime or 0.25), vdiff, 1) * RealFrameTime() * 2)
		end

		local fdelta = delta
		if self:GetIronsights() then
			fdelta = Lerp(0.21, math.ease.OutBack(fdelta), math.ease.InOutSine(fdelta))
		else
			fdelta = Lerp(0.65, math.ease.InOutSine(fdelta), math.ease.InOutBack(fdelta))
		end

		self.ViewModelFOV = Lerp(fdelta, self.m_nBaseVMFOV, self.m_nSmoothVMFOV)
	elseif self.m_nBaseVMFOV then
		-- 运行时声明被移除（热重载/调参）时兜底还原基础值
		self.ViewModelFOV = self.m_nBaseVMFOV
		self.m_nBaseVMFOV = nil
		self.m_nSmoothVMFOV = nil
	end

	local iron_pos, iron_ang = self:GetIronSightOffset()
	if not isvector(iron_pos) then iron_pos = vector_origin end
	if not (isvector(iron_ang) or isangle(iron_ang)) then iron_ang = angle_zero end

	-- 类型修正
	if isvector(iron_ang) then iron_ang = Angle(iron_ang.x, iron_ang.y, iron_ang.z) end
	if isangle(iron_pos) then iron_pos = Vector(iron_pos.p, iron_pos.y, iron_pos.r) end

	-- [姿势参数 · ARC9 双层制] 模型自带 sights 姿态参数时始终驱动（工厂对齐层），
	-- IronSights 表的 Pos/Ang 作为该层之上的微调偏移叠加（ARC9 同款语义——
	-- 其 PreDrawViewModel 同样驱动 sights poseparam 后再叠 sight.Pos/Ang）。
	-- DisableSightsPoseParam=true 可禁用工厂层，此时表值/旧字段为纯手动偏移
	if self.DisableSightsPoseParam ~= true then
		local mdl = vm:GetModel()
		if self.m_SightsPPModel ~= mdl then
			self.m_SightsPPModel = mdl
			self.m_SightsPPIdx = vm:LookupPoseParameter("sights") or -1
			if self.m_SightsPPIdx >= 0 then
				self.m_SightsPPRangeMin, self.m_SightsPPRangeMax = vm:GetPoseParameterRange(self.m_SightsPPIdx)
			end
		end
		if self.m_SightsPPIdx and self.m_SightsPPIdx >= 0 then
			-- [ARC9 同款] 姿态参数吃原始线性进度（ThinkSights SetPoseParameter 同源），
			-- 缓动/过冲值会让工厂对齐动画在中段 wiggle
			vm:SetPoseParameter(self.m_SightsPPIdx, Lerp(sd_raw, self.m_SightsPPRangeMin or 0, self.m_SightsPPRangeMax or 1))
			-- [ARC9 双层制] 不清零偏移：工厂对齐（姿态参数）之上叠加表/旧字段微调
		end
	end

	-- [入瞄姿态 · ARC9 "funny" 弧线插值 + 零二次滤波]
	-- 位移按原始进度走三轴异构缓动弧线，角度按缓动进度叠加滚转中段弧线；
	-- ARC9 直接应用确定性目标值。旧版在此之上还叠 RealFrameTime 指数追赶
	-- （IronSpeed）：帧率相关、恒定引入 ~0.1s 滞后层，枪模永远晚于 FOV 到位
	-- （观感发肉）——已移除。零偏移武器回退纯 eased 缩放保持旧行为
	if iron_pos:LengthSqr() > 0 or AngLen(iron_ang) > 0.0001 then
		self.CurrentIronPos = ArcLerpVector(sd_raw, vector_origin, iron_pos, entering)
		self.CurrentIronAng = ArcLerpAngle(sd_ease, iron_ang, entering)
	else
		self.CurrentIronPos = iron_pos * eased
		self.CurrentIronAng = iron_ang * eased
	end

	local ft = RealFrameTime() -- 帧步进供后续幽灵探身层使用

    -- 3. 动态晃动 (Sway & Bob)
    -- [ARC9 移植·DarsuBob] 六轴步行循环（跳跃惯性/横移倾斜/下蹲节奏），唯一摆动来源：
    -- 直接改写 pos/ang 并清零引擎 BobScale/SwayScale（见 cl_sway.lua）
    pos, ang = self:ApplyARC9Bob(pos, ang, eased)

    -- 4. 呼吸效果
    self.Breath = math.sin(CurTime()) / ((self.Breathmult or 1) * Lerp(eased, 4, 80))

    -- 5. 应用基础变换
    ang = Angle(ang.p, ang.y, ang.r) -- 复制以防修改原引用
    
    -- 应用机瞄旋转
    ang:RotateAroundAxis(ang:Right(), self.CurrentIronAng.p)
    ang:RotateAroundAxis(ang:Up(),    self.CurrentIronAng.y)
    ang:RotateAroundAxis(ang:Forward(), self.CurrentIronAng.r)
    
    -- 应用机瞄位移
    pos = pos + (self.CurrentIronPos.x * ang:Right()) + (self.CurrentIronPos.y * ang:Forward()) + (self.CurrentIronPos.z * ang:Up())

    -- ===========================================================
    -- 6. [核心] 应用视觉后坐力 (Visual Recoil)
    --    幅度即作者所写：开镜/腰射两套参数组在 sh_recoil 注入时已交叉插值，此处不再二次缩放
    -- ===========================================================
    if self.UseVisualRecoil and self.VisRecoilPos and self.VisRecoilAng then
        local center = self.VisualRecoilCenter or Vector(0, 0, 0)
        local vrPos = self.VisRecoilPos
        -- [ARC9 VisualRecoilEmergency] 总幅度倍率；默认 1（注入值已按 ZS 量纲调校）
        local emg = self.VisualRecoilEmergency or 1
        local vrAng = Angle(self.VisRecoilAng.p * emg, self.VisRecoilAng.y * emg, self.VisRecoilAng.r * emg)

        -- 使用矩阵绕点旋转应用后坐力
        pos, ang = RotateAroundPoint(pos, ang, center, vrPos, vrAng)
    end
    -- ===========================================================

    -- 7. 叠加呼吸/Offset（摇摆已在第 3 / 7.3 步由 ARC9 系统处理）
    pos = pos + (ang:Up() * self.Breath)
    pos = pos + (ang:Forward() * (self.offset or 0))

    -- 7.3 [ARC9 移植·鼠标摇摆] 视角转动时枪身惯性滞后（MouseSway=false 关闭；
    --      MouseSwayInertia=false 切经典位移变体，总强度乘 MouseSwayMult）
    if self.MouseSway ~= false then
        pos, ang = self:ApplyMouseSway(pos, ang, eased)
    end

    -- 7.5 [视模型手部 IK] RHIK 整枪平移补偿（opt-in，未声明 SWEP.ViewIK 时零开销；
    --      置于全部常规变换之后，保证补偿是纯粹的枪身平移不与其他层互相污染）
    if self.IsViewIKEnabled and self:IsViewIKEnabled() then
        local ikoff = self:CalcViewIKOffset(vm, ang)
        if ikoff then pos = pos + ikoff end
    end

    -- 8. 幽灵模式 (靠近墙壁)
    if owner:GetBarricadeGhosting() then 
        ghostlerp = math.min(1, ghostlerp + ft * 4)
    else 
        ghostlerp = math.max(0, ghostlerp - ft * 5) 
    end
    
    if ghostlerp > 0 then
        pos = pos + 3.5 * ghostlerp * ang:Up()
        ang:RotateAroundAxis(ang:Right(), -30 * ghostlerp)
    end

    -- [视模型渲染] 引擎原生路径（自定义投影管线已按需求移除；
    -- 开镜视模型 FOV 走 SWEP.ViewModelFOV 动态写回，见上方第 2 步）

    -- 9. [开镜枪模处理] 经典模式复刻旧版"完全开镜隐藏枪模"行为（远移出视野）；
    --    PIP 生效时保持 ARC9 式贴瞄姿态，镜内画面走镜片子材质，无需藏枪
    if self.Scoped and self.IsScoped and self:IsScoped() then
        local use_pip = self.WantsPIPScope and self:WantsPIPScope()
            and self.IsPIPActive and self:IsPIPActive()

        if not use_pip then
            pos = pos + ang:Up() * 256
        end
    end

    return pos, ang
end

function SWEP:ViewModelDrawn()
    if self.Anim_ViewModelDrawn then
        self:Anim_ViewModelDrawn()
    end
end