-- ============================================================================
-- weapon_zs_hunter.lua - 猎手狙击步枪
-- 负责：单发高伤害狙击步枪，开镜瞄准后精度极高；改造分支为双发弹匣+击杀爆炸
-- ============================================================================
AddCSLuaFile()

-- 武器显示名称与描述（本地化键）
SWEP.PrintName = ""..translate.Get("weapon_zs_hunter")
SWEP.Description = ""..translate.Get("weapon_zs_hunter_description")

-- 栏位内排序位置
SWEP.SlotPos = 0

if CLIENT then
	-- 武器栏位（步枪栏）
	SWEP.Slot = GAMEMODE:GetWeaponSlot("WeaponSelectSlotRifles")
	-- 武器类型与栏位分组（步枪）
	SWEP.WeaponType = "rifle"	
	SWEP.SlotGroup = WEPSELECT_RIFLE
	-- 第一人称视角设置
	SWEP.ViewModelFlip = false
	SWEP.ViewModelFOV = 65

	-- 3D HUD 绘制参数（在 AWM 骨上绘制弹药信息）
	SWEP.HUD3DBone = "v_weapon.awm_parent"
	SWEP.HUD3DPos = Vector(-1.25, -3.5, -16)
	SWEP.HUD3DAng = Angle(0, 0, 0)
	SWEP.HUD3DScale = 0.02
end

-- 注册自定义开火音效（基于 AWP 射击音，高音调起止）
sound.Add(
{
	name = "Weapon_Hunter.Single",
	channel = CHAN_WEAPON,
	volume = 1.0,
	soundlevel = 100,
	pitchstart = 134,
	pitchend = 10,
	sound = "weapons/awp/awp1.wav"
})

-- 继承基础武器类
SWEP.Base = "weapon_zs_base"

-- 持握姿势：AR2（步枪）
SWEP.HoldType = "ar2"

-- 第一人称/世界模型（AWP 狙击枪）
SWEP.ViewModel = "models/weapons/cstrike/c_snip_awp.mdl"
SWEP.VElements = {
	["pip_lens"] = { type = "Quad", bone = "v_weapon.awm_parent", rel = "", pos = Vector(0.0285, -6.51, 1.72), angle = Angle(0, 0, 0), size = 0.05, pip_aspect = 1.1,pip_chamfer = { tl = 0.000, tr = 0.000, br = 0.000, bl = 0.000 }, draw_func = nil}
}

SWEP.Scoped = true
SWEP.PIPScope = true
-- Unity Quad 方案：VElements 里的 pip_lens 面片开镜时显示 RT 放大画面（draw_func 基座自动注入）
SWEP.ScopeLensElement = "pip_lens"
SWEP.ScopeMagnification = 2 
SWEP.WorldModel = "models/weapons/w_snip_awp.mdl"
-- 使用 C 模型手部
SWEP.UseHands = true

-- 换弹音效与开火音效
SWEP.ReloadSound = Sound("Weapon_AWP.ClipOut")
SWEP.Primary.Sound = Sound("Weapon_Hunter.Single")
-- 单发伤害、子弹数、攻击延迟
SWEP.Primary.Damage = 222
SWEP.Primary.NumShots = 1
SWEP.Primary.Delay = 1.5
-- 换弹延迟等于攻击延迟
SWEP.ReloadDelay = SWEP.Primary.Delay

-- 弹匣容量1发、非全自动、使用357弹药、默认15发备弹
SWEP.Primary.ClipSize = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "357"
SWEP.Primary.DefaultClip = 15

-- 开火与换弹手势动画
SWEP.Primary.Gesture = ACT_HL2MP_GESTURE_RANGE_ATTACK_CROSSBOW
SWEP.ReloadGesture = ACT_HL2MP_GESTURE_RELOAD_SHOTGUN

-- 准星扩散：最大扩散较大，最小扩散为0（开镜时完全精准）
SWEP.ConeMax = 2
SWEP.ConeMin = 0

-- [机瞄配置 · ARC9 形式] Pos/Ang=开镜贴瞄偏移
SWEP.IronSights = {
	Pos = Vector(-7.435, -8.89, 2.326),
	Ang = Angle(0, 0, 0),
	Magnification = 1.15,	
	ViemModelFOV = 60,
}

-- 持有时的移动速度（较慢）
SWEP.WalkSpeed = SPEED_SLOWER
-- 标记为狙击步枪（影响机瞄逻辑）
SWEP.SniperRifle = true
-- 武器等级
SWEP.Tier = 3
SWEP.AimDownSightsTime = 0.47
-- 弹道曳光弹类型（大型狙击曳光）
SWEP.TracerName = "tracer_sniper_big"

-- 武器修饰符：换弹速度+0.1
GAMEMODE:AttachWeaponModifier(SWEP, WEAPON_MODIFIER_RELOAD_SPEED, 0.1)

-- 改造分支1：双发弹匣+击杀爆炸
GAMEMODE:AddNewRemantleBranch(SWEP, 1, ""..translate.Get("weapon_zs_hunter_r1"), ""..translate.Get("weapon_zs_hunter_r1_description"), function(wept)
	-- 弹匣容量改为2发
	wept.Primary.ClipSize = 2
	-- 每次射击需要2发弹药
	wept.RequiredClip = 2
	-- 换弹速度提升
	wept.ReloadSpeed = 0.9

	-- 覆盖击杀僵尸回调：击杀时触发爆炸
	wept.OnZombieKilled = function(self, zombie, total, dmginfo)
		local killer = self:GetOwner()
		-- 计算溢出伤害（负生命值）
		local minushp = -zombie:Health()
		-- 溢出伤害超过10时触发爆炸
		if killer:IsValid() and minushp > 10 then
			local pos = zombie:GetPos()

			-- 延迟0.15秒后造成范围爆炸伤害
			timer.Simple(0.15, function()
				util.BlastDamagePlayer(killer:GetActiveWeapon(), killer, pos, 72, minushp, DMG_ALWAYSGIB, 0.94)
			end)

			-- 播放爆炸特效
			local effectdata = EffectData()
				effectdata:SetOrigin(pos)
			util.Effect("Explosion", effectdata, true, true)
		end
	end
end)

-- ==== IsScoped - 判断是否处于开镜瞄准状态 ====
-- [重构] IsScoped 已收敛进 weapon_zs_base/sh_scope.lua；本武器 PIP 配置见下方

-- ==== SendWeaponAnimation - 发送武器开火动画 ====
function SWEP:SendWeaponAnimation()
	-- 播放主攻击动画
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)

	local owner = self:GetOwner()
	local vm = owner:GetViewModel()
	-- 计算换弹速度倍率
	local speed = self.ReloadSpeed * self:GetReloadSpeedMultiplier()

	if vm:IsValid() then
		-- 视角模型播放速率设为0.5倍（慢动作拉栓）
		vm:SetPlaybackRate(0.5 * speed)
	end

	-- 设置换弹完成时间（2.5秒除以速度倍率）
	self:SetReloadFinish(CurTime() + 2.5 / speed)
end

-- ==== MockReload - 模拟换弹（不实际换弹，仅设置换弹完成时间） ====
function SWEP:MockReload()
	local speed = self.ReloadSpeed * self:GetReloadSpeedMultiplier()
	self:SetReloadFinish(CurTime() + 2.5 / speed)
end

-- ==== Reload - 换弹 ====
function SWEP:Reload()
	local owner = self:GetOwner()
	-- 搬运物体时禁止换弹
	if owner:IsHolding() then return end

	-- 换弹时关闭机瞄
	if self:GetIronsights() then
		self:SetIronsights(false)
	end

	-- 可以换弹时执行模拟换弹
	if self:CanReload() then
		self:MockReload()
	end
end

-- ==== Deploy - 武器部署 ====
function SWEP:Deploy()
	-- 调用基类部署逻辑
	self.BaseClass.Deploy(self)

	-- 部署时弹匣为空则自动开始模拟换弹
	if self:Clip1() <= 0 then
		self:MockReload()
	end

	return true
end

-- ==== Think - 每帧检查弹药状态 ====
function SWEP:Think()
	-- 调用基类 Think 逻辑
	self.BaseClass.Think(self)

	-- 弹匣和备弹都耗尽时触发模拟换弹（播放空弹换弹动画）
	if self:Clip1() <= 0 and self:GetPrimaryAmmoCount() <= 0 then
		self:MockReload()
	end
end

-- ==== BulletCallback - 子弹命中回调（绘制命中特效） ====
function SWEP.BulletCallback(attacker, tr, dmginfo)
	-- 在命中位置播放猎手专属命中特效
	local effectdata = EffectData()
		effectdata:SetOrigin(tr.HitPos)
		effectdata:SetNormal(tr.HitNormal)
	util.Effect("hit_hunter", effectdata)
end

-- ==== 瞄准镜配置（重构：基座统一实现，见 weapon_zs_base/sh_scope.lua） ====
SWEP.Scoped = true
SWEP.PIPScope = true
SWEP.ScopeMagnification = 4
