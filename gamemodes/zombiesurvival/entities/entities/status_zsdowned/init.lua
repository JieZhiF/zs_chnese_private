-- ============================================================================
-- init.lua - PvE 人类倒地状态（服务端）
-- 负责：倒地期间虚血持续衰减；虚血归零 → 真死（观战等下波复活）；
--       被队友救起/自救 → 爬起回血；倒地玩家免疫再次伤害并锁定输入。
-- ============================================================================
INC_SERVER()

-- 倒地期间虚血每秒衰减量（默认 1.5，优先读 GAMEMODE.ZSDownedHealthDrain 即 zs_downdrain ConVar）
ENT.HealthDrain = 1.5

-- 倒地玩家不再被击杀（真正的死亡由虚血归零触发）
function ENT:PlayerSet(pPlayer, bExists)
	pPlayer.ZSDowned = self

	pPlayer:GodEnable()
	self.GodDisableTime = CurTime() + 0.2

	-- 确保倒地玩家有可见的布娃娃（死亡玩家本体不可见，靠布娃娃表现"倒在地上"）
	if not pPlayer:GetRagdollEntity() or not pPlayer:GetRagdollEntity():IsValid() then
		pPlayer:CreateRagdoll()
	end

	-- 隐藏玩家本体（由布娃娃代替显示），隐藏武器模型
	pPlayer:DrawWorldModel(false)
	pPlayer:DrawViewModel(false)

	-- 通知武器/技能脚本：玩家已被击倒
	pPlayer:CallWeaponFunction("KnockedDown", self, bExists)
end

function ENT:Think()
	local fCurTime = CurTime()
	local owner = self:GetOwner()
	if owner:IsValid() then
		-- 倒地玩家是"死亡"状态（Alive()==false），不能因未存活就移除。
		-- 只在玩家离队/回合结束/被救走时移除。
		if owner:Team() ~= TEAM_HUMAN then
			self:Remove()
			return
		end

		if self.GodDisableTime and fCurTime >= self.GodDisableTime then
			owner:GodDisable()
			self.GodDisableTime = nil
		end

		-- 虚血持续衰减（读 ConVar 实时值，默认 1.5/s）
		local health = self:GetDownedHealth()
		local drain = (GAMEMODE and GAMEMODE.ZSDownedHealthDrain) or self.HealthDrain or 1.5
		health = health - drain * FrameTime()
		if health <= 0 then
			-- 虚血归零：真死（变僵尸，走原版"被感染"循环）
			self:Remove()
			local gm = GAMEMODE or GM
			if gm and gm.EnterZSDownedTrueDeath then
				gm:EnterZSDownedTrueDeath(owner)
			end
			return
		end
		self:SetDownedHealth(health)

		-- 同步救援进度到客户端（DTFloat 2）
		local progress = self.RescueProgress or 0
		local rescuelen = (GAMEMODE and GAMEMODE.RescueTime) or 2.5
		self:SetRescueProgress(math.max(0, math.min(1, progress / rescuelen)))
	end

	self:NextThink(fCurTime)
	return true
end

function ENT:OnRemove()
	local parent = self:GetOwner()
	if parent:IsValid() then
		parent.ZSDowned = nil
		parent:GodDisable()
	end
end
