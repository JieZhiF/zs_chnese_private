AddCSLuaFile()

SWEP.PrintName = ""..translate.Get("weapon_zs_akbar")
SWEP.Description = ""..translate.Get("weapon_zs_akbar_description")


SWEP.SlotPos = 0

if CLIENT then
    SWEP.Slot = GAMEMODE:GetWeaponSlot("WeaponSelectSlotAssaultRifles")
	SWEP.WeaponType = "rifle"
    SWEP.SlotGroup = WEPSELECT_ASSAULT_RIFLE
	SWEP.ViewModelFlip = false
	SWEP.ViewModelFOV = 60

	SWEP.HUD3DBone = "v_weapon.AK47_Parent"
	SWEP.HUD3DPos = Vector(-1, -4.5, -4)
	SWEP.HUD3DAng = Angle(0, 0, 0)
	SWEP.HUD3DScale = 0.015
end

SWEP.Base = "weapon_zs_base"

SWEP.HoldType = "ar2"

SWEP.ViewModel = "models/weapons/cstrike/c_rif_ak47.mdl"
SWEP.WorldModel = "models/weapons/w_rif_ak47.mdl"
SWEP.UseHands = true

SWEP.ReloadSound = Sound("Weapon_AK47.Clipout")
SWEP.Primary.Sound = Sound("Weapon_AK47.Single")
SWEP.Primary.Damage = 43.5
SWEP.Primary.NumShots = 1
SWEP.Primary.Delay = 0.1

SWEP.Primary.ClipSize = 30
SWEP.Primary.DefaultClip = 9999
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "ar2"

--GAMEMODE:SetupDefaultClip(SWEP.Primary)

SWEP.ConeMax = 2.65
SWEP.ConeMin = 1.275
SWEP.WalkSpeed = SPEED_SLOW
-- [机瞄配置 · ARC9 形式] Pos/Ang=贴瞄偏移，Magnification=开镜变焦倍率（FOV÷值），
-- ViewModelFOV=开镜时视模型 FOV 平滑过渡目标

SWEP.IronSights = {
	Pos = Vector(-6.6, -12.57, 2.864),
    Ang = Angle(1.689, 0, 0	),
    Magnification = 1.15,
    ViewModelFOV = 55,
}
SWEP.Tier = 3

-- ============================================================================
-- [新版武器迁移模板 · 官方示例]
-- 把下方「复制区开始」到「复制区结束」整块拷进旧版武器文件，即可接入与 akbar
-- 一致的新版动画框架 + 双轨后坐力。最小必选只有两行：
--   SWEP.Recoil_Enabled = true          （多数存量枪默认 false，不开则弹簧层全无效）
--   SWEP.Animations.fire 声明           （不声明则仍走存量兼容路径）
-- ============================================================================

---------------- >>>>>>>> 复制区开始（从这里拷到「复制区结束」）<<<<<< ----------------

-- [1/5 动画框架接入·必选] 声明即成为框架"接入者"。
-- Activity 为 ZS 扩展：无标准化 "fire" 序列名的模型用它保持移植前表现，零风险；
-- 模型有标准化序列的武器可改用 Source = "fire"。
SWEP.Animations = {
	fire = { Activity = ACT_VM_PRIMARYATTACK },
	-- [升级位] 模型添加 "fire_sights"（或 "fire_iron"）序列并在此声明后，
	-- 开镜开火自动优先播专用动画，且优先生效于下方 [2/4] 的抑制开关：
	-- fire_sights = { Source = "fire_sights", Time = 0.06 },
}

-- [2/5 开镜开火行为·按武器定位选其一，本段可不拷走基座默认]
SWEP.CustomSightsAttackAnim = true -- akbar 现用：完全开镜不播关键帧、纯弹簧承担开火表现
-- SWEP.DoFireAnimation = false    -- 备选：任何状态都不播开火关键帧（纯弹簧极端形态）
SWEP.SuppressedFireFX = true   -- 备选开关：纯弹簧开火时不手动补发弹壳（枪口焰与此开关无关，始终由框架统一生成；默认补发）

-- [3/5 双轨后坐力·首行必选，数值按手感调]
--   FireAnimationEvent 屏蔽，勿在子类重接）
SWEP.Recoil_Enabled = true -- 启用双轨后坐力（不启用则镜头/枪模弹簧层全部无效）
SWEP.RecoilUp = 0.4 -- 基础垂直后坐力（度，经 cl_recoil_handler 注入真实视角）
SWEP.RecoilSide = 0.2 -- 基础水平后坐力（度）
SWEP.RecoilRandomUp = 0.2 -- 垂直后坐力随机附加范围（度）
SWEP.RecoilRandomSide = 0.2 -- 水平后坐力随机附加范围（度）
SWEP.RecoilAutoControl = 1 -- 停火自动回正强度（越大回正越快；消费点 cl_recoil_handler 阶段4）
SWEP.RecoilAutoControlTime = 0.08 -- 停火后多久重置连发计数（恢复首发倍率与 fire_N 变体判定）
SWEP.RecoilAutoControl_DontTryToReturnBack = false -- true=禁用手动压枪抵扣与自动回正（永久踢枪风格）
SWEP.RecoilResetTime = 0.12 -- 停火后多久开始冷却热度（RecoilAmount 渐进衰减的启动延迟）
SWEP.RecoilDissipationRate = 1 -- 热度冷却速率（停火后每秒按此倍率衰减 RecoilAmount，越大回落越快）
-- 渐进曲线
SWEP.RecoilFirstShotMult = 1.0 -- 首发后坐力倍率（第一发通常较大）
SWEP.RecoilSideBias = 0 -- 水平漂移方向偏好：正=视角向左漂移、负=向右（Source yaw 轴向）；0=随连射图案自然摆动
SWEP.RecoilPerShot = 1 -- 每发子弹增加的热度
SWEP.RecoilMax = 6 -- 热度上限
SWEP.RecoilModifierCap = 1.2 -- 满热度时的后坐力倍率上限
SWEP.RecoilMaxTotalUp = 45 -- [实际轨] 弹道垂直爬升累积上限(度)

-- [实际轨] 累积量经 cl_recoil_handler 渐进注入真实视角
SWEP.RecoilPatternDrift = 0.35 -- 连射方向图案逐发漂移幅度(度)，越大水平走位越飘
SWEP.RecoilAccumScale = 1 -- 实际轨累积量总乘数（服务器平衡旋钮；显式设定 [4/5] 弹簧参数后不影响视觉层）
SWEP.RecoilRiseSpeed = 25 -- 视角上抬速率乘数（ARC9 的 m=25），越大抬头越猛
SWEP.RecoilTimeStep = 0.02 -- 注入采样步长(秒)，越小上抬越平滑

-- [4/5 镜头与枪模弹簧·表现层，建议整段保留后微调]
SWEP.CamRecoilUp = 0.015 -- 镜头垂直后坐力 (屏幕视角弹跳)
SWEP.CamRecoilSide = 0.008 -- 镜头水平后坐力
SWEP.CamRecoilRoll = 0.01 -- 镜头滚转后坐力 (射击时屏幕倾斜)
SWEP.CamRecoilFOV = 1.2 -- 镜头FOV后坐力 (射击时FOV微变化)
SWEP.CamRecoilFOVStiffness = 200 -- FOV弹簧刚度
SWEP.CamRecoilFOVDamping = 12 -- FOV弹簧阻尼
SWEP.CamRecoilADSMult = 2.0 -- 开镜时镜头后坐力增强倍率（随开镜进度线性生效）

-- 枪模弹簧（ARC9 式双参数组：`*` 仅作用于开镜；腰射值由对应的 `*HipFire` 定义，
SWEP.UseVisualRecoil = true -- 启用枪模物理后坐力

SWEP.VisualRecoilPunch = 0 -- [开镜组] 枪模后坐冲击感（沿视轴的短促抽动分量）
SWEP.VisualRecoilPunchRandom = 0 -- [可选] 冲击感随机幅度

SWEP.VisualRecoilUp = 0 -- [开镜组] 枪模垂直位移
SWEP.VisualRecoilUpRandom = 0 -- [可选] 垂直位移随机幅度（同"基准 ± 此值"模式）

SWEP.VisualRecoilRoll = 0 -- [开镜组] 枪模滚转
SWEP.VisualRecoilRollRandom = 0 -- [可选] 滚转随机幅度

SWEP.VisualRecoilBack = 3 -- [开镜组] 沿枪身方向的后坐位移（朝射手方向的主体运动）
SWEP.VisualRecoilBackRandom = 0.2 -- 后坐随机幅度：每发在基准 ± 此值间取落点（0=逐发完全一致）

--SWEP.VisualRecoilUpHipFire = 0.6 -- [腰射组示例] Punch/Up/Roll/Back 均有各自 *HipFire 对应项
SWEP.VisualRecoilStiffness = 200 -- 弹簧刚度 (越高越"硬")
SWEP.VisualRecoilDamping = 20 -- 弹簧阻尼 (越高越快衰减)
SWEP.VisualRecoilCenter = Vector(0, 0, 0)

-- 微抖层：独立于上方振幅参数的高频细碎抖动系统（开火后 0.75s 内活跃）
-- 数值是强度倍率；要连主层一起完全静止，除上方振幅归零外还需本行 false
SWEP.SubtleVisualRecoil = false
SWEP.VisualRecoilYawFollow = 0 -- 水平跟随抖动：枪模偏航随实际轨水平漂移摆动（与三振幅参数解耦；0=关闭）

-- 鼠标摇摆：视角转动时枪身惯性滞后（默认惯性变体；经典变体 MouseSwayInertia=false）
SWEP.MouseSway = true -- 总开关（false=关闭）
SWEP.MouseSwayMult = 1 -- 强度倍率
-- SWEP.MouseSwayInertia = false -- 切换经典位移+整体旋转变体

-- 移动摇摆（ARC9 DarsuBob 步行循环：六轴正弦节奏 + 跳跃惯性 + 横移倾斜 + 下蹲变化；基座统一启用）
SWEP.BobWalkMult = 1 -- 走路摇摆倍率
SWEP.BobSprintMult = 1 -- 奔跑摇摆倍率
-- SWEP.BobSettingsMove = {0.5, 0.25, 1, 0.75, 2, 0.875} -- [逐枪微调] x y z pitch yaw roll 幅度表
-- SWEP.BobSettingsSpeed = {1, 0.75, 1, 1, 1, 0.75} -- 各轴节奏倍率

-- [5/5 弹道与特效·可选，不拷即继承基座默认]
SWEP.TracerName = "zs_tracer"           -- 曳光：ZS 适配版 ARC9 曳光（基座已默认；置 nil 回引擎默认）
SWEP.TracerSpeed = 15000                -- 曳光速度 units/s，越大尾迹越短
SWEP.TracerColor = Color(255, 214, 130) -- 曳光颜色覆写（示例：AKM 暖黄曳光）
SWEP.TracerSize = 1                     -- 曳光粗细倍率
SWEP.MuzzleFlashEffect = "zs_muzzleflash" -- 枪口焰：ARC9 同款 PCF 粒子（基座已默认；置 false 回引擎原版）
-- SWEP.MuzzleParticle = "muzzleflash_ak47" -- [升级位] 枪口粒子按武器定制（默认按 HoldType 自动选 muzzleflash_ar 等）
-- 纯弹簧开火时的弹壳补偿开关见 [2/5] 的 SuppressedFireFX

---------------- >>>>>>>> 复制区结束 <<<<<<<< ----------------


GAMEMODE:AttachWeaponModifier(SWEP, WEAPON_MODIFIER_MAX_SPREAD, -0.344)
GAMEMODE:AttachWeaponModifier(SWEP, WEAPON_MODIFIER_MIN_SPREAD, -0.172)
