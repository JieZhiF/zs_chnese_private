-- sh_sights.lua
-- 机械瞄准（ADS）核心：ARC9 风格平滑过渡状态机 + 输入处理 + FOV/灵敏度

-- [切换模式] 双端一致的复制变量：1=右键按一下切换开关，0=长按瞄准
local CVAR_TOGGLE_ADS = CreateConVar("zs_toggleads", "0", bit.bor(FCVAR_REPLICATED, FCVAR_ARCHIVE), "切换式机械瞄准（1=按一下切换，0=长按）")

function SWEP:IsToggleADS()
	return CVAR_TOGGLE_ADS:GetBool()
end

--[[ 平滑过渡说明：
	GetIronsightDelta（CLIENT）采用持续逼近式进度：从当前值向目标滑动，
	中途反打收/开镜时从当前位置继续，不产生跳变。
	self.fIronTime 仅保留给狙击系武器的 IsScoped() 做完全瞄准时序判断。 ]]

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
	-- [过渡进度] 持续逼近式 0~1：按真实耗时推进，与调用频率无关；单次上限 0.1 秒防卡顿瞬移
	function SWEP:GetIronsightDelta()
		if GAMEMODE.NoIronsights then return 0 end

		local st = SysTime()
		local dt = math.min(st - (self.m_fIronLastSysT or st), 0.1)
		self.m_fIronLastSysT = st

		local target = self:GetIronsights() and 1 or 0
		self.m_nIronDelta = math.Approach(self.m_nIronDelta or 0, target, dt / (self.AimDownSightsTime or 0.25))

		return self.m_nIronDelta
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

	--[FOV 缩放 · ARC9 GetSmoothedFOVMag 移植] 双轴缓动混合 + 指数逼近
	--[框架陷阱修复] 旧版以 self.IsScoped（方法存在性）判断狙击武器，基座统一提供
	--IsScoped 后该判断对所有武器恒真，改用显式标志位 self.Scoped（见 sh_scope.lua）
	--[PIP 全程一致] 目标倍率必须整段过渡不变：UsesPIPScope 与进度无关，
	--若按进度中段切换目标会出现"先深缩放再弹回"的断裂感
	local function GetAimFOVTarget(self)
		if self.Scoped and not GAMEMODE.DisableScopes then
			if self.UsesPIPScope and self:UsesPIPScope() then
				-- PIP：放大交给镜内画面，主视角全程只做轻微变焦保持周边视野
				return self.PIPMainFOVMult or 0.75
			end
			return self.IronsightsMultiplier or 0.25
		end

		local zoom = GAMEMODE.IronsightZoomScale or 1

		-- [ARC9 倍率语义] Magnification：FOV ÷ 倍率（×0.95 与 ARC9 cl_camera 同因子）；
		-- 同样受全局缩放阻尼约束
		local magnification = istable(self.IronSights) and tonumber(self.IronSights.Magnification)
		if magnification and magnification > 0 then
			return 1 - (1 - math.Clamp(1 / (magnification * 0.95), 0.05, 1)) * zoom
		end

		return 1 - (1 - (self.IronsightsMultiplier or 0.6)) * zoom
	end

	function SWEP:GetSmoothedFOVMult()
		local delta = self:GetIronsightDelta()
		if delta <= 0 then return 1 end

		-- [三重缓动链] OutQuart → InOutQuad 推进开镜前段；InCirc 独立轴控制后段收尾
		local d1 = math.ease.InOutQuad(math.ease.OutQuart(delta))
		local d2 = math.ease.InCirc(delta)

		local target = GetAimFOVTarget(self)

		-- [换弹回退] 换弹动作期间倍率回退 5%，枪身上抬不遮挡视野（ARC9 reloadanim 同款）
		if self.GetReloadFinish and self:GetReloadFinish() > 0 then
			target = target * 0.95
		end

		-- 双轴混合（ARC9: Lerp(d1, 1, Lerp(d2, target2, target))；ZS 无双段变倍，两轴同目标）
		local mag = Lerp(d1, 1, Lerp(d2, target, target))

		-- [指数逼近] 目标突变（滚轮变焦/换弹起止）时按差值比例追赶，深倍率追得更快
		local cur = self.m_fSmoothedFOVMult or 1
		local speed = (target < 0.5 and d2 < 1) and 50 or 10
		cur = math.Approach(cur, mag, RealFrameTime() * math.abs(cur - mag) * speed)
		self.m_fSmoothedFOVMult = cur

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
			local mainzoom = 1 / math.max(self.PIPMainFOVMult or 0.75, 0.01)
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
