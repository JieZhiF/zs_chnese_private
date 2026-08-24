-- cl_camera.lua
-- 镜头层：应用武器镜头后坐力 —— ARC9 风格弹簧-阻尼体系
-- [架构] sh_recoil 开火时注入弹簧速度（CamRecoilAngVel/RollVel），此处做
-- Verlet 积分：拖曳 + 回复 + 阻尼，射击瞬间弹跳、随后自然回稳（无目标值追赶）。
-- FOV 冲击为独立半隐式欧拉弹簧。

local math_min = math.min

-- [Angle 无 Length 方法] GMod 角度元表不含 Length（与 cl_viewmodel 同款处理）
local function AngLen(a)
	return math.sqrt(a.p * a.p + a.y * a.y + a.r * a.r)
end

-- [弹簧字段类型守卫] 与 cl_viewmodel 同款：字段被外部污染时自愈并一次性告警
local function GuardField(wep, key, isok, maker)
	local v = wep[key]
	if v == nil or isok(v) then return v or maker() end

	if not wep.m_RecoilFieldWarned then
		wep.m_RecoilFieldWarned = true
		local keys = {}
		if istable(v) then
			for k in pairs(v) do
				keys[#keys + 1] = tostring(k)
				if #keys >= 6 then break end
			end
		end
		ErrorNoHalt(string.format(
			"[ZS Recoil] %s 的 %s 字段被外部污染(type=%s, keys=[%s])，已自动重置——请将本行反馈给开发者定位污染源\n",
			wep:GetClass(), key, type(v), table.concat(keys, " ")))
	end
	return maker()
end

function SWEP:CalcView(ply, pos, ang, fov)
	local ft = FrameTime()
	if ft <= 0 or ft > 0.1 then return end

	-- [FOV 弹簧] 半隐式欧拉积分：射击瞬间收缩，随后回弹稳定
	self.CamFOVOffset = self.CamFOVOffset or 0
	self.CamFOV_Vel = self.CamFOV_Vel or 0

	local stiffness = self.CamRecoilFOVStiffness or 200
	local damping = self.CamRecoilFOVDamping or 12

	self.CamFOV_Vel = self.CamFOV_Vel + (-self.CamFOVOffset * stiffness - self.CamFOV_Vel * damping) * ft
	self.CamFOVOffset = self.CamFOVOffset + self.CamFOV_Vel * ft

	-- [MAGIC 限幅] 与枪模弹簧同源：帧率自适应收紧，极端卡顿钳到 0.1
	local magic
	if ft > 0.09 then magic = 0.1 else magic = math_min(210, 210 / (ft / 0.015)) end

	-- [镜头角度弹跳] Verlet 积分（ARC9 ThinkVisualRecoil 同式）
	local k = self.CamRecoilStiffness or 90
	local m = self.CamRecoilSpringMagnitude or 1
	local d = self.CamRecoilDamping or 8

	local cam = GuardField(self, "CamRecoilCurrent", isangle, Angle)
	local vel = GuardField(self, "CamRecoilAngVel", isangle, Angle)
	local acc = GuardField(self, "CamRecoilAngAcc", isangle, Angle)

	cam = cam + vel * ft + acc * ft * ft * 0.5
	local drag = -(vel * AngLen(vel) * 0.5)
	local clen = math.max(AngLen(cam), 0.0001)
	local ret = (-cam * AngLen(cam) * k) + (-cam / clen * m) + (-vel * d)
	local nacc = drag + ret
	vel = vel + ((acc + nacc) * (ft * 0.5))
	for i = 1, 3 do
		cam[i] = math.Clamp(cam[i], -magic, magic)
		vel[i] = math.Clamp(vel[i], -magic, magic)
		nacc[i] = math.Clamp(nacc[i], -magic, magic)
	end

	self.CamRecoilCurrent = cam
	self.CamRecoilAngVel = vel
	self.CamRecoilAngAcc = nacc

	-- [滚转] 单轴弹簧
	local roll = self.CamRecoilRollVal or 0
	local rvel = self.CamRecoilRollVel or 0
	local racc = self.CamRecoilRollAcc or 0

	roll = roll + rvel * ft + racc * ft * ft * 0.5
	local rdrag = -(rvel * math.abs(rvel) * 0.5)
	local rlen = math.max(math.abs(roll), 0.0001)
	local rret = (-roll * math.abs(roll) * k) + (-roll / rlen * m * 2) + (-rvel * d)
	local rnacc = rdrag + rret
	rvel = rvel + ((racc + rnacc) * (ft * 0.5))
	roll = math.Clamp(roll, -magic, magic)

	self.CamRecoilRollVal = roll
	self.CamRecoilRollVel = rvel
	self.CamRecoilRollAcc = rnacc

	-- [应用] 角度弹跳 + 滚转叠加到本帧视角
	local outang = Angle(ang.p, ang.y, ang.r)
	outang.p = outang.p + cam.p
	outang.y = outang.y + cam.y
	outang.roll = outang.roll + roll

	return pos, outang, fov + self.CamFOVOffset
end
