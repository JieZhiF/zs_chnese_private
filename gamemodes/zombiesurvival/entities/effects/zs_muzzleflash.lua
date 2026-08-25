-- ============================================================================
-- zs_muzzleflash.lua - 枪口焰驱动器（ARC9 原版 PCF 粒子方案）
-- ARC9 的枪口焰由其 PCF 粒子系统驱动（arc9_fas_muzzleflashes 等），本特效
-- 不再自绘 sprite，只做三件事：解析枪口附件 → 在该附件上挂接同款 PCF
-- 粒子（PATTACH_POINT_FOLLOW 跟随枪口）→ 生成暖黄动态光。
-- 粒子系统名由武器侧 SWEP:GetMuzzleParticle() 决定（见 sh_effects.lua），
-- 观感即 ARC9 原版；粒子生命周期由引擎管理，本实体随即消亡。
-- 数据接口：SetEntity（视模型或世界模型）、SetAttachment（muzzle 附件索引）、
--           SetOrigin+SetAngles（无附件时的位置兜底）
-- 消费方：sh_anim.lua SpawnMuzzleFX（框架开火的统一第一人称枪口焰）
-- ============================================================================

EFFECT.DieTime = 0

function EFFECT:Init(data)
	local ent = data:GetEntity()

	local att = data:GetAttachment() or 0

	-- [本地第一人称去重] 本视角的视模型特效已由武器端直接挂接（对齐最准，
	-- 开镜全程不错位），广播份一律拦下防双焰；广播份只服务于远端观察者与
	-- 本地第三人称视角。广播携带实体仅作归属标识，位置走 Origin 坐标
	-- （不依赖世界模型骨骼状态）
	if CLIENT and IsValid(ent) then
		local owner = ent.GetOwner and ent:GetOwner()
		if IsValid(owner) and owner == LocalPlayer()
			and ent ~= owner:GetViewModel()
			and not owner:ShouldDrawLocalPlayer() then
			self:Remove() return
		end
	end

	local pa = (att > 0 and IsValid(ent)) and ent:GetAttachment(att) or nil
	-- [版本兼容] GetAttachment 新版返回 {Pos,Ang} 表、旧版返回 pos,ang 双值
	local pos, ang
	if istable(pa) and isvector(pa.Pos) then
		pos, ang = pa.Pos, pa.Ang
	elseif isvector(pa) then
		pos, ang = pa, ent:GetAngles()
	else
		pos = data:GetOrigin()
		ang = data:GetAngles()
		if ang:IsZero() and IsValid(ent) then ang = ent:GetAngles() end
	end

	-- [实体池防御] 特效 CSEnt 会被引擎回收复用，所有字段先于提前 return 初始化
	self.Pos = pos
	self.Ang = ang
	self.DieTime = CurTime()

	-- 粒子系统名：武器侧决定（HoldType 自动映射 / SWEP.MuzzleParticle 覆写）
	local name = "muzzleflash_ar"
	local wep = IsValid(ent) and ent.GetOwner and ent:GetOwner()
	if IsValid(wep) and wep.GetMuzzleParticle then
		name = wep:GetMuzzleParticle() or name
	end

	if att > 0 and IsValid(ent) then
		-- 跟随附件：开火期间枪口位移时火焰不脱锚（本地视模型路径）
		ParticleEffectAttach(name, PATTACH_POINT_FOLLOW, ent, att)
	else
		-- [世界坐标路径] 服务器广播（纯坐标、无附件）：一次性世界生成，
		-- 不依赖任何骨骼状态，恒可见
		ParticleEffect(name, self.Pos, self.Ang, nil)
	end

	-- [动态光] 量纲端口自 arc9_muzzleeffect：暖黄、高衰减、约 0.1 秒熄灭
	local light = DynamicLight(self:EntIndex())
	if light then
		light.Pos = self.Pos
		light.r = 244
		light.g = 209
		light.b = 66
		light.Brightness = 2
		light.Decay = 2500
		light.Size = 256
		light.DieTime = CurTime() + 0.1
	end
end

function EFFECT:Think()
	-- 粒子已挂接到父实体自行演化，宿主特效立即退场即可
	return false
end

function EFFECT:Render()
end
