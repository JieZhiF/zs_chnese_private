-- ============================================================================
-- weapon_zs_base/cl_viewik.lua - 第一人称视模型手部 IK（ARC9 LHIK/RHIK 对应物）
--
-- [定位] 与第三人称 TPIK（gamemode/cl_tpik.lua）互补：本文件只处理视模型。
--
-- [默认惰性] 未声明 SWEP.ViewIK 的武器零开销零行为变化。
--            SWEP.NoViewIK = true 一票否决（骨骼命名不一致武器的逃生口）。
-- [为何 opt-in] 视模型骨骼命名抽样结论：CS:S c_model 系（v_weapon.*_Parent）、
--            HL2 系（ValveBiped.Gun/base）、自定义名三派并存，
--            无法全量自动启用，必须逐把武器校准后声明配置。
--
-- 武器配置示例（全部字段可选）：
--   SWEP.ViewIK = {
--       -- RHIK 枪身运动补偿：IK 时间窗内右手/枪身骨骼偏离静止基准时整枪平移跟随，
--       -- 消除"换弹/开火动画手滑离枪"（ARC9 IKGunMotion 的渲染层简化版）
--       right = { bone = "v_weapon.MP5_Parent", strength = 0.8 },
--       -- LHIK 左手跟随：时间窗内左手骨骼向目标点位置牵引（简化版：
--       -- 位置插值而非二骨余弦解算；目标为视模型局部空间坐标）
--       left = { bone = "ValveBiped.Bip01_L_Hand",
--                target = function(wep, vm) return Vector(10, -4, -6) end,
--                strength = 0.6 },
--   }
-- 补偿窗口由动画条目 IKTimeLine=true 声明（sh_anim.lua PlayAnimation 记录窗口）。
-- ============================================================================

local CurTime = CurTime
local math_Clamp = math.Clamp

-- ==== IsViewIKEnabled - 总门控 ====
function SWEP:IsViewIKEnabled()
	return self.ViewIK ~= nil and not self.NoViewIK
end

-- ==== CalcViewIKOffset - [RHIK] 整枪平移补偿量 ====
-- 在 CalcViewModelView 其余变换全部应用后调用；
-- 返回视模型渲染位移增量（世界向量），无补偿时返回 nil。
local function GetBoneWorldPos(vm, bonename)
	local idx = vm:LookupBone(bonename)
	if not idx then return nil end
	local mat = vm:GetBoneMatrix(idx)
	return mat and mat:GetTranslation() or nil
end

function SWEP:CalcViewIKOffset(vm, ang)
	local cfg = self.ViewIK
	local rcfg = cfg and cfg.right
	if not rcfg or not isstring(rcfg.bone) then return end

	local in_window = self.m_IKTimeStart and CurTime() < self.m_IKTimeStart + (self.m_IKTimeDur or 0)

	if not in_window then
		-- 窗口外持续记录静止位置：动画开始的瞬间基准总是新鲜的
		self.m_IKRestPos = GetBoneWorldPos(vm, rcfg.bone)
		self.m_IKRefCaptured = false
		return
	end

	-- 首帧仅捕获基准不补偿：避免把动画起始帧与静止基准的固有差当成位移
	if not self.m_IKRefCaptured then
		self.m_IKRefPos = GetBoneWorldPos(vm, rcfg.bone)
		self.m_IKRefCaptured = true
		return
	end

	local cur = GetBoneWorldPos(vm, rcfg.bone)
	local ref = self.m_IKRefPos or self.m_IKRestPos
	if not cur or not ref then return end

	local delta = cur - ref
	if delta:IsZero() then return end

	-- 世界位移投影到视模型姿态轴系（ang 为当前帧视模型渲染角度）
	local strength = rcfg.strength or 1
	return (ang:Right() * delta.x + ang:Forward() * delta.y + ang:Up() * delta.z) * strength
end

-- ==== ApplyLeftHandIK - [LHIK] 左手骨骼牵引 ====
-- 在 cl_model.lua Anim_ViewModelDrawn 的 UpdateBonePositions 之后调用
-- （与 SCK 骨骼修改同一管线，保证矩阵改动进入本帧渲染）。
-- 子骨骼连带平移保持手指相对手掌的姿态（cl_tpik 同款思路的位置简化版）。
local function ShiftChildren(vm, boneidx, delta_world)
	for _, cid in ipairs(vm:GetChildBones(boneidx)) do
		local cm = vm:GetBoneMatrix(cid)
		if cm then
			cm:SetTranslation(cm:GetTranslation() + delta_world)
			vm:SetBoneMatrix(cid, cm)
			ShiftChildren(vm, cid, delta_world)
		end
	end
end

function SWEP:ApplyLeftHandIK(vm)
	local cfg = self.ViewIK
	if not cfg or not cfg.left then return end

	-- 仅在 IK 时间轴窗口内生效
	local start_t = self.m_IKTimeStart
	if not start_t then return end
	local dur = self.m_IKTimeDur or 0
	local elapsed = CurTime() - start_t
	if elapsed < 0 or elapsed > dur then return end

	local lcfg = cfg.left

	-- 强度包络：前/后各 fade 段线性进出（默认 25% 时长），中段满强度
	local fade = math.max((lcfg.fade or 0.25) * dur, 0.001)
	local blend = math.min(elapsed / fade, 1, math.max(dur - elapsed, 0) / fade)
	blend = math_Clamp(blend, 0, 1) * (lcfg.strength or 1)
	if blend <= 0 then return end

	-- 目标解析：函数形式每帧求值（可读动画状态），常量为视模型局部空间坐标
	local target = lcfg.target
	if isfunction(target) then target = target(self, vm) end
	if not isvector(target) then return end

	if not isstring(lcfg.bone) then return end
	local goal = vm:LocalToWorld(target)
	local hmat_idx = vm:LookupBone(lcfg.bone)
	if not hmat_idx then return end

	local hmat = vm:GetBoneMatrix(hmat_idx)
	if not hmat then return end

	local cur = hmat:GetTranslation()
	local shifted = cur + (goal - cur) * blend
	local delta_world = shifted - cur
	if delta_world:IsZero() then return end

	hmat:SetTranslation(shifted)
	vm:SetBoneMatrix(hmat_idx, hmat)
	ShiftChildren(vm, hmat_idx, delta_world)
end
