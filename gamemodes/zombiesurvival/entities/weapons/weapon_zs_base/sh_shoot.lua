-- sh_shoot.lua

function SWEP:PrimaryAttack()
    if self:Clip1() <= 0 then 
        self:Reload()
        return
    end
    
    if not self:CanPrimaryAttack() then return end

    self:SetNextPrimaryFire(CurTime() + self:GetFireDelay())

    self:EmitFireSound()
    self:TakeAmmo()
    
    -- 连发计数先于 ShootBullets 递增：动画框架的 fire_N 连发变体探测依赖本帧新值
    self.ShotCount = (self.ShotCount or 0) + 1
    
    self:ShootBullets(self.Primary.Damage, self.Primary.NumShots, self:GetCone())
    
    -- [动画框架] IdleAnimation 已由 PlayAnimation 按实际播放时长精确写入；
    -- 此处仅兜底：子类 override SendWeaponAnimation / 抑制路径未写时维持旧行为
    -- （SequenceDuration() 取刚播放序列的时长，与旧版语义一致）
    if not self.m_bIdleFromAnim then
        self.IdleAnimation = CurTime() + self:SequenceDuration()
    end
    self.m_bIdleFromAnim = nil
end

function SWEP:ShootBullets(dmg, numbul, cone)
    local owner = self:GetOwner()
    
    -- [ARC9 动画框架] 开镜抑制逻辑已内化到 SendWeaponAnimation 基座实现；
    -- CustomSightsAttackAnim=true 且开镜时走完全抑制（不播关键帧，纯弹簧表现）
    if not self:GetIronsights() or not self.CustomSightsAttackAnim then 
        self:SendWeaponAnimation()
    else
        self:SuppressFireAnimation()
        -- [特效补位] 该分支绕过 SendWeaponAnimation，枪口焰需在此单独生成
        --（SendWeaponAnimation 顶部的生成点对本分支不可达——akbar 开镜无焰的根源）
        self.m_bFrameworkFire = true
        self:SpawnMuzzleFX()
    end
    
    owner:DoAttackEvent()
    
    -- [ARC9 原版机制] 实际后坐力由 cl_recoil_handler 渐进注入真实视角，
    -- 子弹自然跟随移动后的准星，此处不再单独偏转弹道
    owner:LagCompensation(true)
    owner:FireBulletsLua(
        owner:GetShootPos(), 
        owner:GetAimVector(), 
        cone, 
        numbul, 
        dmg, 
        nil, 
        self.Primary.KnockbackScale, 
        self.TracerName, 
        self.BulletCallback, 
        self.Primary.HullSize, 
        nil, 
        self.Primary.MaxDistance, 
        nil, 
        self
    )
    owner:LagCompensation(false)
    
    -- 应用新的 ARC9 风格后坐力逻辑 (定义在 sh_recoil.lua)
    self:ApplyRecoil()
end

-- [ARC9 风格特效] 屏蔽枪模序列内置的引擎枪口焰动画事件（5001~5003，
-- CS:S 原版火光的来源），改由 SendWeaponAnimation 统一生成的
-- MuzzleFlashEffect 特效替代。注意不能扩到 5004——那是 AE_CL_PLAYSOUND
-- 序列声音事件，换弹的 clipin/clipout/boltpull 音效走它。
-- 仅在框架开火过的武器上生效——未接入框架的子类保持引擎原版行为不受
-- 影响；置 MuzzleFlashEffect=false 可整体退回
function SWEP:FireAnimationEvent(pos, ang, event, name)
    if self.m_bFrameworkFire
        and self.MuzzleFlashEffect ~= false
        and event >= 5001 and event <= 5003 then
        return true
    end
end

function SWEP:CanPrimaryAttack()
    local owner = self:GetOwner()
    if owner:IsHolding() or owner:GetBarricadeGhosting() or self:GetReloadFinish() > 0 then return false end

    -- 完全冻结状态下无法攻击
    if owner:IsFrozenFull() then return false end

    -- [动画框架] lock 播放的动画在 MinProgress 进度点前锁攻击（默认调用不设锁）
    if self.AnimLockTime and self.AnimLockTime > CurTime() then return false end

    if self:Clip1() < self.RequiredClip then
        self:EmitSound(self.DryFireSound)
        self:SetNextPrimaryFire(CurTime() + math.max(0.25, self.Primary.Delay))
        return false
    end

    return self:GetNextPrimaryFire() <= CurTime()
end

function SWEP:GetCone()
	local owner = self:GetOwner()

	local basecone = self.ConeMin
	local conedelta = self.ConeMax - basecone

	local orphic = not owner.Orphic and 1 or self:GetIronsights() and 0.9 or 1.1
	local tiervalid = (self.Tier or 1) <= 3
	local spreadmul = (owner.AimSpreadMul or 1) - ((tiervalid and owner:HasTrinket("refinedsub")) and 0.27 or 0)

	if owner.TrueWooism then
		return (basecone + conedelta * 0.5 ^ self.ConeRamp) * spreadmul * orphic
	end

	if not owner:OnGround() or self.ConeMax == basecone then return self.ConeMax end

	local multiplier = math.min(owner:GetVelocity():Length() / self.WalkSpeed, 1) * 0.5

	local ironsightmul = 0.25 * (owner.IronsightEffMul or 1)
	local ironsightdiff = 0.25 - ironsightmul
	multiplier = multiplier + ironsightdiff

	if not owner:Crouching() then multiplier = multiplier + 0.25 end
	if not self:GetIronsights() then multiplier = multiplier + ironsightmul end

	return (basecone + conedelta * (self.FixedAccuracy and 0.6 or multiplier) ^ self.ConeRamp) * spreadmul * orphic
end


function SWEP:GetFireDelay()
    local owner = self:GetOwner()
    local baseDelay = self.Primary.Delay
    local currentDelay = baseDelay -- 初始化当前延迟为基础延迟

    -- 处理“霜冻”状态：
    -- 如果拥有者处于“frost”状态，开火延迟增加30% (乘以1.3)。
    -- 这将导致武器的射速变慢。
    if owner:GetStatus("frost") then
        currentDelay = currentDelay * 1.3
    end

    -- 处理“fastshoot”状态：
    -- 如果拥有者拥有“fastshoot”状态，开火延迟减少10% (乘以0.9)。
    -- 这将导致武器的射速加快。
    if owner:GetStatus("fastshoot") then
        currentDelay = currentDelay * 0.9
    end

    -- 返回最终修正后的开火延迟
    return currentDelay
end

SWEP.AU = 0
function SWEP:TakeAmmo()
    if self.AmmoUse then
        self.AU = (self.AU or 0) + self.AmmoUse
        if self.AU >= 1 then
            local use = math.floor(self.AU)
            self:TakePrimaryAmmo(use)
            self.AU = self.AU - use
        end
    else
        self:TakePrimaryAmmo(self.RequiredClip)
    end
end

function SWEP:EmitFireSound()
	self:EmitSound(self.Primary.Sound)
end