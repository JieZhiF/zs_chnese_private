-- sh_sights.lua
-- 机械瞄准（ADS）核心：ARC9 风格平滑过渡状态机 + 输入处理 + FOV/灵敏度

-- [切换模式] 双端一致的复制变量：1=右键按一下切换开关，0=长按瞄准
local CVAR_TOGGLE_ADS = CreateConVar("zs_toggleads", "0", bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), "切换式机械瞄准（1=按一下切换，0=长按）")

function SWEP:IsToggleADS()
	return CVAR_TOGGLE_ADS:GetBool()
end

--[[ 平滑过渡说明：
	过渡进度由 Think 每帧确定性推进（UpdateIronsightDelta，ARC9 ThinkSights 同构），
	GetIronsightDelta 为纯读取——全部消费方（主视角 FOV/枪模/PIP 镜片/灵敏度）
	同帧读到同一份进度；中途反打收/开镜从当前位置继续，不产生跳变。
	self.fIronTime 仅作为服务端回退时序保留（IsScoped 的非客户端分支）。 ]]

function SWEP:SecondaryAttack()
	-- 切换模式下由 Think 的按键沿检测接管，这里直接让行避免双重翻转
	if self:IsToggleADS() then return end
	-- 武器可显式禁用机瞄（如霰弹枪基座）
	if self.IronEnable == false then return end

	if self:GetNextSecondaryFire() <= CurTime() and not self:GetOwner():IsHolding() and self:GetReloadFinish() == 0 then
		self:SetIronsights(true)
	end
end

function SWEP:SetIronsights(b)
	b = b and true or false
	-- 状态未变化直接跳过：否则 Deploy 强制收镜等重复调用会重盖时间戳，制造一次假的退出过渡（表现为切枪瞬间放大）
	if self:GetDTBool(0) == b then return end

	self:SetDTBool(0, b)
	self.fIronTime = CurTime() -- 记录状态翻转时间戳，驱动 GetIronsightDelta 平滑过渡
	self.m_bLastIronNet = b -- 同步缓存，供 Think 检测网络侧翻转
	local hold = b and self.IronSightsHoldType or self.HoldType
	if hold then self:SetWeaponHoldType(hold) end

	if GAMEMODE then
		gamemode.Call("WeaponDeployed", self:GetOwner(), self)
	end
end

function SWEP:GetIronsights()
	return self:GetDTBool(0)
end

--[机瞄配置 · ARC9 形式] 支持 SWEP.IronSights 表：
--  SWEP.IronSights = { Pos = Vector(...), Ang = Angle(...),
--                      Magnification = 1.15, ViewModelFOV = 55 }
--表优先、旧字段（IronSightsPos/Ang/IronsightsMultiplier）逐项回退：
--Pos/Ang 经 GetIronSightOffset 统一出口；Magnification 在 GetAimFOVTarget 折算。
--ViewModelFOV 由 CalcViewModelView 按开镜进度平滑插值写回 SWEP.ViewModelFOV
--（引擎原生消费，见 cl_viewmodel 第 2 步）；未声明则视模型 FOV 全程不变。

function SWEP:GetIronSightOffset()
	local t = self.IronSights
	if istable(t) and t.Pos ~= nil then
		return t.Pos, t.Ang
	end
	return self.IronSightsPos, self.IronSightsAng
end

function SWEP:GetWalkSpeed()
	if self:GetIronsights() then
		return math.min(self.WalkSpeed, math.max(90, self.WalkSpeed * (self:GetOwner().Wooism and 0.75 or 0.5)))
	end
	return self.WalkSpeed
end

if CLIENT then
	-- [过渡进度推进 · ARC9 ThinkSights 同构] 按真实耗时向目标滑动（单次上限 0.1 秒
	-- 防卡顿瞬移），到位后清时间戳零开销待命。可从两个入口调用：
	--   1) Think 每帧确定性驱动（sh_think）
	--   2) GetIronsightDelta 的惰性兜底（覆写 Think 未调基类的武器，如 sawedoff）
	-- 两入口共享同一时间戳：同帧多次调用时时间片自动均分，总速率恒为真实耗时
	function SWEP:UpdateIronsightDelta()
		if GAMEMODE.NoIronsights then return end

		local target = self:GetIronsights() and 1 or 0
		local cur = self.m_nIronDelta or 0
		if cur == target then
			self.m_fIronLastSysT = nil
			return
		end

		local st = SysTime()
		local dt = math.min(st - (self.m_fIronLastSysT or st), 0.1)
		self.m_fIronLastSysT = st

		self.m_nIronDelta = math.Approach(cur, target, dt / math.max(self.AimDownSightsTime or 0.25, 0.01))
	end

	-- [过渡进度读取] 纯语义出口；内部先做惰性兜底推进，保证任何武器都可依赖
	function SWEP:GetIronsightDelta()
		if GAMEMODE.NoIronsights then return 0 end

		if self.UpdateIronsightDelta then self:UpdateIronsightDelta() end

		return self.m_nIronDelta or 0
	end

	local OverrideIronSights = {}
	function SWEP:CheckCustomIronSights()
		local class = self:GetClass()
		if OverrideIronSights[class] then
			if type(OverrideIronSights[class]) == "table" then
				self.IronSightsPos = OverrideIronSights[class].Pos
				self.IronSightsAng = OverrideIronSights[class].Ang
			end
			return
		end

		local filename = "ironsights/" .. class .. ".txt"
		if file.Exists(filename, "MOD") then
			local content = file.Read(filename, "MOD")
			local tab = string.Explode(" ", content)
			local pos = Vector(tonumber(tab[1]) or 0, tonumber(tab[2]) or 0, tonumber(tab[3]) or 0)
			local ang = Angle(tonumber(tab[4]) or 0, tonumber(tab[5]) or 0, tonumber(tab[6]) or 0)
			OverrideIronSights[class] = {Pos = pos, Ang = ang}
			self.IronSightsPos, self.IronSightsAng = pos, ang
		else
			OverrideIronSights[class] = true
		end
	end

	--[FOV 缩放目标 · ARC9 配置形式] 优先级：
	--  1) IronSights.Magnification（武器完整 ARC9 表）
	--  2) ADSMagnification 平铺字段（基座默认 1.15，除法语义 FOV÷mag，×0.95 与 ARC9 同因子）
	--  3) 经典狙回退（zs_pipscope=0）：IronsightsMultiplier（原版数值 0.25）优先，
	--     未声明时按 ScopeMagnification 推导——经典模式表现与原版 ZS 完全一致
	--  4) 旧字段兜底（未迁移第三方配置）
	--[框架陷阱修复] 旧版以 self.IsScoped（方法存在性）判断狙击武器，基座统一提供
	--IsScoped 后该判断对所有武器恒真，改用显式标志位 self.Scoped（见 sh_scope.lua）
	--[PIP 全程一致] 目标倍率必须整段过渡不变：UsesPIPScope 与进度无关，
	--若按进度中段切换目标会出现"先深缩放再弹回"的断裂感
	local function GetAimFOVTarget(self)
		if self.Scoped and not GAMEMODE.DisableScopes then
			if self.UsesPIPScope and self:UsesPIPScope() then
				-- PIP：放大交给镜内画面，主视角只做极轻微变焦（ARC9 RT 镜同款浅变焦）
				return self.PIPMainFOVMult or 0.88
			end

			-- 经典狙回退（zs_pipscope=0）：优先旧声明（原版数值 0.25），未声明时按
			-- 光学倍率推导——表现与原版 ZS 完全一致：深 FOV 缩放 + 全屏圆形遮罩
			local deep = tonumber(self.IronsightsMultiplier)
				or math.Clamp(1 / math.max(self.ScopeMagnification or 1, 1), 0.1, 0.6)
			local zoom_scoped = GAMEMODE.IronsightZoomScale or 1
			return 1 - (1 - deep) * zoom_scoped
		end

		local zoom = GAMEMODE.IronsightZoomScale or 1

		local magnification = (istable(self.IronSights) and tonumber(self.IronSights.Magnification))
			or tonumber(self.ADSMagnification)
		if magnification and magnification > 0 then
			return 1 - (1 - math.Clamp(1 / (magnification * 0.95), 0.05, 1)) * zoom
		end

		return 1 - (1 - (self.IronsightsMultiplier or 0.6)) * zoom
	end

	function SWEP:GetSmoothedFOVMult()
		local delta = self:GetIronsightDelta()

		-- [双轴缓动 · ARC9 同式] OutQuart→InOutQuad 主轴推进；InCirc 副轴只管逼近节奏
		local d1 = math.ease.InOutQuad(math.ease.OutQuart(delta))
		local d2 = math.ease.InCirc(delta)

		local target = GetAimFOVTarget(self)

		-- [换弹回退] 换弹动作期间倍率回退 5%，枪身上抬不遮挡视野（ARC9 reloadanim 同款）
		if self.GetReloadFinish and self:GetReloadFinish() > 0 then
			target = target * 0.95
		end

		-- 双轴混合（ARC9: Lerp(d1, 1, Lerp(d2, target2, target))；ZS 无双段变倍，两轴同目标）
		local mag = Lerp(d1, 1, target)

		-- [变速指数逼近 · ARC9 手感核心] 步长 ∝ 剩余差值 × 分段速度：
		-- 开镜中速度系数从 1 随 InCirc 缓升到 10（深倍率中途 50）——给前载缓动加
		-- "慢起步"低通滤波，滤掉突兀的第一段缩放，形成软起手→中段加速→缓收尾的 S 曲线；
		-- 收镜中/后 10→25 加速收敛，尾巴利落。
		-- [无早退] 全程无条件执行：差值随 mag→1 自然归零，杜绝旧版 delta 归零瞬间
		-- 直接 return 1 造成的收镜末端硬跳变（pop）
		local cur = self.m_fSmoothedFOVMult or 1
		local speed
		if self:GetIronsights() then
			speed = Lerp(d2, 1, (target < 0.5 and d2 < 1) and 50 or 10)
		else
			speed = Lerp(delta, 25, 10)
		end

		local diff = math.abs(cur - mag)
		if diff > 0.0001 then
			cur = math.Approach(cur, mag, RealFrameTime() * diff * speed)
			self.m_fSmoothedFOVMult = cur
		end

		return cur
	end

	function SWEP:GetAimFOVMultiplier()
		return self:GetSmoothedFOVMult()
	end

	function SWEP:TranslateFOV(fov)
		return self:GetSmoothedFOVMult() * fov
	end

	-- [ARC9 移植 · cl_sight_autosolve AdjustMouseSensitivity]
	-- amt = sqrt(1 / (1 - (delta * (1 - mag))))：开方感知补偿——比线性缩放"跟手"，
	-- 高倍率下不会慢得拖泥带水。总放大率 = 主视角变焦 × 镜内光学倍率。
	local CVAR_MULT_SENS = CreateClientConVar("zs_mult_sens", "1", true, false, "开镜灵敏度总倍率", 0.1, 10)

	function SWEP:AdjustMouseSensitivity()
		local delta = self:GetIronsightDelta()
		if delta <= 0 then return end

		local mag
		if self.Scoped and self.UsesPIPScope and self:UsesPIPScope() then
			local mainzoom = 1 / math.max(self.PIPMainFOVMult or 0.88, 0.01)
			local optical = self.GetEffectiveScopeMagnification and self:GetEffectiveScopeMagnification() or self.ScopeMagnification or 4
			mag = mainzoom * optical
		else
			mag = 1 / math.max(GetAimFOVTarget(self), 0.01)
		end

		local amt = 1 / (1 - (delta * (1 - mag)))
		amt = math.sqrt(math.max(amt, 0.001))

		return amt * CVAR_MULT_SENS:GetFloat()
	end
end

function SWEP:OnRestore()
	self:SetIronsights(false)
end
