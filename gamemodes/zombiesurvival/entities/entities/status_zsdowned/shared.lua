-- ============================================================================
-- shared.lua - PvE 人类倒地状态（共享）：声明实体类型与虚血数据接口
-- 负责：提供虚血（DownedHealth）、虚血上限、倒地次数、救援者等 DT 读写接口
-- 倒地规则（PvE）：
--   * 人类被僵尸攻击致死 → 进入倒地（不再变僵尸）
--   * 倒地期间有虚血（DownedHealth），持续衰减；虚血归零 → 真死（观战等下一波）
--   * 队友靠近按住 E 读条拉起；可用自救道具直接爬起；波间无人拉自动爬起
--   * 限次倒地：每局每人可倒地 N 次，次数越多虚血越短，次数耗尽被放倒直接真死
-- ============================================================================
ENT.Type = "anim"
ENT.Base = "status__base"

AddCSLuaFile("shared.lua")

-- ==== SetDownedHealth - 设置当前虚血 ====
function ENT:SetDownedHealth(h)
	self:SetDTFloat(0, h)
end

-- ==== GetDownedHealth - 读取当前虚血 ====
function ENT:GetDownedHealth()
	return self:GetDTFloat(0)
end

-- ==== SetDownedHealthMax - 设置虚血上限 ====
function ENT:SetDownedHealthMax(h)
	self:SetDTFloat(1, h)
end

-- ==== GetDownedHealthMax - 读取虚血上限 ====
function ENT:GetDownedHealthMax()
	return self:GetDTFloat(1)
end

-- ==== SetDownedCount - 设置本局已倒地次数 ====
function ENT:SetDownedCount(n)
	self:SetDTInt(0, n)
end

-- ==== GetDownedCount - 读取本局已倒地次数 ====
function ENT:GetDownedCount()
	return self:GetDTInt(0)
end

-- ==== SetRescuer - 设置当前正在救援的玩家 ====
function ENT:SetRescuer(pl)
	self:SetDTEntity(0, pl)
end

-- ==== GetRescuer - 读取当前救援者 ====
function ENT:GetRescuer()
	return self:GetDTEntity(0)
end

-- ==== IsBeingRescued - 是否正在被救援 ====
function ENT:IsBeingRescued()
	return self:GetRescuer():IsValid()
end

-- ==== SetRescueProgress - 设置救援读条进度（0~1） ====
function ENT:SetRescueProgress(p)
	self:SetDTFloat(2, p)
end

-- ==== GetRescueProgress - 读取救援读条进度 ====
function ENT:GetRescueProgress()
	return self:GetDTFloat(2)
end
