-- ============================================================================
-- weapon_zs_base/sh_scope.lua - 瞄准镜系统（共享域）
-- 负责：基座级 IsScoped 判定、狙击镜配置约定、PIP（画中画）配置字段。
--
-- [重构说明] 此前约 14 把狙击武器各自复制粘贴同一份 IsScoped 实现，
-- 现收敛为本文件的基座统一实现；武器只需声明下方配置字段即可获得完整
-- 瞄准镜能力，不再需要覆写 IsScoped / GetViewModelPosition / DrawHUDBackground。
--
-- [框架陷阱修复] 旧版 sh_sights 以 self.IsScoped（方法存在性）判断狙击武器，
-- 基座统一提供 IsScoped 后该判断会对所有武器生效，因此改用显式标志位
-- SWEP.Scoped 判定，迁移武器时必须同时声明 Scoped = true。
-- ============================================================================

local CurTime = CurTime

---------------- [瞄准镜默认配置] ----------------
SWEP.Scoped = false             -- 狙击镜武器总开关：true 走完整开镜流程（深 FOV 缩放/经典遮罩回退/PIP 资格）
SWEP.ScopeStableTime = 0.25     -- 开镜后到达"完全瞄准"的稳定秒数（旧版各武器硬编码 0.25）
SWEP.PIPScope = false           -- 允许画中画渲染：真实放大画面取代糊脸 FOV 深缩放（客户端 zs_pipscope 可调）
SWEP.ScopeLensElement = nil     -- [3D 镜片] VElements 里作为镜片的元素名（推荐 SCK 手摆的 Quad 面片，
                                -- 兼容 Model 玻璃网格的材质交换路径）；开镜显示 RT 放大画面（cl_scope 状态机）
SWEP.ScopeMagnification = 4     -- PIP 光学倍率（镜内画面相对主视角的放大倍数），鼠标灵敏度按此匹配
SWEP.ScopeMagMin = 2            -- 滚轮变焦下限（倍率）
SWEP.ScopeMagMax = 8            -- 滚轮变焦上限（倍率），nil 时默认 max(基准×2, 8)
SWEP.PIPMainFOVMult = 0.88      -- PIP 完全瞄准时主视角保留的 FOV 倍率（极轻微变焦）。
                                -- [0.88 · ARC9 对齐] ARC9 RT 镜主视角仅 ÷1.15（~13% 变化），
                                -- 深倍率全部由镜内画面承担；快速点按右键主视角几乎无感
SWEP.ScopeReticle = "mil-dot"   -- 分划板样式："mil-dot" | "cross" | "dot" | "chevron" | "german" |
                                -- "tdot" | "acog" | 材质路径 | 自绘函数 function(wep, cx, cy, dia, alpha)
SWEP.ScopeReticleColor = nil    -- 分划板颜色，nil 时使用默认暗红
SWEP.ScopeLegacyStyle = nil     -- 经典回退遮罩（zs_pipscope=0 或非 PIP 武器）："futuristic" | function(wep) | nil

-- [3D 镜片接入] 推荐用 SCK 在 VElements 里手摆 Quad 镜片面片（hunter/m82a3 方案），
-- 再声明 ScopeLensElement 指向它；未配置时基座按 ViewModel 匹配内置预设自动合成
-- （c_snip_awp 为 hunter 实测值，g3sg1/sg550/crossbow 为种子值），见 cl_scope.lua。

-- ==== IsScoped - 是否已完全开镜（基座统一实现） ====
-- [跟随式] 客户端以平滑过渡进度走满（GetIronsightDelta >= 1）为准：
-- 镜面遮罩/PIP 合成/藏枪等切换时机自动对齐各武器的 AimDownSightsTime，
-- 不再绑定固定秒数（旧版各武器副本硬编码 fIronTime + 0.25）。
-- 进度尚未推进的首帧或服务端调用时，回退旧版固定秒数语义
-- （GetIronsights() 且 fIronTime + ScopeStableTime <= CurTime()）
function SWEP:IsScoped()
	if GAMEMODE and GAMEMODE.NoIronsights then return false end
	if GAMEMODE and GAMEMODE.DisableScopes then return false end

	if CLIENT and self.GetIronsightDelta then
		-- 带 GetIronsights() 前置：松开右键瞬间立即失效（旧版同款），
		-- 不等已走满的进度衰减下来
		return self:GetIronsights() and self:GetIronsightDelta() >= 1
	end

	local irontime = self.fIronTime
	return self:GetIronsights() and irontime and irontime + (self.ScopeStableTime or 0.25) <= CurTime()
end

-- ==== WantsPIPScope - 该武器是否有资格使用画中画（双端可查；实际渲染仅客户端） ====
function SWEP:WantsPIPScope()
	return self.Scoped == true and self.PIPScope == true
end

-- ==== GetScopeMagnification - 光学倍率（非 PIP 武器恒为 1） ====
function SWEP:GetScopeMagnification()
	if not self:WantsPIPScope() then return 1 end
	return math.max(1, self.ScopeMagnification or 4)
end
