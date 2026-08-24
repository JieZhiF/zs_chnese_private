-- ============================================================================
-- sh_effects.lua - 枪口粒子（PCF）注册与选择（移植自 ARC9 particles/）
-- 负责：加载 ARC9 的两个枪口焰 PCF、预缓存常用粒子系统、
--       提供 HoldType → 通用枪口粒子的自动映射（可被 SWEP.MuzzleParticle 覆写）
-- 消费方：zs_muzzleflash 特效（框架开火的统一第一人称枪口焰）
-- ============================================================================

game.AddParticles("particles/arc9_fas_muzzleflashes.pcf")
game.AddParticles("particles/arc9_muzzleflashes_test_b.pcf")

-- 按类型通用的枪口粒子（与 ARC9 同名，观感即 ARC9 原版）
local precache = {
	"muzzleflash_pistol",
	"muzzleflash_pistol_deagle",
	"muzzleflash_smg",
	"muzzleflash_ar",
	"muzzleflash_shotgun",
	"muzzleflash_slug",
	"muzzleflash_lmg",
	"muzzleflash_dmr",
	"muzzleflash_suppressed",
	"muzzleflash_ak47",
	"muzzleflash_ak74",
	"muzzleflash_mp5",
	"muzzleflash_m3",
	"muzzleflash_g3",
	"muzzleflash_FAMAS",
}
for _, name in ipairs(precache) do
	PrecacheParticleSystem(name)
end

-- HoldType → 通用粒子映射（ZS 武器的 HoldType 与 ARC9 武器类型天然对应）
local holdmap = {
	pistol = "muzzleflash_pistol",
	revolver = "muzzleflash_pistol_deagle",
	smg = "muzzleflash_smg",
	ar2 = "muzzleflash_ar",
	rifle = "muzzleflash_ar",
	shotgun = "muzzleflash_shotgun",
	duel = "muzzleflash_pistol",
}

function SWEP:GetMuzzleParticle()
	-- 逐枪覆写优先（如 akbar 可设 SWEP.MuzzleParticle = "muzzleflash_ak47"）
	if self.MuzzleParticle ~= nil then return self.MuzzleParticle end
	return holdmap[self.HoldType] or "muzzleflash_ar"
end
