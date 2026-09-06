-- ============================================================
-- 技能树系统 - 注册表入口（兼容层）
-- 原单文件 registry.lua（约1650行）已拆分为：
--   registry_core.lua      核心数据表与注册API、树常量
--   registry_consts.lua    技能ID（SKILL_*）/ 修饰符ID（SKILLMOD_*）常量
--   registry_mods.lua      共享修饰符处理函数
--   skillweb_health.lua    生命树
--   skillweb_speed.lua     速度树
--   skillweb_support.lua   支援/医疗树
--   skillweb_building.lua  建造树
--   skillweb_gun.lua       枪械树
--   skillweb_melee.lua     近战树
--   skillweb_custom.lua    汉化版自定义技能
-- 本文件仅按固定顺序加载上述文件（顺序不可调整：
-- 常量与API -> 修饰符函数 -> 各树技能定义/数值），
-- 对外的全局效果与拆分前完全一致。新增技能请直接编辑对应树的文件。
-- ============================================================

local files = {
	"registry_core.lua",
	"registry_consts.lua",
	"registry_mods.lua",
	"skillweb_health.lua",
	"skillweb_speed.lua",
	"skillweb_support.lua",
	"skillweb_building.lua",
	"skillweb_gun.lua",
	"skillweb_melee.lua",
	"skillweb_custom.lua",
}

for _, fname in ipairs(files) do
	include(fname)
end
