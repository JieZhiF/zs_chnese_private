--[[---------------------------------------------------------------------------
	zs_quickremantle —— 变体快速重组指令（仅限一档品质武器）

	指令格式：
	  zs_quickremantle standard   （或 zs_quickremantle 0）
	      将手持的一档品质武器回退为基础武器，并按一档升级价退还废料；
	  zs_quickremantle <分支号>    （1..3）
	      将手持的一档品质武器切换为同基础武器、指定分支的一档变体。

	规则：
	  1) 回退：按 GAMEMODE:GetUpgradeScrap(当前武器表, 1) 退还废料，不收不付任何佣金；
	  2) 一档换轨：各分支一档的 GetUpgradeScrap 同值，费用对冲净 0，不扣不退、不发佣金
	     （与「佣金不追回」共识一致，只有正向 zs_upgrade 付费才产生佣金）；
	  3) 仅处理一档品质武器（有 BaseQuality 且 QualityTier == 1），
	     基础武器或二/三档品质武器一律拒绝（提示 pinv_only_tier1）。
---------------------------------------------------------------------------]]

-- 变体快速重组：回退/换轨手持的一档品质武器
concommand.Add("zs_quickremantle", function(sender, command, arguments)
	-- 校验发送者：有效、已连接、存活的巨人类玩家，且必须携带目标参数
	if not (sender:IsValid() and sender:IsConnected() and sender:IsValidLivingHuman()) or #arguments == 0 then return end

	-- 必须靠近重构台（写法照 zs_upgrade）
	if not sender:NearRemantler() then
		GAMEMODE:ConCommandErrorMessage(sender, translate.ClientGet(sender, "need_to_be_near_remantler"))
		return
	end

	-- 取手持武器：必须是带 BaseQuality 的一档品质武器
	local wep = sender:GetActiveWeapon()
	local wtbl = wep and wep:IsValid() and weapons.Get(wep:GetClass()) or nil
	if not wtbl or not wtbl.BaseQuality or wtbl.QualityTier ~= 1 then
		GAMEMODE:ConCommandErrorMessage(sender, translate.ClientGet(sender, "pinv_only_tier1"))
		return
	end

	-- 解析目标参数：standard/0 = 回退基础武器；1..3 = 切换分支
	local oldclass = wep:GetClass()
	local target = arguments[1]
	local revert = target == "standard" or target == "0"
	local targetclass

	if revert then
		-- 回退：目标类 = 基础武器类
		targetclass = wtbl.BaseQuality
	else
		local branch = tonumber(target)
		if not branch or branch < 1 or branch > 3 then return end

		-- 已处于该分支：原地直接返回
		if wtbl.Branch == branch then return end

		-- 换轨：目标类 = 基础武器对应分支的一档变体
		targetclass = GAMEMODE:GetWeaponClassOfQuality(wtbl.BaseQuality, 1, branch)
	end

	-- 目标类必须已注册（照 zs_upgrade 静默返回）
	local classtbl = weapons.Get(targetclass)
	if not classtbl then return end

	-- 玩家已拥有目标类武器时照 zs_upgrade 拒绝
	if sender:HasWeapon(targetclass) then
		GAMEMODE:ConCommandErrorMessage(sender, translate.ClientGet(sender, "remantle_cannot"))
		return
	end

	-- 回退退款额：与当初升级到一档的花费同源同值（换轨时为 0，不扣不退）
	local refund = revert and GAMEMODE:GetUpgradeScrap(wtbl, 1) or 0

	-- 换枪序列（照 zs_upgrade）：给空枪 → 旧枪弹匣退回备弹 → 选中新枪 → 移除旧枪 → 更新备选武器
	local newwep = sender:GiveEmptyWeapon(targetclass)
	if newwep and newwep:IsValid() then
		sender:GetActiveWeapon():EmptyAll(true)
		sender:SelectWeapon(targetclass)
		sender:StripWeapon(oldclass)
		sender:UpdateAltSelectedWeapon()

		-- AmmoIfHas 类武器的弹药计数迁移（照 zs_upgrade）
		if wtbl.AmmoIfHas then
			sender:RemoveAmmo(1, wtbl.Primary.Ammo)
		end
		if newwep.AmmoIfHas then
			sender:GiveAmmo(1, newwep.Primary.Ammo)
		end

		if revert then
			-- 回退：退还升级废料（不收不付佣金）
			sender:GiveAmmo(refund, "scrap")
			sender:CenterNotify(translate.ClientGet(sender, "pinv_reverted"))
		else
			-- 一档换轨：费用对冲净 0，不扣不退、不发佣金
			sender:CenterNotify(translate.ClientGet(sender, "pinv_switched"))
		end

		-- 回发重构确认，通知客户端刷新重构界面
		net.Start(NET_MSG.REMANTLECONF)
		net.Send(sender)
	end
end)
