-- ============================================================================
-- zs_tracer.lua - 曳光弹效果（ARC9 arc9_tracer 的 ZS 去耦适配版）
-- 来源：addons/arc9_weapon_base/lua/effects/arc9_tracer.lua
-- 改动：移除 wep.ARC9 门禁与 GetProcessedValue 依赖（改读 SWEP.TracerColor /
--       SWEP.TracerSize / SWEP.TracerSpeed 直通字段）；起点优先武器基座的
--       GetTracerOrigin（QCA→引擎附件→眼位三级解析）；忽略引擎 Scale 字段。
-- 接入：SWEP.TracerName = "zs_tracer"（weapon_zs_base/shared.lua 已设为默认）。
-- ============================================================================

EFFECT.StartPos = Vector(0, 0, 0)
EFFECT.EndPos = Vector(0, 0, 0)
EFFECT.StartTime = 0
EFFECT.LifeTime = 0.2
EFFECT.LifeTime2 = 0.2
EFFECT.DieTime = 0
EFFECT.Color = Color(255, 255, 255)
EFFECT.Speed = 15000
EFFECT.Size = 1

local head = Material("effects/whiteflare")
local tracer = Material("arc9/tracer")
local smoke = Material("effects/fas_smoke_beam")
local smoker, smoked = Color(155, 155, 155, 155), Color(155, 155, 155, 0)

function EFFECT:Init(data)
	local hit = data:GetOrigin()
	local wep = data:GetEntity()

	if not IsValid(wep) then return end

	-- 起点：武器实体优先走基座锚点解析（防御非 Vector 返回），非武器实体
	-- （引擎可能传玩家）回退引擎传入的枪口点
	if wep.GetTracerOrigin then
		local o = wep:GetTracerOrigin()
		if isvector(o) then self.StartPos = o end
	end
	if not isvector(self.StartPos) then
		self.StartPos = data:GetStart()
	end
	local start = self.StartPos

	local diff = hit - start
	self.Dir = diff:GetNormalized()

	-- 弹着点方向上做一次快速检测，命中天空盒时把终点外推，曳光穿入天空（ARC9 同款）
	local hitt = util.QuickTrace(hit, self.Dir)
	self.EndPos = hitt.HitPos
	if hitt.HitSky then
		hit = start + self.Dir * 32768
		self.EndPos = hit
	end

	self.Speed = wep.TracerSpeed or self.Speed

	self.LifeTime = (hit - start):Length() / self.Speed
	self.StartTime = UnPredictedCurTime()
	self.DieTime = UnPredictedCurTime() + math.max(self.LifeTime, self.LifeTime2)

	-- 武器可直通覆写视觉参数
	self.Color = wep.TracerColor or self.Color
	self.Size = wep.TracerSize or self.Size

	self.Weapon = wep
end

function EFFECT:Think()
	return self.DieTime > UnPredictedCurTime()
end

local Lerp = Lerp
local function LerpColor(d, col1, col2)
	local r = Lerp(d, col1.r, col2.r)
	local g = Lerp(d, col1.g, col2.g)
	local b = Lerp(d, col1.b, col2.b)
	local a = Lerp(d, col1.a, col2.a)
	return Color(r, g, b, a)
end

function EFFECT:Render()
	if self.Cancelled or (IsValid(self.Weapon) and self.Weapon.TracerCancelled) then self.Cancelled = true return end
	if not self.Dir then self.Cancelled = true return end

	local d = (UnPredictedCurTime() - self.StartTime) / self.LifeTime
	local d2 = (UnPredictedCurTime() - self.StartTime) / self.LifeTime2
	local startpos = self.StartPos + (d * 0.1 * (self.EndPos - self.StartPos))
	local endpos = self.StartPos + (d * (self.EndPos - self.StartPos))
	local size = self.Size * math.Clamp(math.log(EyePos():DistToSqr(endpos) - math.pow(256, 2)), 0, math.huge)

	local col = self.Color
	local col2 = LerpColor(d2, smoker, smoked)

	-- 光斑头：视线与弹道夹角越小越大（模拟过曝星芒）
	local vel = self.Dir * self.Speed - LocalPlayer():GetVelocity()
	local dot = math.abs(EyeAngles():Forward():Dot(vel:GetNormalized()))
	local headsize = size * dot * 2

	render.SetMaterial(head)
	render.DrawSprite(endpos, headsize, headsize, col)

	-- 高亮短尾迹 + 渐消烟带（后段随时间淡出）
	local tail = self.Dir * math.min(self.Speed / 25, 512, (endpos - startpos):Length() - 64)
	render.SetMaterial(tracer)
	render.DrawBeam(endpos, endpos - tail, size * 0.75, 1, 0, col)

	render.SetMaterial(smoke)
	render.DrawBeam(endpos - tail, startpos, size * d2, 0, 1, col2)
end
