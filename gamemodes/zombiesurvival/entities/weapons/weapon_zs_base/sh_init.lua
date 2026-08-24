-- sh_init.lua

function SWEP:Initialize()
    if not self:IsValid() then return end

    self:SetWeaponHoldType(self.HoldType)
    
    -- ZS 权重与阶级逻辑
    if self.Weight and self.Tier then
        self.Weight = self.Weight + self.Tier
    end

    -- 旧版数据兼容处理
    if self.Cone then
        self.ConeMin = self.ConeIronCrouching
        self.ConeMax = self.ConeMoving
        self.ConeRamp = 2
    end
    
    -- 客户端初始化动画和模型
    if CLIENT then
        self:CheckCustomIronSights()
        self:Anim_Initialize()
    end
    
    self:ResetRecoilState()
        -- 初始化所有后坐力相关的变量，防止 Think 报错
    self.last_shot_time = 0
    self.RecoilAmount = 0
    self.ShotCount = 0
    
    self:ResetRecoilState(false) -- false 表示完全重置
    if GAMEMODE then
        GAMEMODE:DoChangeDeploySpeed(self)
    end
end

-- 修改重置函数
function SWEP:ResetRecoilState(isReload)
	if not isReload then
		self.last_shot_time = 0
		self.RecoilAmount = 0
		self.ShotCount = 0
	end

	self.last_frame_total_offset = Angle(0, 0, 0)
	self.CamRecoilRollVal = 0
	self.CamRecoilCurrent = Angle(0, 0, 0)
	self.CamRecoilAngVel = Angle(0, 0, 0)
	self.CamRecoilAngAcc = Angle(0, 0, 0)
	self.CamRecoilRollVel = 0
	self.CamRecoilRollAcc = 0
	self.CamFOV_Val = 0
	self.CamFOV_Vel = 0
	self.LastEyeAngles = nil
	self.m_fSmoothedFOVMult = nil

	self.RecoilAccumUp = 0
	self.RecoilAccumSide = 0
	self.RecoilPatternCache = nil
	self.RecoilInjectUp = 0
	self.RecoilInjectSide = 0
	self.RecoilInjectNext = 0
	self.RecoilInjectProgress = 1
	self.RecoilRiseAngle = Angle(0, 0, 0)

	self.VisRecoilPos = Vector(0, 0, 0)
	self.VisRecoilVel = Vector(0, 0, 0)
	self.VisRecoilAcc = Vector(0, 0, 0)
	self.VisRecoilAng = Angle(0, 0, 0)
	self.VisRecoilAngVel = Angle(0, 0, 0)
	self.VisRecoilAngAcc = Angle(0, 0, 0)

	-- 微抖层（ARC9 SubtleVisualRecoil）独立状态
	self.SubVisRecoilPos = Vector(0, 0, 0)
	self.SubVisRecoilVel = Vector(0, 0, 0)
	self.SubVisRecoilAcc = Vector(0, 0, 0)
	self.SubVisRecoilAng = Vector(0, 0, 0)
	self.SubVisRecoilAngVel = Vector(0, 0, 0)
	self.SubVisRecoilAngAcc = Vector(0, 0, 0)

	-- [旧版摇摆已移除] CurrentSwayAngle/CurrentBobVector 不再使用（ARC9 系统见 cl_sway.lua）
	self.Breath = 0
end