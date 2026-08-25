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

	-- [过渡进度] 进入用 OutBack/InOutSine 混合，退出用 InOutQuad/InQuad 混合
	local delta = self.GetIronsightDelta and self:GetIronsightDelta() or 0
	local eased = 0
	if delta > 0 then
		if self:GetIronsights() then
			eased = Lerp(0.25, math.ease.OutBack(delta), math.ease.InOutSine(delta))
		else
			eased = Lerp(0.7, math.ease.InOutQuad(delta), math.ease.InQuad(delta))
		end
	end
	eased = math.Clamp(eased, 0, 1)

	-- [开镜视模型 FOV · 平滑过渡] IronSights.ViewModelFOV 声明时生效：按开镜
	-- 缓动进度在武器基础 FOV 与声明目标间插值，写回引擎原生每帧读取的
	-- SWEP.ViewModelFOV（自绘投影管线已移除，动态写回是该字段唯一可行接法）。
	-- 基础值只缓存一次，防止把上帧插值结果当基准造成逐帧漂移；
	-- 未声明该字段的武器完全不受影响
	local iron_fov = istable(self.IronSights) and tonumber(self.IronSights.ViewModelFOV) or nil
	if iron_fov and iron_fov > 0 then
		if not self.m_nBaseVMFOV then
			self.m_nBaseVMFOV = self.ViewModelFOV or 60
		end
		self.ViewModelFOV = Lerp(eased, self.m_nBaseVMFOV, iron_fov)
	elseif self.m_nBaseVMFOV then
		-- 运行时声明被移除（热重载/调参）时兜底还原基础值
		self.ViewModelFOV = self.m_nBaseVMFOV
		self.m_nBaseVMFOV = nil
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
			vm:SetPoseParameter(self.m_SightsPPIdx, Lerp(eased, self.m_SightsPPRangeMin or 0, self.m_SightsPPRangeMax or 1))
			-- [ARC9 双层制] 不清零偏移：工厂对齐（姿态参数）之上叠加表/旧字段微调
		end
	end

	local target_pos = iron_pos * eased
	local target_ang = iron_ang * eased

	local ft = RealFrameTime()
	self.CurrentIronPos = LerpVector(ft * (self.IronSpeed or 10), self.CurrentIronPos, target_pos)
	self.CurrentIronAng = LerpAngle(ft * (self.IronSpeed or 10), self.CurrentIronAng, target_ang)

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