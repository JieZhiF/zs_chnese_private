-- ============================================================================
-- weapon_zs_base/sh_anim.lua - 武器母本动画系统
--
-- 两部分：
--   [1] HoldType 活动翻译（原逻辑，未改动）
--   [2] 动画框架（ARC9 子集移植，来源 arc9_base/sh_anim.lua / sh_animtranslate.lua）
--
-- [框架说明] 链式解析（对齐 ARC9）：
--   ① 显式条目  SWEP.Animations["fire"] = { Source, Time, MinProgress, Mult,
--                  Activity, RareSource, RareSourceChance }
--               Source 支持 序列名(string) / 序列名数组(随机) / 活动(number，
--               ZS 扩展)；Activity 仅在作者显式声明时使用。
--   ② 引擎序列  仅对 fire 系（"fire"、"fire_*"）做模型序列名直查：
--               模型里只要有同名序列就直接播（ARC9 合成默认条目同款）。
--   ③ 无资源    返回 nil → 不播任何关键帧，开火表现由视觉后坐力弹簧承担
--               （ARC9 第3层原设计；⚠ 禁止以引擎 ACT 兜底"修"此层，见 todo.md 二.3）
-- [存量兼容] 未接入新系统的武器（Animations 为空）在 SendWeaponAnimation 中
--            走独立标注的旧版活动播放分支——那是旧系统继续运行，不属于本链。
--
-- [mult 语义] 与旧版 FireAnimSpeed 一致：播放速率倍率（2 = 两倍速），
--             实际播放时长 = (entry.Time 或序列时长) / mult。
--
-- [入口] 统一经 SWEP:PlayAnimation(name, mult, lock)；
--        开火路径由 SWEP:SendWeaponAnimation() 包装（保持可被子类 override）。
-- ============================================================================

local ActIndex = {
    [ "pistol" ]        = ACT_HL2MP_IDLE_PISTOL,
    [ "smg" ]           = ACT_HL2MP_IDLE_SMG1,
    [ "grenade" ]       = ACT_HL2MP_IDLE_GRENADE,
    [ "ar2" ]           = ACT_HL2MP_IDLE_AR2,
    [ "shotgun" ]       = ACT_HL2MP_IDLE_SHOTGUN,
    [ "rpg" ]           = ACT_HL2MP_IDLE_RPG,
    [ "physgun" ]       = ACT_HL2MP_IDLE_PHYSGUN,
    [ "crossbow" ]      = ACT_HL2MP_IDLE_CROSSBOW,
    [ "melee" ]         = ACT_HL2MP_IDLE_MELEE,
    [ "slam" ]          = ACT_HL2MP_IDLE_SLAM,
    [ "normal" ]        = ACT_HL2MP_IDLE,
    [ "fist" ]          = ACT_HL2MP_IDLE_FIST,
    [ "melee2" ]        = ACT_HL2MP_IDLE_MELEE2,
    [ "passive" ]       = ACT_HL2MP_IDLE_PASSIVE,
    [ "knife" ]         = ACT_HL2MP_IDLE_KNIFE,
    [ "duel" ]          = ACT_HL2MP_IDLE_DUEL,
    [ "revolver" ]      = ACT_HL2MP_IDLE_REVOLVER,
    [ "camera" ]        = ACT_HL2MP_IDLE_CAMERA
}

function SWEP:SetWeaponHoldType( t )
    t = string.lower( t )
    local index = ActIndex[ t ]

    if ( index == nil ) then
        Msg( "SWEP:SetWeaponHoldType - ActIndex[ \""..t.."\" ] isn't set! (defaulting to normal) (from "..self:GetClass()..")\n" )
        t = "normal"
        index = ActIndex[ t ]
    end

    self.ActivityTranslate = {}
    self.ActivityTranslate [ ACT_MP_STAND_IDLE ]                = index
    self.ActivityTranslate [ ACT_MP_WALK ]                      = index+1
    self.ActivityTranslate [ ACT_MP_RUN ]                       = index+2
    self.ActivityTranslate [ ACT_MP_CROUCH_IDLE ]               = index+3
    self.ActivityTranslate [ ACT_MP_CROUCHWALK ]                = index+4
    self.ActivityTranslate [ ACT_MP_ATTACK_STAND_PRIMARYFIRE ]  = index+5
    self.ActivityTranslate [ ACT_MP_ATTACK_CROUCH_PRIMARYFIRE ] = index+5
    self.ActivityTranslate [ ACT_MP_RELOAD_STAND ]              = index+6
    self.ActivityTranslate [ ACT_MP_RELOAD_CROUCH ]             = index+6
    self.ActivityTranslate [ ACT_MP_JUMP ]                      = index+7
    self.ActivityTranslate [ ACT_RANGE_ATTACK1 ]                = index+8
    self.ActivityTranslate [ ACT_MP_SWIM_IDLE ]                 = index+8
    self.ActivityTranslate [ ACT_MP_SWIM ]                      = index+9

    if t == "normal" then self.ActivityTranslate [ ACT_MP_JUMP ] = ACT_HL2MP_JUMP_SLAM end
    if t == "knife" or t == "melee2" then self.ActivityTranslate [ ACT_MP_CROUCH_IDLE ] = nil end
end
SWEP:SetWeaponHoldType("pistol")

function SWEP:TranslateActivity(act)
    if self:GetIronsights() and self.ActivityTranslateIronSights then
        return self.ActivityTranslateIronSights[act] or -1
    end
    return self.ActivityTranslate and self.ActivityTranslate[act] or -1
end

-- ============================================================================
-- 动画框架（ARC9 子集移植）
-- ============================================================================

SWEP.Animations = SWEP.Animations or {}

-- [兜底层①] idle/fire 恒真：即使模型没有对应资源也允许进入统一流程（ARC9 alwayshave）
local alwayshave = {
    ["idle"] = true,
    ["fire"] = true,
}

-- fire 系动画才做引擎序列名直查（见文件头 [框架说明]②）
local function IsFireFamily(seq)
    return seq == "fire" or string.sub(seq, 1, 5) == "fire_"
end

-- ==== HasAnimation - 动画存在性判定 ====
-- lq=true 时只认显式 Animations 条目（连发变体探测用，防止误中引擎杂散序列名）
function SWEP:HasAnimation(seq, lq)
    if alwayshave[seq] then return true end

    if self.Animations[seq] then return true end

    if lq then return false end

    -- 引擎序列直查仅限 fire 系（换弹/待机等路径不劫持，保证存量零回归）
    if not IsFireFamily(seq) then return false end

    local owner = self:GetOwner()
    local vm = owner and owner:GetViewModel()
    if not IsValid(vm) then return false end

    return vm:LookupSequence(seq) ~= -1
end

-- ==== GetAnimationEntry - 取动画条目（ARC9 三层链的合并出口）====
-- 返回 nil 即第3层：该名字无任何关键帧资源，开火表现由视觉后坐力弹簧承担。
-- [⚠ 设计约束] 本链内禁止回退引擎 ACT（todo.md 二.3 已验证 ARC9 无此路径）；
-- 引擎活动播放只存在于 SendWeaponAnimation 的存量兼容分支。
function SWEP:GetAnimationEntry(seq)
	-- ① 显式条目优先（作者意图最高）
	local custom = self.Animations[seq]
	if custom then return custom end

	-- ② 引擎同名序列合成默认条目（仅 fire 系）：Source=名字，时长取引擎值
	if IsFireFamily(seq) then
		local owner = self:GetOwner()
		local vm = owner and owner:GetViewModel()
		if IsValid(vm) then
			local idx = vm:LookupSequence(seq)
			if idx and idx ~= -1 then
				return { Source = seq, Time = vm:SequenceDuration(idx) }
			end
		end
	end

	-- ③ nil：不播任何关键帧（ARC9 原设计；DoFireAnimation=false 为其显式形态）
	return nil
end

-- ==== GetAnimationTime - 条目声明时长（供外部计时，不触发播放）====
function SWEP:GetAnimationTime(anim)
    local entry = self:GetAnimationEntry(anim)
    if not entry then return 0 end

    if entry.Time then return entry.Time end

    if entry.Activity then
        local owner = self:GetOwner()
        local vm = owner and owner:GetViewModel()
        return IsValid(vm) and vm:SequenceDuration() or 0.1
    end

    local src = entry.Source
    if istable(src) then src = src[1] end

    local owner = self:GetOwner()
    local vm = owner and owner:GetViewModel()
    if not IsValid(vm) or not isstring(src) then return 0 end

    local idx = vm:LookupSequence(src)
    return (idx and idx ~= -1) and vm:SequenceDuration(idx) or 0
end

-- ==== TranslateAnimation - 后缀翻译链 ====
-- 首期实现 ZS 有对应状态的分支（其余后缀留作可扩展空位）：
--   _iron / _sights : 开镜专用动画（本次需求核心，_iron 优先级高与 ARC9 一致）
--   _empty          : 弹匣打空状态
--   fire_N          : 连发累计变体（仅认显式 Animations 条目，lq 探测）
-- 后缀按序短路：一旦命中即返回，不做组合叠加（与 ARC9 单后缀语义一致）
function SWEP:TranslateAnimation(anim)
    if self:GetIronsights() then
        if self:HasAnimation(anim .. "_iron") then return anim .. "_iron" end
        if self:HasAnimation(anim .. "_sights") then return anim .. "_sights" end
    end

    if self:Clip1() <= 0 and self:HasAnimation(anim .. "_empty") then
        return anim .. "_empty"
    end

    -- 连发累计变体：第 n 发优先匹配最大已声明编号（ARC9 从 1 扫到上限取最后命中）
    -- 只查 Animations 表（lq=true）；上限 10 防御性截断
    local n = math.min(self.ShotCount or 0, 10)
    for i = n, 1, -1 do
        local variant = anim .. "_" .. i
        if self:HasAnimation(variant, true) then return variant end
    end

    return anim
end

-- ==== PlayAnimation - 动画播放统一入口 ====
-- name 经 TranslateAnimation 翻译后三层解析并播放；notranslate=true 跳过翻译
-- （调用方已自行翻译时传入，防止对已带后缀的名字二次叠加探测）。
-- mult 为播放速率倍率（见文件头 [mult 语义]）；lock=true 时记录 AnimLockTime
-- （MinProgress 进度点前禁止再次攻击，CanPrimaryAttack 已接入）。
-- 返回 实际播放时长, MinProgress（无法播放时返回 0, 1）。
function SWEP:PlayAnimation(name, mult, lock, notranslate)
    mult = mult or 1

    local anim = (notranslate == true) and name or self:TranslateAnimation(name)
    local entry = self:GetAnimationEntry(anim)
    if not entry then return 0, 1 end

    local owner = self:GetOwner()
    local vm = owner and owner:GetViewModel()

    -- 解析 Source：数组随机 / RareSource 低概率替换 / 数字视为活动
    local source = entry.Source
    if istable(source) then
        source = source[math.Round(util.SharedRandom("zs_anim_src", 1, #source, CurTime()))]
    end

    if entry.RareSource and util.SharedRandom("zs_anim_rare", 0, 1) <= (entry.RareSourceChance or 0.01) then
        source = entry.RareSource
    end

    local activity = entry.Activity
    if not activity and isnumber(source) then activity = source end

    local played_time = 0
    local minprogress = entry.MinProgress or 1

    if activity then
        -- [活动路径] 旧式 ACT 播放（存量武器垫片）
        if not IsValid(vm) then return 0, 1 end

        self:SendWeaponAnim(activity)

        local dur = vm:SequenceDuration()
        local time = entry.Time or dur
        played_time = time / math.max(mult, 0.001)

        -- 速率 = 时长比 × 速率倍率，±12 封顶（ARC9 同款钳制，引擎限制）
        vm:SetPlaybackRate(math.Clamp((time > 0 and dur / time or 1) * mult, -12, 12))
    else
        -- [序列路径] 序列名直播（ARC9 主路径）
        if not IsValid(vm) or not isstring(source) then return 0, 1 end

        local idx = vm:LookupSequence(source)
        if not idx or idx == -1 then return 0, 1 end

        local dur = vm:SequenceDuration(idx)
        local time = entry.Time or dur
        played_time = time / math.max(mult, 0.001)

        vm:SendViewModelMatchingSequence(idx)
        vm:SetPlaybackRate(math.Clamp((time > 0 and dur / time or 1) * mult, -12, 12))
    end

	-- [IK 时间轴] 条目声明 IKTimeLine=true 时记录播放窗口，
	-- cl_viewik 的手部补偿（RHIK/LHIK）仅在该窗口内采样生效
	if entry.IKTimeLine then
		self.m_IKTimeStart = CurTime()
		self.m_IKTimeDur = math.max(played_time, 0.001)
	end

	-- [动画锁] MinProgress 进度点前锁攻击（仅 lock 调用方受影响）
	if lock then
        self.AnimLockTime = CurTime() + played_time * minprogress
    else
        self.AnimLockTime = nil
    end

    -- [待机骨架接管] 由动画层写入精确到期时间（PrimaryAttack 的兜底写检测此标志）
    self.IdleAnimation = CurTime() + math.max(played_time, 0.05)
    self.m_bIdleFromAnim = true

    return played_time, minprogress
end

-- ============================================================================
-- 开火动画包装（保持方法名可被子类 override —— 盘点确认 11 把武器依赖此能力）
-- ============================================================================

-- ==== SendWeaponAnimation - 开火动画入口（基座实现走框架 + 开镜抑制）====
function SWEP:SendWeaponAnimation()
    -- [特效统一] 每次框架开火即生成自定义枪口焰，并标记本武器进入
    -- 引擎火光屏蔽名单（见 sh_shoot.lua FireAnimationEvent）
    self.m_bFrameworkFire = true
    self:SpawnMuzzleFX()

    -- [ARC9 解耦开关] DoFireAnimation=false 整体关闭开火关键帧（todo 二.4），
    -- 开火表现完全交给视觉后坐力弹簧——第3层的显式形态
    if self.DoFireAnimation == false then
        self:SuppressFireAnimation()
        return
    end

    -- 开镜进度：客户端用平滑进度，服务端/预测用二值近似（仅影响表现层缩放）
    local ads = 0
    if CLIENT and self.GetIronsightDelta then
        ads = math.Clamp(self:GetIronsightDelta() or 0, 0, 1)
    elseif self:GetIronsights() then
        ads = 1
    end

    local mult = self.FireAnimSpeed or 1
    local anim = self:TranslateAnimation("fire")
    local dedicated = anim ~= "fire" -- 后缀命中 = 模型/条目声明了专用开镜动画

    if not dedicated then
        if ads >= 1 and self.CustomSightsAttackAnim then
            -- [CustomSightsAttackAnim 旧语义] 完全开镜时不播关键帧，
            -- 开火表现整体交给视觉后坐力双层弹簧（m4/akbar 依赖）
            self:SuppressFireAnimation()
            return
        end
    else
        -- 有专用动画：默认不额外缩放（作者已为开镜调校该序列），
        -- 可用 SightsDedicatedAnimScale 轻缩放
        if ads > 0 then
            mult = mult * Lerp(ads, 1, self.SightsDedicatedAnimScale or 1)
        end
    end

    -- anim 已翻译（上方需其结果判定专用动画），notranslate 防止二次叠加探测
    local t = self:PlayAnimation(anim, mult, nil, true)
    if t and t > 0 then return end

    -- 走到这里：链①②均未命中（无显式条目且模型无同名序列）
    if self.Animations and next(self.Animations) then
        -- [第3层·ARC9 设计] 已接入新系统的武器：不播任何关键帧，
        -- 开火表现由视觉后坐力弹簧独立承担（开镜抖动小的根源）
        self:SuppressFireAnimation()
    else
        -- [存量兼容路径·非本链] Animations 为空的未迁移武器维持移植前行为。
        -- 这是旧系统继续运行，不是对链内第3层的兜底"修复"——两者语义边界见文件头
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
        local owner = self:GetOwner()
        local vm = owner and owner:GetViewModel()
        if IsValid(vm) then vm:SetPlaybackRate(math.Clamp(mult, -12, 12)) end
        self.IdleAnimation = CurTime() + self:SequenceDuration()
        self.m_bIdleFromAnim = true
    end
end

-- 视模型特效附件索引按视模型缓存（换模自动失效）。
-- 命名回退链："muzzle" → "muzzle_flash" → 1 号附件——引擎序列火光事件
-- （5001）按索引引用附件、不查名字，CS:S 枪模普遍只有无名 1 号附件，
-- 只认名字会在这些模型上静默丢失全部枪口焰。
local function CacheViewFXAtts(self, vm)
	local mdl = vm:GetModel()
	if self.m_fxVMModel == mdl then return end
	self.m_fxVMModel = mdl
	local muzzle = vm:LookupAttachment("muzzle")
	if not muzzle or muzzle <= 0 then
		muzzle = vm:LookupAttachment("muzzle_flash")
	end
	if not muzzle or muzzle <= 0 then
		muzzle = 1
	end
	self.m_fxMuzzleAtt = (muzzle and muzzle > 0) and muzzle or 0
	local eject = vm:LookupAttachment("eject")
	self.m_fxShellAtt = (eject and eject > 0) and eject or self.m_fxMuzzleAtt
end

-- ==== SpawnMuzzleFX - 框架开火的统一枪口焰生成 ====
-- 序列内嵌的引擎枪口焰事件（5001~5003）被 sh_shoot 的 FireAnimationEvent
-- 屏蔽后，由本方法在每次框架开火时替代生成 zs_muzzleflash。
-- 仅客户端本视角生成（IsFirstTimePredicted 防预测回放重复）
function SWEP:SpawnMuzzleFX()
	if not IsFirstTimePredicted() then return end
	if self.MuzzleFlashEffect == false then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	-- [服务器广播] 纯世界坐标枪口焰：覆盖远端观察者与本地第三人称视角。
	-- 不锚定武器实体附件——本地玩家第一人称下其世界模型骨骼可能未更新，
	-- 附件解析会得到陈旧/零点位置导致特效消失；GetTracerOrigin 恒有兜底
	if SERVER then
		local pos, ang = self:GetTracerOrigin()
		pos = pos or owner:GetShootPos()
		ang = ang or owner:EyeAngles()
		-- [相机规避] 兜底位置（眼位）会落进近平面导致不可见，沿视线前推
		if pos:DistToSqr(owner:GetShootPos()) < 100 then
			pos = pos + ang:Forward() * 24
		end
		local ed = EffectData()
		ed:SetEntity(self) -- [身份标识] 仅供特效端去重判定归属，位置以 Origin 为准
		ed:SetOrigin(pos)
		ed:SetAngles(ang)
		util.Effect(self.MuzzleFlashEffect or "zs_muzzleflash", ed, true, true)
		return
	end

	-- [客户端] 第三人称视角下视模型已隐藏，交由上面的服务器广播负责
	if owner:ShouldDrawLocalPlayer() then return end

	-- [近平面规避] 开镜过程中枪身向眼位收拢，视模型枪口点越过主视角
	-- 近裁剪面后 PCF 粒子整体不可见——此时同样交由服务器广播的世界模型
	-- 特效呈现（其锚点恒在相机外部），避免"开镜开火无特效"
	local delta = self.GetIronsightDelta and (self:GetIronsightDelta() or 0) or 0
	if delta > 0.5 then return end

	local vm = owner:GetViewModel()
	if not IsValid(vm) then return end

	CacheViewFXAtts(self, vm)

	local ed = EffectData()
	ed:SetEntity(vm)
	ed:SetScale(1)

	-- 模型连一个附件都没有的极端情况：退化为位置直传（曳光锚点同源）
	if not self.m_fxMuzzleAtt or self.m_fxMuzzleAtt <= 0
		or not vm:GetAttachment(self.m_fxMuzzleAtt) then
		local pos, ang = self:GetTracerOrigin()
		ed:SetOrigin(pos or owner:GetShootPos())
		ed:SetAngles(ang or owner:EyeAngles())
	else
		ed:SetAttachment(self.m_fxMuzzleAtt)
	end

	util.Effect(self.MuzzleFlashEffect or "zs_muzzleflash", ed)
end

-- ==== SpawnSuppressedFireFX - 动画抑制时的弹壳补偿 ====
-- 关键帧被压住时，模型序列内嵌的弹壳抛出事件不会触发，此处手动补发
-- ShellEject（枪口焰已由 SendWeaponAnimation 统一生成，不再在此重复）
function SWEP:SpawnSuppressedFireFX()
	if not CLIENT or not IsFirstTimePredicted() then return end

	local owner = self:GetOwner()
	local vm = owner and owner:GetViewModel()
	if not IsValid(vm) then return end

	CacheViewFXAtts(self, vm)

	if not self.m_fxShellAtt or self.m_fxShellAtt <= 0 then return end

	local sed = EffectData()
	sed:SetEntity(vm)
	sed:SetAttachment(self.m_fxShellAtt)
	util.Effect("ShellEject", sed)
end

-- ==== SuppressFireAnimation - 开火动画完全抑制（弹簧承担表现）====
-- 仅维护 IdleAnimation 待机骨架；计时与旧行为一致（旧路径由 PrimaryAttack
-- 兜底写入 SequenceDuration，此处镜像同一算式避免抑制态下待机循环被更频繁重置）
function SWEP:SuppressFireAnimation()
	self.IdleAnimation = CurTime() + self:SequenceDuration()
	self.m_bIdleFromAnim = true

	-- [特效补偿] 关键帧没了，枪口火焰/弹壳不能跟着消失（默认开启）
	if self.SuppressedFireFX ~= false then
		self:SpawnSuppressedFireFX()
	end
end

-- ==== SendReloadAnimation - 换弹动画入口 ====
-- 未定制武器：Animations 无 reload 条目 → 活动垫片 ACT_VM_RELOAD（与旧行为一致，
-- ProcessReloadEndTime 随后照旧覆写播放速率为换弹速度）。stm4 等子类 override 不受影响。
function SWEP:SendReloadAnimation()
    local t = self:PlayAnimation("reload", 1)
    if not t or t <= 0 then
        self:SendWeaponAnim(ACT_VM_RELOAD)
    end
end
