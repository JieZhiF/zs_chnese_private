-- shared.lua

---------------- [武器基本属性] ----------------
--SWEP.Base = "weapon_base"
SWEP.PrintName = ""..translate.Get("weapon_zs_base")
SWEP.Description = "武器母本"
SWEP.DrawAmmo = true                      -- 是否绘制游戏默认的弹药 HUD。
SWEP.DrawCrosshair = false                -- 是否绘制准星。
SWEP.Slot = 0                             -- 武器在武器选择栏中的位置（0 - 5 对应我们在游戏中的1-6号位置）
SWEP.Weight = 5 --武器的权重，权重越高在对应栏位的位置就越靠上
SWEP.Tier = 1 --武器的等级
SWEP.WalkSpeed = 190 --拿着武器的速度
SWEP.HoldType = "pistol" --拿着武器的姿势
SWEP.IronSightsHoldType = "ar2" --机瞄时的姿势
---------------- [武器模型设置] ----------------
SWEP.VMPos = Vector(0, 0, 0)
SWEP.VMAng = Angle(0, 0, 0)
SWEP.ViewModelFOV = 60 --第一人称镜头的大小
SWEP.ViewModelFlip = true

-- SCK 元素容器
SWEP.VElements = {}
SWEP.WElements = {}
SWEP.ViewModelBoneMods = {}
---------------- [特殊属性] ----------------
SWEP.CSMuzzleFlashes = true -- 是否使用 Counter-Strike 样式的枪口闪光效果（需要配合模型支持）
SWEP.EmptyWhenPurchased = true -- 购买时是否空弹夹（需要配合 GAMEMODE:SetupDefaultClip 使用）
SWEP.Undroppable = false --禁止丢弃，true 为禁止丢弃，false 为允许丢弃
SWEP.NoPickupNotification = false --捡起的时候是否显示提示，true 为禁止提示，false 为显示提示
SWEP.NoDismantle = false --禁止拆除，true 为禁止拆除，false 为允许拆除
SWEP.NoGlassWeapons = true --不是玻璃武器
SWEP.AllowQualityWeapons = true --是否允许强化
---------------- [武器扩散] ----------------
SWEP.ConeMax = 1.5 --最大
SWEP.ConeMin = 0.5 --最小准星（这个是白板武器和没有装备
SWEP.ConeRamp = 2 --准星扩散速度
SWEP.FixedAccuracy = false  -- 如果设为 true，则完全忽略玩家状态和移动，始终使用 ConeMin 作为扩散。
SWEP.RecoilMultSights = 0.5 -- 瞄准时后坐力倍率
SWEP.RecoilMultCrouch = 0.75 -- 蹲下时后坐力倍率
SWEP.RecoilMultMidAir = 2.0 -- 半空中时后坐力倍率
SWEP.RecoilMultMove = 1.3 -- 移动时后坐力倍率

---------------- [左键设置] ----------------

SWEP.Primary.Sound = Sound("Weapon_Pistol.Single") --左键开火音效
SWEP.DryFireSound = Sound("Weapon_Pistol.Empty") --没子弹音效
SWEP.Primary.Damage = 60 --伤害
SWEP.Primary.KnockbackScale = 1
SWEP.Primary.NumShots = 1 --一次射击的子弹数目
SWEP.Primary.Delay = 0.15 --一次射击的延迟
SWEP.Primary.ClipSize = 8 --主弹匣的子弹数
SWEP.Primary.DefaultClip = 0 --默认送的弹匣数目，如果不为零最终送的子弹数是： ClipSize × DefaultClip ，两个相乘
SWEP.Primary.Automatic = false --全自动设置
SWEP.Primary.Ammo = "pistol" --左键开火需要的弹药
SWEP.RequiredClip = 1
SWEP.TracerName = "zs_tracer" -- 曳光效果：ZS 适配版 ARC9 曳光（置 nil 回引擎默认；激光等特殊武器可各自覆盖）
SWEP.TracerSpeed = 15000       -- 曳光飞行速度（units/s，越大尾迹越短）
-- SWEP.TracerColor = Color(255,255,255) -- 可选：曳光颜色覆写
-- SWEP.TracerSize = 1                   -- 可选：曳光粗细倍率
SWEP.MuzzleFlashEffect = "zs_muzzleflash" -- 枪口焰：框架开火统一生成（序列内置引擎火光已被屏蔽；置 false 回引擎原版）
---------------- [右键设置] ----------------
SWEP.Secondary.ClipSize = 1
SWEP.Secondary.DefaultClip = 1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "dummy"
---------------- [武器HUD] ----------------
SWEP.HUD3DBone = "base"
SWEP.HUD3DScale = 0.01
SWEP.HUD3DAng = Angle(180, 0, 0)
SWEP.HUD3DPos = Vector(0, 0, 0)
SWEP.CooldownExtraSize = 1 --冷却环大小
---------------- [后坐力系统] ----------------
SWEP.Recoil_Enabled = false -- 设为 true 来为武器启用此系统（不启用则镜头/枪模弹簧层全部无效）
--SWEP.Recoil = 0 -- [旧系统遗留] 当前无任何消费者，仅为兼容保留
SWEP.RecoilUp = 0.4 -- 基础垂直后坐力（度，经 cl_recoil_handler 注入真实视角）
SWEP.RecoilSide = 0.2 -- 基础水平后坐力（度）
SWEP.RecoilRandomUp = 0.2 -- 垂直后坐力随机附加范围（度）
SWEP.RecoilRandomSide = 0.2 -- 水平后坐力随机附加范围（度）
SWEP.RecoilAutoControl = 1 -- 停火自动回正强度（越大回正越快；消费点 cl_recoil_handler 阶段4）
SWEP.RecoilAutoControlTime = 0.08 -- 停火后多久重置连发计数（恢复首发倍率与 fire_N 变体判定）
SWEP.RecoilAutoControl_DontTryToReturnBack = false -- true=禁用手动压枪抵扣与自动回正（永久踢枪风格）
SWEP.RecoilResetTime = 0.12 -- 停火后多久开始冷却热度（RecoilAmount 渐进衰减的启动延迟）
SWEP.RecoilDissipationRate = 1 -- 热度冷却速率（停火后每秒按此倍率衰减 RecoilAmount，越大回落越快）
--SWEP.RecoilRecoveryPercentage = 0.6 -- [旧系统遗留] 当前无任何消费者，仅为兼容保留

-- 后坐力曲线系统（渐进式递增）
SWEP.RecoilFirstShotMult = 1.0 -- 首发后坐力倍率（第一发通常较大）
SWEP.RecoilSideBias = 0 -- 水平漂移方向偏好：正=视角向左漂移、负=向右（Source yaw 轴向）；0=随连射图案自然摆动
SWEP.RecoilPerShot = 1 -- 每发子弹增加的热度
SWEP.RecoilMax = 6 -- 热度上限
SWEP.RecoilModifierCap = 1.2 -- 满热度时的后坐力倍率上限
SWEP.RecoilMaxTotalUp = 45 -- [实际轨] 弹道垂直爬升累积上限(度)

-- ====== [双轨分离·实际轨] ARC9 移植参数（累积量经 cl_recoil_handler 渐进注入视角） ======
SWEP.RecoilPatternDrift = 0.35 -- 连射方向图案逐发漂移幅度(度)，越大水平走位越飘
SWEP.RecoilAccumScale = 1      -- 实际轨累积量总乘数（服务器平衡旋钮；显式设定弹簧参数后不影响视觉层）
SWEP.RecoilRiseSpeed = 25      -- 视角上抬速率乘数（ARC9 的 m=25），越大抬头越猛
SWEP.RecoilTimeStep = 0.06     -- 注入采样步长(秒)，越小上抬越平滑

-- 视觉后坐力 (镜头与模型)
SWEP.CamRecoilUp = 0.015 -- 镜头垂直后坐力 (屏幕视角弹跳)
SWEP.CamRecoilSide = 0.008 -- 镜头水平后坐力
SWEP.CamRecoilRoll = 0.01 -- 镜头滚转后坐力 (射击时屏幕倾斜)
SWEP.CamRecoilFOV = 1.2   -- 镜头FOV后坐力 (射击时FOV微变化)
SWEP.CamRecoilFOVStiffness = 200 -- FOV弹簧刚度
SWEP.CamRecoilFOVDamping = 12 -- FOV弹簧阻尼
SWEP.CamRecoilLerpSpeed = 22 -- [旧系统遗留] 当前无消费者（镜头回正已由 cl_camera Verlet 弹簧接管），仅为兼容保留
SWEP.CamRecoilADSMult = 2.0 --开镜时镜头后坐力增强倍率（随开镜进度线性生效；枪模侧比例由 *HipFire 双参数组承担）

---枪模视觉效果（ARC9 式双参数组：* 为开镜组，配对 *HipFire 另定义腰射组，注入时按开镜进度插值）
SWEP.CustomSightsAttackAnim = false --是否启用模拟开镜开火动画
SWEP.UseVisualRecoil = true -- 启用枪模物理后坐力
SWEP.VisualRecoilPunch = 1.5 -- [开镜组] 枪模后坐冲击感
SWEP.VisualRecoilUp = -1.8 -- [开镜组] 枪模垂直位移
SWEP.VisualRecoilRoll = 2.5 -- [开镜组] 枪模滚转
SWEP.VisualRecoilStiffness = 200 -- 弹簧刚度 (越高越"硬")
SWEP.VisualRecoilDamping = 20 -- 弹簧阻尼 (越高越快衰减)
SWEP.VisualRecoilCenter = Vector(0, 0, 0)


---------------- 机械瞄准 (Iron Sights)----------------
SWEP.IronEnable = true --是否允许机瞄（false 时右键不再进入瞄准状态）
SWEP.AimDownSightsTime = 0.25 --完成一次开镜/收镜的平滑过渡秒数（ARC9 风格）
SWEP.IronSightsPos = Vector(0, 0, 0)
SWEP.IronSightsAng = Angle(0, 0, 0)
SWEP.IronSpeed = 8
-- [ARC9 形式默认 · 主视角放大率] 除法语义：FOV ÷ Magnification（polyarms 全系 1.05~1.15）。
-- 1.15 ≈ 全开镜主视角仅收窄 13%；深倍率由 PIP 镜内画面承担，不再用深 FOV 缩放伪装狙击镜。
-- 平铺字段与 IronSights.Magnification 表键等价（表优先）；旧字段 IronsightsMultiplier
-- 仅作未迁移武器的回退，新配置一律不要再写它（灵敏度由基座按本值自动推导）
SWEP.ADSMagnification = 1.15
SWEP.Breathmult = 1 -- 呼吸强度系数

-- 视模型摇摆/步摆（ARC9 移植，实现在 cl_sway.lua；详细说明见该文件头）
SWEP.MouseSway = true -- 鼠标摇摆总开关：视角转动时枪身惯性滞后
SWEP.MouseSwayMult = 1 -- 鼠标摇摆强度倍率
SWEP.MouseSwayInertia = true -- true=惯性变体（仅旋转、回中快）；false=经典位移+整体旋转
SWEP.BobWalkMult = 1 -- 走路摆动倍率
SWEP.BobSprintMult = 1 -- 奔跑摆动倍率
-- 逐枪微调六元表 {x, y, z, pitch, yaw, roll}，不写则用 ARC9 标准默认值：
-- SWEP.BobSettingsMove = {0.5, 0.25, 1, 0.75, 2, 0.875}
-- SWEP.BobSettingsSpeed = {1, 0.75, 1, 1, 1, 0.75}

-- 检视与动画
SWEP.InspectOnDeploy = false
SWEP.DeployInspectTime = 5
SWEP.InspectSpeed = 1
SWEP.ReloadSpeed = 1.0
SWEP.FireAnimSpeed = 1.0
SWEP.IdleActivity = ACT_VM_IDLE

-- [ARC9 动画框架] 开火动画开镜抑制（逻辑见 sh_anim.lua；条目表 SWEP.Animations 同文件）
SWEP.SightsDedicatedAnimScale = 1  -- 有 _sights/_iron 专用动画时：随开镜进度的附加缩放（默认不缩放）
SWEP.DoFireAnimation = true        -- [ARC9 解耦开关] false=开火不播任何关键帧，纯弹簧表现（链内第3层的显式形态）
SWEP.SuppressedFireFX = true       -- 纯弹簧开火时手动补发枪口火焰/弹壳特效（补偿被抑制的动画事件；仅第一人称）


-- =============================================================================
-- SECTION: ARC9 风格加载器 (Auto Loader)
-- =============================================================================

local baseName = "weapon_zs_base" -- 请确保文件夹名与此一致
local searchdir = "weapons/" .. baseName

local function autoinclude(dir)
    local files, dirs = file.Find(dir .. "/*.lua", "LUA")

    for _, filename in pairs(files) do
        if filename ~= "shared.lua" and filename ~= "init.lua" and filename ~= "cl_init.lua" then
            local luatype = string.sub(filename, 1, 3)

            if luatype == "sv_" then
                if SERVER then
                    include(dir .. "/" .. filename)
                end
            elseif luatype == "cl_" then
                if SERVER then
                    AddCSLuaFile(dir .. "/" .. filename)
                else
                    include(dir .. "/" .. filename)
                end
            elseif luatype == "sh_" then
                if SERVER then
                    AddCSLuaFile(dir .. "/" .. filename)
                end
                include(dir .. "/" .. filename)
            end
        end
    end

    for _, path in pairs(dirs) do
        autoinclude(dir .. "/" .. path)
    end
end

autoinclude(searchdir)