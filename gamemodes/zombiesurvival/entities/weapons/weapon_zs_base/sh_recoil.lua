-- ============================================================================
-- weapon_zs_base/sh_recoil.lua - 武器母本后坐力系统（共享）
-- 双轨分离（移植自 ARC9 原版机制）：
--   [实际轨] RecoilAccumUp/RecoilAccumSide 累积量 → cl_recoil_handler 在 CreateMove
--            中按时间步长渐进注入真实视角（平滑上抬、RecoilRise 回正、手动压枪抵扣）。
--            子弹自然跟随移动后的准星。停火指数衰减（见 sh_think ThinkRecoil）。
--   [视觉轨] CamRecoil 镜头弹跳 + VisRecoil 枪模 Verlet 弹簧 —— 纯表现层，
--            不写视角角度、不碰弹道。枪模水平抖动方向跟随实际轨走向。
-- ============================================================================

-- ==== GetRecoilModifier - 按机瞄/蹲下/空中/移动状态计算后坐力倍率 ====
function SWEP:GetRecoilModifier()
	local owner = self:GetOwner()
	if not IsValid(owner) then return 1 end

	local mod = 1
	if self:GetIronsights() then mod = mod * (self.RecoilMultSights or 0.5) end
	if owner:Crouching() then mod = mod * (self.RecoilMultCrouch or 0.75) end
	if not owner:IsOnGround() then mod = mod * (self.RecoilMultMidAir or 2.0) end
	if owner:GetVelocity():Length2D() > 70 then mod = mod * (self.RecoilMultMove or 1.3) end

	return mod
end

-- ==== GetRecoilPatternDirection - 确定性连射方向图案 ====
-- 移植自 ARC9 RecoilPatternDirection：以武器类名派生种子，
-- 第 shot 发的方向 = 上一发方向 + 有界随机漂移；同一连射序号在
-- 服务端与客户端预测中得出完全一致的角度（弹道偏移双端一致的前提）。
function SWEP:GetRecoilPatternDirection(shot)
	self.RecoilPatternCache = self.RecoilPatternCache or {}

	local cached = self.RecoilPatternCache[shot]
	if cached then return cached end

	local prev = shot > 1 and (self.RecoilPatternCache[shot - 1] or 0) or 0

	-- 类名各字符字节值之和作为种子基数
	local numseed = 0
	for ch in string.gmatch(self:GetClass(), ".") do
		numseed = numseed + string.byte(ch)
	end

	math.randomseed((numseed % 16777216) + shot)
	local drift = self.RecoilPatternDrift or 0.35
	local dir = prev + math.Rand(-drift, drift)
	math.randomseed(math.Round(CurTime() * 1000) + self:EntIndex()) -- 归还全局随机熵（ARC9 同款技巧）

	self.RecoilPatternCache[shot] = dir
	return dir
end

-- [作者量纲] 枪模振幅参数（VisualRecoilPunch/Up/Roll/Back 及其 *HipFire）
-- 填入值为放大十倍后的数值：SWEP 填 1 = 内部量 0.1。换算集中在此处，
-- 调参者只面对 0~1 区间的小数，避免"填 0.04 实际位移却很大"的错位
local AMP10 = 0.1
local function ScaleAmp(v, fallback)
	if v == nil then return fallback end
	return v * AMP10
end

-- ==== ApplyRecoil - 开火时累积实际弹道偏移并驱动视觉层 ====
function SWEP:ApplyRecoil()
	if not self.Recoil_Enabled then return end

	local mod = self:GetRecoilModifier()
	local seed = "zs_" .. self:EntIndex() .. (self.ShotCount or 0)

	-- 1. 热度累积 (非线性曲线: 前几发稳定, 后段加速上升)
	self.RecoilAmount = self.RecoilAmount or 0
	self.RecoilAmount = math.min(self.RecoilAmount + (self.RecoilPerShot or 1), self.RecoilMax or 6)

	local heatRatio = self.RecoilAmount / math.max(self.RecoilMax or 6, 1)
	local buildupMult = 1 + ((self.RecoilModifierCap or 1.2) - 1) * (heatRatio * heatRatio)

	local finalMod = mod * buildupMult

	-- 2. 首发倍率（第一发跳动通常更大）
	if self.ShotCount == 1 then
		finalMod = finalMod * (self.RecoilFirstShotMult or 1.0)
	end

	-- 3. 确定性方向图案（ARC9式）：本发方位角由种子漂移决定
	local shot = math.max(self.ShotCount or 1, 1)
	local pat_dir = math.rad(self:GetRecoilPatternDirection(shot) - 90)

	-- 4. [实际轨] 后坐力累积 —— 共享域计算保证预测一致；
	--    RecoilAccumUp ≥ 0 表示向上爬升分量(度)，RecoilAccumSide 右偏为正。
	--    消费方：cl_recoil_handler 渐进注入视角（ARC9 原版路径）
	local scale = self.RecoilAccumScale or 1
	local up = (self.RecoilUp + util.SharedRandom(seed .. "bu", 0, self.RecoilRandomUp)) * finalMod * scale

	-- 水平走向：图案 cos 给出确定性左右漂移；RecoilSideBias 在图案相悖时按强度翻转
	local pat_side = math.cos(pat_dir)
	local bias = self.RecoilSideBias or 0
	if math.abs(bias) > 0.01 and pat_side * bias < 0 then
		if math.abs(math.sin(pat_dir)) < math.abs(bias) then
			pat_side = (bias > 0) and math.abs(pat_side) or -math.abs(pat_side)
		end
	end
	local side = pat_side * (self.RecoilSide + util.SharedRandom(seed .. "bs", 0, self.RecoilRandomSide)) * finalMod * scale

	self.RecoilAccumUp = self.RecoilAccumUp or 0
	self.RecoilAccumSide = self.RecoilAccumSide or 0

	-- 垂直爬升上限沿用 RecoilMaxTotalUp；水平对称限半
	local max_up = self.RecoilMaxTotalUp or 45
	self.RecoilAccumUp = math.Clamp(self.RecoilAccumUp + up, 0, max_up)
	self.RecoilAccumSide = math.Clamp(self.RecoilAccumSide + side, -max_up * 0.5, max_up * 0.5)

	local kick = up -- 视觉层的量纲回退基准（未显式配置 CamRecoil*/VisualRecoil* 时使用）

	-- 5. 视觉层 —— 仅表现，不触碰视角与弹道
	if CLIENT or game.SinglePlayer() then
		if IsFirstTimePredicted() then
			-- [镜头增强] 开镜进度按 CamRecoilADSMult 放大镜头层
			local ads = (CLIENT and self.GetIronsightDelta) and self:GetIronsightDelta() or 0
			local camBoost = 1 + ads * math.max((self.CamRecoilADSMult or 2) - 1, 0)

			-- 5.1 FOV 冲击（轻微的FOV收缩感）
			local fovPunch = self.CamRecoilFOV or 1.2
			if fovPunch > 0 then
				self.CamFOV_Vel = (self.CamFOV_Vel or 0) - math.abs(kick) * fovPunch * 8 * camBoost
			end

			-- 5.2 镜头角度弹跳 —— 注入弹簧速度（cl_camera Verlet 积分回正），单轴未显式配置时由弹道踢量自动演绎
			local camUp   = self.CamRecoilUp   or math.abs(kick) * (self.KickCameraGain or 1.2)
			local camSide = self.CamRecoilSide or math.abs(kick) * (self.KickCameraSideGain or 1.6)
			local camRoll = self.CamRecoilRoll or math.abs(kick) * (self.KickCameraRollGain or 1.5)

			self.CamRecoilAngVel = self.CamRecoilAngVel or Angle(0, 0, 0)
			self.CamRecoilAngVel.p = self.CamRecoilAngVel.p - (camUp * finalMod * 40 * camBoost)
			self.CamRecoilAngVel.y = self.CamRecoilAngVel.y + util.SharedRandom(seed .. "cam_y", -1, 1) * camSide * finalMod * 40 * camBoost
			self.CamRecoilRollVel = (self.CamRecoilRollVel or 0) + util.SharedRandom(seed .. "roll", -1, 1) * camRoll * finalMod * 30 * camBoost

			-- 5.3 枪模弹簧注入 —— ARC9 式双参数组：`*` 仅作开镜终值、*HipFire 为腰射终值，
			-- 随开镜进度插值（未声明 HipFire 时腰射端为 0）。填入值经 ScaleAmp ÷10 折算
			if self.UseVisualRecoil then
				self.VisRecoilAngVel = self.VisRecoilAngVel or Angle(0, 0, 0)
				self.VisRecoilVel = self.VisRecoilVel or Vector(0, 0, 0)

				local v_up = ScaleAmp(self.VisualRecoilUp, -math.abs(kick) * (self.KickModelGain or 4.5))
				local v_punch = ScaleAmp(self.VisualRecoilPunch, math.abs(kick) * (self.KickModelPunchGain or 3.75))
				local v_roll = ScaleAmp(self.VisualRecoilRoll, math.abs(kick) * (self.KickModelRollGain or 6.25))
				local v_back = ScaleAmp(self.VisualRecoilBack, 0) -- 沿枪身向后（朝射手）的主体位移

				-- [组语义] `*` 仅作开镜终值，`*HipFire` 为腰射终值，随开镜进度插值；
				-- 未声明 HipFire 组时腰射端按 0 处理（"开镜组"字面生效：腰射无枪模动作）
				v_up = Lerp(ads, ScaleAmp(self.VisualRecoilUpHipFire, 0), v_up)
				v_punch = Lerp(ads, ScaleAmp(self.VisualRecoilPunchHipFire, 0), v_punch)
				v_roll = Lerp(ads, ScaleAmp(self.VisualRecoilRollHipFire, 0), v_roll)
				v_back = Lerp(ads, ScaleAmp(self.VisualRecoilBackHipFire, 0), v_back)

				-- [随机幅度] 四轴每发在基准上叠加对称随机量：把"固定值"
				-- 变成"基准值 ± 范围"的落点分布，消除逐发完全一致的机械感
				local up_rand = ScaleAmp(self.VisualRecoilUpRandom, 0)
				if up_rand ~= 0 then v_up = v_up + math.Rand(-up_rand, up_rand) end

				local punch_rand = ScaleAmp(self.VisualRecoilPunchRandom, 0)
				if punch_rand ~= 0 then v_punch = v_punch + math.Rand(-punch_rand, punch_rand) end

				local roll_rand = ScaleAmp(self.VisualRecoilRollRandom, 0)
				if roll_rand ~= 0 then v_roll = v_roll + math.Rand(-roll_rand, roll_rand) end

				local back_rand = ScaleAmp(self.VisualRecoilBackRandom, 0)
				if back_rand ~= 0 then v_back = v_back + math.Rand(-back_rand, back_rand) end

				-- [ARC9 VisualRecoilPositionBump] 开镜越满枪模向眼轴冲程越大；PIP 镜另有上抬分量
				local bump = Lerp(ads, 1, self.VisualRecoilPositionBump or 1.5)
				local pip_on = self.IsPIPActive and self:IsPIPActive()
				local bumpup = pip_on and (self.VisualRecoilPositionBumpUpRTScope or 0.12) or 0

				self.VisRecoilAngVel.p = self.VisRecoilAngVel.p + (v_up * 10)
				-- 水平抖动方向跟随实际轨走向（ARC9：视觉 side 取自实际 RecoilSide 的符号）
				-- [注意] 本项与三个振幅参数解耦——即使振幅全零也会踢，故设独立增益开关
				local side_sign = (self.RecoilAccumSide or 0) >= 0 and 1 or -1
				local yawfollow = self.VisualRecoilYawFollow
				if yawfollow == nil then yawfollow = 1 end
				self.VisRecoilAngVel.y = self.VisRecoilAngVel.y + (side_sign * util.SharedRandom(seed .. "vr_y", 0.3, 0.6) * 5 * finalMod * yawfollow)
				self.VisRecoilAngVel.r = self.VisRecoilAngVel.r + (v_roll * util.SharedRandom(seed .. "vr_r", -1, 1) * 10)
				-- 位移注入（视轴坐标系）：x 右 / y 前（负＝向射手后坐）/ z 上
				self.VisRecoilVel = self.VisRecoilVel
					+ Vector(-v_back * 15 * bump, -v_punch * 15 * bump, math.abs(v_up) * 2.5 + bumpup * 30)

				-- [ARC9 SubtleVisualRecoil] 高频微抖层注入
				if CLIENT then
					self:DoSubtleVisualRecoil()
				end
			end
		end
	end

	self.last_shot_time = CurTime()
end
