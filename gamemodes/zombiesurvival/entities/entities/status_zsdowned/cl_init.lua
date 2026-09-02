-- ============================================================================
-- cl_init.lua - PvE 人类倒地状态（客户端）
-- 负责：锁定倒地玩家输入（视角/移动），同步虚血数据供 HUD 渲染；
--       每帧跟随拥有者，并注册到拥有者供 HUD 读取。
-- ============================================================================
INC_CLIENT()

-- ==== Initialize - 挂接输入钩子并记录初始视角 ====
function ENT:Initialize()
	hook.Add("CreateMove", self, self.CreateMove)

	self:DrawShadow(false)
	self:SetRenderBounds(Vector(-40, -40, -18), Vector(40, 40, 80))

	local owner = self:GetOwner()
	if owner:IsValid() then
		owner.ZSDowned = self
		self.CommandYaw = owner:GetAngles().yaw

		-- 隐藏玩家本体（由布娃娃代替显示"倒在地上"，队友才能看到）
		owner:SetNoDraw(true)

		-- 通知武器/技能脚本：玩家已被击倒
		owner:CallWeaponFunction("KnockedDown", self, false)
	end
end

-- ==== CreateMove - 输入接管：固定视角朝向，清除移动/攻击键，保留 R 键（自救） ====
function ENT:CreateMove(cmd)
	if MySelf ~= self:GetOwner() then return end

	local ang = cmd:GetViewAngles()
	ang.yaw = self.CommandYaw or ang.yaw
	cmd:SetViewAngles(ang)

	-- 清除移动与攻击按键，但保留 IN_RELOAD（R 键用于倒地自救，不能被吞）
	cmd:ClearButtons(IN_RELOAD)
	cmd:ClearMovement()
end

-- ==== Think - 布娃娃吸附到固定倒地位置（服务端同步）+ 跟随 ====
function ENT:Think()
	local owner = self:GetOwner()
	if owner:IsValid() then
		-- 位置由服务端同步（EnterZSDowned 时固定），客户端不覆盖，保证标记位置准确

		-- 把倒地玩家的布娃娃吸到玩家位置，让队友能看到"有人倒在地上"
		local rag = owner:GetRagdollEntity()
		if rag and rag:IsValid() then
			local phys = rag:GetPhysicsObject()
			if phys and phys:IsValid() then
				phys:Wake()
				phys:ComputeShadowControl({secondstoarrive = 0.05, pos = owner:GetPos() + Vector(0, 0, 20), angle = phys:GetAngles(), maxangular = 2000, maxangulardamp = 10000, maxspeed = 5000, maxspeeddamp = 1000, dampfactor = 0.85, teleportdistance = 200, deltatime = FrameTime()})
			end
		end
	end

	self:NextThink(CurTime())
	return true
end

-- ==== OnRemove - 解除输入接管、恢复显示、删除倒地布娃娃 ====
function ENT:OnRemove()
	local owner = self:GetOwner()
	if owner:IsValid() then
		if owner.ZSDowned == self then
			owner.ZSDowned = nil
		end
		-- 恢复玩家本体显示（被救起/变僵尸后）
		-- 注意：DrawWorldModel/DrawViewModel 是服务端方法，客户端只恢复 SetNoDraw
		owner:SetNoDraw(false)

		-- 删除倒地布娃娃（避免残留）——客户端布娃娃是预测实体，直接删会不同步，
		-- 布娃娃的清理交给服务端（状态移除时）
	end
	hook.Remove("CreateMove", self)
end

-- ==== Draw - 自身不可见（HUD 由 zsdowned HUD 渲染） ====
function ENT:Draw()
end
