-- ============================================================================
-- weapon_zs_base/sh_qca.lua - 数据驱动锚点系统（QC $attachment 的 Lua 替代）
--
-- [背景] ZS 视模型普遍缺少为特效/IK 设计的 QC $attachment 锚点，
--        ARC9 直接 GetAttachment(QCA索引) 的路线走不通。改为作者在 SWEP 表里
--        声明局部坐标锚点（Lua 数据替代 QC 烘焙），运行时经骨骼矩阵换算：
--
--   SWEP.QCAs = {
--       muzzle = { bone = "muzzle", pos = Vector(2, 0, 0), ang = Angle(0, 0, 0) },
--       eject  = { pos = Vector(...) },   -- 缺省 bone 时以模型根坐标系为基准
--   }
--
-- [消费方] GetTracerOrigin（本文件基座实现）/ 枪口火焰与弹壳特效 /
--          手部 IK 基准锚点（cl_viewik）。
-- ============================================================================

SWEP.QCAs = SWEP.QCAs or {}

-- ==== GetQCA - 取数据锚点的世界坐标 ====
-- name 锚点名；wm=true 以武器世界模型为参考系，否则用第一人称视模型。
-- 返回 pos, ang；锚点未声明或模型无效返回 nil。
function SWEP:GetQCA(name, wm)
	local tab = self.QCAs and self.QCAs[name]
	if not tab then return nil end

	local mdl
	if wm then
		mdl = self
	else
		local owner = self:GetOwner()
		mdl = owner and owner:GetViewModel()
	end
	if not IsValid(mdl) then return nil end

	local lpos = tab.pos or vector_origin
	local lang = tab.ang or angle_zero

	if tab.bone then
		local idx = mdl:LookupBone(tab.bone)
		if idx then
			local mat = mdl:GetBoneMatrix(idx)
			if mat then
				return LocalToWorld(lpos, lang, mat:GetTranslation(), mat:GetAngles())
			end
		end
	end

	-- 骨骼缺失/未声明：模型根坐标系兜底（保证锚点永远有值，消费方免判空层级）
	return LocalToWorld(lpos, lang, mdl:GetPos(), mdl:GetAngles())
end

-- ==== GetTracerOrigin - 曳光/特效起点基座实现 ====
-- 解析顺序：QCA["muzzle"]（世界模型系）→ 引擎附件 "muzzle" → 眼位。
-- 存量 override（dag/redeemers/deathdealers/hephaestus）优先级更高，不受影响；
-- 新武器只需声明 QCAs.muzzle 即可获得正确起点。
function SWEP:GetTracerOrigin()
	local qpos, qang = self:GetQCA("muzzle", true)
	if qpos then return qpos, qang end

	local att = self:LookupAttachment("muzzle")
	if att and att > 0 then
		-- [版本兼容] 新版 GMod 的 GetAttachment 返回单张 {Pos,Ang} 表，
		-- 旧版返回 pos,ang 双值——两种形态都归一化处理
		local r1, r2 = self:GetAttachment(att)
		local apos, aang
		if isvector(r1) then
			apos, aang = r1, r2
		elseif istable(r1) and isvector(r1.Pos) then
			apos, aang = r1.Pos, r1.Ang
		end
		if apos then return apos, aang end
	end

	local owner = self:GetOwner()
	if IsValid(owner) then return owner:GetShootPos(), owner:EyeAngles() end

	return self:GetPos(), self:GetAngles()
end
