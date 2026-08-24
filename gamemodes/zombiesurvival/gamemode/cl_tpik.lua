-- ============================================================
-- cl_tpik.lua - 第三人称逆向运动学（TPIK，Third Person Inverse Kinematics）
--
-- 移植自 ARC9 武器基座 lua/weapons/arc9_base/cl_tpik.lua（优化与 tween：Onge.org；
-- 两段式余弦定理解算 Solve2PartIK：AWholeCream，经许可使用）。
--
-- [区域] 镜像世界模型管理
-- [位置] GetMirror() / SyncMirrorAppearance()
-- [作用] 为持枪人类玩家创建与引擎世界模型同模型的客户端镜像，
--        EF_BONEMERGE 合并到玩家，位置与原生第三人称完全一致
-- [常改] RENDERGROUP、同步字段（皮肤/身体组/序列）
--
-- [区域] 解算器
-- [位置] ZSTPIK.DoTPIK()
-- [作用] 从镜像读取手部/手指骨骼矩阵直拷回玩家骨骼（ARC9 同款 ±38 钳制），
--        再用 Solve2PartIK 余弦定理解算肘关节角度；tween 平滑 + 降频节流
-- [常改] NOLEFTHAND_HOLDTYPES 左手豁免列表、HEAD_AIM_ANGLE 头部微调角
--
-- [区域] 入口与接入点
-- [位置] hook "PrePlayerDraw"（ZSTPIK_PrePlayerDraw）；
--        weapon_zs_base/cl_model.lua 的 DrawWorldModel 调用 ZSTPIK.DrawMirror
-- [作用] 每玩家每帧去重后解算；镜像代替引擎世界模型参与第三人称绘制
-- [常改] 节流 ConVar 默认值（zs_tpik_framerate_local / _others / zs_tpik_distance）
--
-- 与 ARC9 的差异：
--   1. ARC9 世界模型是自绘 CSModel（slottbl 手动定位），ZS 改用 bonemerge
--      镜像——枪的指向仍由引擎 holdtype 动画驱动，无需逐把武器校准偏移；
--   2. GetSightAmount → GetIronsightDelta（ZS 基座现成的开镜进度）；
--   3. 序列/循环直接从网络化武器实体同步（ARC9 用自有网络字段）；
--   4. 省略 ARC9 专属子系统：HelperBone 补丁、PoseLayer API、DoRHIK、
--      贴墙/窥探偏移。
-- 单武器逃生口：SWEP.NoTPIK = true。
--   5. 新增上身俯仰追踪层（zs_tpik_spinepitch）：ZS 的第三人称持枪姿态由
--      holdtype 活动（ACT_HL2MP_* 系列）驱动，俯仰表现力极差且无法像 ARC9
--      那样用每武器 TPIKPosSightOffset 直接把枪挪到眼前；改为开镜时按
--      视线俯仰角偏转 Spine2，带动合并的枪一起抬向视轴。
--   6. 双模式支持（ARC9 同款）：武器定义 SWEP.WorldModelOffset 时，镜像放弃
--      bonemerge 改为手动锚定——默认锚在玩家 R_Hand 骨骼（TPIKParentToSpine4
--      可改锚 Spine4），坐标采用 ARC9 的 Y 取反 + 错轴角度映射；开镜时叠加
--      TPIKPosSightOffset 把枪抬到眼前。未定义该表的武器维持 bonemerge。
--      示例：
--      SWEP.WorldModelOffset = {
--          Pos = Vector(-5.5, 3, -6), Ang = Angle(0, 0, 180),
--          TPIKPos = Vector(-8, 2, -5), TPIKAng = Angle(-12, 0, 180),
--          Scale = 1,
--          TPIKPosSightOffset = Vector(-1, 3, -2),
--          TPIKHolsterOffset = Vector(4, 0, -1),
--      }
--      可选 SWEP.WorldModelMirror = "模型路径" 覆盖第三人称模型。
-- ============================================================

-- 全局模块表：weapon_zs_base/cl_model.lua 通过 ZSTPIK.DrawMirror 接入；
-- 必须在任何 ZSTPIK.xxx 方法定义之前初始化
ZSTPIK = ZSTPIK or {}

local cv_TPIK = CreateClientConVar("zs_tpik", "1", true, false, "启用第三人称持枪逆向运动学（TPIK）")
local cv_Others = CreateClientConVar("zs_tpik_others", "1", true, false, "对其他玩家应用 TPIK")
local cv_FPSLocal = CreateClientConVar("zs_tpik_framerate_local", "60", true, false, "本地玩家的 TPIK 解算频率上限", 10, 150)
local cv_FPSOthers = CreateClientConVar("zs_tpik_framerate_others", "20", true, false, "其他玩家的 TPIK 解算频率上限", 5, 150)
local cv_Distance = CreateClientConVar("zs_tpik_distance", "2500", true, false, "超出该距离的其他玩家跳过 TPIK（0 为不限制）")
local cv_Debug = CreateClientConVar("zs_tpik_debug", "0", true, false, "绘制 TPIK 手臂 IK 链调试线（需 developer 1 才可见）")
local cv_SpinePitch = CreateClientConVar("zs_tpik_spinepitch", "1", true, false, "开镜时上身俯仰追踪视线，带动第三人称的枪抬向视轴")

local math_Clamp = math.Clamp
local math_Deg = math.deg
local math_ACos = math.acos
local math_ATan2 = math.atan2
local math_Sqrt = math.sqrt
local math_Exp = math.exp
local math_NormalizeAngle = math.NormalizeAngle
local RealFrameTime = RealFrameTime
local CurTime = CurTime
local FrameNumber = FrameNumber
local EyePos = EyePos
local LocalPlayer = LocalPlayer
local WorldToLocal = WorldToLocal
local LocalToWorld = LocalToWorld

local ENTITY = FindMetaTable("Entity")
local Entity_GetBoneMatrix = ENTITY.GetBoneMatrix
local Entity_SetBoneMatrix = ENTITY.SetBoneMatrix

-- ARC9.TPIKBones 原表：双手 + 全部手指（腕/尺骨刻意排除，见 ARC9 注释）
local TPIKBONES = {
	"ValveBiped.Bip01_L_Hand",
	"ValveBiped.Bip01_L_Finger4",
	"ValveBiped.Bip01_L_Finger41",
	"ValveBiped.Bip01_L_Finger42",
	"ValveBiped.Bip01_L_Finger3",
	"ValveBiped.Bip01_L_Finger31",
	"ValveBiped.Bip01_L_Finger32",
	"ValveBiped.Bip01_L_Finger2",
	"ValveBiped.Bip01_L_Finger21",
	"ValveBiped.Bip01_L_Finger22",
	"ValveBiped.Bip01_L_Finger1",
	"ValveBiped.Bip01_L_Finger11",
	"ValveBiped.Bip01_L_Finger12",
	"ValveBiped.Bip01_L_Finger0",
	"ValveBiped.Bip01_L_Finger01",
	"ValveBiped.Bip01_L_Finger02",
	"ValveBiped.Bip01_R_Hand",
	"ValveBiped.Bip01_R_Finger4",
	"ValveBiped.Bip01_R_Finger41",
	"ValveBiped.Bip01_R_Finger42",
	"ValveBiped.Bip01_R_Finger3",
	"ValveBiped.Bip01_R_Finger31",
	"ValveBiped.Bip01_R_Finger32",
	"ValveBiped.Bip01_R_Finger2",
	"ValveBiped.Bip01_R_Finger21",
	"ValveBiped.Bip01_R_Finger22",
	"ValveBiped.Bip01_R_Finger1",
	"ValveBiped.Bip01_R_Finger11",
	"ValveBiped.Bip01_R_Finger12",
	"ValveBiped.Bip01_R_Finger0",
	"ValveBiped.Bip01_R_Finger01",
	"ValveBiped.Bip01_R_Finger02"
}

-- ARC9.RHIKHandBones 原表：单手模式（左手豁免时只处理右手链，含腕/尺骨）
local TPIKBONES_NOLEFT = {
	"ValveBiped.Bip01_R_Wrist",
	"ValveBiped.Bip01_R_Ulna",
	"ValveBiped.Bip01_R_Hand",
	"ValveBiped.Bip01_R_Finger4",
	"ValveBiped.Bip01_R_Finger41",
	"ValveBiped.Bip01_R_Finger42",
	"ValveBiped.Bip01_R_Finger3",
	"ValveBiped.Bip01_R_Finger31",
	"ValveBiped.Bip01_R_Finger32",
	"ValveBiped.Bip01_R_Finger2",
	"ValveBiped.Bip01_R_Finger21",
	"ValveBiped.Bip01_R_Finger22",
	"ValveBiped.Bip01_R_Finger1",
	"ValveBiped.Bip01_R_Finger11",
	"ValveBiped.Bip01_R_Finger12",
	"ValveBiped.Bip01_R_Finger0",
	"ValveBiped.Bip01_R_Finger01",
	"ValveBiped.Bip01_R_Finger02"
}

-- 这些持枪姿势的世界模型没有可信的左手握点（ARC9 列表 + ZS 的近战类）
local NOLEFTHAND_HOLDTYPES = {
	pistol = true,
	revolver = true,
	normal = true,
	passive = true,
	slam = true,
	magic = true,
	melee = true,
	melee2 = true,
	fist = true,
	duel = true
}

-- 开镜时的头部微调角（ARC9 固定值），乘以开镜进度后叠加
local HEAD_AIM_ANGLE = Angle(5, -15, 15)

-- 调试线颜色：右臂红 / 左臂青（zs_tpik_debug 1 时绘制）
local DEBUG_COLOR_RIGHT = Color(255, 80, 80)
local DEBUG_COLOR_LEFT = Color(80, 220, 220)

-- 上身俯仰追踪：视线俯仰角 × SPINE_PITCH_SCALE × 开镜进度，结果钳制在 ±MAX 度
local SPINE_PITCH_SCALE = 0.5
local SPINE_PITCH_MAX = 25

-- 直拷骨骼位置的安全半径：偏离脊柱锚点超过该值视为解算异常，强制钳制
local BONE_CLAMP_RADIUS = 38

-- 四肢默认长度兜底值（单位）：BoneLength 取不到时使用
local DEFAULT_LIMB_LENGTH = 12

local vector_up = Vector(0, 0, 1)

-- ------------------------------------------------------------
-- 二骨 IK：余弦定理解算肘关节（AWholeCream 原作，ARC9 sh_util.lua 移植）
-- start_p 肩点，end_p 手点，length0 上臂长，length1 前臂长，
-- sign 弯曲方向符号（右臂 -1.3 / 左臂 1），angs 眼睛角度（防鸡翼用）
-- 返回：肘位置、手位置、上臂角、前臂角
-- ------------------------------------------------------------
local function Solve2PartIK(start_p, end_p, length0, length1, sign, angs)
	local diff = end_p - start_p
	local length2 = diff:Length()
	-- 手与肩重合等退化情况无法解算，交由调用方跳过本帧
	if length2 < 0.001 then return nil end

	local cosAngle0 = math_Clamp((length2 * length2 + length0 * length0 - length1 * length1) / (2 * length2 * length0), -1, 1)
	local angle0 = -math_Deg(math_ACos(cosAngle0))
	local cosAngle1 = math_Clamp((length1 * length1 + length0 * length0 - length2 * length2) / (2 * length1 * length0), -1, 1)
	local angle1 = -math_Deg(math_ACos(cosAngle1))

	diff:Normalize()

	local angle2 = math_Deg(math_ATan2(-math_Sqrt(diff.x * diff.x + diff.y * diff.y), diff.z)) - 90
	local angle3 = -math_Deg(math_ATan2(diff.x, diff.y)) - 90
	angle3 = math_NormalizeAngle(angle3)

	local axis = diff

	local diffa2 = 90 + (sign > 0 and -30 or 30)
	local torsoright = angs.y + 120 * sign

	local joint0ang = Angle(angle0 + angle2, angle3, 0)
	joint0ang:RotateAroundAxis(joint0ang:Forward(), diffa2)
	joint0ang:RotateAroundAxis(axis, angle3 - torsoright)
	local ang1 = Angle(joint0ang.p, joint0ang.y, joint0ang.r)

	local joint0vec = joint0ang:Forward() * length0

	local joint1ang = Angle(angle0 + angle2 + 180 + angle1, angle3, 0)
	joint1ang:RotateAroundAxis(joint1ang:Forward(), diffa2)
	joint1ang:RotateAroundAxis(axis, angle3 - torsoright)
	local ang2 = Angle(joint1ang.p, joint1ang.y, joint1ang.r)

	local joint1vec = joint1ang:Forward() * length1

	return start_p + joint0vec, start_p + joint0vec + joint1vec, ang1, ang2
end

-- 骨骼名 → 索引缓存（按实体弱引用，模型变更自动失效）
local BoneIndexCache = setmetatable({}, { __mode = "k" })
local function GetCachedBoneIndex(ent, boneName)
	if not IsValid(ent) or not boneName then return nil end
	local mdl = ent:GetModel() or ""
	local cache = BoneIndexCache[ent]
	if not cache or cache.mdl ~= mdl then
		cache = { mdl = mdl, bones = {} }
		BoneIndexCache[ent] = cache
	end

	local cached = cache.bones[boneName]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end

	local idx = ent:LookupBone(boneName)
	cache.bones[boneName] = idx or false
	return idx
end

-- 子骨骼收集（按模型字符串缓存一次，ARC9 同款 evil recursive children hack）
local ChildrenCache = {}

local function RecursiveGetChildren(ent, bone, bones, endbone)
	if bone == endbone then return end

	local children = ent:GetChildBones(bone)
	for i = 1, #children do
		local id = children[i]
		if id ~= endbone then
			RecursiveGetChildren(ent, id, bones, endbone)
			bones[#bones + 1] = id
		end
	end
end

local function GetChildBonesCached(ent, bone, endbone)
	local mdl = ent:GetModel() or ""
	local modelCache = ChildrenCache[mdl]
	if not modelCache then
		modelCache = {}
		ChildrenCache[mdl] = modelCache
	end

	local key = tostring(bone) .. ":" .. tostring(endbone or "")
	local cached = modelCache[key]
	if cached then return cached end

	local bones = {}
	RecursiveGetChildren(ent, bone, bones, endbone)
	modelCache[key] = bones

	return bones
end

-- 写入骨骼矩阵并连带平移全部子骨骼（保持手指跟随手掌等层级关系）
local function ApplyBoneMatrix(ent, bone, new_matrix, endbone)
	if not bone or bone == -1 then return end

	local matrix = Entity_GetBoneMatrix(ent, bone)
	if not matrix then return end
	local inv_matrix = matrix:GetInverse()
	if not inv_matrix then return end

	local children = GetChildBonesCached(ent, bone, endbone)

	local translate = new_matrix * inv_matrix
	for i = 1, #children do
		local id = children[i]
		local mat = Entity_GetBoneMatrix(ent, id)
		if mat then
			Entity_SetBoneMatrix(ent, id, translate * mat)
		end
	end

	Entity_SetBoneMatrix(ent, bone, new_matrix)
end

-- 头部子骨骼数缓存（大于 1 说明模型头上有挂件骨骼，不做微调以免拉扯挂件）
local HeadChildCache = setmetatable({}, { __mode = "k" })
local function GetHeadChildCount(ply, headIndex)
	if not headIndex then return 99 end
	local mdl = ply:GetModel() or ""
	local cache = HeadChildCache[ply]
	if not cache or cache.mdl ~= mdl or cache.headIndex ~= headIndex then
		local children = ply:GetChildBones(headIndex)
		cache = { mdl = mdl, headIndex = headIndex, count = children and #children or 0 }
		HeadChildCache[ply] = cache
	end
	return cache.count or 0
end

-- 上臂/前臂长度缓存（按玩家模型）
local LimbLengthCache = {}
local function GetLimbLength(ply)
	local mdl = ply:GetModel() or ""
	local cached = LimbLengthCache[mdl]
	if cached then return cached end

	local idx = ply:LookupBone("ValveBiped.Bip01_L_Forearm")
	local len = (idx and ply:BoneLength(idx)) or 0
	if not len or len <= 0 then len = DEFAULT_LIMB_LENGTH end
	LimbLengthCache[mdl] = len

	return len
end

-- ------------------------------------------------------------
-- tween 平滑（Onge.org 优化：帧率无关指数收敛 + 目标未变时零开销）
-- ------------------------------------------------------------
local TPIK_EPS = 0.0001

local function TweenAlpha(speed)
	speed = math_Clamp(speed * 1.5, 1, 60)
	return math_Clamp(1 - math_Exp(-speed * RealFrameTime()), 0, 1)
end

local function VecAlmostEqual(a, b)
	return a and b
		and math.abs(a.x - b.x) <= TPIK_EPS
		and math.abs(a.y - b.y) <= TPIK_EPS
		and math.abs(a.z - b.z) <= TPIK_EPS
end

local function AngAlmostEqual(a, b)
	return a and b
		and math.abs(a.p - b.p) <= TPIK_EPS
		and math.abs(a.y - b.y) <= TPIK_EPS
		and math.abs(a.r - b.r) <= TPIK_EPS
end

local function TweenVec(cache, key, target, alpha)
	local current = cache[key]
	if not current then
		current = Vector(target.x, target.y, target.z)
		cache[key] = current
		return current
	end

	if VecAlmostEqual(current, target) then return current end
	if alpha >= 1 then
		current.x = target.x
		current.y = target.y
		current.z = target.z
		return current
	end

	current.x = current.x + (target.x - current.x) * alpha
	current.y = current.y + (target.y - current.y) * alpha
	current.z = current.z + (target.z - current.z) * alpha

	return current
end

local function TweenAng(cache, key, target, alpha)
	if not target then return target end

	local current = cache[key]
	if not current then
		current = Angle(target.p, target.y, target.r)
		cache[key] = current
		return current
	end

	if AngAlmostEqual(current, target) then return current end
	if alpha >= 1 then
		current.p = target.p
		current.y = target.y
		current.r = target.r
		return current
	end

	current.p = current.p + math.AngleDifference(target.p, current.p) * alpha
	current.y = current.y + math.AngleDifference(target.y, current.y) * alpha
	current.r = current.r + math.AngleDifference(target.r, current.r) * alpha

	return current
end

-- ------------------------------------------------------------
-- 镜像世界模型管理
-- ------------------------------------------------------------
-- 世界模型是否具备 ValveBiped 手部骨架（决定该武器能否 TPIK，按模型缓存）
local ModelHasGripCache = {}
local function WorldModelHasGrip(wep)
	local mdl = wep:GetModel() or ""
	if mdl == "" then return false end

	local cached = ModelHasGripCache[mdl]
	if cached == nil then
		cached = wep:LookupBone("ValveBiped.Bip01_R_Hand") ~= nil
		ModelHasGripCache[mdl] = cached
	end

	return cached
end

-- 取或建镜像：默认与引擎世界模型同模型 bonemerge 到玩家身上；
-- 定义 WorldModelOffset 的武器走手动锚定（不合并、不挂父级，逐帧绝对摆位）
local function GetMirror(wep, ply)
	local mirror = wep.ZS_TPIK_Mirror
	local mdl = wep.WorldModelMirror or wep:GetModel()
	local manual = wep.WorldModelOffset ~= nil

	if IsValid(mirror) and mirror.ZS_Model == mdl and mirror.ZS_Manual == manual and mirror:GetParent() == ply then
		return mirror
	end

	if IsValid(mirror) then
		mirror:Remove()
	end

	mirror = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
	if not IsValid(mirror) then
		wep.ZS_TPIK_Mirror = nil
		return nil
	end

	if not manual then
		mirror:SetPos(ply:GetPos())
		mirror:SetAngles(ply:GetAngles())
		mirror:SetParent(ply)
		mirror:AddEffects(EF_BONEMERGE)
	else
		-- 手动锚定模式不能挂父级：SetParent 会把 SetPos 改写为局部坐标语义
	end
	mirror:SetNoDraw(true) -- 只在 DrawWorldModel 里手动绘制，避免重复绘制
	mirror:SetPlaybackRate(0) -- 循环进度完全由武器实体驱动
	mirror.ZS_Model = mdl
	mirror.ZS_Manual = manual
	wep.ZS_TPIK_Mirror = mirror

	return mirror
end

-- 外观同步：皮肤与身体组跟随武器实体（序列/循环在 DoTPIK 完整更新中同步）
local function SyncMirrorAppearance(wep, mirror)
	local skin = wep:GetSkin()
	if mirror:GetSkin() ~= skin then
		mirror:SetSkin(skin)
	end

	for i = 0, mirror:GetNumBodyGroups() - 1 do
		local bg = wep:GetBodygroup(i)
		if mirror:GetBodygroup(i) ~= bg then
			mirror:SetBodygroup(i, bg)
		end
	end
end

-- ------------------------------------------------------------
-- 手动锚定（ARC9 WorldModelOffset 模式）
-- 锚点骨骼：默认 R_Hand；SWEP.TPIKParentToSpine4 = true 且 TPIK 生效时锚 Spine4。
-- 坐标换算与 ARC9 GetAttachmentPos 完全一致：
--   位置 = LocalToWorld(偏移量 Y 取反 × Scale, 骨骼角, 骨骼位, 骨骼角)
--   角度 = 骨骼角依次绕 forward×Ang.r / right×Ang.p / up×Ang.y 旋转（错轴映射）
-- TPIK 生效时用 TPIKPos/TPIKAng 并叠加 TPIKPosSightOffset × InOutCubic(开镜进度)，
-- 否则回退 Pos/Ang。
-- ------------------------------------------------------------
local function ComputeManualPlacement(wep, ply)
	local wo = wep.WorldModelOffset
	if not wo then return nil end

	local tpik = ZSTPIK.ShouldTPIK(wep, ply)
	local bonename = (tpik and wep.TPIKParentToSpine4) and "ValveBiped.Bip01_Spine4" or "ValveBiped.Bip01_R_Hand"
	local idx = GetCachedBoneIndex(ply, bonename)
	if not idx then return nil end

	ply:SetupBones()
	ply:InvalidateBoneCache() -- ARC9 同款：确保读到本帧最新骨骼矩阵

	local bonemat = Entity_GetBoneMatrix(ply, idx)
	if not bonemat then return nil end
	local bpos, bang = bonemat:GetTranslation(), bonemat:GetAngles()

	local pos, ang
	if tpik then
		pos = wo.TPIKPos or wo.Pos or vector_origin
		ang = wo.TPIKAng or wo.Ang or angle_zero

		if wo.TPIKPosSightOffset then
			local sd = 0
			if wep.GetIronsightDelta then
				sd = math_Clamp(wep:GetIronsightDelta() or 0, 0, 1)
			end
			if sd > 0 then
				pos = pos + wo.TPIKPosSightOffset * math.ease.InOutCubic(sd)
			end
		end
	else
		pos = wo.Pos or vector_origin
		ang = wo.Ang or angle_zero
	end

	local apos = LocalToWorld(Vector(pos.x, -pos.y, pos.z) * (wo.Scale or 1), bang, bpos, bang)

	local aang = Angle(bang.p, bang.y, bang.r)
	aang:RotateAroundAxis(aang:Forward(), ang.r)
	aang:RotateAroundAxis(aang:Right(), ang.p)
	aang:RotateAroundAxis(aang:Up(), ang.y)

	return apos, aang
end

-- ------------------------------------------------------------
-- 门控
-- ------------------------------------------------------------
-- 依次检查各门控条件；返回 是否通过, 失败原因（供 zs_tpik_status 报告）
local function CheckTPIKGates(wep, ply)
	if not IsValid(wep) then return false, "武器无效" end
	if wep.NoTPIK then return false, "SWEP.NoTPIK" end
	if not IsValid(ply) or not ply:IsPlayer() then return false, "非玩家" end
	if not ply:Alive() then return false, "未存活" end
	if ply:Team() ~= TEAM_HUMAN then return false, "非人类阵营" end
	if ply:IsPlayingTaunt() then return false, "嘲讽动作中" end
	if IsValid(ply:GetVehicle()) and not ply:GetAllowWeaponsInVehicle() then return false, "载具中" end
	-- 手动锚定模式的武器由作者数据摆位，不强求世界模型带 ValveBiped 手部骨架
	if not wep.WorldModelOffset and not WorldModelHasGrip(wep) then return false, "世界模型无手部骨架" end

	if ply ~= LocalPlayer() then
		if not cv_Others:GetBool() then return false, "zs_tpik_others 已关闭" end
		local maxdist = cv_Distance:GetFloat()
		if maxdist > 0 and EyePos():DistToSqr(ply:GetPos()) > maxdist * maxdist then return false, "超出 zs_tpik_distance" end
	end

	return true
end

function ZSTPIK.ShouldTPIK(wep, ply)
	return CheckTPIKGates(wep, ply) == true
end

-- 供 weapon_zs_base/cl_model.lua DrawWorldModel 调用：
-- 返回 true 表示镜像已接管本次第三人称绘制（引擎世界模型本次跳过）。
-- 手动锚定模式（定义了 WorldModelOffset）只要 TPIK 总开关开启就接管，
-- 非 TPIK 状态用 Pos/Ang 摆位——与 ARC9 MirrorVMWM 行为一致。
function ZSTPIK.DrawMirror(wep, ply)
	if wep.ShowWorldModel == false then return false end -- SCK 全挂件武器不接管
	if not cv_TPIK:GetBool() then return false end

	local manual = wep.WorldModelOffset ~= nil
	if not manual and not ZSTPIK.ShouldTPIK(wep, ply) then return false end

	local mirror = GetMirror(wep, ply)
	if not mirror then return false end

	SyncMirrorAppearance(wep, mirror)

	if manual then
		local apos, aang = ComputeManualPlacement(wep, ply)
		if not apos then return false end

		mirror:SetPos(apos)
		mirror:SetAngles(aang)
		mirror:SetRenderOrigin(apos) -- ARC9 同款：渲染变换与骨骼变换双写
		mirror:SetRenderAngles(aang)
	end

	mirror:SetupBones()
	mirror:DrawModel()

	return true
end

-- ------------------------------------------------------------
-- 解算器主体（ARC9 DoTPIK 移植）
-- ------------------------------------------------------------
function ZSTPIK.DoTPIK(wep, ply, isdepth)
	local mirror = wep.ZS_TPIK_Mirror
	if not IsValid(mirror) then return end

	-- 节流间隔：完整解算（含镜像动画同步 + IK 重解）按频率限制执行
	local delay
	if ply == LocalPlayer() then
		delay = 1 / math_Clamp(cv_FPSLocal:GetInt() or 60, 10, 150)
	else
		delay = 1 / math_Clamp(cv_FPSOthers:GetInt() or 20, 5, 150)
	end

	local fullupdate = (wep.ZS_TPIK_LastTime or 0) + delay <= CurTime()
	if fullupdate then
		wep.ZS_TPIK_LastTime = CurTime()
	end

	-- 平滑系数：两次完整解算之间仍持续向缓存目标收敛
	local alpha = TweenAlpha(1 / delay)

	local htype = wep:GetHoldType()
	local nolefthand = NOLEFTHAND_HOLDTYPES[htype] == true or wep.TPIKNoLeftHand == true
	if ply:IsTyping() then nolefthand = true end

	-- 完整更新：镜像按武器实体的网络化序列/循环同步动画，随后重建骨骼
	if fullupdate then
		mirror:SetupBones()
		SyncMirrorAppearance(wep, mirror)
		local seq = wep:GetSequence()
		if seq and seq >= 0 then
			mirror:SetSequence(seq)
			mirror:SetCycle(wep:GetCycle())
		end
		mirror:InvalidateBoneCache()
	end

	ply:SetupBones()

	-- 开镜进度：本函数内头部微调与上身俯仰追踪共用
	local sightdelta = 0
	if wep.GetIronsightDelta then
		sightdelta = math_Clamp(wep:GetIronsightDelta() or 0, 0, 1)
	end

	-- 上身俯仰追踪：HL2 活动动画（ACT_HL2MP_* 系列）几乎不表现俯仰，
	-- 开镜时按视线俯仰角偏转 Spine2 并传播到全部子骨骼（手臂/头/枪），
	-- 让合并在上面的枪随躯干抬向视轴。仅 bonemerge 模式需要——手动锚定模式
	-- 的抬枪由 TPIKPosSightOffset 数据直接完成。
	if not wep.WorldModelOffset and cv_SpinePitch:GetBool() and sightdelta > 0.01 then
		local idx_spine2 = GetCachedBoneIndex(ply, "ValveBiped.Bip01_Spine2")
		if idx_spine2 then
			local mat_spine2 = Entity_GetBoneMatrix(ply, idx_spine2)
			if mat_spine2 then
				local pitch = math_Clamp(ply:EyeAngles().p, -45, 45)
				local delta = math_Clamp(pitch * SPINE_PITCH_SCALE * sightdelta, -SPINE_PITCH_MAX, SPINE_PITCH_MAX)
				local rot = Matrix()
				rot:SetAngles(Angle(delta, 0, 0)) -- 绕骨骼自身右轴的局部俯仰旋转
				ApplyBoneMatrix(ply, idx_spine2, mat_spine2 * rot)
			end
		end
	end

	-- 开镜头部微调：让头部朝向贴近视轴（ARC9 固定角 × 开镜进度）
	if sightdelta > 0.01 then
		local headindex = GetCachedBoneIndex(ply, "ValveBiped.Bip01_Head1")
		if headindex and GetHeadChildCount(ply, headindex) < 2 then
			local headmat = Entity_GetBoneMatrix(ply, headindex)
			if headmat then
				local headang = headmat:GetAngles()
				headang:Add(HEAD_AIM_ANGLE * sightdelta)
				headmat:SetAngles(headang)
				Entity_SetBoneMatrix(ply, headindex, headmat)
			end
		end
	end

	-- 脊柱锚点：直拷位置以此为参考做 ±38 钳制，防解算异常拉长手臂
	local spineindex = GetCachedBoneIndex(ply, "ValveBiped.Bip01_Spine4")
	if not spineindex then return end
	local spinemat = Entity_GetBoneMatrix(ply, spineindex)
	if not spinemat then return end
	local spinepos = spinemat:GetTranslation()

	-- 直拷循环：镜像手部/手指骨骼矩阵写回玩家骨骼（双手真正贴合握把的关键）
	local bonelist = nolefthand and TPIKBONES_NOLEFT or TPIKBONES
	for _, bonename in ipairs(bonelist) do
		local wmbone = GetCachedBoneIndex(mirror, bonename)
		if wmbone then
			local wmmat = Entity_GetBoneMatrix(mirror, wmbone)
			if wmmat then
				local plybone = GetCachedBoneIndex(ply, bonename)
				if plybone then
					local plymat = Entity_GetBoneMatrix(ply, plybone)
					if plymat then
						local bonepos = wmmat:GetTranslation()
						bonepos.x = math_Clamp(bonepos.x, spinepos.x - BONE_CLAMP_RADIUS, spinepos.x + BONE_CLAMP_RADIUS)
						bonepos.y = math_Clamp(bonepos.y, spinepos.y - BONE_CLAMP_RADIUS, spinepos.y + BONE_CLAMP_RADIUS)
						bonepos.z = math_Clamp(bonepos.z, spinepos.z - BONE_CLAMP_RADIUS, spinepos.z + BONE_CLAMP_RADIUS)
						local boneang = wmmat:GetAngles()

						plymat:SetTranslation(bonepos)
						plymat:SetAngles(boneang)

						Entity_SetBoneMatrix(ply, plybone, plymat)
						ply:SetBonePosition(plybone, bonepos, boneang)
					end
				end
			end
		end
	end

	-- 六根手臂骨骼索引（缺任何一根都无法完成两臂 IK）
	local idx_l_upper = GetCachedBoneIndex(ply, "ValveBiped.Bip01_L_UpperArm")
	local idx_r_upper = GetCachedBoneIndex(ply, "ValveBiped.Bip01_R_UpperArm")
	local idx_l_fore = GetCachedBoneIndex(ply, "ValveBiped.Bip01_L_Forearm")
	local idx_r_fore = GetCachedBoneIndex(ply, "ValveBiped.Bip01_R_Forearm")
	local idx_l_hand = GetCachedBoneIndex(ply, "ValveBiped.Bip01_L_Hand")
	local idx_r_hand = GetCachedBoneIndex(ply, "ValveBiped.Bip01_R_Hand")
	if not (idx_l_upper and idx_r_upper and idx_l_fore and idx_r_fore and idx_l_hand and idx_r_hand) then return end

	local limblength = GetLimbLength(ply)

	-- passive/normal 姿势不跟视角，用躯干 aim_yaw 修正目标方向（ARC9 同款思路）
	local eyeang = ply:EyeAngles()
	if htype == "passive" or htype == "normal" then
		local yawid = ply:LookupPoseParameter("aim_yaw")
		local aimyaw = yawid and yawid >= 0 and ply:GetPoseParameter(yawid) or 0
		eyeang.y = eyeang.y - aimyaw * 160 + 80
	end

	-- 右臂：肩点固定，以直拷后的手点为目标解算肘部，结果缓存在肩局部空间
	local mat_r_upper = Entity_GetBoneMatrix(ply, idx_r_upper)
	local mat_r_fore = Entity_GetBoneMatrix(ply, idx_r_fore)
	local mat_r_hand = Entity_GetBoneMatrix(ply, idx_r_hand)
	if not (mat_r_upper and mat_r_fore and mat_r_hand) then return end

	local cache = wep.ZS_TPIK_IKCache
	if fullupdate or not cache or not cache.r_up_pos then
		local up_pos, fore_pos, up_ang, fore_ang = Solve2PartIK(
			mat_r_upper:GetTranslation(), mat_r_hand:GetTranslation(),
			limblength, limblength, -1.3, eyeang)
		if up_pos then
			cache = cache or {}
			wep.ZS_TPIK_IKCache = cache
			cache.r_up_pos, cache.r_up_ang = WorldToLocal(up_pos, up_ang,
				mat_r_upper:GetTranslation(), mat_r_upper:GetAngles())
			cache.r_fore_pos, cache.r_fore_ang = WorldToLocal(fore_pos, fore_ang,
				mat_r_upper:GetTranslation(), mat_r_upper:GetAngles())
		end
	end

	if cache and cache.r_up_pos then
		local t_up_pos = TweenVec(cache, "r_up_pos", cache.r_up_pos, alpha)
		local t_up_ang = TweenAng(cache, "r_up_ang", cache.r_up_ang, alpha)
		local t_fore_pos = TweenVec(cache, "r_fore_pos", cache.r_fore_pos, alpha)
		local t_fore_ang = TweenAng(cache, "r_fore_ang", cache.r_fore_ang, alpha)

		local rup_pos, rup_ang = LocalToWorld(t_up_pos, t_up_ang,
			mat_r_upper:GetTranslation(), mat_r_upper:GetAngles())
		local rfore_pos, rfore_ang = LocalToWorld(t_fore_pos, t_fore_ang,
			mat_r_upper:GetTranslation(), mat_r_upper:GetAngles())

		mat_r_upper:SetAngles(rup_ang)
		mat_r_fore:SetTranslation(rup_pos)
		mat_r_fore:SetAngles(rfore_ang)
		mat_r_hand:SetTranslation(rfore_pos) -- ARC9 原注：左手怪问题查不出来，这里是创可贴

		ApplyBoneMatrix(ply, idx_r_upper, mat_r_upper, idx_r_fore)
		ApplyBoneMatrix(ply, idx_r_fore, mat_r_fore, idx_r_hand)
		ApplyBoneMatrix(ply, idx_r_hand, mat_r_hand)

		if cv_Debug:GetBool() then -- 调试链：肩→肘→手（红），需 developer 1 可见
			debugoverlay.Line(mat_r_upper:GetTranslation(), rup_pos, 0.05, DEBUG_COLOR_RIGHT, true)
			debugoverlay.Line(rup_pos, rfore_pos, 0.05, DEBUG_COLOR_RIGHT, true)
		end
	end

	if nolefthand then return end

	-- 左臂同流程（sign 反向）；pistol/近战等姿势已在前面豁免
	local mat_l_upper = Entity_GetBoneMatrix(ply, idx_l_upper)
	local mat_l_fore = Entity_GetBoneMatrix(ply, idx_l_fore)
	local mat_l_hand = Entity_GetBoneMatrix(ply, idx_l_hand)
	if not (mat_l_upper and mat_l_fore and mat_l_hand) then return end

	if fullupdate or not cache or not cache.l_up_pos then
		local up_pos, fore_pos, up_ang, fore_ang = Solve2PartIK(
			mat_l_upper:GetTranslation(), mat_l_hand:GetTranslation(),
			limblength, limblength, 1, eyeang)
		if up_pos then
			cache = cache or {}
			wep.ZS_TPIK_IKCache = cache
			cache.l_up_pos, cache.l_up_ang = WorldToLocal(up_pos, up_ang,
				mat_l_upper:GetTranslation(), mat_l_upper:GetAngles())
			cache.l_fore_pos, cache.l_fore_ang = WorldToLocal(fore_pos, fore_ang,
				mat_l_upper:GetTranslation(), mat_l_upper:GetAngles())
		end
	end

	if cache and cache.l_up_pos then
		local t_up_pos = TweenVec(cache, "l_up_pos", cache.l_up_pos, alpha)
		local t_up_ang = TweenAng(cache, "l_up_ang", cache.l_up_ang, alpha)
		local t_fore_pos = TweenVec(cache, "l_fore_pos", cache.l_fore_pos, alpha)
		local t_fore_ang = TweenAng(cache, "l_fore_ang", cache.l_fore_ang, alpha)

		local lup_pos, lup_ang = LocalToWorld(t_up_pos, t_up_ang,
			mat_l_upper:GetTranslation(), mat_l_upper:GetAngles())
		local lfore_pos, lfore_ang = LocalToWorld(t_fore_pos, t_fore_ang,
			mat_l_upper:GetTranslation(), mat_l_upper:GetAngles())

		mat_l_upper:SetAngles(lup_ang)
		mat_l_fore:SetTranslation(lup_pos)
		mat_l_fore:SetAngles(lfore_ang)
		mat_l_hand:SetTranslation(lfore_pos)

		ApplyBoneMatrix(ply, idx_l_upper, mat_l_upper, idx_l_fore)
		ApplyBoneMatrix(ply, idx_l_fore, mat_l_fore, idx_l_hand)
		ApplyBoneMatrix(ply, idx_l_hand, mat_l_hand)

		if cv_Debug:GetBool() then -- 调试链（青）：肩→肘→手
			debugoverlay.Line(mat_l_upper:GetTranslation(), lup_pos, 0.05, DEBUG_COLOR_LEFT, true)
			debugoverlay.Line(lup_pos, lfore_pos, 0.05, DEBUG_COLOR_LEFT, true)
		end
	end
end

-- ------------------------------------------------------------
-- 入口：PrePlayerDraw（ARC9 同款入口——每玩家每帧去重；
-- flags == 134217729 为深度缓冲 pass，也执行以保证深度一致）
-- ------------------------------------------------------------
local LastFrameByPly = setmetatable({}, { __mode = "k" })

hook.Add("PrePlayerDraw", "ZSTPIK_PrePlayerDraw", function(ply, flags)
	if not cv_TPIK:GetBool() then return end

	local wpn = ply:GetActiveWeapon()
	if not IsValid(wpn) then return end
	if not ZSTPIK.ShouldTPIK(wpn, ply) then return end

	local tick = FrameNumber()
	if flags ~= 0 or LastFrameByPly[ply] ~= tick then
		LastFrameByPly[ply] = tick

		local mirror = GetMirror(wpn, ply)
		if not mirror then return end

		ZSTPIK.DoTPIK(wpn, ply, flags == 134217729)
	end
end)

-- 武器实体移除时回收其镜像（玩家断线/武器销毁）
hook.Add("EntityRemoved", "ZSTPIK_MirrorCleanup", function(ent)
	local mirror = ent.ZS_TPIK_Mirror
	if mirror then
		ent.ZS_TPIK_Mirror = nil
		if IsValid(mirror) then
			mirror:Remove()
		end
	end
end)

-- ------------------------------------------------------------
-- 诊断：zs_tpik_status 打印每名玩家的 TPIK 生效状态与未生效原因；
-- zs_tpik_debug 1（需 developer 1）在已解算玩家手臂上画肩→肘→手调试线
-- ------------------------------------------------------------
concommand.Add("zs_tpik_status", function()
	print(string.format(
		"[ZS TPIK] zs_tpik=%d zs_tpik_others=%d zs_tpik_distance=%d framerate(local/others)=%d/%d",
		cv_TPIK:GetInt(), cv_Others:GetInt(), cv_Distance:GetInt(),
		cv_FPSLocal:GetInt(), cv_FPSOthers:GetInt()))

	if not cv_TPIK:GetBool() then return end

	for _, ply in ipairs(player.GetAll()) do
		local wep = ply:GetActiveWeapon()
		local ok, reason
		if IsValid(wep) and cv_TPIK:GetBool() then
			ok, reason = CheckTPIKGates(wep, ply)
		else
			reason = "无有效武器"
		end

		local hasmirror = IsValid(wep) and IsValid(wep.ZS_TPIK_Mirror) or false
		local lasttime = IsValid(wep) and wep.ZS_TPIK_LastTime or nil
		local age = lasttime and CurTime() - lasttime or -1

		print(string.format("  %s%-12s [%s] 武器=%-24s 镜像=%s 解算=%s %s",
			ply == LocalPlayer() and ">" or " ",
			ply:Name(),
			ply:Team() == TEAM_HUMAN and "人类" or "僵尸",
			IsValid(wep) and wep:GetClass() or "无",
			hasmirror and "有" or "无",
			age >= 0 and string.format("%.2fs前", age) or "从未",
			ok and "| TPIK 生效中" or ("| 未生效：" .. tostring(reason))))
	end

	print("[ZS TPIK] 提示：解算时间应持续刷新（<0.1s）；镜像=有 表示该玩家第三人称由 TPIK 接管")
end)

-- ------------------------------------------------------------
-- 校准辅助：zs_tpik_anchor 把当前 bonemerge 摆位换算成 WorldModelOffset 起始值。
-- Pos 为精确解（Y 已按存储约定取反）；Ang 因错轴映射只能给出近似起点，
-- 粘贴进武器后配合第三人称观察微调（开镜高度调 TPIKPosSightOffset）。
-- ------------------------------------------------------------
concommand.Add("zs_tpik_anchor", function()
	local lp = LocalPlayer()
	if not IsValid(lp) or not lp:Alive() then return end
	local wep = lp:GetActiveWeapon()
	if not IsValid(wep) then return end
	if wep.WorldModelOffset then print("[ZS TPIK] 该武器已是手动锚定模式，无需校准") return end

	local mirror = wep.ZS_TPIK_Mirror
	if not IsValid(mirror) then print("[ZS TPIK] 无可用镜像（需在第三人称下且该武器 TPIK 生效）") return end

	mirror:SetupBones()
	lp:SetupBones()

	local handidx = lp:LookupBone("ValveBiped.Bip01_R_Hand")
	local mpos, mang = mirror:GetPos(), mirror:GetAngles()
	if not handidx or mpos:IsZero() then print("[ZS TPIK] 镜像位姿无效，稍后再试") return end

	local bmat = lp:GetBoneMatrix(handidx)
	if not bmat then return end

	local pos, ang = WorldToLocal(mpos, mang, bmat:GetTranslation(), bmat:GetAngles())
	print("[ZS TPIK] 以下为起始参考值，粘入武器文件后再微调：")
	print("SWEP.WorldModelOffset = {")
	print(string.format("	Pos = Vector(%.2f, %.2f, %.2f), Ang = Angle(%.2f, %.2f, %.2f),",
		pos.x, -pos.y, pos.z, ang.p, ang.y, ang.r))
	print(string.format("	TPIKPos = Vector(%.2f, %.2f, %.2f), TPIKAng = Angle(%.2f, %.2f, %.2f),",
		pos.x, -pos.y, pos.z, ang.p, ang.y, ang.r))
	print("	Scale = 1,")
	print("	TPIKPosSightOffset = Vector(0, 0, 0), -- 开镜抬枪量，向眼前方向调")
	print("}")
end)
