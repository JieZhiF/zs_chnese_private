-- ============================================================================
-- swep_construction_kit/menu/models.lua - SCK 元素编辑面板（客户端）
-- 负责：第一/第三人称元素（模型/精灵/Quad/裁剪面）树形列表、位置/角度/大小/
--       颜色/材质等修改器、Ctrl+Z 撤销重做、元素复制/重命名/导入导出
-- ============================================================================
-- 元素类型图标
local icon_model = "icon16/brick.png"
local icon_sprite = "icon16/asterisk_yellow.png"
local icon_quad = "icon16/picture_empty.png"
local icon_clip = "icon16/cut.png"

-- Some hacky shit to keep the relative DComboBoxes updated
-- 登记需要保持同步的相对关系下拉框
local boxes_to_update = {}
-- ==== RegisterRelBox - 登记相对元素下拉框以在改名/改动时同步更新 ====
local function RegisterRelBox( elementname, box, w_or_v, preset_choice )
	table.insert(boxes_to_update, { box, w_or_v, elementname, preset_choice })
end

local wep = GetSCKSWEP( LocalPlayer() )
local pmodels = wep.pmodels
local pwmodels = wep.pwmodels
local lastVisible = ""

local mlabel = vgui.Create( "DPanel", pmodels )
	mlabel:SetTall( 24 )
	mlabel.Paint = function() end
mlabel:Dock(TOP)

local mlock = vgui.Create( "DButton", mlabel )
	mlock:SetSize( 24, 24 )
	mlock:SetIsToggle( true )
	mlock:SetText("")
	mlock:SetIcon( wep.lockRelativePositions and "icon16/lock.png" or "icon16/lock_open.png" )
	mlock:SetToggle( wep.lockRelativePositions )
	mlock:SetTooltip( "Elements will retain their position when their bone or relative are changed" )
	mlock.Think = function( self )
		self:SetToggle( wep.lockRelativePositions )
		self:SetIcon( wep.lockRelativePositions and "icon16/lock.png" or "icon16/lock_open.png" )
	end
	mlock.OnToggled = function( self, toggleState )
		wep.lockRelativePositions = toggleState
	end

mlock:Dock( RIGHT )

local mlabeltext = vgui.Create( "DLabel", mlabel )
	mlabeltext:SetText( "New viewmodel element:" )
mlabeltext:Dock(FILL)

-- ==== CreateNote - 在面板上弹出提示通知 ====
local function CreateNote( text )
	local templabel = vgui.Create( "DLabel" )
		templabel:SetText( text )
		templabel:SizeToContents()

	local x, y = mlabel:GetPos()
	local notif = vgui.Create( "DNotify" , pmodels )
		notif:SetPos( x + 160, y )
		notif:SetSize( templabel:GetWide(), 20 )
		notif:SetLife( 5 )
		notif:AddItem(templabel)
end

local pnewelement = SimplePanel( pmodels )
pnewelement:SetTall(20)

	local mntext = vgui.Create("DTextEntry", pnewelement )
		mntext:SetTall( 20 )
		mntext:SetMultiline(false)
		mntext:SetText( "element_name" )
	mntext:Dock(FILL)

	local mnbtn = vgui.Create( "DButton", pnewelement )
		mnbtn:SetSize( 50, 20 )
		mnbtn:SetText( "Add" )
	mnbtn:DockMargin(5,0,0,0)
	mnbtn:Dock(RIGHT)

	local tpbox = vgui.Create( "DComboBox", pnewelement )
		tpbox:SetSize( 100, 20 )
		tpbox:SetText( "Model" )
		tpbox:AddChoice( "Model" )
		tpbox:AddChoice( "Sprite" )
		tpbox:AddChoice( "Quad" )
		tpbox:AddChoice( "ClipPlane" )
		local boxselected = "Model"
		local wboxselected = "Model"
		tpbox.OnSelect = function( p, index, value )
			boxselected = value
		end
	tpbox:DockMargin(5,0,0,0)
	tpbox:Dock(RIGHT)

pnewelement:DockMargin(0,5,0,5)
pnewelement:Dock(TOP)

-- dark magic, do not touch
-- 修复拖拽插入节点的引擎问题（黑魔法，勿动）
-- ==== FixInsertNode - 手动完成节点插入的补丁 ====
local function FixInsertNode( self, pNode )
	self:CreateChildNodes()
	pNode:SetRoot( self:GetRoot() )
	self:InstallDraggable( pNode )
	self.ChildNodes:Add( pNode )
	pNode._ParentNode = self
	self:InvalidateLayout()

	return pNode
end

-- yet again, this is a very stupid fix
-- 修复子节点顺序标记的引擎问题
-- ==== FixDoChildrenOrder - 重设最后一个子节点的标记 ====
local function FixDoChildrenOrder( self )
	if not IsValid( self.ChildNodes ) then return end

	local children = self.ChildNodes:GetChildren()
	local last = #children

	if last == 0 then return end

	for i = 1, (last - 1) do
		children[i]:SetLastChild( false )
	end
	children[last]:SetLastChild( true )
end

-- ==== MaintainRelativePosition - 锁定相对位置时，切换父级/骨骼后保持元素世界位置不变 ====
local function MaintainRelativePosition( name, new_parent_name, v_or_w, overridebone )
	if not wep.lockRelativePositions then return end

	local tbl = v_or_w == "w" and wep.w_models or wep.v_models
	local ent = v_or_w == "w" and LocalPlayer() or LocalPlayer():GetViewModel()

	if not IsValid( ent ) then return end

	if name and tbl[ name ] then

		local el = tbl[ name ]
		local to_bone

		local goal_pos, goal_ang

		if new_parent_name and tbl[ new_parent_name ] then
			local new_el = tbl[ new_parent_name ]
			goal_pos, goal_ang = wep:GetBoneOrientation( tbl, new_parent_name, ent )
			goal_pos = goal_pos + goal_ang:Forward() * new_el.pos.x + goal_ang:Right() * new_el.pos.y + goal_ang:Up() * new_el.pos.z
			if new_el.angle then
				goal_ang:RotateAroundAxis(goal_ang:Up(), new_el.angle.y)
				goal_ang:RotateAroundAxis(goal_ang:Right(), new_el.angle.p)
				goal_ang:RotateAroundAxis(goal_ang:Forward(), new_el.angle.r)
			end
		end

		if new_parent_name == "" then
			to_bone = el.bone
		end

		if overridebone then
			to_bone = overridebone
		end

		if to_bone then
			local bone = ent:LookupBone( to_bone )
			if bone then
				local m = ent:GetBoneMatrix( bone )
				if m then
					goal_pos, goal_ang = m:GetTranslation(), m:GetAngles()
				end
			end
		end

		local el_pos, el_ang = wep:GetBoneOrientation( tbl, name, ent )

		if not el_pos or not el_ang then
			return
		end

		el_pos = el_pos + el_ang:Forward() * el.pos.x + el_ang:Right() * el.pos.y + el_ang:Up() * el.pos.z
		if el.angle then
			el_ang:RotateAroundAxis(el_ang:Up(), el.angle.y)
			el_ang:RotateAroundAxis(el_ang:Right(), el.angle.p)
			el_ang:RotateAroundAxis(el_ang:Forward(), el.angle.r)
		end


		if el_pos and el_ang and goal_pos and goal_ang then
			local save_pos, save_ang = WorldToLocal( el_pos, el_ang, goal_pos, goal_ang )

			-- shakes fist at Clavus
			save_pos.y = save_pos.y * -1
			save_ang.p = save_ang.p * -1

			el.pos = save_pos * 1
			el.angle = save_ang * 1
		end
	end
end

-- ==== SetRelativeForNode - 设置节点元素的相对父级（含重命名场景） ====
local function SetRelativeForNode( pnl, new_parent, v_or_w, rename )
	local name = pnl:GetText()
	local new_rel = ""

	if not new_parent:IsRootNode() then
		new_rel = new_parent:GetText()
	end

	local data = wep.v_models[name]
	if v_or_w == "w" then
		data = wep.w_models[name]
	end

	if data and new_rel then
		-- make sure it is before we set our relative
		-- oh and skip recalculations if we are just renaming our model
		if not rename then
			MaintainRelativePosition( name, new_rel, v_or_w )
		end
		data.rel = new_rel
	end
end

local copy_element, copy_hierarchy
-- ==== node_do_rclick - 节点右键菜单：复制层级结构 ====
local function node_do_rclick(self)
	local node_menu = DermaMenu(false, self)
	node_menu:AddOption("Copy Hierarchy", function()
		--copy our first node first
		local newnode = copy_element(self.realm, self:GetRoot(), self)

		if #self:GetChildNodes() > 0 then
			copy_hierarchy(self, newnode, self.realm, true)
		end
	end)

	node_menu:Open()
end

-- ==== copy_element - 复制单个元素：深拷贝数据并重建面板与树节点 ====
copy_element = function(realm, tree, override)
	local line = override or tree:GetSelectedItem()
	if not IsValid(line) then return end

	local name = line:GetText()

	local view = realm == "v"
	local mdltab = view and wep.v_models or wep.w_models
	local rotab_name = view and "vRenderOrder" or "wRenderOrder"
	local pcachetab = view and wep.v_panelCache or wep.w_panelCache

	local to_copy = mdltab[name]
	local new_preset = table.Copy(to_copy)

	-- quickly generate a new unique name
	while(mdltab[name]) do
		local adder = override and "_c" or "+"

		name = name..adder
	end

	-- have to fix every sub-table as well because table.Copy copies references
	new_preset.pos = Vector(to_copy.pos.x, to_copy.pos.y, to_copy.pos.z)
	if (to_copy.angle) then
		new_preset.angle = Angle(to_copy.angle.p, to_copy.angle.y, to_copy.angle.r)
	end
	if (to_copy.color) then
		new_preset.color = Color(to_copy.color.r,to_copy.color.g,to_copy.color.b,to_copy.color.a)
	end
	if (type(to_copy.size) == "table") then
		new_preset.size = table.Copy(to_copy.size)
	elseif (type(to_copy.size) == "Vector") then
		new_preset.size = Vector(to_copy.size.x, to_copy.size.y, to_copy.size.z)
	end
	if (to_copy.bodygroup) then
		new_preset.bodygroup = table.Copy(to_copy.bodygroup)
	end

	mdltab[name] = {}

	local icon = "icon16/exclamation.png"

	if (new_preset.type == "Model") then
		pcachetab[name] = view and CreateModelPanel( name, new_preset ) or CreateWorldModelPanel( name, new_preset )
		icon = icon_model
	elseif (new_preset.type == "Sprite") then
		pcachetab[name] = view and CreateSpritePanel( name, new_preset ) or CreateWorldSpritePanel( name, new_preset )
		icon = icon_sprite
	elseif (new_preset.type == "Quad") then
		pcachetab[name] = view and CreateQuadPanel( name, new_preset ) or CreateWorldQuadPanel( name, new_preset )
		icon = icon_quad
	elseif (new_preset.type == "ClipPlane") then
		pcachetab[name] = view and CreateClipPanel( name, new_preset ) or CreateWorldClipPanel( name, new_preset )
		icon = icon_clip
	end

	pcachetab[name]:SetVisible(false)

	local node = tree:AddNode( name, icon )
	node.Type = new_preset.type
	node.InsertNode = FixInsertNode
	node.DoRightClick = node_do_rclick
	node.DoChildrenOrder = FixDoChildrenOrder
	node.realm = realm
	node._ParentNode = node:GetParentNode()
	node:SetDrawLines( true )

	local old_DroppedOn = node.DroppedOn
	node.DroppedOn = function( self, pnl )
		old_DroppedOn( self, pnl )
		SetRelativeForNode( pnl, self, "v" )
		wep[rotab_name] = nil
	end

	node.OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			SetRelativeForNode( v, self, "v" )
		end
		wep[rotab_name] = nil
	end

	local parent = IsValid(line._ParentNode) and line._ParentNode or line:GetParentNode()
	if IsValid( parent ) and not parent:IsRootNode() then
		parent:InsertNode( node )
	end

	wep[rotab_name] = nil

	return node
end

-- ==== copy_hierarchy - 递归复制节点的整个子层级 ====
copy_hierarchy = function(self, parent, realm, first)
	local children = self:GetChildNodes()

	local newnode
	if not first then
		newnode = copy_element(realm, self:GetRoot(), self)
		parent:InsertNode(newnode)
		newnode._ParentNode = newnode:GetParentNode()
		SetRelativeForNode(newnode, parent, realm)
	end

	if #children < 1 then
		return
	else
		for k, v in ipairs(children) do
			copy_hierarchy(v, newnode or parent, realm)
		end
	end
end

-- 第一人称元素树形列表
local mtree = vgui.Create( "DTree", pmodels)
	mtree:SetTall( 160 )
	wep.v_modelListing = mtree
	mtree:Root():SetDraggableName( "Viewmodel" )

	function mtree:DoClick()
		local cursel = self:GetSelectedItem()
		if cursel ~= self.LastSelected then
			self.LastSelected = cursel
			return
		end

		if IsValid(cursel) then
			self:SetSelectedItem(nil)
		end
	end

	mtree:Root().OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			v._ParentNode = self
			SetRelativeForNode( v, self, "v" )
		end
		wep.vRenderOrder = nil
	end

	mtree.OnNodeSelected = function( panel )
		local name = mtree:GetSelectedItem():GetText()
		if wep.v_panelCache[name] == nil then return end

		if (wep.v_panelCache[lastVisible]) then
			wep.v_panelCache[lastVisible]:SetVisible(false)
		end
		wep.v_panelCache[name]:SetVisible(true)

		lastVisible = name
		wep.selectedElement = lastVisible
	end

mtree:Dock(TOP)

-- 元素操作按钮行：删除/复制选中元素、导入第三人称元素
local pbuttons = SimplePanel( pmodels )
	local rmbtn = vgui.Create( "DButton", pbuttons )
		rmbtn:SetSize( 160, 25 )
		rmbtn:SetText( "Remove selected" )
	rmbtn:Dock(LEFT)

	local copybtn = vgui.Create( "DButton", pbuttons )
		copybtn:SetSize( 160, 25 )
		copybtn:SetText( "Copy selected" )
	copybtn:Dock(RIGHT)

	local importbtn = vgui.Create( "DButton", pbuttons )
		importbtn:SetTall( 25 )
		importbtn:SetText( "Import worldmodels" )
	importbtn:Dock(FILL)

pbuttons:DockMargin(0,5,0,5)
pbuttons:Dock(TOP)

-- 粘贴导入入口：解析武器源码中的 SWEP.VElements / SWEP.WElements 片段并一键生成元素
local ppaste_v = vgui.Create( "DButton", pmodels )
	ppaste_v:SetTall( 25 )
	ppaste_v:SetText( "Paste import elements (SWEP.VElements / WElements)" )
	ppaste_v:SetTooltip( "Paste weapon lua code containing SWEP.VElements / SWEP.WElements blocks,\nand generate the corresponding view/world elements.\n\n粘贴包含 SWEP.VElements / SWEP.WElements 的武器源码，一键生成对应元素模型。" )
ppaste_v:DockMargin(0,0,0,5)
ppaste_v:Dock(TOP)
ppaste_v.DoClick = function()
	OpenSCKPasteImport()
end

-- 修改面板交替背景色
local pCol = 0
local function PanelBackgroundReset()
	pCol = 0
end

-- ==== PanelApplyBackground - 交替设置面板背景色 ====
local function PanelApplyBackground(panel)
	if (pCol == 1) then
		panel:SetPaintBackground(true)
		panel.Paint = function() surface.SetDrawColor( 85, 85, 85, 255 ) surface.DrawRect( 0, 0, panel:GetWide(), panel:GetTall() ) end
	end

	pCol = (pCol + 1) % 2
end

--track position, angle, and size changes as mouse is down
-- 记录鼠标拖动期间的位置/角度/大小变化，用于 Ctrl+Z 撤销
local ctrlzhistory = {}
local currentzindex = 0

local prevchange
local prevname
local wasmousepressed = false
local wasmousereleased = false
local mousepressed = false

local nextregister = 0
-- ==== handle_undo - 撤销上一次元素修改 ====
local function handle_undo()
	if #ctrlzhistory == 0 then return end
	if currentzindex == 0 then return end

	local snapshot = ctrlzhistory[currentzindex-1]
	if not snapshot then return end

	local name = snapshot.name
	local data = wep.v_models[name]
	if not data then return end

	for k, v in pairs(snapshot) do
		if k ~= "name" then

		data[k] = v
		end
	end

	currentzindex = currentzindex - 1

	return true
end

-- ==== handle_redo - 重做已撤销的元素修改 ====
local function handle_redo()
	if #ctrlzhistory == 0 then return end
	if currentzindex == #ctrlzhistory then return end

	local snapshot = table.FullCopy(ctrlzhistory[currentzindex+1])
	if not snapshot then return end

	local name = snapshot.name
	local data = wep.v_models[name]
	if not data then return end

	for k, v in pairs(snapshot) do
		if k ~= "name" then

		data[k] = v
		end
	end

	currentzindex = currentzindex + 1

	return true
end

-- ==== undoredolisten - 监听 Ctrl+Z / Ctrl+Y 按键 ====
local function undoredolisten()
	-- 粘贴导入窗口打开期间暂停监听：输入框内的按键不应触发撤销/重做
	if wep.pasteImportActive then return end

	if nextregister < CurTime() and input.IsKeyDown(KEY_LCONTROL) then
		if input.WasKeyPressed(KEY_Z) then
			handle_undo()

			nextregister = CurTime() + 0.1
			return
		elseif input.WasKeyPressed(KEY_Y) then
			handle_redo()

			nextregister = CurTime() + 0.1
			return
		end
	end
end

-- ==== copy - 深拷贝向量或角度值 ====
local function copy(var)
	if isvector(var) then
		return Vector(var)
	elseif isangle(var) then
		return Angle(var)
	end
end

--we check for mouse press and release since sliders can update continuously
--this means we only save the snapshots when the user releases a mouse button from moving and element
--alternatively, we could start a timer and save snapshots after set intervals if this appears to be too jank in practice
hook.Add("CreateMove", "TrackMouseCTRLZ", function()
	if not IsFirstTimePredicted() and not game.SinglePlayer() then return end
	if not IsValid(wep) then return end
	if LocalPlayer():GetActiveWeapon() ~= wep then return end

	--when testing, the Pressed called more than once, so this is done to filter out the extra calls (IFTP didn't seem to work)
	if (input.WasMousePressed(MOUSE_LEFT) or input.WasMousePressed(MOUSE_RIGHT) or input.WasMouseDoublePressed(MOUSE_LEFT)) and not wasmousepressed then
		wasmousepressed = true
		wasmousereleased = false
	elseif (input.WasMouseReleased(MOUSE_LEFT) or input.WasMouseReleased(MOUSE_RIGHT)) and not wasmousereleased then
		wasmousepressed = false
		wasmousereleased = true
	end

	undoredolisten()

	if mousepressed ~= wasmousepressed then
		mousepressed = wasmousepressed
		local data = wep.v_models[lastVisible]
		if not data then return end

		if wasmousepressed then
			prevchange = table.FullCopy(data)
			prevname = lastVisible
		elseif prevchange then
			if lastVisible ~= prevname then return end --if we click off of an element, we shouldn't misinterpret that as the angle/pos changing!

			local snapshot = {}
			local snapshotold = {}
			for k, v in pairs(prevchange) do
				if (k == "pos" or k == "angle" or k == "size") then

				local old = v
				local new = data[k]
				if old ~= new then

				snapshot[k] = copy(new) --since they're objects, we'll need to copy it or they'll change when the user changes them
				snapshotold[k] = copy(old)
				end
				end
			end

			if table.Count(snapshot) == 0 then return end
			snapshot.name = lastVisible
			snapshotold.name = lastVisible

			--clear our forward history if we make a change (really only matters if we add redo)
			if #ctrlzhistory > currentzindex then
				for i = currentzindex+1, #ctrlzhistory do
					ctrlzhistory[i] = nil
				end
			end

			local key = table.insert(ctrlzhistory, snapshot)
			if key == 1 then
				table.insert(ctrlzhistory, 1, snapshotold)
			end
			currentzindex = #ctrlzhistory
		end
	end
end)

-- ==== CreatePositionModifiers - 位置 XYZ 修改器面板 ====
local function CreatePositionModifiers( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(32*3)
	PanelApplyBackground(panel)

	local trlabel = vgui.Create( "DLabel", panel )
		trlabel:SetText( "Position:" )
		trlabel:SizeToContents()
		trlabel:SetWide(45)
		trlabel:SetMouseInputEnabled( true )
	trlabel:Dock(LEFT)

	local mxwang = vgui.Create( "DNumSlider", panel )
		mxwang:SetText("x")
		mxwang:SetMinMax( -400, 400 )
		mxwang:SetDecimals( 3 )
		mxwang.Wang.ConVarChanged = function( p, value ) panel.data.pos.x = tonumber(value) end
		mxwang:SetValue( panel.data.pos.x )
		mxwang.Think = function( self )
			if panel.data and panel.data.pos and panel.data.pos.x and panel.data.pos.x ~= self:GetValue() then
				self:SetValue( panel.data.pos.x )
			end
		end
	mxwang:DockMargin(10,0,0,0)

	local mywang = vgui.Create( "DNumSlider", panel )
		mywang:SetText("y")
		mywang:SetMinMax( -400, 400 )
		mywang:SetDecimals( 3 )
		mywang.Wang.ConVarChanged = function( p, value ) panel.data.pos.y = tonumber(value) end
		mywang:SetValue( panel.data.pos.y )
		mywang.Think = function( self )
			if panel.data and panel.data.pos and panel.data.pos.y and panel.data.pos.y ~= self:GetValue() then
				self:SetValue( panel.data.pos.y )
			end
		end
	mywang:DockMargin(10,0,0,0)

	local mzwang = vgui.Create( "DNumSlider", panel )
		mzwang:SetText("z")
		mzwang:SetMinMax( -400, 400 )
		mzwang:SetDecimals( 3 )
		mzwang.Wang.ConVarChanged = function( p, value ) panel.data.pos.z = tonumber(value) end
		mzwang:SetValue( data.pos.z )
		mzwang.Think = function( self )
			if panel.data and panel.data.pos and panel.data.pos.z and panel.data.pos.z ~= self:GetValue() then
				self:SetValue( panel.data.pos.z )
			end
		end
	mzwang:DockMargin(10,0,0,0)

	panel.PerformLayout = function()
		mxwang:SetWide(panel:GetWide()*4/15)
		mywang:SetWide(panel:GetWide()*4/15)
		mzwang:SetWide(panel:GetWide()*4/15)
	end

	trlabel.DoDoubleClick = function( self )
		if mxwang then
			mxwang:SetValue( 0 )
		end
		if mywang then
			mywang:SetValue( 0 )
		end
		if mzwang then
			mzwang:SetValue( 0 )
		end
	end

	mxwang:Dock(TOP)
	mywang:Dock(TOP)
	mzwang:Dock(TOP)

	return panel
end

-- ==== CreateAngleModifiers - 角度 pitch/yaw/roll 修改器面板 ====
local function CreateAngleModifiers( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(32*3)
	PanelApplyBackground(panel)

	local anlabel = vgui.Create( "DLabel", panel )
		anlabel:SetText( "Angle:" )
		anlabel:SizeToContents()
		anlabel:SetWide(45)
		anlabel:SetMouseInputEnabled( true )
	anlabel:Dock(LEFT)

	local mpitchwang = vgui.Create( "DNumSlider", panel )
		mpitchwang:SetText("pitch")
		mpitchwang:SetMinMax( -180, 180 )
		mpitchwang:SetDecimals( 3 )
		mpitchwang.Wang.ConVarChanged = function( p, value ) panel.data.angle.p = tonumber(value) end
		mpitchwang:SetValue( panel.data.angle.p )
		mpitchwang.Think = function( self )
			if panel.data and panel.data.angle and panel.data.angle.p and panel.data.angle.p ~= self:GetValue() then
				self:SetValue( panel.data.angle.p )
			end
		end
	mpitchwang:DockMargin(10,0,0,0)

	local myawwang = vgui.Create( "DNumSlider", panel )
		myawwang:SetText("yaw")
		myawwang:SetMinMax( -180, 180 )
		myawwang:SetDecimals( 3 )
		myawwang.Wang.ConVarChanged = function( p, value ) panel.data.angle.y = tonumber(value) end
		myawwang:SetValue( panel.data.angle.y )
		myawwang.Think = function( self )
			if panel.data and panel.data.angle and panel.data.angle.y and panel.data.angle.y ~= self:GetValue() then
				self:SetValue( panel.data.angle.y )
			end
		end
	myawwang:DockMargin(10,0,0,0)

	local mrollwang = vgui.Create( "DNumSlider", panel )
		mrollwang:SetText("roll")
		mrollwang:SetMinMax( -180, 180 )
		mrollwang:SetDecimals( 3 )
		mrollwang.Wang.ConVarChanged = function( p, value ) panel.data.angle.r = tonumber(value) end
		mrollwang:SetValue( panel.data.angle.r )
		mrollwang.Think = function( self )
			if panel.data and panel.data.angle and panel.data.angle.r and panel.data.angle.r ~= self:GetValue() then
				self:SetValue( panel.data.angle.r )
			end
		end
	mrollwang:DockMargin(10,0,0,0)

	panel.PerformLayout = function()
		mrollwang:SetWide(panel:GetWide()*4/15)
		myawwang:SetWide(panel:GetWide()*4/15)
		mpitchwang:SetWide(panel:GetWide()*4/15)
	end

	anlabel.DoDoubleClick = function( self )
		if mpitchwang then
			mpitchwang:SetValue( 0 )
		end
		if myawwang then
			myawwang:SetValue( 0 )
		end
		if mrollwang then
			mrollwang:SetValue( 0 )
		end
	end

	mpitchwang:Dock(TOP)
	myawwang:Dock(TOP)
	mrollwang:Dock(TOP)

	return panel
end

-- ==== CreateSizeModifiers - 大小缩放修改器面板（1~3 维） ====
local function CreateSizeModifiers( data, panel, dimensions )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(32*( dimensions + 1 ))
	PanelApplyBackground(panel)

	local sizelabel = vgui.Create( "DLabel", panel )
		sizelabel:SetText( "Size:" )
		sizelabel:SizeToContents()
		sizelabel:SetWide(45)
		sizelabel:SetMouseInputEnabled( true )
	sizelabel:Dock(LEFT)

	local msx2wang, msywang, mszwang

	local msxwang = vgui.Create( "DNumSlider", panel )
		msxwang:SetMinMax( -1, 120 )--0.01, 1000
		msxwang:SetDecimals( 3 )

	if (dimensions > 1 ) then

		msx2wang = vgui.Create( "DNumSlider", panel )
			msx2wang:SetText("x")
			msx2wang:SetMinMax( -1, 120 )
			msx2wang:SetDecimals( 3 )
			msx2wang.Wang.ConVarChanged = function( p, value ) panel.data.size.x = tonumber(value) end
		msx2wang:DockMargin(10,0,0,0)
		msx2wang:Dock(TOP)

		msywang = vgui.Create( "DNumSlider", panel )
			msywang:SetText("y")
			msywang:SetMinMax( -1, 120 )
			msywang:SetDecimals( 3 )
			msywang.Wang.ConVarChanged = function( p, value ) panel.data.size.y = tonumber(value) end
		msywang:DockMargin(10,0,0,0)
		msywang:Dock(TOP)

		if (dimensions > 2) then
			mszwang = vgui.Create( "DNumSlider", panel )
				mszwang:SetText("z")
				mszwang:SetMinMax( -1, 120 )
				mszwang:SetDecimals( 3 )
				mszwang.Wang.ConVarChanged = function( p, value ) panel.data.size.z = tonumber(value) end
			mszwang:DockMargin(10,0,0,0)
			mszwang:Dock(TOP)
		end

	end

	-- make the x numberwang set the total size
	msxwang.Wang.ConVarChanged = function( p, value )
		if (mszwang) then
			mszwang:SetValue( value )
		end
		if (msywang) then
			msywang:SetValue( value )
		end
		if (msx2wang) then
			msx2wang:SetValue( value )
		end

		if dimensions <= 1 then
			panel.data.size = tonumber(value)
		end
	end

	sizelabel.DoDoubleClick = function( self )
		if msxwang then
			msxwang:SetValue( 1 )
		end
		if msx2wang then
			msx2wang:SetValue( 1 )
		end
		if msywang then
			msywang:SetValue( 1 )
		end
		if mszwang then
			mszwang:SetValue( 1 )
		end
	end

	msxwang:DockMargin(10,0,0,0)
	msxwang:Dock(TOP)

	if dimensions == 1 then
		msxwang:SetText("factor")
		msxwang:SetValue( data.size )
	else
		local new_y = panel.data.size.y
		local new_z = panel.data.size.z

		msxwang:SetText("x / y")
		msxwang:SetValue( panel.data.size.x )
		msywang:SetValue( new_y )

		if mszwang then
			msxwang:SetText("x / y / z")
			mszwang:SetValue( new_z )
		end
	end

	return panel
end

-- ==== CreateColorModifiers - 颜色修改器面板 ====
local function CreateColorModifiers( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel:SetTall(32*5)
	panel.data = data
	PanelApplyBackground(panel)

	local collabel = vgui.Create( "DLabel", panel )
		collabel:SetText( "Color:" )
		collabel:SizeToContents()
		collabel:SetWide(45)
	collabel:Dock(LEFT)

	local colpicker = vgui.Create("DColorMixer", panel)
	colpicker:Dock(FILL)

	colpicker.ValueChanged = function(self, tcol)
		panel.data.color.r = tcol.r
		panel.data.color.g = tcol.g
		panel.data.color.b = tcol.b
		panel.data.color.a = tcol.a or 255
	end

	local loadcol = Color(panel.data.color.r or 255, panel.data.color.g or 255, panel.data.color.b or 255, panel.data.color.a or 255)
	colpicker:SetColor(loadcol)

	panel.PerformLayout = function()

	end

	return panel
end

-- ==== CreateModelModifier - 模型路径修改器面板 ====
local function CreateModelModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel:SetTall(20)
	panel.data = data

	local pmolabel = vgui.Create( "DLabel", panel )
		pmolabel:SetText( "Model:" )
		pmolabel:SetWide(60)
		pmolabel:SizeToContentsY()
	pmolabel:Dock(LEFT)

	local wtbtn = vgui.Create( "DButton", panel )
		wtbtn:SetSize( 25, 20 )
		wtbtn:SetText("...")
	wtbtn:Dock(RIGHT)

	local pmmtext = vgui.Create( "DTextEntry", panel )
		pmmtext:SetMultiline(false)
		pmmtext:SetTooltip("Path to the model file")
		pmmtext.OnTextChanged = function()
			local newmod = pmmtext:GetValue()
			if file.Exists(newmod, "GAME") then
				util.PrecacheModel(newmod)
				panel.data.model = newmod
			end
		end
		pmmtext:SetText( panel.data.model )
		pmmtext.OnTextChanged()
	pmmtext:DockMargin(10,0,0,0)
	pmmtext:Dock(FILL)

	wtbtn.DoClick = function()
		wep:OpenModelBrowser( panel.data.model, function( val ) pmmtext:SetText(val) pmmtext:OnTextChanged() end )
	end

	return panel
end

-- ==== CreateSpriteModifier - 精灵材质路径修改器面板 ====
local function CreateSpriteModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel:SetTall(20)
	panel.data = data

	local pmolabel = vgui.Create( "DLabel", panel )
		pmolabel:SetText( "Sprite:" )
		pmolabel:SetWide(60)
		pmolabel:SizeToContentsY()
	pmolabel:Dock(LEFT)

	local wtbtn = vgui.Create( "DButton", panel )
		wtbtn:SetSize( 25, 20 )
		wtbtn:SetText("...")
	wtbtn:Dock(RIGHT)

	local pmmtext = vgui.Create( "DTextEntry", panel )
		pmmtext:SetMultiline(false)
		pmmtext:SetTooltip("Path to the sprite material")
		pmmtext.OnTextChanged = function()
			local newsprite = pmmtext:GetValue()
			if file.Exists("materials/"..newsprite..".vmt", "GAME") then
				panel.data.sprite = newsprite
			end
		end
		pmmtext:SetText( panel.data.sprite )
		pmmtext.OnTextChanged()
	pmmtext:DockMargin(10,0,0,0)
	pmmtext:Dock(FILL)

	wtbtn.DoClick = function()
		wep:OpenMaterialBrowser(panel.data.sprite, function( val ) pmmtext:SetText(val) pmmtext:OnTextChanged() end )
	end

	return panel
end

-- ==== renamev - 重命名第一人称元素（同步面板缓存与树节点） ====
local function renamev(old, new, panel)
	local wep = GetSCKSWEP( LocalPlayer() )
	if wep.v_panelCache[old] and not wep.v_panelCache[new] then
		wep.v_panelCache[new] = wep.v_panelCache[old]
		wep.v_panelCache[old] = nil
		wep.v_models[new] = table.Copy(wep.v_models[old])
		wep.v_models[old] = nil

		-- update da reference for our color panel
		for k, v in pairs( wep.v_panelCache[new]:GetItems() ) do
			if IsValid( v ) and v.data then
				v.data = wep.v_models[new]
			end
		end

		panel.m_PrevName = new

		local listing = wep.v_modelListing

		local item = listing:GetSelectedItem()
		if IsValid(item) and item:GetText() == old then
			item:SetText(new)

			if lastVisible == old then
				lastVisible = new
			end

			for k, v in pairs( item:GetChildNodes() ) do
				SetRelativeForNode( v, item, "v", true )
			end

			listing:SetSelectedItem( item )
		end
		return true
	end
	return false
end

-- ==== renamew - 重命名第三人称元素（同步面板缓存与树节点） ====
local function renamew(old, new, panel)
	local wep = GetSCKSWEP(LocalPlayer())
	if wep.w_panelCache[old] and not wep.w_panelCache[new] then
		wep.w_panelCache[new] = wep.w_panelCache[old]
		wep.w_panelCache[old] = nil
		wep.w_models[new] = table.Copy(wep.w_models[old])
		wep.w_models[old] = nil

		-- update da reference for our color panel
		for k, v in pairs( wep.w_panelCache[new]:GetItems() ) do
			if IsValid( v ) and v.data then
				v.data = wep.w_models[new]
			end
		end

		panel.m_PrevName = new

		local listing = wep.w_modelListing
		local item = listing:GetSelectedItem()
		if IsValid(item) and item:GetText() == old then
			item:SetText(new)

			if lastVisible == old then
				lastVisible = new
			end

			for k, v in pairs( item:GetChildNodes() ) do
				SetRelativeForNode( v, item, "w", true )
			end

			listing:SetSelectedItem( item )
		end
		return true
	end
	return false
end

-- ==== CreateNameLabel - 名称显示与重命名输入框 ====
local function CreateNameLabel(name, panel, world)
	panel:SetTall(20)

	local pnmlabel = vgui.Create( "DLabel", panel )
	pnmlabel:SetText("Name: ")
	pnmlabel:SizeToContents()
	pnmlabel:Dock(LEFT)

	local nametxt = vgui.Create("DTextEntry", panel)
	nametxt:SetText(name)
	nametxt:MoveRightOf(pnmlabel)
	nametxt:Dock(FILL)

	panel.m_PrevName = name

	local rename = world and renamew or renamev
	nametxt.OnValueChange = function(s, txt)
		local success = rename(panel.m_PrevName, txt, panel)
		if not success then
			nametxt:SetText(panel.m_PrevName)
		end
	end

	nametxt.OnLoseFocus = function()
		local success = rename(panel.m_PrevName, nametxt:GetValue(), panel)
		if not success then
			nametxt:SetText(panel.m_PrevName)
		end
	end

	return panel
end

-- ==== CreateParamModifiers - 精灵材质参数（nocull/additive 等）复选框面板 ====
local function CreateParamModifiers( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(45)

	local strip1 = SimplePanel( panel )
	strip1:SetTall(20)

		local ncchbox = vgui.Create( "DCheckBoxLabel", strip1 )
			ncchbox:SetText("$nocull")
			ncchbox:SizeToContents()
			ncchbox:SetValue( 0 )
			ncchbox.OnChange = function()
				panel.data.nocull = ncchbox:GetChecked()
				panel.data.spriteMaterial = nil -- dump old material
			end
			if (panel.data.nocull) then ncchbox:SetValue( 1 ) end
		ncchbox:DockMargin(0,0,10,0)
		ncchbox:Dock(LEFT)

		local adchbox = vgui.Create( "DCheckBoxLabel", strip1 )
			adchbox:SetText("$additive")
			adchbox:SizeToContents()
			adchbox:SetValue( 0 )
			adchbox.OnChange = function()
				panel.data.additive = adchbox:GetChecked()
				panel.data.spriteMaterial = nil -- dump old material
			end
			if (panel.data.additive) then adchbox:SetValue( 1 ) end
		adchbox:DockMargin(0,0,10,0)
		adchbox:Dock(LEFT)

		local vtachbox = vgui.Create( "DCheckBoxLabel", strip1 )
			vtachbox:SetText("$vertexalpha")
			vtachbox:SizeToContents()
			vtachbox:SetValue( 0 )
			vtachbox.OnChange = function()
				panel.data.vertexalpha = vtachbox:GetChecked()
				panel.data.spriteMaterial = nil -- dump old material
			end
			if (panel.data.vertexalpha) then vtachbox:SetValue( 1 ) end
		vtachbox:DockMargin(0,0,10,0)
		vtachbox:Dock(LEFT)

	strip1:DockMargin(0,0,0,5)
	strip1:Dock(TOP)

	local strip2 = SimplePanel( panel )
	strip2:SetTall(20)

		local vtcchbox = vgui.Create( "DCheckBoxLabel", strip2 )
			vtcchbox:SetText("$vertexcolor")
			vtcchbox:SizeToContents()
			vtcchbox:SetValue( 0 )
			vtcchbox.OnChange = function()
				panel.data.vertexcolor = vtcchbox:GetChecked()
				panel.data.spriteMaterial = nil -- dump old material
			end
			if (panel.data.vertexcolor) then vtcchbox:SetValue( 1 ) end
		vtcchbox:DockMargin(0,0,10,0)
		vtcchbox:Dock(LEFT)

		local izchbox = vgui.Create( "DCheckBoxLabel", strip2 )
			izchbox:SetText("$ignorez")
			izchbox:SizeToContents()
			izchbox:SetValue( 0 )
			izchbox.OnChange = function()
				panel.data.ignorez = izchbox:GetChecked()
				panel.data.spriteMaterial = nil -- dump old material
			end
			if (panel.data.ignorez) then izchbox:SetValue( 1 ) end
		izchbox:DockMargin(0,0,10,0)
		izchbox:Dock(LEFT)

	strip2:Dock(TOP)

	return panel
end

-- ==== CreateMaterialModifier - 材质路径修改器面板 ====
local function CreateMaterialModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(20)

	local matlabel = vgui.Create( "DLabel", panel )
		matlabel:SetText( "Material:" )
		matlabel:SetWide(60)
		matlabel:SizeToContentsY()
	matlabel:Dock(LEFT)

	local wtbtn = vgui.Create( "DButton", panel )
		wtbtn:SetSize( 25, 20 )
		wtbtn:SetText("...")
	wtbtn:Dock(RIGHT)

	local mattext = vgui.Create("DTextEntry", panel )
		mattext:SetMultiline(false)
		mattext:SetTooltip("Path to the material file")
		mattext.OnTextChanged = function()
			local newmat = mattext:GetValue()
			local newmatmat = Material(newmat)
			if file.Exists("materials/"..newmat..".vmt", "GAME") or newmatmat and not newmatmat:IsError() then
				panel.data.material = newmat
			else
				panel.data.material = ""
			end
		end
		mattext:SetText( panel.data.material )
	mattext:DockMargin(10,0,0,0)
	mattext:Dock(FILL)

	wtbtn.DoClick = function()
		wep:OpenMaterialBrowser( panel.data.material, function( val ) mattext:SetText(val) mattext:OnTextChanged() end )
	end

	return panel
end

-- ==== CreateSLightningModifier - 引擎光照抑制开关面板 ====
local function CreateSLightningModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local lschbox = vgui.Create( "DCheckBoxLabel", panel )
		lschbox:SetText("Surpress engine lightning")
		lschbox:SizeToContents()
		lschbox.OnChange = function()
			panel.data.surpresslightning = lschbox:GetChecked()
		end
		if panel.data.surpresslightning then
			lschbox:SetValue( 1 )
		else
			lschbox:SetValue( 0 )
		end
	lschbox:Dock(LEFT)

	return panel
end

-- ==== CreateBonemergeModifier - 骨骼合并开关面板 ====
local function CreateBonemergeModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local lschbox = vgui.Create( "DCheckBoxLabel", panel )
		lschbox:SetText("Enable bonemerge")
		lschbox:SizeToContents()
		lschbox.OnChange = function()
			panel.data.bonemerge = lschbox:GetChecked()
		end
		if panel.data.bonemerge then
			lschbox:SetValue( 1 )
		else
			lschbox:SetValue( 0 )
		end
	lschbox:Dock(LEFT)

	return panel
end

-- ==== CreateNocullModifier - 背面剔除禁用开关面板 ====
local function CreateNocullModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local lschbox = vgui.Create( "DCheckBoxLabel", panel )
		lschbox:SetText("Disable backface culling")
		lschbox:SizeToContents()
		lschbox.OnChange = function()
			panel.data.nocull = lschbox:GetChecked()
		end
		if panel.data.nocull then
			lschbox:SetValue( 1 )
		else
			lschbox:SetValue( 0 )
		end
	lschbox:Dock(LEFT)

	return panel
end

-- ==== CreateHighRenderModifier - 强制顶层渲染开关面板 ====
local function CreateHighRenderModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local lschbox = vgui.Create( "DCheckBoxLabel", panel )
		lschbox:SetText("Force draw element on top of other elements")
		lschbox:SizeToContents()
		lschbox.OnChange = function()
			panel.data.highrender = lschbox:GetChecked()
			-- redo the render order on demand
			if wep and wep:IsValid() then
				wep.vRenderOrder = nil
				wep.wRenderOrder = nil
			end
		end
		if (panel.data.highrender) then
			lschbox:SetValue( 1 )
		else
			lschbox:SetValue( 0 )
		end
	lschbox:Dock(LEFT)

	return panel
end

-- ==== CreateBoneModifier - 骨骼选择下拉框面板 ====
local function CreateBoneModifier( data, panel, ent, name )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local pbonelabel = vgui.Create( "DLabel", panel )
		pbonelabel:SetText( "Bone:" )
		pbonelabel:SetWide(60)
		pbonelabel:SizeToContentsY()
	pbonelabel:Dock(LEFT)

	local bonebox = vgui.Create( "DComboBox", panel )
		bonebox:SetTooltip("Bone to parent the selected element to. Is ignored if the 'Relative' field is not empty")
		bonebox.OnSelect = function( p, index, value )
			-- dont mess shit up if there is a relative already
			if panel.data.rel == "" then
				MaintainRelativePosition( name, nil, ent:IsPlayer() and "w" or "v", value )
			end

			panel.data.bone = value
		end
		bonebox:SetValue( panel.data.bone )
	bonebox:DockMargin(10,0,0,0)
	bonebox:Dock(FILL)

	local delay = 0
	-- we have to call it later when loading settings because the viewmodel needs to be changed first
	if (data.bone ~= "") then delay = 2 end

	timer.Simple(delay, function()
		if not IsValid(bonebox) then return end
		local option = PopulateBoneList( bonebox, ent )
		if (option and panel.data.bone == "") then
			bonebox:ChooseOptionID(1)
		else
			bonebox:SetValue( panel.data.bone )
		end
	end)

	bonebox.OnMenuOpened = function( self, menu )
		if IsValid( menu ) then
			wep.ShouldShowBones = menu
			for k, v in pairs( menu:GetCanvas():GetChildren() ) do
				local oldOnCursorEntered = v.OnCursorEntered
				v.OnCursorEntered = function( s )
					oldOnCursorEntered( s )
					wep.ShowCurrentBone = s:GetText()
				end
				v.OnCursorExited = function( s )
					wep.ShowCurrentBone = nil
				end
			end
		end
	end

	panel.bonebox = bonebox

	return panel
end

-- ==== CreateVRelativeModifier - 第一人称相对父级下拉框面板 ====
local function CreateVRelativeModifier( name, data, panel )
	local prellabel = vgui.Create( "DLabel", panel )
		prellabel:SetText( "Relative:" )
		prellabel:SetWide(60)
		prellabel:SizeToContentsY()
	prellabel:Dock(LEFT)

	local relbox = vgui.Create( "DComboBox", panel )
		relbox:SetTooltip("Element you want to parent this element to (position and angle become relative). Overrides parenting to a bone if not blank.")
		relbox.OnSelect = function( p, index, value )
			data.rel = value
		end
	relbox:DockMargin(10,0,0,0)
	relbox:Dock(FILL)

	RegisterRelBox(name, relbox, "v", data.rel)

	return panel
end

-- ==== CreateWRelativeModifier - 第三人称相对父级下拉框面板 ====
local function CreateWRelativeModifier( name, data, panel )
	local prellabel = vgui.Create( "DLabel", panel )
		prellabel:SetText( "Relative:" )
		prellabel:SetWide(60)
		prellabel:SizeToContentsY()
	prellabel:Dock(LEFT)

	local relbox = vgui.Create( "DComboBox", panel )
		relbox:SetTooltip("Element you want to parent this element to (position and angle become relative). Overrides parenting to a bone if not blank.")
		relbox.OnSelect = function( p, index, value )
			data.rel = value
		end
	relbox:DockMargin(10,0,0,0)
	relbox:Dock(FILL)

	RegisterRelBox(name, relbox, "w", data.rel)

	return panel
end

-- ==== CreateBodygroupSkinModifier - 身体组与皮肤修改器面板 ====
local function CreateBodygroupSkinModifier( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	local bdlabel = vgui.Create( "DLabel", panel )
		bdlabel:SetText( "Bodygroup:" )
		bdlabel:SizeToContents()
	bdlabel:Dock(LEFT)

	local bdwang = vgui.Create( "DNumberWang", panel )
		bdwang:SetSize( 30, 20 )
		bdwang:SetMinMax( 1, 9 )
		bdwang:SetDecimals( 0 )
		bdwang:SetTooltip("Bodygroup number")
	bdwang:DockMargin(10,0,0,0)
	bdwang:Dock(LEFT)

	local islabel = vgui.Create( "DLabel", panel )
		islabel:SetSize( 10, 20 )
		islabel:SetText( "=" )
	islabel:DockMargin(1,0,1,0)
	islabel:Dock(LEFT)

	local bdvwang = vgui.Create( "DNumberWang", panel )
		bdvwang:SetSize( 30, 20 )
		bdvwang:SetMinMax( 0, 9 )
		bdvwang:SetDecimals( 0 )
		bdvwang:SetTooltip("State number")
	bdvwang:Dock(LEFT)

	bdvwang.ConVarChanged = function( p, value )
		local group = tonumber(bdwang:GetValue())
		local val = tonumber(value)
		panel.data.bodygroup[group] = val
	end
	bdvwang:SetValue(0)

	bdwang.ConVarChanged = function( p, value )
		local group = tonumber(value)
		if (group < 1) then return end
		local setval = panel.data.bodygroup[group] or 0
		bdvwang:SetValue(setval)
	end
	bdwang:SetValue(1)

	local sklabel = vgui.Create( "DLabel", panel )
		sklabel:SetText( "Skin:" )
		sklabel:SizeToContents()
	sklabel:DockMargin(50,0,0,0)
	sklabel:Dock(LEFT)

	local skwang = vgui.Create( "DNumberWang", panel )
		skwang:SetSize( 30, 20 )
		skwang:SetMin( 0 )
		skwang:SetMax( 9 )
		skwang:SetDecimals( 0 )
		skwang.ConVarChanged = function( p, value ) data.skin = tonumber(value) end
		skwang:SetValue(panel.data.skin)
	skwang:DockMargin(10,0,0,0)
	skwang:Dock(LEFT)

	return panel
end

--[[** Model panel for adjusting models ***
Name:
Model:
Bone name:
Translation x / y / z
Rotation pitch / yaw / role
Model size x / y / z
Material
Color modulation
]]
-- ==== CreateModelPanel - 构建第一人称模型元素编辑面板（名称/模型/骨骼/变换/材质等） ====
function CreateModelPanel( name, preset_data )
	local data = wep.v_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Model"
	data.model = preset_data.model and "" .. preset_data.model .. "" or ""
	data.bone = preset_data.bone and "" .. preset_data.bone .. "" or ""
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )
	data.size = preset_data.size and Vector( preset_data.size.x, preset_data.size.y, preset_data.size.z ) or Vector(0.5,0.5,0.5)
	data.color = preset_data.color and Color( preset_data.color.r, preset_data.color.g, preset_data.color.b, preset_data.color.a ) or Color(255,255,255,255)
	data.surpresslightning = preset_data.surpresslightning and true or false
	data.bonemerge = preset_data.bonemerge and true or false
	data.nocull = preset_data.nocull and true or false
	data.highrender = preset_data.highrender and true or false
	data.material = preset_data.material and "" .. preset_data.material .. "" or ""
	data.bodygroup = preset_data.bodygroup and table.Copy(preset_data.bodygroup) or {}
	data.skin = preset_data.skin and preset_data.skin * 1 or 0

	wep.vRenderOrder = nil -- force viewmodel render order to recache

	local panellist = vgui.Create("DPanelList", pmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = true, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist) ))
	panellist:AddItem(CreateModelModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer():GetViewModel(), name ))
	panellist:AddItem(CreateBonemergeModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist), name ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 3 ))
	panellist:AddItem(CreateColorModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateHighRenderModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateNocullModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSLightningModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateMaterialModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBodygroupSkinModifier( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist

end

--[[** Sprite panel for adjusting sprites ***
Name:
Sprite:
Bone name:
Translation x / y / z
Sprite x / y size
Color
]]
-- ==== CreateSpritePanel - 构建第一人称精灵元素编辑面板 ====
function CreateSpritePanel( name, preset_data )
	local data = wep.v_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Sprite"
	data.sprite = preset_data.sprite and "" .. preset_data.sprite .. "" or ""
	data.bone = preset_data.bone and "" .. preset_data.bone .. "" or ""
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.size = preset_data.size and { x = preset_data.size.x * 1, y = preset_data.size.y * 1 } or { x = 1, y = 1 }
	data.color = preset_data.color and Color( preset_data.color.r, preset_data.color.g, preset_data.color.b, preset_data.color.a ) or Color(255,255,255,255)
	data.nocull = preset_data.nocull or true
	data.additive = preset_data.additive or true
	data.vertexalpha = preset_data.vertexalpha or true
	data.vertexcolor = preset_data.vertexcolor or true
	data.ignorez = preset_data.ignorez or false

	wep.vRenderOrder = nil

	local panellist = vgui.Create("DPanelList", pmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = true, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name,SimplePanel(panellist) ))
	panellist:AddItem(CreateSpriteModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer():GetViewModel(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 2 ))
	panellist:AddItem(CreateColorModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateParamModifiers( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

--[[** Model panel for adjusting models ***
Name:
Model:
Bone name:
Translation x / y / z
Rotation pitch / yaw / role
Size
]]
-- ==== CreateLensModifiers - ZS PIP 镜片形状参数面板（Quad 专用） ====
-- 形状 / 可见圆半径 / 长宽比 / 四角切角，实时写入元素表并联动视口内的
-- 青色镜片预览（client.lua Quad 分支）；导出由 tool.lua GetVModelsText 输出。
-- 构建顺序与 Position/Angle 面板严格同构：先创建配置全部控件 →
-- PerformLayout 显式设宽 → 最后统一 Dock(TOP)，避免布局错位
local function CreateLensModifiers( data, panel )

	if panel._passdata and panel._passdata._name then
		local data_check = panel._passdata._v and wep.v_models[ panel._passdata._name ] or wep.w_models[ panel._passdata._name ]
		if data_check ~= data then
			data = data_check
		end
	end

	panel.data = data

	panel:SetTall(32 * 7)
	PanelApplyBackground(panel)

	local lenslabel = vgui.Create( "DLabel", panel )
		lenslabel:SetText( "ZS Lens:" )
		lenslabel:SizeToContents()
		lenslabel:SetWide(45)
		lenslabel:SetMouseInputEnabled( true )
	lenslabel:Dock(LEFT)

	-- 裁剪形状：圆形（默认）/ 方形 / 切角多边形（显式高度，消除默认值歧义）
	local shapebox = vgui.Create( "DComboBox", panel )
		shapebox:SetTall( 24 )
		shapebox:SetText( data.pip_shape == "square" and "方形" or data.pip_shape == "poly" and "切角多边形" or "圆形（默认）" )
		shapebox:AddChoice( "圆形（默认）", "circle" )
		shapebox:AddChoice( "方形", "square" )
		shapebox:AddChoice( "切角多边形", "poly" )
		shapebox.OnSelect = function( _, _, _, value )
			data.pip_shape = value
			if value == "poly" and not istable(data.pip_chamfer) then
				data.pip_chamfer = { tl = 0.25, tr = 0.25, br = 0, bl = 0 }
			end
		end
	shapebox:DockMargin(10,0,0,0)

	-- 滑条工厂：先创建配置（含初值），收集进表，最后统一 Dock
	local lenswangs = {}
	local function NewLensWang( text, minv, maxv, init, onchanged )
		local wang = vgui.Create( "DNumSlider", panel )
			wang:SetTall( 32 )
			wang:SetText( text )
			wang:SetMinMax( minv, maxv )
			wang:SetDecimals( 2 )
			wang.Wang.ConVarChanged = function( p, value ) onchanged( tonumber(value) ) end
			wang:SetValue( init )
		wang:DockMargin(10,0,0,0)
		lenswangs[#lenswangs + 1] = wang
	end

	-- 可见圆半径比（仅圆形生效；size 放大留定位余量时用它把圆收回筒口）
	NewLensWang( "半径", 0.05, 1, tonumber(data.pip_radius) or 1, function(v) data.pip_radius = v end)

	-- 长宽比（宽/高；>1 拉宽镜内画面窗口，RT 采样同步保持角密度）
	NewLensWang( "宽/高", 0.25, 4, tonumber(data.pip_aspect) or 1, function(v) data.pip_aspect = v end)

	-- 四角切角量（仅切角多边形生效）
	local chamfer_fields = { { "左上切角", "tl" }, { "右上切角", "tr" }, { "右下切角", "br" }, { "左下切角", "bl" } }
	for _, cf in ipairs( chamfer_fields ) do
		NewLensWang( cf[1], 0, 0.95, istable(data.pip_chamfer) and tonumber(data.pip_chamfer[cf[2]]) or 0, function(v)
			data.pip_chamfer = data.pip_chamfer or {}
			data.pip_chamfer[cf[2]] = v
		end)
	end

	-- 宽度自适应：控件占标签列右侧区域（留 60px 标签列 + 边距）
	panel.PerformLayout = function()
		local wide = panel:GetWide() - 70
		shapebox:SetWide( wide )
		for _, wang in ipairs( lenswangs ) do
			wang:SetWide( wide )
		end
	end

	-- 统一 Dock（顺序即行序：形状 → 半径 → 宽高比 → 四角切角）
	shapebox:Dock(TOP)
	for _, wang in ipairs( lenswangs ) do
		wang:Dock(TOP)
	end

	return panel
end

-- ==== CreateQuadPanel - 构建第一人称 Quad 元素编辑面板 ====
function CreateQuadPanel( name, preset_data )
	local data = wep.v_models[name]
	if (not preset_data) then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Quad"
	data.model = preset_data.model or ""
	data.bone = preset_data.bone and "" .. preset_data.bone .. "" or ""
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )
	data.size = preset_data.size and preset_data.size * 1 or 0.05

	wep.vRenderOrder = nil -- force viewmodel render order to recache

	local panellist = vgui.Create("DPanelList", pmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = true, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer():GetViewModel(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 1 ))
	panellist:AddItem(CreateLensModifiers( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

-- ==== CreateClipPanel - 构建第一人称裁剪面元素编辑面板 ====
function CreateClipPanel( name, preset_data )
	local data = wep.v_models[name]
	if (not preset_data) then preset_data = {} end

	-- default data
	data.type = preset_data.type or "ClipPlane"
	data.bone = preset_data.bone and "" .. preset_data.bone .. "" or ""
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )

	wep.vRenderOrder = nil -- force viewmodel render order to recache

	local panellist = vgui.Create("DPanelList", pmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = true, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer():GetViewModel(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

-- adding button DoClick
-- ==== add_element - 添加新元素：创建数据、面板与树节点 ====
local function add_element(btn, realm, tree)
	local line = tree:GetSelectedItem()

	local new = string.Trim( btn:GetValue() )
	if not new then return end

	local is_v = realm == "v"
	local note_func = is_v and CreateNote or CreateWNote
	local model_tab = is_v and wep.v_models or wep.w_models
	local panel_cache = is_v and wep.v_panelCache or wep.w_panelCache

	if new == "" then note_func("Empty name field!") return end
	if model_tab[new] ~= nil then note_func("Name already exists!") return end
	model_tab[new] = {}

	local icon = "icon16/exclamation.png"

	local box_selec = is_v and boxselected or wboxselected
	if not panel_cache[new] then
		if box_selec == "Model" then
			panel_cache[new] = is_v and CreateModelPanel( new ) or CreateWorldModelPanel(new)
			icon = icon_model
		elseif box_selec == "Sprite" then
			panel_cache[new] = is_v and CreateSpritePanel( new ) or CreateWorldSpritePanel(new)
			icon = icon_sprite
		elseif box_selec == "Quad" then
			panel_cache[new] = is_v and CreateQuadPanel( new ) or CreateWorldQuad(new)
			icon = icon_quad
		elseif box_selec == "ClipPlane" then
			panel_cache[new] = is_v and CreateClipPanel( new ) or CreateWorldClipPanel(new)
			icon = icon_clip
		else
			Error("Invalid type selected")
		end
	end

	panel_cache[new]:SetVisible(false)

	local node = tree:AddNode( new, icon )
	node.Type = box_selec
	node.InsertNode = FixInsertNode
	node.DoRightClick = node_do_rclick
	node.realm = realm
	node.DoChildrenOrder = FixDoChildrenOrder
	node._ParentNode = node:GetParentNode()
	node:SetDrawLines( true )

	local ro_tab_name = is_v and "vRenderOrder" or "wRenderOrder"
	local old_DroppedOn = node.DroppedOn
	node.DroppedOn = function( self, pnl )
		old_DroppedOn( self, pnl )
		SetRelativeForNode( pnl, self, realm )
		wep[ro_tab_name] = nil
	end

	node.OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			SetRelativeForNode( v, self, realm )
		end
		wep[ro_tab_name] = nil
	end

	local parent = IsValid(line) and line--IsValid(line._ParentNode) and line._ParentNode or line:GetParentNode()
	if IsValid( parent ) and not parent:IsRootNode() then
		parent:InsertNode( node )
		SetRelativeForNode( node, parent, realm )
		wep[ro_tab_name] = nil
	end
end

mnbtn.DoClick = function()
	add_element(mntext, "v", mtree)
end

local temp_v_nodes = {}
for k, v in SortedPairs(wep.save_data.v_models) do
	wep.v_models[k] = {}

	local icon = "icon16/exclamation.png"

	if (v.type == "Model") then
		wep.v_panelCache[k] = CreateModelPanel( k, v )
		icon = icon_model
	elseif (v.type == "Sprite") then
		wep.v_panelCache[k] = CreateSpritePanel( k, v )
		icon = icon_sprite
	elseif (v.type == "Quad") then
		wep.v_panelCache[k] = CreateQuadPanel( k, v )
		icon = icon_quad
	elseif (v.type == "ClipPlane") then
		wep.v_panelCache[k] = CreateClipPanel( k, v )
		icon = icon_clip
	end

	if IsValid(wep.v_panelCache[k]) then

	wep.v_panelCache[k]:SetVisible(false)

	local node = mtree:AddNode( k, icon )
	node.Type = v.type
	node.InsertNode = FixInsertNode
	node.DoRightClick = node_do_rclick
	node.realm = "v"
	node._ParentNode = node:GetParentNode()
	node.DoChildrenOrder = FixDoChildrenOrder
	node:SetDrawLines( true )

	local old_DroppedOn = node.DroppedOn
	node.DroppedOn = function( self, pnl )
		old_DroppedOn( self, pnl )
		SetRelativeForNode( pnl, self, "v" )
		wep.vRenderOrder = nil
	end

	node.OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			SetRelativeForNode( v, self, "v" )
		end
		wep.vRenderOrder = nil
	end

	temp_v_nodes[k] = node
	end
end

for k, v in SortedPairs( wep.v_models ) do
	if v.rel and v.rel ~= "" and temp_v_nodes[v.rel] and temp_v_nodes[k] and wep.v_models[v.rel] then
		temp_v_nodes[v.rel]:InsertNode( temp_v_nodes[k] )
	end
end

-- remove a line
rmbtn.DoClick = function()
	local line = mtree:GetSelectedItem()

	if not IsValid(line) then return end

	local name = line:GetText()

	for k,v in pairs( line:GetChildNodes() ) do
		mtree:Root():InsertNode( v )
		SetRelativeForNode( v, mtree:Root(), "v" )
	end

	wep.v_models[name] = nil
	-- clear from panel cache
	if wep.v_panelCache[name] then
		wep.v_panelCache[name]:Remove()
		wep.v_panelCache[name] = nil
	end

	line:Remove()
end

-- duplicate line
copybtn.DoClick = function()
	copy_element("v", mtree)
end

-- import worldmodels
importbtn.DoClick = function()
	local temp_v_nodes = {}

	local num = 0
	for k, v in pairs( wep.w_models ) do

		if v.type then

		local name = k
		local i = 1
		while(wep.v_models[name] ~= nil) do
			name = k..""..i
			i = i + 1

			-- changing names might mess up the relative transitions of some stuff
			-- but whatever.
		end

		local new_preset = table.Copy(v)
		new_preset.bone = "ValveBiped.Bip01_R_Hand" -- switch to hand bone by default

		new_preset.pos = Vector(v.pos.x, v.pos.y, v.pos.z)
		if (v.angle) then
			new_preset.angle = Angle(v.angle.p, v.angle.y, v.angle.r)
		end

		if (v.color) then
			new_preset.color = Color(v.color.r,v.color.g,v.color.b,v.color.a)
		end
		if (type(v.size) == "table") then
			new_preset.size = table.Copy(v.size)
		elseif (type(v.size) == "Vector") then
			new_preset.size = Vector(v.size.x, v.size.y, v.size.z)
		end
		if (v.bodygroup) then
			new_preset.bodygroup = table.Copy(v.bodygroup)
		end

		wep.v_models[name] = {}

		local icon = "icon16/exclamation.png"

		if (v.type == "Model") then
			wep.v_panelCache[name] = CreateModelPanel( name, new_preset )
			icon = icon_model
		elseif (v.type == "Sprite") then
			wep.v_panelCache[name] = CreateSpritePanel( name, new_preset )
			icon = icon_sprite
		elseif (v.type == "Quad") then
			wep.v_panelCache[name] = CreateQuadPanel( name, new_preset )
			icon = icon_quad
		elseif (v.type == "ClipPlane") then
			wep.v_panelCache[name] = CreateClipPanel( name, new_preset )
			icon = icon_clip
		end
		wep.v_panelCache[name]:SetVisible(false)

		local node = mtree:AddNode( name, icon )
		node.Type = v.type
		node.InsertNode = FixInsertNode
		node.DoRightClick = node_do_rclick
		node.realm = "v"
		node.DoChildrenOrder = FixDoChildrenOrder
		node._ParentNode = node:GetParentNode()
		node:SetDrawLines( true )

		local old_DroppedOn = node.DroppedOn
		node.DroppedOn = function( self, pnl )
			old_DroppedOn( self, pnl )
			SetRelativeForNode( pnl, self, "v" )
			wep.vRenderOrder = nil
		end

		node.OnModified = function( self )
			for k, v in pairs( self:GetChildNodes() ) do
				SetRelativeForNode( v, self, "v" )
			end
			wep.vRenderOrder = nil
		end

		temp_v_nodes[k] = node

		num = num + 1
		end
	end

	for k, v in SortedPairs(wep.v_models) do
		if v.rel and v.rel ~= "" and temp_v_nodes[v.rel] and temp_v_nodes[k] and wep.v_models[v.rel] then
			temp_v_nodes[v.rel]:InsertNode( temp_v_nodes[k] )
		end
	end
end

--[[--------------------------------------------------------------

					World Models

------------------------------------------------------------/]]
local lastVisible = ""

local mlabel = vgui.Create( "DPanel", pwmodels )
	mlabel:SetTall( 24 )
	mlabel.Paint = function() end
mlabel:Dock(TOP)

local mlock = vgui.Create( "DButton", mlabel )
	mlock:SetSize( 24, 24 )
	mlock:SetIsToggle( true )
	mlock:SetText("")
	mlock:SetIcon( wep.lockRelativePositions and "icon16/lock.png" or "icon16/lock_open.png" )
	mlock:SetToggle( wep.lockRelativePositions )
	mlock:SetTooltip( "Elements will retain their position when their bone or relative are changed" )
	mlock.Think = function( self )
		self:SetToggle( wep.lockRelativePositions )
		self:SetIcon( wep.lockRelativePositions and "icon16/lock.png" or "icon16/lock_open.png" )
	end
	mlock.OnToggled = function( self, toggleState )
		wep.lockRelativePositions = toggleState
	end

mlock:Dock( RIGHT )

local mlabeltext = vgui.Create( "DLabel", mlabel )
	mlabeltext:SetText( "New worldmodel element:" )
mlabeltext:Dock(FILL)

-- ==== CreateWNote - 在第三人称面板上弹出提示通知 ====
local function CreateWNote( text )
	local templabel = vgui.Create( "DLabel" )
		templabel:SetText( text )
		templabel:SizeToContents()

	local x, y = mlabel:GetPos()
	local notif = vgui.Create( "DNotify" , pwmodels )
		notif:SetPos( x + 160, y )
		notif:SetSize( templabel:GetWide(), 20 )
		notif:SetLife( 5 )
		notif:AddItem(templabel)
end

local pnewelement = SimplePanel( pwmodels )
pnewelement:SetTall(20)

	local mnwtext = vgui.Create("DTextEntry", pnewelement )
		mnwtext:SetTall( 20 )
		mnwtext:SetMultiline(false)
		mnwtext:SetText( "element_name" )
	mnwtext:Dock(FILL)

	local mnwbtn = vgui.Create( "DButton", pnewelement )
		mnwbtn:SetSize( 50, 20 )
		mnwbtn:SetText( "Add" )
	mnwbtn:DockMargin(5,0,0,0)
	mnwbtn:Dock(RIGHT)

	local tpbox = vgui.Create( "DComboBox", pnewelement )
		tpbox:SetSize( 100, 20 )
		tpbox:SetText( "Model" )
		tpbox:AddChoice( "Model" )
		tpbox:AddChoice( "Sprite" )
		tpbox:AddChoice( "Quad" )
		tpbox:AddChoice( "ClipPlane" )
		tpbox.OnSelect = function( p, index, value )
			wboxselected = value
		end
	tpbox:DockMargin(5,0,0,0)
	tpbox:Dock(RIGHT)

pnewelement:DockMargin(0,5,0,5)
pnewelement:Dock(TOP)

-- 第三人称元素树形列表
local mwtree = vgui.Create( "DTree", pwmodels)
	mwtree:SetTall( 160 )
	wep.w_modelListing = mwtree
	mwtree:Root():SetDraggableName( "Worldmodel" )

	mwtree:Root().OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			SetRelativeForNode( v, self, "w" )
		end
		wep.wRenderOrder = nil
	end

	function mwtree:DoClick()
		local cursel = self:GetSelectedItem()
		if cursel ~= self.LastSelected then
			self.LastSelected = cursel
			return
		end

		if IsValid(cursel) then
			self:SetSelectedItem(nil)
		end
	end

	mwtree.OnNodeSelected = function( panel )
		local name = mwtree:GetSelectedItem():GetText()
		if wep.w_panelCache[name] == nil then return end

		if (wep.w_panelCache[lastVisible]) then
			wep.w_panelCache[lastVisible]:SetVisible(false)
		end
		wep.w_panelCache[name]:SetVisible(true)

		lastVisible = name
		wep.selectedElement = lastVisible
	end

mwtree:Dock(TOP)

-- 第三人称元素操作按钮行：删除/复制选中元素、导入第一人称元素
local pwbuttons = SimplePanel( pwmodels )

	local rmbtn = vgui.Create( "DButton", pwbuttons )
		rmbtn:SetSize( 140, 25 )
		rmbtn:SetText( "Remove selected" )
	rmbtn:Dock(LEFT)

	local copybtn = vgui.Create( "DButton", pwbuttons )
		copybtn:SetSize( 140, 25 )
		copybtn:SetText( "Copy selected" )
	copybtn:Dock(RIGHT)

	local importbtn = vgui.Create( "DButton", pwbuttons )
		importbtn:SetTall( 25 )
		importbtn:SetText( "Import viewmodels" )
	importbtn:Dock(FILL)

pwbuttons:DockMargin(0,5,0,5)
pwbuttons:Dock(TOP)

-- 粘贴导入入口：与第一人称页面共用同一个粘贴导入对话框
local ppaste_w = vgui.Create( "DButton", pwmodels )
	ppaste_w:SetTall( 25 )
	ppaste_w:SetText( "Paste import elements (SWEP.VElements / WElements)" )
	ppaste_w:SetTooltip( "Paste weapon lua code containing SWEP.VElements / SWEP.WElements blocks,\nand generate the corresponding view/world elements.\n\n粘贴包含 SWEP.VElements / SWEP.WElements 的武器源码，一键生成对应元素模型。" )
ppaste_w:DockMargin(0,0,0,5)
ppaste_w:Dock(TOP)
ppaste_w.DoClick = function()
	OpenSCKPasteImport()
end

--[[** Model panel for adjusting models ***
Name:
Model:
Translation x / y / z
Rotation pitch / yaw / role
Model size x / y / z
Material
Color modulation
]]
-- ==== CreateWorldModelPanel - 构建第三人称模型元素编辑面板 ====
function CreateWorldModelPanel( name, preset_data )
	local data = wep.w_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Model"
	data.model = preset_data.model and "" .. preset_data.model .. "" or ""
	data.bone = preset_data.bone or "ValveBiped.Bip01_R_Hand"
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )
	data.size = preset_data.size and Vector( preset_data.size.x, preset_data.size.y, preset_data.size.z ) or Vector(0.5,0.5,0.5)
	data.color = preset_data.color and Color( preset_data.color.r, preset_data.color.g, preset_data.color.b, preset_data.color.a ) or Color(255,255,255,255)
	data.surpresslightning = preset_data.surpresslightning and true or false
	data.bonemerge = preset_data.bonemerge and true or false
	data.nocull = preset_data.nocull and true or false
	data.highrender = preset_data.highrender and true or false
	data.material = preset_data.material and "" .. preset_data.material .. "" or ""
	data.bodygroup = preset_data.bodygroup and table.Copy(preset_data.bodygroup) or {}
	data.skin = preset_data.skin and preset_data.skin * 1 or 0

	wep.wRenderOrder = nil

	local panellist = vgui.Create("DPanelList", pwmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = false, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist), true ))
	panellist:AddItem(CreateModelModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer(), name ))
	panellist:AddItem(CreateBonemergeModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 3 ))
	panellist:AddItem(CreateColorModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateHighRenderModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateNocullModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSLightningModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateMaterialModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBodygroupSkinModifier( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

--[[** Sprite panel for adjusting sprites ***
Name:
Sprite:
Translation x / y / z
Sprite x / y size
Color
]]
-- ==== CreateWorldSpritePanel - 构建第三人称精灵元素编辑面板 ====
function CreateWorldSpritePanel( name, preset_data )
	local data = wep.w_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Sprite"
	data.sprite = preset_data.sprite and "" .. preset_data.sprite .. "" or ""
	data.bone = preset_data.bone and "" .. preset_data.bone .. "" or "ValveBiped.Bip01_R_Hand"
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.size = preset_data.size and { x = preset_data.size.x * 1, y = preset_data.size.y * 1 } or { x = 1, y = 1 }
	data.color = preset_data.color and Color( preset_data.color.r, preset_data.color.g, preset_data.color.b, preset_data.color.a ) or Color(255,255,255,255)
	data.nocull = preset_data.nocull or true
	data.additive = preset_data.additive or true
	data.vertexalpha = preset_data.vertexalpha or true
	data.vertexcolor = preset_data.vertexcolor or true
	data.ignorez = preset_data.ignorez or false

	wep.wRenderOrder = nil

	local panellist = vgui.Create("DPanelList", pwmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = false, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist), true ))
	panellist:AddItem(CreateSpriteModifier( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 2 ))
	panellist:AddItem(CreateColorModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateParamModifiers( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

--[[** Model panel for adjusting models ***
Name:
Model:
Bone name:
Translation x / y / z
Rotation pitch / yaw / role
Size
]]
-- ==== CreateWorldQuadPanel - 构建第三人称 Quad 元素编辑面板 ====
function CreateWorldQuadPanel( name, preset_data )
	local data = wep.w_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "Quad"
	data.model = preset_data.model and "" .. preset_data.model .. "" or ""
	data.bone = preset_data.bone and "" .. preset_data.bone .. ""  or "ValveBiped.Bip01_R_Hand"
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )
	data.size = preset_data.size and preset_data.size * 1 or 0.05

	wep.vRenderOrder = nil -- force viewmodel render order to recache

	local panellist = vgui.Create("DPanelList", pwmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = false, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist), true ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateSizeModifiers( data, SimplePanel(panellist), 1 ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end

-- ==== CreateWorldClipPanel - 构建第三人称裁剪面元素编辑面板 ====
function CreateWorldClipPanel( name, preset_data )
	local data = wep.w_models[name]
	if not preset_data then preset_data = {} end

	-- default data
	data.type = preset_data.type or "ClipPlane"
	data.bone = preset_data.bone and "" .. preset_data.bone .. ""  or "ValveBiped.Bip01_R_Hand"
	data.rel = preset_data.rel and "" .. preset_data.rel .. "" or ""
	data.pos = preset_data.pos and Vector( preset_data.pos.x, preset_data.pos.y, preset_data.pos.z ) or Vector( 0, 0, 0 )
	data.angle = preset_data.angle and Angle( preset_data.angle.p, preset_data.angle.y, preset_data.angle.r ) or Angle( 0, 0, 0 )

	wep.vRenderOrder = nil -- force viewmodel render order to recache

	local panellist = vgui.Create("DPanelList", pwmodels )
	panellist:SetPaintBackground( true )
		panellist.Paint = function() surface.SetDrawColor( 90, 90, 90, 255 ) surface.DrawRect( 0, 0, panellist:GetWide(), panellist:GetTall() ) end
		panellist:EnableVerticalScrollbar( true )
		panellist:SetSpacing(5)
		panellist:SetPadding(5)
	panellist:DockMargin(0,0,0,5)
	panellist:Dock(TOP)

	panellist._passdata = {  _v = false, _name =  "" .. name .. "" }

	PanelBackgroundReset()

	panellist:AddItem(CreateNameLabel( name, SimplePanel(panellist), true ))
	panellist:AddItem(CreateBoneModifier( data, SimplePanel(panellist), LocalPlayer(), name ))
	panellist:AddItem(CreatePositionModifiers( data, SimplePanel(panellist) ))
	panellist:AddItem(CreateAngleModifiers( data, SimplePanel(panellist) ))

	panellist:InvalidateLayout( true )
	panellist:SizeToChildren( false, true )

	return panellist
end



mnwbtn.DoClick = function()
	add_element(mnwtext, "w", mwtree)
end

local temp_w_nodes = {}
for k, v in SortedPairs( wep.save_data.w_models ) do
	wep.w_models[k] = {}

	-- backwards compatability
	if not v.bone or v.bone == "" then
		v.bone = "ValveBiped.Bip01_R_Hand"
	end

	local icon = "icon16/exclamation.png"

	if (v.type == "Model") then
		wep.w_panelCache[k] = CreateWorldModelPanel( k, v )
		icon = icon_model
	elseif (v.type == "Sprite") then
		wep.w_panelCache[k] = CreateWorldSpritePanel( k, v )
		icon = icon_sprite
	elseif (v.type == "Quad") then
		wep.w_panelCache[k] = CreateWorldQuadPanel( k, v )
		icon = icon_quad
	elseif (v.type == "ClipPlane") then
		wep.w_panelCache[k] = CreateWorldClipPanel( k, v )
		icon = icon_clip
	end

	if IsValid(wep.w_panelCache[k]) then

	wep.w_panelCache[k]:SetVisible(false)

	local node = mwtree:AddNode( k, icon )
	node.Type = v.type
	node.InsertNode = FixInsertNode
	node.DoRightClick = node_do_rclick
	node.realm = "w"
	node.DoChildrenOrder = FixDoChildrenOrder
	node._ParentNode = node:GetParentNode()
	node:SetDrawLines( true )

	local old_DroppedOn = node.DroppedOn
	node.DroppedOn = function( self, pnl )
		old_DroppedOn( self, pnl )
		SetRelativeForNode( pnl, self, "w" )
		wep.wRenderOrder = nil
	end

	node.OnModified = function( self )
		for k, v in pairs( self:GetChildNodes() ) do
			SetRelativeForNode( v, self, "w" )
		end
		wep.wRenderOrder = nil
	end

	temp_w_nodes[k] = node
	end
end

for k, v in SortedPairs( wep.w_models ) do
	if v.rel and v.rel ~= "" and temp_w_nodes[v.rel] and temp_w_nodes[k] and wep.w_models[v.rel] then
		temp_w_nodes[v.rel]:InsertNode( temp_w_nodes[k] )
	end
end

-- import viewmodels
importbtn.DoClick = function()
	local num = 0
	for k, v in SortedPairs(wep.v_models) do

		if v.type then

		local name = k
		local i = 1
		while wep.w_models[name] ~= nil do
			name = k..""..i
			i = i + 1

			-- changing names might mess up the relative transitions of some stuff
			-- but whatever.
		end

		local new_preset = table.Copy(v)
		new_preset.bone = "ValveBiped.Bip01_R_Hand" -- switch to hand bone by default

		new_preset.pos = Vector(v.pos.x, v.pos.y, v.pos.z)
		if v.angle then
			new_preset.angle = Angle(v.angle.p, v.angle.y, v.angle.r)
		end

		if v.color then
			new_preset.color = Color(v.color.r,v.color.g,v.color.b,v.color.a)
		end
		if type(v.size) == "table" then
			new_preset.size = table.Copy(v.size)
		elseif type(v.size) == "Vector" then
			new_preset.size = Vector(v.size.x, v.size.y, v.size.z)
		end

		if v.bodygroup then
			new_preset.bodygroup = table.Copy(v.bodygroup)
		end

		wep.w_models[name] = {}

		local icon = "icon16/exclamation.png"

		if v.type == "Model" then
			wep.w_panelCache[name] = CreateWorldModelPanel( name, new_preset )
			icon = icon_model
		elseif v.type == "Sprite" then
			wep.w_panelCache[name] = CreateWorldSpritePanel( name, new_preset )
			icon = icon_sprite
		elseif v.type == "Quad" then
			wep.w_panelCache[name] = CreateWorldQuadPanel( name, new_preset )
			icon = icon_quad
		elseif v.type == "ClipPlane" then
			wep.w_panelCache[name] = CreateWorldClipPanel( name, new_preset )
			icon = icon_clip
		end
		wep.w_panelCache[name]:SetVisible(false)

		local node = mwtree:AddNode( name, icon )
		node.Type = v.type
		node.InsertNode = FixInsertNode
		node.DoRightClick = node_do_rclick
		node.realm = "w"
		node.DoChildrenOrder = FixDoChildrenOrder
		node._ParentNode = node:GetParentNode()
		node:SetDrawLines( true )

		local old_DroppedOn = node.DroppedOn
		node.DroppedOn = function( self, pnl )
			old_DroppedOn( self, pnl )
			SetRelativeForNode( pnl, self, "w" )
			wep.wRenderOrder = nil
		end

		node.OnModified = function( self )
			for k, v in pairs( self:GetChildNodes() ) do
				SetRelativeForNode( v, self, "w" )
			end
			wep.wRenderOrder = nil
		end

		temp_w_nodes[k] = node

		num = num + 1
		end
	end

	for k, v in SortedPairs( wep.w_models ) do
		if v.rel and v.rel ~= "" and temp_w_nodes[v.rel] and temp_w_nodes[k] and wep.w_models[v.rel] then
			temp_w_nodes[v.rel]:InsertNode( temp_w_nodes[k] )
		end
	end
end

-- remove a line
rmbtn.DoClick = function()
	local line = mwtree:GetSelectedItem()
	if not IsValid(line) then return end

	local name = line:GetText()
	for k,v in pairs(line:GetChildNodes()) do
		mwtree:Root():InsertNode(v)
		SetRelativeForNode(v, mwtree:Root(), "w")
	end

	wep.w_models[name] = nil
	-- clear from panel cache
	if wep.w_panelCache[name] then
		wep.w_panelCache[name]:Remove()
		wep.w_panelCache[name] = nil
	end

	line:Remove()
end

-- duplicate line
copybtn.DoClick = function()
	copy_element("w", mwtree)
end

--[[*************************************************************************

					Paste import (SWEP.VElements / SWEP.WElements)

	从任意武器源码或 SCK 导出文本中提取 SWEP.VElements / SWEP.WElements 表，
	安全求值后批量生成对应的第一/第三人称元素模型。

*************************************************************************]]

-- 支持导入的元素类型白名单
local import_valid_types = {
	Model = true,
	Sprite = true,
	Quad = true,
	ClipPlane = true
}

-- 元素类型 -> 树节点图标
local import_type_icons = {
	Model = icon_model,
	Sprite = icon_sprite,
	Quad = icon_quad,
	ClipPlane = icon_clip
}

-- 示例代码（供"Fill example"按钮填入粘贴框）
local import_example_code = [[
SWEP.VElements = {
	["example"] = { type = "Model", model = "models/props_junk/PopCan01a.mdl", bone = "ValveBiped.Bip01_R_Hand", rel = "", pos = Vector(0, 0, 0), angle = Angle(0, 0, 0), size = Vector(0.5, 0.5, 0.5), color = Color(255, 255, 255, 255), surpresslightning = false, bonemerge = false, highrender = false, nocull = false, material = "", skin = 0, bodygroup = {} },
}
]]

-- ==== StripLuaComments - 去除代码中的块注释与行注释，避免误匹配 ====
-- 同时兼容仓库内遗留的 C 风格注释（/* */）
local function StripLuaComments(str)
	str = string.gsub(str, "/%*.-%*/", "")
	str = string.gsub(str, "/%*.*", "")
	str = string.gsub(str, "%-%-%[%[.-%]%]", "")
	str = string.gsub(str, "%-%-%[%[.*", "")
	str = string.gsub(str, "%-%-[^\n]*", "")

	return str
end

-- ==== SkipQuotedString - 跳过引号字符串内容，返回结束后的位置 ====
local function SkipQuotedString(str, start_pos)
	local len = #str
	local quote = string.sub(str, start_pos, start_pos)
	local i = start_pos + 1

	while i <= len do
		local c = string.sub(str, i, i)

		if c == "\\" then
			i = i + 2
		elseif c == quote then
			return i + 1
		else
			i = i + 1
		end
	end

	return len + 1
end

-- ==== FindMatchingBrace - 从左花括号扫描到配对的右花括号 ====
-- 跳过引号字符串与 [==[ 长字符串]，保证嵌套表结构完整；不闭合时返回 nil
local function FindMatchingBrace(str, open_pos)
	local len = #str
	local depth = 0
	local i = open_pos

	while i <= len do
		local c = string.sub(str, i, i)

		if c == "{" then
			depth = depth + 1
			i = i + 1
		elseif c == "}" then
			depth = depth - 1

			if depth == 0 then return i end

			i = i + 1
		elseif c == "\"" or c == "'" then
			i = SkipQuotedString(str, i)
		elseif c == "[" then
			local equals = string.match(str, "^%[(=*)%[", i)

			if equals then
				local token_len = #equals + 2
				local close_pos = string.find(str, "]" .. equals .. "]", i + token_len, true)

				if not close_pos then return nil end

				i = close_pos + token_len
			else
				i = i + 1
			end
		else
			i = i + 1
		end
	end

	return nil
end

-- ==== ExtractElementsBlock - 提取字段名（VElements/WElements）对应的表源码块 ====
local function ExtractElementsBlock(str, field_name)
	local init = 1

	while true do
		local _, brace_pos = string.find(str, "%f[%w_]" .. field_name .. "%f[^%w_]%s*=%s*%{", init)

		if not brace_pos then return nil end

		local close_pos = FindMatchingBrace(str, brace_pos)

		if close_pos then
			return string.sub(str, brace_pos, close_pos)
		end

		init = brace_pos + 1
	end
end

-- ==== ToImportVector - 把导入值安全转换为 Vector ====
local function ToImportVector(src, default)
	if isvector(src) then
		return Vector(src.x, src.y, src.z)
	end

	if istable(src) and src.x and src.y and src.z then
		return Vector(tonumber(src.x) or 0, tonumber(src.y) or 0, tonumber(src.z) or 0)
	end

	if isnumber(src) then
		return Vector(src, src, src)
	end

	return default
end

-- ==== ToImportAngle - 把导入值安全转换为 Angle ====
-- 注意：GMod 的 Angle 对象不是普通 table（istable 为 false），必须先用 isangle 判断
local function ToImportAngle(src)
	if isangle(src) then
		return Angle(src.p, src.y, src.r)
	end

	if istable(src) and src.p then
		return Angle(tonumber(src.p) or 0, tonumber(src.y) or 0, tonumber(src.r) or 0)
	end

	return Angle(0, 0, 0)
end

-- ==== ToImportColor - 把导入值安全转换为 Color ====
local function ToImportColor(src)
	if istable(src) and src.r then
		return Color(tonumber(src.r) or 255, tonumber(src.g) or 255, tonumber(src.b) or 255, tonumber(src.a) or 255)
	end

	return Color(255, 255, 255, 255)
end

-- ==== SanitizeImportedElement - 校验并补全单个导入元素的必需字段 ====
-- 不支持类型的元素返回 nil（调用方跳过）
local function SanitizeImportedElement(src, is_world)
	if not istable(src) or not import_valid_types[src.type] then return nil end

	local out = {}
	out.type = src.type
	out.bone = tostring(src.bone or "")
	out.rel = tostring(src.rel or "")

	-- 第三人称元素缺省挂在右手骨骼上（与存档加载逻辑保持一致）
	if is_world and out.bone == "" then
		out.bone = "ValveBiped.Bip01_R_Hand"
	end

	out.pos = ToImportVector(src.pos, Vector(0, 0, 0))
	out.angle = ToImportAngle(src.angle)

	if src.type == "Model" then
		out.model = tostring(src.model or "")
		out.size = ToImportVector(src.size, Vector(0.5, 0.5, 0.5))
		out.color = ToImportColor(src.color)
		out.surpresslightning = tobool(src.surpresslightning)
		out.bonemerge = tobool(src.bonemerge)
		out.highrender = tobool(src.highrender)
		out.nocull = tobool(src.nocull)
		out.material = tostring(src.material or "")
		out.skin = tonumber(src.skin) or 0

		out.bodygroup = {}
		if istable(src.bodygroup) then
			for bg_index, bg_value in pairs(src.bodygroup) do
				if isnumber(bg_index) and isnumber(bg_value) then
					out.bodygroup[bg_index] = math.floor(bg_value)
				end
			end
		end
	elseif src.type == "Sprite" then
		out.sprite = tostring(src.sprite or "")
		out.color = ToImportColor(src.color)
		out.nocull = tobool(src.nocull)
		out.additive = tobool(src.additive)
		out.vertexalpha = tobool(src.vertexalpha)
		out.vertexcolor = tobool(src.vertexcolor)
		out.ignorez = tobool(src.ignorez)

		local size_x = 1
		local size_y = 1

		if istable(src.size) or isvector(src.size) then
			size_x = tonumber(src.size.x) or 1
			size_y = tonumber(src.size.y) or 1
		end

		out.size = { x = size_x, y = size_y }
	elseif src.type == "Quad" then
		out.model = tostring(src.model or "")
		out.size = tonumber(src.size) or 0.05
	end

	-- ClipPlane 只需要 bone / rel / pos / angle，上面已处理完毕
	return out
end

-- ==== ParsePastedElementCode - 从粘贴文本解析并净化 V/W 元素表 ====
-- 失败返回 nil + 错误信息；成功返回 { v = {[名字]=元素数据}, w = {[名字]=元素数据} }
local function ParsePastedElementCode(text)
	if not isstring(text) or string.Trim(text) == "" then
		return nil, "Paste is empty!"
	end

	local stripped = StripLuaComments(text)
	local v_block = ExtractElementsBlock(stripped, "VElements")
	local w_block = ExtractElementsBlock(stripped, "WElements")

	if not v_block and not w_block then
		return nil, "No SWEP.VElements or SWEP.WElements block found!"
	end

	-- 只把提取出的表代码包进隔离片段执行，避免粘贴文件中的其他语句产生副作用
	local chunks = {}
	chunks[#chunks + 1] = "local __SCK_IMPORT = {}"

	if v_block then
		chunks[#chunks + 1] = "__SCK_IMPORT.VElements = " .. v_block
	end

	if w_block then
		chunks[#chunks + 1] = "__SCK_IMPORT.WElements = " .. w_block
	end

	chunks[#chunks + 1] = "return __SCK_IMPORT"

	local ok_compile, func, compile_err = pcall(CompileString, table.concat(chunks, "\n"), "SCKPasteImport")

	if not ok_compile or not isfunction(func) then
		return nil, "Code syntax error: " .. tostring(compile_err or func)
	end

	local ok_run, result = pcall(func)

	if not ok_run or not istable(result) then
		return nil, "Code runtime error: " .. tostring(result)
	end

	local parsed = { v = {}, w = {} }

	for realm, raw_table in pairs({ v = result.VElements, w = result.WElements }) do
		if istable(raw_table) then
			for name, element in pairs(raw_table) do
				local clean = SanitizeImportedElement(element, realm == "w")

				if clean then
					parsed[realm][tostring(name)] = clean
				end
			end
		end
	end

	return parsed
end

-- ==== InjectImportedElements - 批量注入元素到第一(v)/第三(w)人称页面 ====
-- 返回成功生成的元素数量
local function InjectImportedElements(realm, elements)
	if not istable(elements) or next(elements) == nil then return 0 end

	local is_v = realm == "v"
	local tree = is_v and mtree or mwtree
	local model_tab = is_v and wep.v_models or wep.w_models
	local panel_cache = is_v and wep.v_panelCache or wep.w_panelCache
	local render_order_field = is_v and "vRenderOrder" or "wRenderOrder"
	local temp_nodes = {}
	local final_names = {}

	-- 已占用名字集合：现有元素 + 本次导入的其他元素，防止导入内部互相顶名
	local claimed_names = {}
	for existing_name in pairs(model_tab) do
		claimed_names[existing_name] = true
	end

	-- 第一遍：为每个元素确定最终名字（重名自动追加数字后缀）
	for orig_name in pairs(elements) do
		local base_name = tostring(orig_name)
		local desired = base_name ~= "" and base_name or "imported_element"
		local final_name = desired

		if claimed_names[final_name] then
			local index = 1

			while claimed_names[desired .. index] do
				index = index + 1
			end

			final_name = desired .. index
		end

		claimed_names[final_name] = true
		final_names[base_name] = final_name
	end

	-- 第二遍：同步修正被重命名元素之间的 rel 相对引用
	for _, element in pairs(elements) do
		if element.rel and element.rel ~= "" and final_names[element.rel] then
			element.rel = final_names[element.rel]
		end
	end

	-- 第三遍：创建数据、编辑面板与树节点（流程与手动添加/互导按钮一致）
	local count = 0

	for orig_name, element in SortedPairs(elements) do
		local name = final_names[tostring(orig_name)]

		model_tab[name] = {}

		if is_v then
			if element.type == "Model" then
				panel_cache[name] = CreateModelPanel(name, element)
			elseif element.type == "Sprite" then
				panel_cache[name] = CreateSpritePanel(name, element)
			elseif element.type == "Quad" then
				panel_cache[name] = CreateQuadPanel(name, element)
			elseif element.type == "ClipPlane" then
				panel_cache[name] = CreateClipPanel(name, element)
			end
		else
			if element.type == "Model" then
				panel_cache[name] = CreateWorldModelPanel(name, element)
			elseif element.type == "Sprite" then
				panel_cache[name] = CreateWorldSpritePanel(name, element)
			elseif element.type == "Quad" then
				panel_cache[name] = CreateWorldQuadPanel(name, element)
			elseif element.type == "ClipPlane" then
				panel_cache[name] = CreateWorldClipPanel(name, element)
			end
		end

		if not IsValid(panel_cache[name]) then
			model_tab[name] = nil
		else
			panel_cache[name]:SetVisible(false)

			local node = tree:AddNode(name, import_type_icons[element.type])
			node.Type = element.type
			node.InsertNode = FixInsertNode
			node.DoRightClick = node_do_rclick
			node.realm = realm
			node.DoChildrenOrder = FixDoChildrenOrder
			node._ParentNode = node:GetParentNode()
			node:SetDrawLines(true)

			local old_DroppedOn = node.DroppedOn
			node.DroppedOn = function(s, pnl)
				old_DroppedOn(s, pnl)
				SetRelativeForNode(pnl, s, realm)
				wep[render_order_field] = nil
			end

			node.OnModified = function(s)
				for _, child in pairs(s:GetChildNodes()) do
					SetRelativeForNode(child, s, realm)
				end
				wep[render_order_field] = nil
			end

			temp_nodes[name] = node
			count = count + 1
		end
	end

	-- 第四遍：恢复本次导入范围内的相对父子层级
	for name, data in SortedPairs(model_tab) do
		if data.rel and data.rel ~= ""
			and temp_nodes[data.rel] and temp_nodes[name] and model_tab[data.rel] then
			temp_nodes[data.rel]:InsertNode(temp_nodes[name])
		end
	end

	wep[render_order_field] = nil

	return count
end

local paste_import_frame = nil

-- ==== OpenSCKPasteImport - 打开粘贴导入窗口（供第一/第三人称页按钮调用） ====
function OpenSCKPasteImport()
	if IsValid(paste_import_frame) then
		paste_import_frame:Remove()
		wep.pasteImportActive = nil
	end

	-- 挂在菜单框架下：关闭武器菜单时对话框随之销毁
	local menu_frame = IsValid(wep.Frame) and wep.Frame or nil
	local frame = vgui.Create("DFrame", menu_frame)
	frame:SetSize(640, 520)
	frame:Center()
	frame:SetTitle("Paste import - SWEP.VElements / SWEP.WElements")
	frame:SetSizable(true)
	frame:SetDeleteOnClose(true)
	frame:MakePopup()

	paste_import_frame = frame
	wep.pasteImportActive = true

	-- 弹出层关闭后恢复菜单框架的键鼠输入，防止输入焦点残留导致 CTRL 快捷键失效
	frame.OnClose = function()
		wep.pasteImportActive = nil

		timer.Simple(0, function()
			if not IsValid(wep.Frame) then return end

			wep.Frame:SetKeyboardInputEnabled(true)
			wep.Frame:SetMouseInputEnabled(true)
		end)
	end

	local infolabel = vgui.Create("DLabel", frame)
	infolabel:SetTall(32)
	infolabel:SetWrap(true)
	infolabel:SetText("Paste weapon lua code containing SWEP.VElements and/or SWEP.WElements blocks (from any weapon file or \"Copy SCK to clipboard\"). Elements will be added to the current session.")
	infolabel:DockMargin(8, 4, 8, 0)
	infolabel:Dock(TOP)

	local textentry = vgui.Create("DTextEntry", frame)
	textentry:SetMultiline(true)
	textentry:SetTall(360)
	textentry:DockMargin(8, 4, 8, 4)
	textentry:Dock(FILL)

	local statuslabel = vgui.Create("DLabel", frame)
	statuslabel:SetTall(18)
	statuslabel:SetText("")
	statuslabel:DockMargin(8, 0, 8, 0)
	statuslabel:Dock(TOP)

	local btnrow = vgui.Create("DPanel", frame)
	btnrow:SetTall(28)
	btnrow.Paint = function() end
	btnrow:DockMargin(8, 2, 8, 8)
	btnrow:Dock(BOTTOM)

	local closebtn = vgui.Create("DButton", btnrow)
	closebtn:SetText("Close")
	closebtn:SetWide(90)
	closebtn:Dock(RIGHT)
	closebtn.DoClick = function()
		frame:Close()
	end

	local examplebtn = vgui.Create("DButton", btnrow)
	examplebtn:SetText("Fill example")
	examplebtn:SetWide(110)
	examplebtn:DockMargin(0, 0, 5, 0)
	examplebtn:Dock(RIGHT)
	examplebtn.DoClick = function()
		textentry:SetText(import_example_code)
	end

	local confirmbtn = vgui.Create("DButton", btnrow)
	confirmbtn:SetText("Import and generate models")
	confirmbtn:DockMargin(0, 0, 5, 0)
	confirmbtn:Dock(FILL)

	confirmbtn.DoClick = function()
		local parsed, err = ParsePastedElementCode(textentry:GetValue())

		if not parsed then
			statuslabel:SetTextColor(Color(255, 100, 100))
			statuslabel:SetText("Import failed: " .. tostring(err))
			surface.PlaySound("buttons/button10.wav")
			return
		end

		local num_v = InjectImportedElements("v", parsed.v)
		local num_w = InjectImportedElements("w", parsed.w)

		if num_v + num_w == 0 then
			statuslabel:SetTextColor(Color(255, 160, 60))
			statuslabel:SetText("No valid elements found! Supported types: Model / Sprite / Quad / ClipPlane.")
			surface.PlaySound("buttons/button10.wav")
			return
		end

		surface.PlaySound("buttons/button14.wav")
		LocalPlayer():ChatPrint("[SCK] Imported " .. num_v .. " view element(s) and " .. num_w .. " world element(s)!")

		frame:Close()
	end
end
