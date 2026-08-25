-- ============================================================================
-- weapon_zs_base/cl_scope.lua - 画中画（PIP）瞄准镜渲染（客户端）
-- ARC9 式二次渲染管线 · 3D 镜片方案：
--   镜内画面渲染进方形 RT，通过改写 SCK 元素的 material 字段贴到瞄准镜模型的
--   "镜片"网格上（cl_model 每帧自动应用 v.material），观感与 ARC9 一致；
--   武器未配置镜片元素时自动回退为屏幕空间圆形合成（旧实现保留）。
--
-- [窗口策略] RT 每帧沿弹道方向渲染（GetShootPos + GetAimVector，与子弹同源）+ FOV
--   余量视野：弹着点恒在 RT 中心，与烘焙分划板同图本征重合——精度不依赖任何
--   逐帧几何补偿，从根源上杜绝窗口跳动/闪烁/黑屏。默认（zs_pip_parallax ≤ 1）
--   窗口恒钉 RT 中心，画面稳定；开火时镜头弹簧只踢主视角与枪模，镜内画面保持
--   稳定（ARC9 式瞄具稳定观感），分划板随枪模轻微晃动属物理镜正常表现。
--   zs_pip_parallax > 1 切换为夸张浮动观感模式（PreRender 侧射线-平面求交驱动
--   窗口漂移，观感优先、精度不保证）。
--
-- 两级质量模式（ConVar zs_pipscope）：
--   1 = 新版：render.RenderView 独立渲染真实放大画面（清晰，默认）
--   0 = 原版：完全回退旧版行为（主视角深 FOV 缩放 + 旧式遮罩 + 隐藏枪模）
--   （旧档值 2 自动视为 1；原 1=廉价拷屏放大已移除：引擎内部屏幕纹理
--     直采存在驱动级色块，无法根治）
--
-- [武器接入]
--   必备：SWEP.Scoped = true + SWEP.PIPScope = true
--   镜片（二选一）：
--   ① SCK 手工（推荐，hunter/m82a3 即此方案）：SCK 里在 VElements 新建一块
--      Quad 元素贴住目镜，调整 pos/angle/size（红框边界即镜片半高边界），
--      把输出粘进 SWEP.VElements，再声明 SWEP.ScopeLensElement = "元素名"；
--      裁剪形状写在元素上（SCK 面板 ZS Lens 区可直接调，视口青色预览即实际形状）：
--        pip_shape  = "circle"(默认) / "square" / "poly"
--        pip_radius = 可见圆半径比 0.05~1（circle）
--        pip_aspect = 宽/高比 0.25~4（全部形状，>1 拉宽画面窗口）
--        pip_chamfer= { tl,tr,br,bl } 切角速记 或 pip_poly = 顶点表（poly）
--      游戏内校准填充：zs_lens_show 1 显形状描边 → zs_lens_radius /
--      zs_lens_chamfer "tl,tr,br,bl" 实时微调 → zs_lens_dump 导出粘贴
--   ② 什么都不写：按 ViewModel 自动匹配内置预设（c_snip_awp 用 hunter 实测值；
--      g3sg1/sg550/十字弓为同构种子值，可能需微调）；无预设则回退屏幕空间合成。
--      声明了①的手工元素后预设自动失效
--
--   其他可选：ScopeMagnification / ScopeMagMin / ScopeMagMax /
--         ScopeReticle / ScopeReticleColor / ScopePaintFunc(RT 内后处理) /
--         ScopeLegacyStyle
--
-- [镜内显示内容 · 玩家可调 ConVar]
--   zs_scope_reticle   分划板样式覆盖（auto=武器默认 | mil-dot/cross/dot/
--                      chevron/german/tdot/acog | 材质路径）
--   zs_scope_retcustom + zs_scope_retr/g/b/a  自定义分划板颜色（覆盖武器默认色）
--   zs_scope_brightness 镜内画面亮度倍率（0.2~2）
--   zs_scope_info       是否显示变焦读数
--   zs_scope_eyecheck   视线偏离镜头时镜内画面淡出为暗玻璃（ARC9 同款）。
--                       默认关：仅当面片法线沿镜筒轴向时才可安全开启
-- ============================================================================

local surface_SetDrawColor = surface.SetDrawColor
local surface_SetMaterial = surface.SetMaterial
local surface_DrawTexturedRect = surface.DrawTexturedRect
local surface_DrawTexturedRectUV = surface.DrawTexturedRectUV
local surface_DrawRect = surface.DrawRect
local surface_DrawLine = surface.DrawLine
local surface_DrawPoly = surface.DrawPoly
local draw_NoTexture = draw.NoTexture
local math_Clamp = math.Clamp
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local RealTime = RealTime
local IsValid = IsValid

local CVAR_PIP_MODE = CreateClientConVar("zs_pipscope", "1", true, false, "画中画瞄准镜质量：1=新版(独立渲染) 0=原版(FOV缩放+遮罩)", 0, 1)

-- [取值归一] 0=原版，非 0=新版；旧档残留的 2 自动归入新版
local function GetPIPMode()
	if CVAR_PIP_MODE:GetInt() <= 0 then return 0 end
	return 1
end
local CVAR_PIP_FPSLOCK = CreateClientConVar("zs_pip_fpslock", "0", true, false, "PIP 画面刷新帧率上限：0=每帧渲染 30/60=复用帧节省性能", 0, 240)
local CVAR_PIP_DEBUG = CreateClientConVar("zs_pip_debug", "0", true, false, "PIP 管线调试信息显示（2=含 RT 直绘预览与像素采样）", 0, 5)
local CVAR_PIP_SHADER = CreateClientConVar("zs_pip_lensshader", "1", true, false, "镜头着色器：畸变+色差+暗角（需 DX9+，自带编译版无需 ARC9）", 0, 1)
local CVAR_PIP_PARALLAX = CreateClientConVar("zs_pip_parallax", "1", true, false, "镜内画面窗口：≤1=中心锁定(默认,镜内中心=开镜前准星=弹着点) >1=夸张浮动(观感优先,精度不保证)", 0, 2)
local CVAR_PIP_SHADOW = CreateClientConVar("zs_pip_shadow", "1", true, false, "镜筒阴影层叠强度倍率：0=关闭 1=ARC9 标准 2=加强", 0, 2)

-- [镜内显示内容] 分划板样式 / 自定义颜色 / 亮度 / 读数开关 / 视线门控
local CVAR_SCOPE_RETICLE = CreateClientConVar("zs_scope_reticle", "auto", true, false, "分划板样式覆盖：auto=武器默认 | mil-dot/cross/dot/chevron/german/tdot/acog | 材质路径")
local CVAR_SCOPE_RETCUSTOM = CreateClientConVar("zs_scope_retcustom", "0", true, false, "使用自定义分划板颜色（覆盖武器默认色）", 0, 1)
local CVAR_SCOPE_RETR = CreateClientConVar("zs_scope_retr", "190", true, false, "自定义分划板颜色 R")
local CVAR_SCOPE_RETG = CreateClientConVar("zs_scope_retg", "45", true, false, "自定义分划板颜色 G")
local CVAR_SCOPE_RETB = CreateClientConVar("zs_scope_retb", "45", true, false, "自定义分划板颜色 B")
local CVAR_SCOPE_RETA = CreateClientConVar("zs_scope_reta", "255", true, false, "自定义分划板颜色 A")
local CVAR_SCOPE_BRIGHT = CreateClientConVar("zs_scope_brightness", "1", true, false, "镜内画面亮度倍率", 0.2, 2)
local CVAR_SCOPE_INFO = CreateClientConVar("zs_scope_info", "1", true, false, "开镜时显示变焦倍率读数", 0, 1)
local CVAR_SCOPE_EYECHECK = CreateClientConVar("zs_scope_eyecheck", "0", true, false, "视线偏离镜头法线时镜内画面淡出为暗玻璃（ARC9 同款）。默认关：要求镜片面片法线沿镜筒轴向（SCK 手调面片若带角度会误杀画面）", 0, 1)

-- [镜片填充校准] 叠加层 + 临时覆盖：SCK 管位置，这套管"画面圆/多边形与筒口的贴合"
-- 用法：手持武器（无需开镜）zs_lens_show 1 → 看边界描边与筒口的关系 →
--       zs_lens_radius / zs_lens_chamfer 实时微调 → zs_lens_dump 打印最终值贴回文件 →
--       zs_lens_reset 清除临时覆盖。覆盖仅内存态，不影响其他玩家。
local CVAR_LENS_SHOW = CreateClientConVar("zs_lens_show", "0", true, false, "镜片裁剪边界校准描边叠加显示", 0, 1)
local CVAR_LENS_RADIUS = CreateClientConVar("zs_lens_radius", "-1", true, false, "临时覆盖镜片可见圆半径比（-1=用武器文件值）", -1, 1)
local CVAR_LENS_CHAMFER = CreateClientConVar("zs_lens_chamfer", "", true, false, "临时覆盖切角速记，格式 tl,tr,br,bl（空=用武器文件值），如 0.22,0,0.25,0")

-- [自定义颜色缓存] 回调重建，避免每帧 Color 分配
local COLOR_CUSTOM_CACHE = Color(190, 45, 45, 255)
local function RebuildCustomColorCache()
	COLOR_CUSTOM_CACHE = Color(
		math_Clamp(CVAR_SCOPE_RETR:GetInt(), 0, 255),
		math_Clamp(CVAR_SCOPE_RETG:GetInt(), 0, 255),
		math_Clamp(CVAR_SCOPE_RETB:GetInt(), 0, 255),
		math_Clamp(CVAR_SCOPE_RETA:GetInt(), 0, 255))
end
RebuildCustomColorCache()
cvars.AddChangeCallback("zs_scope_retr", RebuildCustomColorCache, "ZSPipeline.RetColorR")
cvars.AddChangeCallback("zs_scope_retg", RebuildCustomColorCache, "ZSPipeline.RetColorG")
cvars.AddChangeCallback("zs_scope_retb", RebuildCustomColorCache, "ZSPipeline.RetColorB")
cvars.AddChangeCallback("zs_scope_reta", RebuildCustomColorCache, "ZSPipeline.RetColorA")

-- [镜内亮度] 统一取值出口：pic.vmt 带 $vertexcolor，SetDrawColor 直接生效
local function GetScopeBrightness()
	return math_Clamp(CVAR_SCOPE_BRIGHT:GetFloat(), 0.2, 2)
end

-- [前置声明] 分划板绘制与视线门控在文件后段定义，昂贵渲染路径运行时调用
local PaintReticle
local GetLensFacingFade

---------------- [渲染目标] ----------------
local scrw, scrh = ScrW(), ScrH()
local rt_pic_w, rt_pic_h = 1024, 1024      -- 方形渲染视口边长（封顶 2048）
local rt_u0, rt_v0, rt_u1, rt_v1 = 0, 0, 1, 1 -- 方形区域在整帧 RT 中的 UV 子矩形

-- [架构说明] LITERAL 方形尺寸 + SEPARATE 独立深度 + POINTSAMPLE 点采样：
--  - FULL_FRAME_BUFFER 从帧缓冲池分配，主场景渲染会直接覆盖其内容（画面随准星漂移）；
--  - SHARED 深度与整帧深度缓冲尺寸不匹配，会产生局部黑块；
--  - SEPARATE 为本 RT 专属深度，两者皆避；
--  - POINTSAMPLE 禁用双线性/mip：否则缩放采样时红绿条会被混合成"纯色块"。
local FLAG_CLAMP_NOMIP = bit.bor(4, 8, 256, 512) -- CLAMP_S | CLAMP_T | NOMIP | NOLOD

local rt_pic = GetRenderTargetEx("zs_pip_pic", rt_pic_w, rt_pic_h,
	RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE,
	bit.bor(FLAG_CLAMP_NOMIP, 1), -- 追加 POINTSAMPLE(1)：禁用过滤混合
	0, IMAGE_FORMAT_RGBA8888)

-- [着色器输出] lens shader 的结果写入这里（不能与采样源同一个 RT，乒乓结构）
local rt_pass = GetRenderTargetEx("zs_pip_pass", rt_pic_w, rt_pic_h,
	RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
	bit.bor(FLAG_CLAMP_NOMIP, 1), 0, IMAGE_FORMAT_RGBA8888)

-- [ZS 自带编译版镜头 shader] 字节码位于 shaders/fxc/（源自 ARC9 工具链，已内置无依赖）
local mat_lens = Material("zombiesurvival/pip/lens")

-- [完整移植] ARC9 cl_pipscope_new.lua 的 CPU 侧 shader 参数计算：
-- 镜头物理(K/CA)、暗角形状、眼距影响，与 ARC9 显示效果同源。
-- eye_x/eye_y: 归一化眼偏移(0.5=居中)；eye_dist: 眼距；camult/kmult: 强度倍率。

local LENS_K_BASE = -0.4          -- 镜头畸变 K（ARC9 默认）
local CA_STRENGTH = 1.25          -- 色差强度（ARC9 默认）
local VIG_FORG_BASE = 5.5         -- 暗角宽容度（ARC9 默认）
local VIG_OFFSET = 4.75           -- 暗角偏移
local VIG_R1 = 0.124              -- 暗角半径1
local VIG_R2 = 0.7                -- 暗角半径2

-- [浮动视差 · ARC9 同源参数]
local EYE_OFFSET_INFLUENCE = 0.8    -- 眼偏移对暗角/色差中心的影响幅度（ARC9 shader_EYE_OFFSET_INFLUENCE）
local EYE_DISTANCE_INFLUENCE = 0.1  -- 眼距影响系数（ARC9 shader_EYE_DISTANCE_INFLUENCE）
local PIP_HEADROOM = 1.5            -- RT 渲染 FOV 余量倍数：多出的视野供采样窗口漂移，实现"画面浮在镜筒里"

local function Arc9Smoothstep(edge0, edge1, x)
	local t = math_Clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- [完整移植] ARC9 CalculateShaderCPU：眼位实时驱动暗角中心/半径、色差方向与强度，
-- 头部相对镜片漂移时暗角随之偏移 —— "暗角随头部漂移"的完整体验。
-- eye_x/eye_y: 归一化眼偏移(0~1, 0.5=居中)；eye_dist: 眼距系数；camult/kmult: 强度倍率。
local function UpdateLensParams(w, h, eye_x, eye_y, eye_dist, camult, kmult)
	if not mat_lens or mat_lens:IsError() then return end

	local scrw2, scrh2 = ScrW(), ScrH()
	local scrlength = math.sqrt(scrw2 * scrw2 + scrh2 * scrh2)

	eye_x = eye_x or 0.5
	eye_y = eye_y or 0.5
	eye_dist = eye_dist or 0.1
	camult = camult or 1
	kmult = kmult or 1

	local eyelength = math.sqrt(eye_x * eye_x + eye_y * eye_y)

	local center_p_x = scrw2 * 0.5
	local center_p_y = scrh2 * 0.5

	local mouse_p_x, mouse_p_y
	if eyelength < 0.01 then
		mouse_p_x, mouse_p_y = center_p_x, center_p_y
	else
		mouse_p_x = eye_x * scrw2
		mouse_p_y = eye_y * scrh2
	end

	local dir_p_x = mouse_p_x - center_p_x
	local dir_p_y = mouse_p_y - center_p_y
	local dir_len = math.sqrt(dir_p_x * dir_p_x + dir_p_y * dir_p_y)

	local norm_dir_x, norm_dir_y = 0, 0
	if dir_len > 1 then
		norm_dir_x = dir_p_x / dir_len
		norm_dir_y = dir_p_y / dir_len
	end

	-- 暗角主中心：随眼偏移方向推移
	local max_dist = 0.25 * scrlength * VIG_FORG_BASE
	local t = math_Clamp(dir_len / max_dist, 0, 1)

	local offset_len = VIG_OFFSET * math_min(scrw2, scrh2) * t
	local c1_p_x = center_p_x + norm_dir_x * offset_len * 1.75
	local c1_p_y = center_p_y + norm_dir_y * offset_len * 1.75

	mat_lens:SetFloat("$c0_x", c1_p_x)
	mat_lens:SetFloat("$c0_y", c1_p_y)

	-- 暗角半径随眼距收放（贴近镜片时视野扩张）
	local rad1_p = ((0.8 - eye_dist) + VIG_R1) * scrh2

	mat_lens:SetFloat("$c0_z", rad1_p)
	mat_lens:SetFloat("$c0_w", (0.55 - eye_dist) * rad1_p)

	-- 次级暗角中心：反向回拉，形成边缘厚度感
	local c2_p_x = center_p_x - norm_dir_x * offset_len * t * t
	local c2_p_y = center_p_y - norm_dir_y * offset_len * t * t

	mat_lens:SetFloat("$c1_x", c2_p_x)
	mat_lens:SetFloat("$c1_y", c2_p_y)

	-- 色差：方向沿眼偏移，强度随偏移量与眼距增长
	local mouse_ca_boost = t * 200 * camult
	local lateral_ca = (0.025 + eye_dist / 15) * (1 + mouse_ca_boost)
	local ca_base = (0.5 + camult) * 1.5
	local forg_scale = (1 / VIG_FORG_BASE * VIG_FORG_BASE) * 0.05
	local ca_t = t * 0.5 + Arc9Smoothstep(0.02, 0.2, t) * 100
	local ca_scale = ca_base * forg_scale * ca_t * 0.5

	mat_lens:SetFloat("$c2_x", norm_dir_x * ca_scale * 2)
	mat_lens:SetFloat("$c2_y", norm_dir_y * ca_scale * 2)
	mat_lens:SetFloat("$c2_z", lateral_ca * 0.2)
	mat_lens:SetFloat("$c2_w", lateral_ca * 0.8 * t)

	mat_lens:SetFloat("$c3_x", LENS_K_BASE * kmult)
	mat_lens:SetFloat("$c3_z", scrw2)
	mat_lens:SetFloat("$c3_w", scrh2)
end

-- [显示材质] 采用文件 VMT（$basetexture 直引 _rt_zs_pip_*）：
-- CreateMaterial + SetTexture 的运行时绑定在部分驱动/渲染路径下会出现
-- "采样内容与实际写入不一致"（红绿条被混色显示）的兼容性问题；
-- 文件材质走引擎原生命名解析，配合每帧显式 SetTexture 双保险。
local mat_pic = Material("zombiesurvival/pip/pic")

-- [手感叠层贴图] 源自 ARC9（已内置 content，无外部依赖）：
-- shadow3 = 镜筒前阴影大渐变 / shadow2 = 全局柔影 / ahmad = 分划板后小阴影
local mat_shadow_front = Material("zombiesurvival/pip/shadow3", "mips smooth")
local mat_shadow_global = Material("zombiesurvival/pip/shadow2", "mips smooth")
local mat_shadow_back = Material("zombiesurvival/pip/ahmad", "mips smooth")

local PIP_READY = false

local function RebuildRenderTargets()
	scrw, scrh = ScrW(), ScrH()
	rt_pic_w = math_Clamp(math_min(scrw, scrh), 256, 2048)
	rt_pic_h = rt_pic_w

	rt_pic = GetRenderTargetEx("zs_pip_pic", rt_pic_w, rt_pic_h,
		RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE,
		bit.bor(FLAG_CLAMP_NOMIP, 1),
		0, IMAGE_FORMAT_RGBA8888)
	rt_pass = GetRenderTargetEx("zs_pip_pass", rt_pic_w, rt_pic_h,
		RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE,
		bit.bor(FLAG_CLAMP_NOMIP, 1), 0, IMAGE_FORMAT_RGBA8888)

	mat_pic:SetTexture("$basetexture", rt_pic)

	PIP_READY = true
end

-- [方形视口几何] LITERAL 方形 RT：整幅即画面，UV 恒为全幅
local function UpdatePicViewport()
	rt_pic_w = math_Clamp(math_min(scrw, scrh), 256, 2048)
	rt_pic_h = rt_pic_w
	rt_u0, rt_v0, rt_u1, rt_v1 = 0, 0, 1, 1
end

-- 初始化 + 分辨率变化时重建（换分辨率后 RT 尺寸必须跟随，否则画面拉伸错位）
RebuildRenderTargets()
UpdatePicViewport()
hook.Add("OnScreenSizeChanged", "ZSPipeline.PIPResize", function()
	RebuildRenderTargets()
	UpdatePicViewport()
end)

---------------- [锁帧复用] ----------------
local next_render_time = 0
local pip_zoom_hint_shown = false -- 滚轮调焦提示：每会话只提示一次
local last_capture_time = 0 -- 像素采样节流（GPU→CPU 同步读取昂贵且易崩）

local function ShouldRenderNow()
	local fpslock = CVAR_PIP_FPSLOCK:GetInt()
	if fpslock <= 0 then return true end

	local now = RealTime()
	if now < next_render_time then return false end
	next_render_time = now + 1 / fpslock
	return true
end

---------------- [状态查询] ----------------

-- ==== UsesPIPScope - 武器本局是否走 PIP 渲染路径（与开镜进度无关的稳定判定） ====
-- FOV/灵敏度目标必须全程一致：若按进度中段切换会造成"先深缩放再弹回"的观感断裂
function SWEP:UsesPIPScope()
	if not PIP_READY then return false end
	if not GAMEMODE or GAMEMODE.DisableScopes or GAMEMODE.NoIronsights then return false end
	if GetPIPMode() < 1 then return false end

	return self:WantsPIPScope()
end

-- ==== IsPIPActive - 当前是否处于 PIP 画面生效阶段（合成/镜片切换时机） ====
function SWEP:IsPIPActive()
	return self:UsesPIPScope() and (self.GetIronsightDelta and self:GetIronsightDelta() or 0) > 0.75
end

-- [合成透明度] 开镜进度 0.75~1 区间平滑淡入分划板，避免画面突跳
local function GetCompositeAlpha(wep)
	local delta = wep.GetIronsightDelta and wep:GetIronsightDelta() or 0
	if delta <= 0.75 then return 0 end

	return math.ease.OutQuad(math_Clamp((delta - 0.75) / 0.25, 0, 1))
end

---------------- [滚轮动态倍率（参考 Unity 瞄具教程第三种方式的脚本控制步骤）] ----------------
-- 完全开镜时滚动滚轮在 [ScopeMagMin, ScopeMagMax] 区间内连续调节光学倍率，
-- 渲染 FOV 与鼠标灵敏度同步跟随，实现"指哪打哪"的变焦体验。

local ZOOM_STEP = 1.12 -- 每格滚轮的倍率乘数

-- [倍率记忆] 按武器类记忆滚轮倍率：收镜、切枪、重生后再开镜都自动恢复上次倍率，
-- 不再每次开镜都回到标称倍率。会话级持久（重进地图后从标称倍率重新开始）
local ZOOM_MEMORY = {}

function SWEP:GetEffectiveScopeMagnification()
	local base = self:GetScopeMagnification()
	local adj = self.m_fPIPZoomAdj
	if not adj then
		-- 实体上没有调整值（未调过/收镜清空/实体被替换）时恢复类记忆
		adj = ZOOM_MEMORY[self:GetClass()]
	end
	if not adj then return base end

	return math_Clamp(base * adj, self.ScopeMagMin or 2, self.ScopeMagMax or math_max(base * 2, 8))
end

-- ==== PIPAdjustZoom - 调整光学倍率（delta>0 放大 / <0 缩小） ====
-- 返回 true 表示本次输入已被消费
function SWEP:PIPAdjustZoom(delta)
	if not self:IsPIPActive() then return false end

	-- 倍率调整量：以基准倍率为锚点做乘法缩放，clamp 回武器上下限
	local base = self:GetScopeMagnification()
	local cur = self:GetEffectiveScopeMagnification() / base
	local nextadj = cur * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
	local lo = (self.ScopeMagMin or 2) / base
	local hi = math_max(self.ScopeMagMax or base * 2, 8) / base

	self.m_fPIPZoomAdj = math_Clamp(nextadj, lo, hi)
	ZOOM_MEMORY[self:GetClass()] = self.m_fPIPZoomAdj -- 写入类记忆，下次开镜恢复
	self.m_fPIPZoomChangedAt = RealTime()
	return true
end

-- [滚轮拦截] 滚轮默认绑定 invnext/invprev 控制台命令，引擎在钩子返回之外
-- 直接执行切枪（MouseWheelPressed 返回 true 压不住）。PlayerBindPress 在
-- 绑定层拦截：完全开镜时吞掉切枪命令并转投倍率调节。
hook.Add("PlayerBindPress", "ZSPipeline.PIPZoom", function(ply, bind, pressed)
	if not pressed then return end
	if bind ~= "invnext" and bind ~= "invprev" then return end

	local wep = MySelf and MySelf.GetActiveWeapon and MySelf:GetActiveWeapon()
	if not IsValid(wep) or not wep.WantsPIPScope then return end

	local delta = bind == "invprev" and 1 or -1 -- 上滚放大 / 下滚缩小
	if wep:PIPAdjustZoom(delta) then
		return true -- 消费绑定，阻止开镜时误切枪
	end
end)

-- [倍率记忆] 旧版在此收镜即清空调整值（下次开镜回标称倍率），已废弃：
-- 倍率现按武器类持久记忆（ZOOM_MEMORY），开镜即恢复上次的倍率

---------------- [视口缓存] ----------------
-- [关键修复] PreRender 阶段引擎视口尚未初始化，render.GetViewSetup() 返回零值，
-- 导致镜内 FOV 被算成 1°——画面变成"准星所指表面的纯色块"且随瞄准变化。
-- 这里在 CalcView（每帧视角计算完成后）缓存真实视口，供 PreRender 渲染使用。
local cached_view_origin, cached_view_angles, cached_view_fov

hook.Add("CalcView", "ZSPipeline.PIPViewCache", function(ply, pos, ang, fov)
	cached_view_origin = pos
	cached_view_angles = ang
	cached_view_fov = fov
end)

local function GetCachedView()
	local ply = MySelf
	local origin = cached_view_origin or (IsValid(ply) and ply:EyePos() or EyePos())
	local angles = cached_view_angles or (IsValid(ply) and ply:EyeAngles() or EyeAngles())
	local fov = cached_view_fov
	if not fov or fov < 30 then fov = IsValid(ply) and ply:GetFOV() or 90 end
	if not fov or fov < 30 then fov = 90 end

	return origin, angles, fov
end

-- ==== GetPIPLensTransform - 镜片元素的世界变换（视差与眼位计算的基础） ====
-- 首选 cl_model.lua Quad 分支每帧写入的 v.info（与 cam.Start3D2D 完全一致的变换）；
-- 尚未渲染过首帧时按同一公式自行推导（GetBoneOrientation + 元素 pos/angle）。
local function GetPIPLensTransform(wep)
	local elems = wep.VElements
	local elem = elems and elems[wep.ScopeLensElement]
	if not elem then return end

	local info = elem.info
	if info and info.pos and info.angle then
		return info.pos, info.angle
	end

	local owner = wep:GetOwner()
	local vm = IsValid(owner) and owner:GetViewModel()
	if not IsValid(vm) or not wep.GetBoneOrientation then return end

	local pos, ang = wep:GetBoneOrientation(elems, elem, vm)
	if not pos then return end

	local drawpos = pos + ang:Forward() * elem.pos.x + ang:Right() * elem.pos.y + ang:Up() * elem.pos.z
	ang = Angle(ang.p, ang.y, ang.r) -- 副本：RotateAroundAxis 会原地改写
	ang:RotateAroundAxis(ang:Up(), elem.angle.y)
	ang:RotateAroundAxis(ang:Right(), elem.angle.p)
	ang:RotateAroundAxis(ang:Forward(), elem.angle.r)

	return drawpos, ang
end

-- ==== ComputePIPParallaxWindow - 求解 RT 采样窗口（uc, vc）====
-- 默认（zs_pip_parallax ≤ 1）【中心锁定】：窗口恒为 RT 中心 (0.5, 0.5)。
--   镜片中心显示的即 RT 中心 = 本帧真实视线方向 = 开镜前准星所指；
--   分划板烘焙在 RT 中心，恒现于镜心。放大中心、准星、弹着点三者无条件重合。
--   为什么默认不再做视差补偿：满瞄时目镜贴眼（沿视线到镜面距离 t 常不足 0.5 单位），
--   交点相对镜心的横向偏移除以镜片半宽（约 0.5 单位）后必然发散，只能被钳在窗口
--   边界（实测 uc/vc 恒饱和在 ±1/6），分划板随之偏离弹着点——这正是旧版
--   "镜内放大中心 ≠ 开镜前中心"的根源，数学上无解，只能锁定。
-- zs_pip_parallax > 1【夸张浮动】：射线-平面精确求交 + 边界钳制，画面在镜筒内
--   浮动的观感模式；分划板随画面漂移，精度不保证（纯观感，实战慎用）。
-- [返回] uc, vc（锁定模式永不失败）；浮动模式求交失败时返回 nil（调用方保留上一帧窗口）
local function ComputePIPParallaxWindow(wep, aspect)
	aspect = math_Clamp(aspect or 1, 0.25, 4)
	local spanV = 1 / PIP_HEADROOM
	local spanU = math_min(spanV * aspect, 1)

	if CVAR_PIP_PARALLAX:GetFloat() <= 1 then
		return 0.5, 0.5 -- 中心锁定：镜内中心恒为开镜前准星方向（弹着点）
	end

	local origin, angles = GetCachedView()
	local lpos, lang = GetPIPLensTransform(wep)
	if not lpos or not lang or not origin then return end

	-- [射线-平面求交] t = ((lpos - eye)·n) / (aim·n)
	local aimfwd = angles:Forward()
	local nfwd = lang:Forward()
	local denom = aimfwd:Dot(nfwd)
	if math.abs(denom) < 0.05 then return end -- 视线与镜面近平行（面片侧对视线）

	local t = (lpos - origin):Dot(nfwd) / denom
	if t <= 0.05 or t > 64 then return end -- 交点在身后/过远的异常姿态

	-- 交点相对面片中心的本地坐标（x=Right，y=-Up[表面 y 向下]）
	local off = origin + aimfwd * t - lpos
	local elem = wep.VElements and wep.VElements[wep.ScopeLensElement]
	local halfsize = (tonumber(elem and elem.size) or 0.05) * 20
	local hw = halfsize * aspect
	local hh = halfsize
	if hw < 0.01 or hh < 0.01 then return end

	local maxshift_u = (1 - spanU) / 2 -- 窗口不得滑出 RT 边界
	local maxshift_v = (1 - spanV) / 2

	local uc = 0.5 + math_Clamp(-(off:Dot(lang:Right()) / hw) * spanU * 0.5 * parallax, -maxshift_u, maxshift_u)
	local vc = 0.5 + math_Clamp((off:Dot(lang:Up()) / hh) * spanV * 0.5 * parallax, -maxshift_v, maxshift_v)

	return uc, vc
end

---------------- [昂贵模式：独立渲染] ----------------

function SWEP:RenderPIPPicture(alpha)
	-- [视线门控] 开启 zs_scope_eyecheck 时画面+烘焙分划板一起淡出（一致行为）
	if CVAR_SCOPE_EYECHECK:GetBool() and GetLensFacingFade then
		alpha = alpha * GetLensFacingFade(self)
	end

	local mag = self:GetEffectiveScopeMagnification()
	local origin, angles, basefov = GetCachedView()

	-- [弹道视角] RT 改沿武器真实弹道方向渲染（GetShootPos + EyeAngles，与 ShootBullets
	-- 的 GetAimVector 完全同源）：弹着点恒落在 RT 中心、与烘焙分划板本征重合（同一张
	-- 图片内不可能分离）——视角 punch / 镜头弹簧（cl_camera 只改主视角不改弹道）
	-- 从此无法拆散"分划板-弹着点"。代价：开火时镜内画面保持稳定不随镜头弹簧踢动
	--（瞄具稳定观感，与 ARC9 镜头表现一致）
	local pipowner = self:GetOwner()
	if IsValid(pipowner) then
		origin = pipowner:GetShootPos()
		angles = pipowner:EyeAngles()
	end

	-- 镜内 FOV = 主视角当前 FOV（已含轻微 ADS 变焦与镜头后坐力冲击）÷ 光学倍率
	-- 下限 5°：即使上游数据异常也不会退化成"纯色块"视图
	local rtfov = math_max(5, basefov / mag)
	self.m_fPIPRenderFOV = rtfov

	-- 每帧求解采样窗口并缓存（DrawPIPLens 在 3D2D 内只读缓存值）：
	-- 默认恒为 RT 中心（放大中心 = 开镜前准星方向 = 弹着点，永不失败不冻结）；
	-- 浮动模式（zs_pip_parallax>1）为射线-平面求交，失败帧保留上一帧窗口防跳变
	local uc, vc = ComputePIPParallaxWindow(self)
	if uc then
		self.m_fPIPUc = uc
		self.m_fPIPvc = vc
	end

	UpdatePicViewport() -- 每帧刷新尺寸（分辨率变化即时生效）
	render.PushRenderTarget(rt_pic, 0, 0, rt_pic_w, rt_pic_h)
		render.Clear(0, 0, 0, 255)

		if CVAR_PIP_DEBUG:GetInt() >= 3 then
			-- [时机测试] 不跑 RenderView，直接画左红右绿色条：
			-- 预览出现色条 => 推栈/绘制/采样全通；仍看不到 => RT 绑定层问题
			cam.Start2D()
				surface_SetDrawColor(255, 0, 0)
				surface_DrawRect(0, 0, rt_pic_w * 0.5, rt_pic_h)
				surface_SetDrawColor(0, 255, 0)
				surface_DrawRect(rt_pic_w * 0.5, 0, rt_pic_w * 0.5, rt_pic_h)
			cam.End2D()
		else
		render.RenderView({
			x = 0,
			y = 0,
			w = rt_pic_w,
			h = rt_pic_h,
			origin = origin,
			angles = angles,
			fov = rtfov * PIP_HEADROOM, -- 余量视野：中央 1/HEADROOM 为标准画面，边缘供视差窗口漂移
			znear = 8,
			zfar = 30000,
			drawviewmodel = false,
			dopostprocess = false,
		})
		end

		-- [调试标记] debug>=2：四角纯色块 + 白色描边，肉眼确认 RT 合成链路
		if CVAR_PIP_DEBUG:GetInt() >= 2 then
			cam.Start2D()
				local m = rt_pic_w * 0.06
				surface_SetDrawColor(255, 0, 0)   surface_DrawRect(0, 0, m, m)
				surface_SetDrawColor(0, 255, 0)   surface_DrawRect(rt_pic_w - m, 0, m, m)
				surface_SetDrawColor(0, 0, 255)   surface_DrawRect(0, rt_pic_h - m, m, m)
				surface_SetDrawColor(255, 255, 0) surface_DrawRect(rt_pic_w - m, rt_pic_h - m, m, m)
				surface_SetDrawColor(255, 255, 255)
				local t = math_max(1, rt_pic_w * 0.004)
				surface_DrawRect(0, 0, rt_pic_w, t)
				surface_DrawRect(0, rt_pic_h - t, rt_pic_w, t)
				surface_DrawRect(0, 0, t, rt_pic_h)
				surface_DrawRect(rt_pic_w - t, 0, t, rt_pic_h)
			cam.End2D()
		end

		-- [独立通道后处理] 夜视/FLIR/热成像等效果只作用于镜内画面，不污染主视角。
		-- 武器可定义 ScopePaintFunc(wep) 在 RT 内追加绘制。
		if self.ScopePaintFunc then
			cam.Start3D(origin, angles, rtfov * PIP_HEADROOM, rt_pic_w, rt_pic_h)
				cam.Start2D()
					self:ScopePaintFunc(self)
				cam.End2D()
			cam.End3D()
		end
		-- [深度诊断] zs_pip_debug>=2：读取 RT 三点像素值。
		-- ⚠ CapturePixels 是 GPU→CPU 强同步读取，每帧调用会在部分驱动上直接崩溃，
		-- 因此独立节流到 2Hz，与渲染频率（zs_pip_fpslock）解耦。
		if CVAR_PIP_DEBUG:GetInt() >= 2 and RealTime() >= (last_capture_time or 0) then
			last_capture_time = RealTime() + 0.5

			render.CapturePixels()
			-- ReadPixel 返回 r,g,b,a 四个独立数值，必须先包成表再入表
			local function ReadPx(x, y)
				local r, g, b = render.ReadPixel(math_floor(x), math_floor(y))
				return { r = r or 0, g = g or 0, b = b or 0 }
			end
			self.m_tPIPDebugPx = {
				ReadPx(rt_pic_w * 0.25, rt_pic_h * 0.5),
				ReadPx(rt_pic_w * 0.5, rt_pic_h * 0.5),
				ReadPx(rt_pic_w * 0.75, rt_pic_h * 0.5),
			}
		end
	render.PopRenderTarget()

	-- [镜头着色器] rt_pic(画面) -> lens shader -> rt_pass(显示源)，乒乓不共写
	local use_shader = CVAR_PIP_SHADER:GetBool()
		and mat_lens and not mat_lens:IsError()
		and render.GetDXLevel() >= 90

	if use_shader then
		-- [真实眼位] 镜片世界坐标投影到屏幕 → 归一化眼偏移 + 眼距（ARC9 DrawRTReticle 同式）。
		-- PreRender 时投影矩阵为上一帧结果，1 帧滞后对暗角漂移无感知。
		local lpos = GetPIPLensTransform(self)
		local scrw_now, scrh_now = ScrW(), ScrH()

		if lpos then
			local toscreen = lpos:ToScreen()
			local offsetx = (math_Clamp(toscreen.x / scrw_now, 0.3, 0.8) - 0.5) * EYE_OFFSET_INFLUENCE
			local offsety = (math_Clamp(toscreen.y / scrh_now, 0.3, 0.8) - 0.5) * EYE_OFFSET_INFLUENCE
			local mreow = math_max(math.abs(offsetx), math.abs(offsety))
			local eyedist = lpos:Distance(origin) + mreow * 20
			local eye_dist = math_Clamp((mreow + eyedist * 0.1) * EYE_DISTANCE_INFLUENCE, -0.15, 0.8)

			UpdateLensParams(rt_pic_w, rt_pic_h, offsetx + 0.5, offsety + 0.5, eye_dist)
		else
			UpdateLensParams(rt_pic_w, rt_pic_h, 0.5, 0.5, 0.1)
		end

		mat_lens:SetTexture("$basetexture", rt_pic)

		render.PushRenderTarget(rt_pass, 0, 0, rt_pic_w, rt_pic_h)
			render.Clear(0, 0, 0, 255)
			cam.Start2D()
				render.SetMaterial(mat_lens)
				render.DrawScreenQuad()
			cam.End2D()
		render.PopRenderTarget()

		mat_pic:SetTexture("$basetexture", rt_pass)
	else
		mat_pic:SetTexture("$basetexture", rt_pic)
	end

	-- [分划板烘焙 · 结构性防错位] 分划板直接画进显示 RT 中心，与画面同源永不分离：
	-- RT 中心 = 视线方向渲染内容，窗口构造保证 RT 中心显示在视线与镜面交点上
	-- （=屏幕中心=弹着点），三者天然重合，不存在世界空间面片的各类失效模式。
	-- 直径取窗口高度的 96%（窗口恒包含 RT 中心，最大漂移也不会裁掉分划板）
	local disp_rt = use_shader and rt_pass or rt_pic
	local ret_dia = rt_pic_h * (1 / PIP_HEADROOM) * 0.96
	render.PushRenderTarget(disp_rt, 0, 0, rt_pic_w, rt_pic_h)
		cam.Start2D()
			PaintReticle(self, rt_pic_w * 0.5, rt_pic_h * 0.5, ret_dia, alpha)
		cam.End2D()
	render.PopRenderTarget()

	self.m_fPIPLastRender = RealTime()
end

---------------- [分划板] ----------------

local COLOR_RETICLE_DEFAULT = Color(190, 45, 45)

-- 细线矩形（以中心线定位的实心条）
local function DrawBar(x, y, w, h, col, alpha)
	surface_SetDrawColor(col.r, col.g, col.b, (col.a or 255) * alpha)
	surface_DrawRect(x, y, w, h)
end

-- mil-dot：细十字主线 + 中心开缝 + 下半密位点 + 四向粗柱（经典狙击分划）
local function PaintReticleMilDot(cx, cy, dia, col, alpha)
	local t = math_max(1, dia * 0.0022)      -- 主线粗细
	local post_t = math_max(2, dia * 0.006)  -- 粗柱粗细
	local gap = dia * 0.02                   -- 中心开缝半宽
	local half = dia * 0.485

	DrawBar(cx - half, cy - t * 0.5, half - gap, t, col, alpha)
	DrawBar(cx + gap, cy - t * 0.5, half - gap, t, col, alpha)
	DrawBar(cx - t * 0.5, cy - half, t, half - gap, col, alpha)
	DrawBar(cx - t * 0.5, cy + gap, t, half - gap, col, alpha)

	-- 下半密位点（越往下越疏，弹道下坠参考）
	local dot = math_max(2, dia * 0.0055)
	for i = 1, 6 do
		local dy = gap + i * dia * 0.05
		if dy < half * 0.85 then
			DrawBar(cx - dot * 0.5, cy + dy - dot * 0.5, dot, dot, col, alpha)
		end
	end

	-- 四向粗柱（快速捕捉镜口方向）
	local post_len = dia * 0.14
	DrawBar(cx - half, cy - post_t * 0.5, post_len, post_t, col, alpha)
	DrawBar(cx + half - post_len, cy - post_t * 0.5, post_len, post_t, col, alpha)
	DrawBar(cx - post_t * 0.5, cy - half, post_t, post_len, col, alpha)
	DrawBar(cx - post_t * 0.5, cy + half - post_len, post_t, post_len, col, alpha)
end

-- cross：极简全十字
local function PaintReticleCross(cx, cy, dia, col, alpha)
	local t = math_max(1, dia * 0.0018)
	local half = dia * 0.47
	DrawBar(cx - half, cy - t * 0.5, half * 2, t, col, alpha)
	DrawBar(cx - t * 0.5, cy - half, t, half * 2, col, alpha)
end

-- [造型基元] 粗线段（两点+宽度画旋转矩形），雪佛兰/德式/T 字/ACOG 共用
local function DrawThickLine(x1, y1, x2, y2, w, col, alpha)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.001 then return end

	local nx, ny = -dy / len * w * 0.5, dx / len * w * 0.5

	draw_NoTexture()
	surface_SetDrawColor(col.r, col.g, col.b, (col.a or 255) * alpha)
	surface_DrawPoly({
		{ x = x1 + nx, y = y1 + ny },
		{ x = x2 + nx, y = y2 + ny },
		{ x = x2 - nx, y = y2 - ny },
		{ x = x1 - nx, y = y1 - ny },
	})
end

-- 实心圆点（多边形近似；红点分划主体）
local function DrawDotShape(cx, cy, radius, segs, col, alpha)
	draw_NoTexture()
	surface_SetDrawColor(col.r, col.g, col.b, (col.a or 255) * alpha)

	local pts = {}
	for i = 1, segs do
		local a = math.rad(i * (360 / segs))
		pts[i] = { x = cx + math.cos(a) * radius, y = cy + math.sin(a) * radius }
	end
	surface_DrawPoly(pts)
end

-- 细环（短粗线段连成圆周；红点外圈/ACOG 主环共用）
local function DrawRing(cx, cy, radius, segs, w, col, alpha)
	for i = 1, segs do
		local a0 = math.rad((i - 1) * (360 / segs))
		local a1 = math.rad(i * (360 / segs))
		DrawThickLine(cx + math.cos(a0) * radius, cy + math.sin(a0) * radius,
			cx + math.cos(a1) * radius, cy + math.sin(a1) * radius, w, col, alpha)
	end
end

-- dot：中心红点 + 外圈细环（近战快瞄镜观感）
local function PaintReticleDot(cx, cy, dia, col, alpha)
	DrawDotShape(cx, cy, dia * 0.011, 16, col, alpha)
	DrawRing(cx, cy, dia * 0.3, 32, dia * 0.003, col, alpha * 0.45)
end

-- chevron：尖端朝下的 V 形箭头 + 尾点（ACOG 近距快瞄样式）
local function PaintReticleChevron(cx, cy, dia, col, alpha)
	local hw = dia * 0.06    -- 开口半宽
	local hh = dia * 0.05    -- 开口高度
	local tip = dia * 0.02   -- 尖端低于中心的距离
	local t = dia * 0.007

	DrawThickLine(cx - hw, cy + tip - hh, cx, cy + tip, t, col, alpha)
	DrawThickLine(cx + hw, cy + tip - hh, cx, cy + tip, t, col, alpha)
	DrawDotShape(cx, cy - dia * 0.09, math.max(1.2, dia * 0.004), 10, col, alpha)
end

-- german：德式三柱（左右下三根粗柱，无上梁）+ 中心细十字
local function PaintReticleGerman(cx, cy, dia, col, alpha)
	local pw = dia * 0.018   -- 柱宽
	local pl = dia * 0.4     -- 柱长
	local edge = dia * 0.455

	DrawBar(cx - edge, cy - pw * 0.5, pl, pw, col, alpha)
	DrawBar(cx + edge - pl, cy - pw * 0.5, pl, pw, col, alpha)
	DrawBar(cx - pw * 0.5, cy + edge - pl, pw, pl, col, alpha)

	PaintReticleCross(cx, cy, dia * 0.16, col, alpha)
end

-- tdot：细十字 + 四端内侧 T 形加厚块（快速捕捉方向）
local function PaintReticleTDot(cx, cy, dia, col, alpha)
	PaintReticleCross(cx, cy, dia, col, alpha)

	local d0 = dia * 0.4    -- 加厚块内沿距离
	local sl = dia * 0.07   -- 块长
	local sw = dia * 0.006  -- 块厚

	DrawBar(cx - sl * 0.5, cy - d0 - sw * 0.5, sl, sw, col, alpha)
	DrawBar(cx - sl * 0.5, cy + d0 - sw * 0.5, sl, sw, col, alpha)
	DrawBar(cx - d0 - sw * 0.5, cy - sl * 0.5, sw, sl, col, alpha)
	DrawBar(cx + d0 - sw * 0.5, cy - sl * 0.5, sw, sl, col, alpha)
end

-- acog：主环 + 内部小雪佛兰 + 四向刻度线
local function PaintReticleACOG(cx, cy, dia, col, alpha)
	local r = dia * 0.2

	DrawRing(cx, cy, r, 24, dia * 0.006, col, alpha * 0.9)

	-- 环内小号雪佛兰（复用 chevron 几何，按比例缩放）
	local hw, hh, tip, t = dia * 0.03, dia * 0.026, dia * 0.01, dia * 0.004
	DrawThickLine(cx - hw, cy + tip - hh, cx, cy + tip, t, col, alpha)
	DrawThickLine(cx + hw, cy + tip - hh, cx, cy + tip, t, col, alpha)

	-- 环外四向刻度
	for _, dir in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		DrawThickLine(cx + dir[1] * r * 1.06, cy + dir[2] * r * 1.06,
			cx + dir[1] * (r + dia * 0.04), cy + dir[2] * (r + dia * 0.04),
			dia * 0.004, col, alpha)
	end
end

-- [分划板注册表] 名称 → 绘制函数(cx, cy, dia, col, alpha)；材质路径与自绘函数不受影响
local RETICLE_PAINTERS = {
	["mil-dot"] = PaintReticleMilDot,
	["cross"] = PaintReticleCross,
	["dot"] = PaintReticleDot,
	["chevron"] = PaintReticleChevron,
	["german"] = PaintReticleGerman,
	["tdot"] = PaintReticleTDot,
	["acog"] = PaintReticleACOG,
}

---------------- [图片分划库 · 移植自 arc9_polyarms_project uplp_reticles] ----------------

--[[ ZS_SCOPE_RETICLE_IMAGES：可直接选用的贴图分划（1024² 透明 PNG，GMod 原生加载）。
	设置方式三选一：
	  1. 武器文件（该武器默认）：SWEP.ScopeReticle = "vgui/uplp_reticles/pso.png"
	  2. 控制台（客户端覆盖所有武器）：zs_scope_reticle vgui/uplp_reticles/pso.png
	  3. 选项菜单：武器设置 → 瞄准镜显示 → 分划板样式
	贴图按正方形铺满镜内画面区，透明部分不遮挡；表外路径同样可用
	（PaintReticle 对未知字符串按材质路径处理），content/materials 下均可。 ]]
ZS_SCOPE_RETICLE_IMAGES = {
	{ path = "vgui/uplp_reticles/pso.png", name = "PSO 俄式密位" },
	{ path = "vgui/uplp_reticles/pgo.png", name = "PGO" },
	{ path = "vgui/uplp_reticles/kobra.png", name = "Kobra" },
	{ path = "vgui/uplp_reticles/okp.png", name = "OKP" },
	{ path = "vgui/uplp_reticles/acog.png", name = "ACOG" },
	{ path = "vgui/uplp_reticles/acog2.png", name = "ACOG II" },
	{ path = "vgui/uplp_reticles/aug.png", name = "AUG 环形" },
	{ path = "vgui/uplp_reticles/g36.png", name = "G36" },
	{ path = "vgui/uplp_reticles/elca.png", name = "ELCAN" },
	{ path = "vgui/uplp_reticles/dedal.png", name = "Dedal 夜视" },
	{ path = "vgui/uplp_reticles/devo.png", name = "Devo" },
	{ path = "vgui/uplp_reticles/holo.png", name = "全息 I" },
	{ path = "vgui/uplp_reticles/holo2.png", name = "全息 II" },
	{ path = "vgui/uplp_reticles/holo3.png", name = "全息 III" },
	{ path = "vgui/uplp_reticles/holo4.png", name = "全息 IV" },
	{ path = "vgui/uplp_reticles/holo4c.png", name = "全息 IV 紧凑" },
	{ path = "vgui/uplp_reticles/holo5.png", name = "全息 V" },
	{ path = "vgui/uplp_reticles/dot.png", name = "红点 I" },
	{ path = "vgui/uplp_reticles/dot2.png", name = "红点 II" },
	{ path = "vgui/uplp_reticles/dot3.png", name = "红点 III" },
	{ path = "vgui/uplp_reticles/rds.png", name = "RDS" },
	{ path = "vgui/uplp_reticles/cross.png", name = "十字 I" },
	{ path = "vgui/uplp_reticles/cross2.png", name = "十字 II" },
	{ path = "vgui/uplp_reticles/trig.png", name = "三线" },
	{ path = "vgui/uplp_reticles/trig45.png", name = "三线 45°" },
}

-- 样式解析：客户端覆盖（zs_scope_reticle ≠ auto）优先于武器默认
local function ResolveReticleStyle(wep)
	local override = string.Trim(CVAR_SCOPE_RETICLE:GetString() or "")
	if override ~= "" and override ~= "auto" then return override end

	return wep.ScopeReticle or "mil-dot"
end

-- 颜色解析：勾选自定义时用玩家颜色，否则用武器默认色
local function ResolveReticleColor(wep)
	if CVAR_SCOPE_RETCUSTOM:GetBool() then return COLOR_CUSTOM_CACHE end

	return wep.ScopeReticleColor or COLOR_RETICLE_DEFAULT
end

function PaintReticle(wep, cx, cy, dia, alpha)
	alpha = alpha or 1
	if alpha <= 0 then return end

	local style = ResolveReticleStyle(wep)

	if isfunction(style) then
		style(wep, cx, cy, dia, alpha)
		return
	end

	local painter = RETICLE_PAINTERS[style]
	if painter then
		painter(cx, cy, dia, ResolveReticleColor(wep), alpha)
		return
	end

	if not Material(style):IsError() then
		-- 材质路径样式：整幅贴图居中铺满镜片
		surface_SetMaterial(Material(style))
		surface_SetDrawColor(255, 255, 255, 255 * alpha)
		surface_DrawTexturedRect(cx - dia * 0.49, cy - dia * 0.49, dia * 0.98, dia * 0.98)
	else
		RETICLE_PAINTERS["mil-dot"](cx, cy, dia, ResolveReticleColor(wep), alpha)
	end
end

---------------- [圆盘绘制工具（Quad 暗角与回退遮罩共用）] ----------------

-- 圆盘多边形缓存（顶点按参数角生成，绕序与社区通用实现一致）
local poly_cache = {}
local function BuildCirclePoly(radius)
	local key = math_floor(radius)
	local cached = poly_cache[key]
	if cached then return cached end

	local pts = {}
	for i = 0, 63 do
		local a = math.rad(i * (360 / 64))
		pts[i + 1] = { x = math.cos(a) * radius, y = math.sin(a) * radius }
	end
	poly_cache[key] = pts
	return pts
end

-- 绝对坐标实心圆（DrawPoly 需要绝对顶点；64 点临时表开销可忽略）
local function DrawFilledCircle(cx, cy, radius)
	local rel = BuildCirclePoly(radius)
	local abs = {}
	for i = 1, 64 do
		abs[i] = { x = cx + rel[i].x, y = cy + rel[i].y }
	end
	surface_DrawPoly(abs)
end


---------------- [镜片支持：Quad 面片（推荐）与 Model 材质交换] ----------------

--[[ [Quad 方案 · 推荐，对齐 Unity 教程做法]
	武器作者在 VElements 里自己加一块四边形面片贴在瞄准镜筒内：
		SWEP.ScopeLensElement = "pip_lens"
		SWEP.VElements = {
			["pip_lens"] = { type = "Quad", bone = "v_weapon.sg550_Parent", rel = "scope",
				pos = Vector(0, 0, -1), angle = Angle(0, 90, 0), size = 0.06 },
		}
	draw_func 无需手写：基座检测到 Quad 元素后自动注入 DrawPIPLens，
	开镜时该面片实时显示 RT 放大画面 + 边缘暗角，收镜显示深色玻璃底。
	pos/angle/size 进游戏微调即可（与 Unity 里拖 Quad 摆位置同理）。

	[镜片裁剪形状] 按镜子造型在元素上加 pip_shape（缺省 "circle"）：
		"circle"  圆镜：stencil 圆盘裁剪。可加 pip_radius = 0~1 收放可见圆
			  半径（默认 1 = 整个面片；size 放大留定位余量时用它把圆收回筒口）
		"square"  方镜/匣式镜：面片本身就是方的，全幅直绘，零 stencil 开销
		"poly"    异形镜（切角矩形、八角、任意轮廓），两种给点方式二选一：
			  pip_poly    = { {x=-1,y=-1}, {x=1,y=-1}, ... } 归一化顶点表
					（-1~1，运行时 × 面片半宽）
			  pip_chamfer = 切角矩形速记：数字=四角统一切割比，
					或 { tl=.25, tr=0, br=.25, bl=0 } 四角各自切
			  例：["pip_lens"] = { ..., pip_shape = "poly",
				  pip_chamfer = { tl = .22, br = .22 } }
			  （tl/tr/br/bl 对应面片本地坐标 -x-y / +x-y / +x+y / -x+y 四角，
			   实际视觉方位随面片 angle 摆放，进游戏对着调即可）

	[Model 方案 · 兼容保留]
	ScopeLensElement 指向 type="Model" 的玻璃网格：开镜把其材质切换为
	content 下的 zombiesurvival/pip/pic.vmt（$basetexture 直引 _rt_ 纹理名，
	文件材质对实体覆盖解析可靠），收镜还原原材质与原颜色。 ]]

-- 由 pip_chamfer 速记生成归一化切角矩形顶点表（绕序与圆盘多边形同向）
local function BuildChamferPoly(cut)
	local ctl, ctr, cbr, cbl
	if type(cut) == "table" then
		ctl = math_Clamp(tonumber(cut.tl) or 0, 0, 0.95)
		ctr = math_Clamp(tonumber(cut.tr) or 0, 0, 0.95)
		cbr = math_Clamp(tonumber(cut.br) or 0, 0, 0.95)
		cbl = math_Clamp(tonumber(cut.bl) or 0, 0, 0.95)
	else
		local u = math_Clamp(tonumber(cut) or 0, 0, 0.95)
		ctl, ctr, cbr, cbl = u, u, u, u
	end

	return {
		{ x = -1 + ctl, y = -1 },
		{ x = 1 - ctr, y = -1 },
		{ x = 1, y = -1 + ctr },
		{ x = 1, y = 1 - cbr },
		{ x = 1 - cbr, y = 1 },
		{ x = -1 + cbl, y = 1 },
		{ x = -1, y = 1 - cbl },
		{ x = -1, y = -1 + ctl },
	}
end

-- ==== ZSPIPLensOutline - 镜片裁剪轮廓点（全局：运行时 stencil 与 SCK 编辑器预览共用） ====
-- 入参：镜片元素表（pip_shape/pip_radius/pip_aspect/pip_poly/pip_chamfer），nil 安全（默认圆镜）
-- 返回：{{x,y},...} 顶点表，半高=1 基准；x 已乘 pip_aspect（宽/高比），圆已按 pip_radius 收放
function ZSPIPLensOutline(elem)
	local aspect = math_Clamp(tonumber(elem and elem.pip_aspect) or 1, 0.25, 4)
	local shape = (elem and elem.pip_shape) or "circle"

	if shape == "square" then
		return {
			{ x = -aspect, y = -1 },
			{ x = aspect, y = -1 },
			{ x = aspect, y = 1 },
			{ x = -aspect, y = 1 },
		}
	elseif shape == "poly" and elem then
		local norm = elem.pip_poly
		if norm == nil and elem.pip_chamfer ~= nil then
			norm = BuildChamferPoly(elem.pip_chamfer)
		end

		if istable(norm) and #norm >= 3 then
			local pts = {}
			for i = 1, #norm do
				pts[i] = { x = (tonumber(norm[i].x) or 0) * aspect, y = tonumber(norm[i].y) or 0 }
			end
			return pts
		end

		-- 顶点配置缺失/不合法：退回方镜轮廓，保证不黑屏
		return ZSPIPLensOutline({ pip_shape = "square", pip_aspect = aspect })
	end

	-- [圆镜 · 默认] 40 段椭圆近似，半径随 pip_radius 收放
	local frac = math_Clamp(tonumber(elem and elem.pip_radius) or 1, 0.05, 1)
	local pts = {}

	for i = 0, 39 do
		local a = math.rad(i * 9)
		pts[i + 1] = { x = math.cos(a) * frac * aspect, y = math.sin(a) * frac }
	end

	return pts
end

-- ==== DrawPIPLensContent - 镜内内容（RT 画面 + 分划板 + 过渡期玻璃底） ====
-- hw/hh：镜片半宽/半高（3D2D 本地单位）；spanU/spanV：横/纵 RT 采样窗口
-- （视差补偿由 ComputePIPParallaxWindow 算出）。分划板画在玻璃上（不进 RT）：
-- 世界画面在镜内浮动时，分划板钉在镜片上——真实瞄具观感。
function SWEP:DrawPIPLensContent(alpha, hw, hh, uc, vc, spanU, spanV)
	uc = uc or 0.5
	vc = vc or 0.5
	spanU = spanU or 1
	spanV = spanV or 1

	if alpha > 0 then
		-- [镜内亮度] zs_scope_brightness 倍率（pic.vmt 带 $vertexcolor，SetDrawColor 生效）
		local bright = GetScopeBrightness()

		surface_SetMaterial(mat_pic)
		surface_SetDrawColor(255 * bright, 255 * bright, 255 * bright, 255)
		surface_DrawTexturedRectUV(-hw, -hh, hw * 2, hh * 2,
			uc - spanU * 0.5, vc - spanV * 0.5, uc + spanU * 0.5, vc + spanV * 0.5)

		-- [分划板烘焙] 分划板已改在 RenderPIPPicture 末段直接画进显示 RT 中心，
		-- 与画面同源永不分离（见"分划板烘焙 · 结构性防错位"注释块）
	end

	-- 过渡期/收镜态的深色玻璃底（未完全淡入时垫底，避免透空）
	if alpha < 1 then
		surface_SetDrawColor(12, 14, 17, 235 * (1 - alpha))
		surface_DrawRect(-hw, -hh, hw * 2, hh * 2)
	end
end

-- ==== DrawPIPLensFeel - 手感叠层（ARC9 DrawRTReticle 的阴影栈移植） ====
-- 层序对齐 ARC9：背阴影 → 分划板(已在 Content 绘制) → 前阴影大/小双层 → 全局柔影。
-- 阴影随眼偏移位移/旋转且倍率放大（对应 ARC9 modelang + diffy*7 / *-3 / *5），
-- 与视差画面反向错位，产生"透过真实镜筒看"的纵深手感。偏移符号进游戏微调。
function SWEP:DrawPIPLensFeel(alpha, s, uc, vc, aspect)
	local intensity = CVAR_PIP_SHADOW:GetFloat()
	if intensity <= 0 or alpha <= 0 then return end
	if not (mat_shadow_front and not mat_shadow_front:IsError()) then return end

	intensity = intensity * alpha
	aspect = math_Clamp(aspect or 1, 0.25, 4)

	local sx = (uc or 0.5) - 0.5 -- 视差窗口位移（UV 比例），阴影按倍率放大并反向
	local sy = (vc or 0.5) - 0.5

	local function DrawShadow(mat, frac, ox, oy, a, rot)
		if not mat or mat:IsError() then return end
		surface_SetMaterial(mat)
		surface_SetDrawColor(255, 255, 255, math_Clamp(a, 0, 255))
		surface_DrawTexturedRectRotated(ox * s, oy * s, s * frac * 2 * aspect, s * frac * 2, rot or 0)
	end

	DrawShadow(mat_shadow_back, 1.35, sx * 5, sy * 5, 110 * intensity)                                   -- 背阴影（分划板后小暗斑）
	DrawShadow(mat_shadow_front, 3.4, sx * 7, sy * 7, 235 * intensity, math_Clamp(sx * 220, -14, 14))    -- 前阴影 A：大幅放大随动
	DrawShadow(mat_shadow_front, 2.5, -sx * 3, -sy * 3, 190 * intensity, math_Clamp(-sx * 120, -8, 8))   -- 前阴影 B：反向回拉出厚度
	DrawShadow(mat_shadow_global, 1.06, 0, 0, 130 * intensity)                                           -- 全局柔影（整镜覆盖）
end

-- 切角覆盖串解析："tl,tr,br,bl" → BuildChamferPoly 速记表
local function ParseChamferString(str)
	local p = string.Explode(",", str)

	local function num(i)
		return math_Clamp(tonumber(string.Trim(p[i] or "")) or 0, 0, 0.95)
	end

	return { tl = num(1), tr = num(2), br = num(3), bl = num(4) }
end

local COLOR_GUIDE = Color(90, 255, 170)

-- ==== DrawPIPLens - 在 Quad 元素的 3D2D 空间内绘制镜内画面 ====
function SWEP:DrawPIPLens()
	local alpha = GetCompositeAlpha(self)

	-- [视线门控 · ARC9 dott 同源] 视线偏离镜头法线时内容平滑淡出为暗玻璃，
	-- 从侧面/背后看镜片不再悬浮发光画面（zs_scope_eyecheck 可关）
	if CVAR_SCOPE_EYECHECK:GetBool() and GetLensFacingFade then
		alpha = alpha * GetLensFacingFade(self)
	end
	self.m_fPIPLensAlpha = alpha -- 调试读数（zs_pip_debug 1 可见）

	-- [SCK 约定] 编辑器里 Quad 预览为 ±20 的 40x40 红框，此处绘制范围与之对齐：
	-- 面片画面高（世界单位）= 元素 size × 40；SCK 里看到的红框边界即镜片半高边界
	local s = 20
	local elem = self.VElements and self.VElements[self.ScopeLensElement]

	-- [校准临时覆盖] zs_lens_radius/zs_lens_chamfer 仅内存态，优先于文件值；
	-- 未启用覆盖时直接传元素本体，零拷贝
	local ov_radius = CVAR_LENS_RADIUS:GetFloat()
	local ov_cham = string.Trim(CVAR_LENS_CHAMFER:GetString() or "")
	local lens_src = elem
	if elem and (ov_radius >= 0 or ov_cham ~= "") then
		lens_src = {}
		for k, v in pairs(elem) do lens_src[k] = v end

		if ov_radius >= 0 then lens_src.pip_radius = ov_radius end
		if ov_cham ~= "" then lens_src.pip_chamfer = ParseChamferString(ov_cham) end
	end

	local aspect = math_Clamp(tonumber(lens_src and lens_src.pip_aspect) or 1, 0.25, 4)
	local spanV = 1 / PIP_HEADROOM
	local spanU = math_min(spanV * aspect, 1)
	local uc = self.m_fPIPUc or 0.5 -- 采样窗口由 RenderPIPPicture 每帧投影法求解
	local vc = self.m_fPIPvc or 0.5

	-- [窗口固定] 中心锁定模式窗口恒为 RT 中心，不做任何逐帧动态偏移：
	-- RT 已沿弹道方向渲染（见 RenderPIPPicture），弹孔与烘焙分划板同在 RT 中心、
	-- 同图本征重合——精度不依赖任何几何计算，从根源上杜绝窗口跳动/闪烁/黑屏。
	-- 分划板随枪模轻微晃动属物理镜的正常表现（弹孔始终在分划板中心）。
	-- 浮动模式（zs_pip_parallax>1）仍由 PreRender 侧窗口公式提供观感偏移。

	local outline = ZSPIPLensOutline(lens_src)

	-- [统一裁剪] 三种形状共用一条 stencil 路径：轮廓点表（含半径/长宽比/切角）
	-- 缩放后写入模板 → 画面/玻璃底/阴影只落在形状内
	render.OverrideDepthEnable(true, true)

	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_NEVER)
	render.SetStencilPassOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.SetStencilFailOperation(STENCIL_REPLACE)

	draw_NoTexture()
	surface_SetDrawColor(0, 0, 0, 255)

	local mask = {}
	for i = 1, #outline do
		mask[i] = { x = outline[i].x * s, y = outline[i].y * s }
	end
	surface_DrawPoly(mask)

	render.SetStencilCompareFunction(STENCIL_EQUAL)
	self:DrawPIPLensContent(alpha, s * aspect, s, uc, vc, spanU, spanV)
	self:DrawPIPLensFeel(alpha, s, uc, vc, aspect)
	render.SetStencilEnable(false)

	-- [校准描边 · zs_lens_show] 形状边界亮环 + 四向刻度线：
	-- 描边被筒壁挡住的部分 = 超出筒口的部分，据此收 pip_radius/切角到贴合
	if CVAR_LENS_SHOW:GetBool() then
		draw_NoTexture()

		for i = 1, #outline do
			local a = outline[i]
			local b = outline[i % #outline + 1]
			DrawThickLine(a.x * s, a.y * s, b.x * s, b.y * s, math_max(1, s * 0.03), COLOR_GUIDE, 230)
		end

		local hw = s * aspect

		DrawThickLine(-hw * 1.12, 0, -hw * 0.88, 0, math_max(1, s * 0.02), COLOR_GUIDE, 190)
		DrawThickLine(hw * 0.88, 0, hw * 1.12, 0, math_max(1, s * 0.02), COLOR_GUIDE, 190)
		DrawThickLine(0, -s * 1.12, 0, -s * 0.88, math_max(1, s * 0.02), COLOR_GUIDE, 190)
		DrawThickLine(0, s * 0.88, 0, s * 1.12, math_max(1, s * 0.02), COLOR_GUIDE, 190)
	end

	render.OverrideDepthEnable(false, false) -- 恢复全局深度状态
end

-- ==== UpdatePIPLensMaterial - 镜片状态机（每帧由 PreRender 驱动） ====
function SWEP:UpdatePIPLensMaterial()
	-- [自动注入] 武器未手工配置镜片元素时，按声明式字段/模型预设合成 Quad
	if self.EnsureAutoLensElement then
		self:EnsureAutoLensElement()
	end

	local elem_name = self.ScopeLensElement
	if not elem_name then return end

	local elems = self.VElements
	local elem = elems and elems[elem_name]
	if not elem then return end

	local want_on = self:IsPIPActive()

	-- [Quad 路径] 只需注入绘制函数并维护迟滞开关（渲染驱动据此决定是否继续渲染）
	if elem.type == "Quad" then
		if not isfunction(elem.draw_func) then
			elem.draw_func = function(wep) wep:DrawPIPLens() end
		end

		if want_on then
			self.m_bPIPLensOn = true
		elseif self.m_bPIPLensOn then
			local delta = self.GetIronsightDelta and self:GetIronsightDelta() or 0
			if delta < 0.55 or not self:GetIronsights() then
				self.m_bPIPLensOn = false
			end
		end
		return
	end

	-- [Model 路径] 材质交换（文件 VMT 引用 _rt_ 纹理，实体覆盖解析可靠）
	if elem.type ~= "Model" then return end

	if self.m_sPIPLensOrigMat == nil then
		self.m_sPIPLensOrigMat = elem.material or ""
		self.m_cPIPLensOrigColor = elem.color
	end

	local on = self.m_bPIPLensOn

	if not on and want_on then
		self.m_bPIPLensOn = true
		elem.material = "zombiesurvival/pip/pic"
		elem.color = color_white
	elseif on and not want_on then
		local delta = self.GetIronsightDelta and self:GetIronsightDelta() or 0
		if delta < 0.55 or not self:GetIronsights() then
			self.m_bPIPLensOn = false
			elem.material = self.m_sPIPLensOrigMat
			elem.color = self.m_cPIPLensOrigColor
		end
	end

	-- 立即写穿到模型实体，不等渲染循环下一帧的比较刷新
	local ment = elem.modelEnt
	if IsValid(ment) then ment:SetMaterial(elem.material) end
end

---------------- [回退方案：屏幕空间圆形合成（武器未配镜片元素时使用）] ----------------

--[[
	DrawLensMask - 圆形镜片遮罩：
	1) stencil 记录圆盘区域；2) 圆外整体涂黑；3) 圆内边缘两段暗角模拟镜筒阴影。
]]
local function DrawLensMask(cx, cy, radius, alpha)
	render.ClearStencil()
	render.SetStencilEnable(true)
	render.SetStencilWriteMask(255)
	render.SetStencilTestMask(255)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_NEVER)
	render.SetStencilPassOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)
	render.SetStencilFailOperation(STENCIL_REPLACE)

	-- 阶段一：圆盘区域写入 stencil（比较恒失败 → 失败即替换为参考值 1）
	draw_NoTexture()
	surface_SetDrawColor(0, 0, 0, 255)
	DrawFilledCircle(cx, cy, radius)

	-- 阶段二：非圆区域涂黑（宽屏两侧一并覆盖）
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
	surface_SetDrawColor(0, 0, 0, 255 * alpha)
	surface_DrawRect(cx - radius - 4, cy - radius - 4, radius * 2 + 8, radius * 2 + 8)

	-- 阶段三：圆内暗角（两层同心圆叠加出渐变，模拟镜片边缘失光）
	render.SetStencilCompareFunction(STENCIL_EQUAL)
	draw_NoTexture()
	surface_SetDrawColor(0, 0, 0, 85 * alpha)
	DrawFilledCircle(cx, cy, radius * 0.985)
	surface_SetDrawColor(0, 0, 0, 55 * alpha)
	DrawFilledCircle(cx, cy, radius * 0.93)

	render.SetStencilEnable(false)
end

-- 屏幕空间合成：镜内画面 + 镜片遮罩 + 变焦读数（无镜片元素武器的回退显示路径）
function SWEP:DrawPIPComposite(mode, alpha)
	local w, h = ScrW(), ScrH()
	local size = math_min(w, h)
	local cx, cy = w * 0.5, h * 0.5
	local radius = size * 0.5

	-- RT 含视差余量视野：屏幕合成取中央标准窗口（无镜片元素武器没有漂移基准）
	local span = 1 / PIP_HEADROOM
	local bright = GetScopeBrightness()

	surface_SetMaterial(mat_pic)
	surface_SetDrawColor(255 * bright, 255 * bright, 255 * bright, 255 * alpha)
	surface_DrawTexturedRectUV(cx - radius, cy - radius, size, size,
		0.5 - span * 0.5, 0.5 - span * 0.5, 0.5 + span * 0.5, 0.5 + span * 0.5)

	-- 分划板改画在合成层（RT 不再烘焙分划板，与镜片路径行为一致）
	if alpha > 0 then
		PaintReticle(self, cx, cy, size * 0.98, alpha)
	end

	-- 全局柔影与镜片路径同一张贴图，保持两条显示路径观感一致
	if alpha > 0 and CVAR_PIP_SHADOW:GetFloat() > 0 and mat_shadow_global and not mat_shadow_global:IsError() then
		surface_SetMaterial(mat_shadow_global)
		surface_SetDrawColor(255, 255, 255, 130 * alpha * CVAR_PIP_SHADOW:GetFloat())
		surface_DrawTexturedRect(cx - size * 0.53, cy - size * 0.53, size * 1.06, size * 1.06)
	end

	DrawLensMask(cx, cy, radius, alpha)

	-- 滚轮变焦读数：调整后约 1.2 秒内在镜下缘淡出显示（zs_scope_info 可关）
	local changed_at = self.m_fPIPZoomChangedAt
	if CVAR_SCOPE_INFO:GetBool() and changed_at and RealTime() - changed_at < 1.2 then
		local fade = 1 - (RealTime() - changed_at) / 1.2
		draw.SimpleText(string.format("x%.2f", self:GetEffectiveScopeMagnification()), "ZSHUDFontSmaller", cx, cy + radius * 0.72, ColorAlpha(color_white, 220 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- 宽屏左右余黑兜底（保证绝对不透光缝隙）
	local extra = (w - size) * 0.5
	if extra > 0 then
		surface_SetDrawColor(0, 0, 0, 255 * alpha)
		surface_DrawRect(0, 0, extra + 1, h)
		surface_DrawRect(w - extra - 1, 0, extra + 1, h)
	end
end

-- 经典回退：旧式遮罩（保持迁移前观感），经典模式下由基座调用
function SWEP:DrawScopeClassicFallback()
	local style = self.ScopeLegacyStyle

	if isfunction(style) then
		style(self)
	elseif style == "futuristic" and self.DrawFuturisticScope then
		self:DrawFuturisticScope()
	else
		-- 无自定义遮罩：默认黑边 + 细十字（接近旧版通用观感）
		local w, h = ScrW(), ScrH()
		local size = math_min(w, h)
		local cx, cy = w * 0.5, h * 0.5
		local extra = (w - size) * 0.5
		if extra > 0 then
			surface_SetDrawColor(0, 0, 0, 255)
			surface_DrawRect(0, 0, extra, h)
			surface_DrawRect(w - extra, 0, extra, h)
		end
		surface_SetDrawColor(160, 30, 30, 200)
		surface_DrawLine(0, cy, w, cy)
		surface_DrawLine(cx, 0, cx, h)
	end
end

---------------- [基座级 HUD 背景] ----------------

--[[ 基座统一入口：GM:_HUDPaintBackground → wep:DrawHUDBackground()
	3D 镜片方案的 HUD 层只负责：无镜片元素时的回退合成 + 经典遮罩 + 变焦读数。
	镜内画面本身走子材质，不占用 HUD。 ]]
function SWEP:DrawHUDBackground()
	if not self.Scoped then return end
	if not GAMEMODE or GAMEMODE.DisableScopes or GAMEMODE.NoIronsights then return end
	if not self:GetIronsights() then return end

	local ply = MySelf
	if not IsValid(ply) or ply:ShouldDrawLocalPlayer() then return end

	local mode = GetPIPMode()

	if mode >= 1 and PIP_READY and self:WantsPIPScope() then
		local alpha = GetCompositeAlpha(self)
		if alpha <= 0 then return end

		-- 未配镜片元素：屏幕空间回退合成；配了（Quad 或 Model）：只画变焦读数，
		-- 镜内画面由镜片自身呈现（Quad 3D2D 绘制 / Model 子材质）
		local elems = self.VElements
		local has_lens = elems ~= nil and elems[self.ScopeLensElement] ~= nil
		if not has_lens then
			self:DrawPIPComposite(mode, alpha)
		elseif CVAR_SCOPE_INFO:GetBool() and self.m_fPIPZoomChangedAt and RealTime() - self.m_fPIPZoomChangedAt < 1.2 then
			local w, h = ScrW(), ScrH()
			local fade = 1 - (RealTime() - self.m_fPIPZoomChangedAt) / 1.2
			draw.SimpleText(string.format("x%.2f", self:GetEffectiveScopeMagnification()), "ZSHUDFontSmaller", w * 0.5, h * 0.5 + h * 0.36, ColorAlpha(color_white, 220 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- [可发现性] 首次完全开镜提示滚轮调焦，停留 4 秒后淡出
		if alpha >= 0.99 and not pip_zoom_hint_shown then
			pip_zoom_hint_shown = true
			self.m_fPIPZoomHintUntil = RealTime() + 4
		end
		local hint_until = self.m_fPIPZoomHintUntil
		if hint_until and RealTime() < hint_until then
			local w, h = ScrW(), ScrH()
			local fade = math_Clamp((hint_until - RealTime()) / 1.5, 0, 1)
			draw.SimpleText("滚动滚轮调节倍率  当前 x" .. string.format("%.1f", self:GetEffectiveScopeMagnification()),
				"ZSHUDFontSmaller", w * 0.5, h * 0.5 + h * 0.30,
				ColorAlpha(color_white, 215 * fade), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- [调试] zs_pip_debug 1：管线状态；>=2 时另加 RT 像素采样与全屏直绘预览
		local dbg = CVAR_PIP_DEBUG:GetInt()
		if dbg >= 1 then
			local _, _, basefov = GetCachedView()
			local px = self.m_tPIPDebugPx
			local pxtext = ""
			if px and px[1] then
				pxtext = string.format(" | RT像素 L%d,%d,%d M%d,%d,%d R%d,%d,%d",
					px[1].r, px[1].g, px[1].b, px[2].r, px[2].g, px[2].b, px[3].r, px[3].g, px[3].b)
			end
			local age = self.m_fPIPLastRender and (RealTime() - self.m_fPIPLastRender) or -1

			-- [真弹着点参考] 沿武器实际弹道方向（GetShootPos + GetAimVector，与
			-- ShootBullets 完全同源）射线求交，十字画在真实命中点的屏幕投影处。
			-- 旧版画在 ScrW/2 的是"渲染画面中心"：镜头后坐力弹簧（cl_camera）只改
			-- 渲染视角不改弹道，开镜后两者可差出一个分划——曾误导排查方向。
			-- 分划板中心与白十字重合 = 分划板真实反映弹道（正确状态）
			local cx, cy = ScrW() * 0.5, ScrH() * 0.5
			local dbgply = MySelf
			if IsValid(dbgply) then
				local shootpos = dbgply:GetShootPos()
				local tr = util.TraceLine({
					start = shootpos,
					endpos = shootpos + dbgply:GetAimVector() * 32768,
					filter = dbgply,
					mask = MASK_SHOT,
				})
				local scr = tr.HitPos:ToScreen()
				if scr.visible then
					cx, cy = scr.x, scr.y
				end
			end

			surface_SetDrawColor(255, 255, 255, 230)
			surface_DrawLine(cx - 14, cy, cx - 5, cy)
			surface_DrawLine(cx + 5, cy, cx + 14, cy)
			surface_DrawLine(cx, cy - 14, cx, cy - 5)
			surface_DrawLine(cx, cy + 5, cx, cy + 14)

			-- [几何中心参考] 黄色暗十字 = 渲染画面几何中心（ScrW/2）。
			-- 与白十字的间距 = 镜头弹簧/视角修饰的纯渲染偏角，开火后会看到它晃动回稳
			local gx, gy = ScrW() * 0.5, ScrH() * 0.5
			surface_SetDrawColor(255, 255, 0, 110)
			surface_DrawLine(gx - 10, gy, gx - 4, gy)
			surface_DrawLine(gx + 4, gy, gx + 10, gy)
			surface_DrawLine(gx, gy - 10, gx, gy - 4)
			surface_DrawLine(gx, gy + 4, gx, gy + 10)

			draw.SimpleText(string.format("mode=%d delta=%.2f mag=%.1f fov=%.0f rt=%dx%d 渲染%.2fs前 alpha=%.2f facing=%.2f uc=%.3f vc=%.3f 窗口=%s%s",
				mode,
				self.GetIronsightDelta and self:GetIronsightDelta() or 0,
				self:GetEffectiveScopeMagnification(),
				basefov or -1,
				rt_pic_w, rt_pic_h, age,
				self.m_fPIPLensAlpha or -1,
				self.m_fPIPFacing or -1,
				self.m_fPIPUc or -1, self.m_fPIPvc or -1,
				CVAR_PIP_PARALLAX:GetFloat() > 1 and "浮动" or "锁定",
				pxtext),
				"DermaDefault", 8, ScrH() * 0.55, color_white)

			if dbg >= 2 then
				-- 绕开面片，直接把 rt_pic 方形区域平铺到屏幕左上角：
				-- 四角有红绿蓝黄标记且边框完整 => RT 合成链路正常；
				-- 局部黑块/无标记 => 渲染层问题；预览正常但面片异常 => 面片层问题
				surface_SetMaterial(mat_pic)
				surface_SetDrawColor(255, 255, 255, 255)
				surface_DrawTexturedRectUV(8, 8, ScrH() * 0.35, ScrH() * 0.35, rt_u0, rt_v0, rt_u1, rt_v1)
				draw.SimpleText("rt_pic 直绘预览（应见四角红绿蓝黄标记）", "DermaDefault", 8, ScrH() * 0.35 + 12, color_yellow)
			end
		end

		return
	end

	-- 经典模式（zs_pipscope=0 或非 PIP 武器）：完全瞄准后绘制旧式遮罩
	if self:IsScoped() then
		self:DrawScopeClassicFallback()
	end
end

---------------- [渲染驱动] ----------------
-- 与 ARC9 同款分工：昂贵模式在 PreRender 渲染（整帧最早，避免与其他效果打架）。

-- [时机架构] 昂贵渲染放回 PreRender（任何绘制开始前完成 RT 工作）：
-- 在 PreDrawViewModels 等帧中段调用 RenderView 会打断视图模型绘制流程，
-- 造成枪模闪烁。视口数据改由 CalcView 缓存提供，不再依赖 GetViewSetup。
hook.Add("PreRender", "ZSPipeline.PIPLensState", function()
	local ply = MySelf
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or not wep.WantsPIPScope then return end

	-- 镜片子材质状态机每帧推进（含收镜还原）
	if wep.UpdatePIPLensMaterial then
		wep:UpdatePIPLensMaterial()
	end

	if ply:ShouldDrawLocalPlayer() then return end
	if GetPIPMode() ~= 1 then return end

	-- 镜片开启态（含迟滞区间）持续渲染，避免收镜过程画面冻结
	if not wep:IsPIPActive() and not wep.m_bPIPLensOn then return end

	if ShouldRenderNow() then
		wep:RenderPIPPicture(GetCompositeAlpha(wep))
	end
end)

---------------- [声明式镜片：模型预设与自动注入（免手写 VElements）] ----------------

--[[ [预设表] 按 ViewModel 路径子串匹配，键为小写。
	c_snip_awp：hunter 实测值（v_weapon.awm_parent 骨骼）。
	g3sg1 / sg550：Valve 同构装配的种子值，进游戏若镜内画面与筒口没对齐，
	用 SCK 把 Quad 摆到位后固化成手工元素即可（见文件头"武器接入"）。
	c_crossbow：HL2 十字弓自带镜筒的种子值。 ]]
local LENS_PRESETS = {
	["c_snip_awp"] = { bone = "v_weapon.awm_parent", pos = Vector(0, -6.545, 1.723), ang = Angle(0, 0, 0), size = 0.05 },
	["c_snip_g3sg1"] = { bone = "v_weapon.g3sg1_Parent", pos = Vector(0, -6.545, 1.723), ang = Angle(0, 0, 0), size = 0.05 },
	["c_snip_sg550"] = { bone = "v_weapon.sg550_Parent", pos = Vector(0, -6.545, 1.723), ang = Angle(0, 0, 0), size = 0.05 },
	["c_crossbow"] = { bone = "ValveBiped.Crossbow_base", pos = Vector(0.5, -4.2, 10.8), ang = Angle(0, 0, 0), size = 0.045 },
}

-- 自动合成元素的注册名（避开各武器手工元素常用的 pip_lens 等命名）
local AUTO_LENS_NAME = "zs_pip_lens_auto"

local function MatchLensPreset(wep)
	local vm = string.lower(wep.ViewModel or "")

	for key, cfg in pairs(LENS_PRESETS) do
		if string.find(vm, key, 1, true) then return cfg end
	end
end

-- ==== GetLensConfig - 按 ViewModel 匹配预设镜片配置，返回副本或 nil ====
-- （手工方案走 SCK 元素 + ScopeLensElement，不经过这里）
local function GetLensConfig(wep)
	local preset = MatchLensPreset(wep)
	if not preset then return end

	return { bone = preset.bone, rel = "", pos = Vector(preset.pos), ang = Angle(preset.ang), size = preset.size }
end

-- ==== EnsureAutoLensElement - 无手工镜片的 PIP 武器自动合成 Quad 元素（每帧幂等） ====
function SWEP:EnsureAutoLensElement()
	local elems = self.VElements

	-- 已指向存在的元素（手工 VElements 或此前合成）：不干预
	if self.ScopeLensElement and elems and elems[self.ScopeLensElement] then return end
	if not self.WantsPIPScope or not self:WantsPIPScope() then return end

	local cfg = GetLensConfig(self)
	if not cfg then return end

	elems = elems or {}
	self.VElements = elems

	-- 每帧重写字段：声明式数值改动（热重载/调参）即时生效
	local elem = elems[AUTO_LENS_NAME]
	if not elem then
		elem = { type = "Quad", bone = cfg.bone, rel = cfg.rel, pos = cfg.pos, angle = cfg.ang, size = cfg.size }
		elems[AUTO_LENS_NAME] = elem
		self.vRenderOrder = nil -- 渲染序缓存作废，纳入新元素
	end

	elem.bone = cfg.bone
	elem.rel = cfg.rel
	elem.pos = cfg.pos
	elem.angle = cfg.ang
	elem.size = cfg.size
	elem.hide = false
	elem.active = true

	self.ScopeLensElement = AUTO_LENS_NAME
end

---------------- [视线门控 · ARC9 dott 同源] ----------------

--[[ 面片法线（3D2D 元素 Forward）与"镜片→眼睛"方向的点积即正对程度：
	沿镜筒轴向看 ≈ ±1（取绝对值，两侧对称，镜像摆放的面片同样工作）→ 全亮；
	仅当视线与法线夹角超过约 69°（几乎侧对镜片）才开始淡出——正常贴瞄/腰射
	姿态都不会触发，避免面片角度微调时镜内画面意外消失。
	调试：zs_pip_debug 1 可在 HUD 读到 facing/alpha 实时值。 ]]
GetLensFacingFade = function(wep)
	local elems = wep.VElements
	local elem = elems and elems[wep.ScopeLensElement]
	local info = elem and elem.info

	if not info or not info.pos or not info.angle then return 1 end

	local dir = EyePos() - info.pos
	local dist = dir:Length()
	if dist < 0.01 then return 1 end

	local facing = math.abs(info.angle:Forward():Dot(dir) / dist)
	wep.m_fPIPFacing = facing -- 调试读数

	return math_Clamp((facing - 0.35) / 0.25, 0, 1)
end

---------------- [镜片填充校准：导出与重置] ----------------

local function GetActivePIPWeapon()
	local ply = MySelf
	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if IsValid(wep) and wep.WantsPIPScope and wep:WantsPIPScope() then return wep end
end

-- ==== zs_lens_dump - 打印当前镜片元素的可粘贴配置行（含生效中的临时覆盖值） ====
concommand.Add("zs_lens_dump", function()
	local wep = GetActivePIPWeapon()
	if not wep then print("[ZS Lens] 请先手持 PIP 狙击武器") return end

	local name = wep.ScopeLensElement
	local elem = wep.VElements and wep.VElements[name]
	if not elem or elem.type ~= "Quad" or not elem.pos or not elem.angle then
		print("[ZS Lens] 当前武器无可用 Quad 镜片元素（ScopeLensElement=" .. tostring(name) .. "）")
		return
	end

	-- 与 DrawPIPLens 同源的覆盖合并：导出的即所见效果
	local ov_radius = CVAR_LENS_RADIUS:GetFloat()
	local ov_cham = string.Trim(CVAR_LENS_CHAMFER:GetString() or "")
	local eff_radius = ov_radius >= 0 and ov_radius or tonumber(elem.pip_radius)
	local eff_cham = ov_cham ~= "" and ParseChamferString(ov_cham) or elem.pip_chamfer

	local parts = {}
	parts[#parts + 1] = 'type = "Quad"'
	parts[#parts + 1] = 'bone = "' .. (elem.bone or "") .. '"'
	parts[#parts + 1] = 'rel = "' .. (elem.rel or "") .. '"'
	parts[#parts + 1] = "pos = Vector(" .. string.format("%.3f, %.3f, %.3f", elem.pos.x, elem.pos.y, elem.pos.z) .. ")"
	parts[#parts + 1] = "angle = Angle(" .. string.format("%.2f, %.2f, %.2f", elem.angle.p, elem.angle.y, elem.angle.r) .. ")"
	parts[#parts + 1] = "size = " .. string.format("%.4f", tonumber(elem.size) or 0.05)

	if elem.pip_shape and elem.pip_shape ~= "circle" then
		parts[#parts + 1] = 'pip_shape = "' .. elem.pip_shape .. '"'
	end
	if eff_radius and eff_radius ~= 1 then
		parts[#parts + 1] = "pip_radius = " .. string.format("%.3f", eff_radius)
	end
	if tonumber(elem.pip_aspect) and tonumber(elem.pip_aspect) ~= 1 then
		parts[#parts + 1] = "pip_aspect = " .. string.format("%.3f", elem.pip_aspect)
	end
	if istable(eff_cham) then
		parts[#parts + 1] = string.format("pip_chamfer = { tl = %.3f, tr = %.3f, br = %.3f, bl = %.3f }",
			tonumber(eff_cham.tl) or 0, tonumber(eff_cham.tr) or 0,
			tonumber(eff_cham.br) or 0, tonumber(eff_cham.bl) or 0)
	end

	print("---- 复制下面一行到武器文件 SWEP.VElements（" .. wep:GetClass() .. " / " .. tostring(name) .. "）")
	print('\t["' .. tostring(name) .. '"] = { ' .. table.concat(parts, ", ") .. ", draw_func = nil }")
	print('---- 临时覆盖: zs_lens_radius=' .. ov_radius .. ' zs_lens_chamfer="' .. ov_cham ..
		'"（值已并入上行；确认后请执行 zs_lens_reset 清除）')
end)

-- ==== zs_lens_reset - 清除运行时临时覆盖 ====
concommand.Add("zs_lens_reset", function()
	RunConsoleCommand("zs_lens_radius", "-1")
	RunConsoleCommand("zs_lens_chamfer", "")
	print("[ZS Lens] 已清除临时覆盖（叠加层 zs_lens_show 如需关闭请单独置 0）")
end)
