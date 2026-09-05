-- ============================================================================
-- pinventory.lua - 按住 ALT 打开的双栏背包面板（SUNRUST 风格复刻，共识 v5.3）
-- 顶部标题行 INVENTORY / ITEM INFO / REMANTLER；左栏 INVENTORY：四类可折叠列表
-- （选中行反白）；右栏 ITEM INFO 自上而下：变体行 → 物品展示行（图标+名称+N）→
-- STATS-DESCRIPTION 文字页签 → 属性/描述页 → 底部自下而上：拆解行 → 动作切段行
-- （丢弃|清空弹夹|给予|▾）→ UPGRADE 大字按钮 + 4 段品质分段条；
-- 底部横跨 ZSAmmoBar 弹药横栏（见 dammobar.lua）+ 开关行。
-- 打开入口：GAMEMODE:OpenInventoryPanel()（集成方在 MenuKey 按下时调用）。
-- UI 文案一律走 translate.Get，翻译键清单见文件尾部注释。
-- 布局比例以 SUNRUST 靶子图（2560x1440 实测）为准：
--   主块宽 0.48 屏宽 / 高 0.80 屏高，栏比 0.48:0.50，栏距 20 基值，
--   分类头行高 33、列表行高 38、变体按钮高 28、展示行高 98、页签行高 24、
--   动作/拆解行高 32、升级行高 44（均为 BetterScreenScale 基值）。
-- ============================================================================
-- UI 结构索引（VGUI 结构索引规范：区域/位置/作用/常改）
--
-- [区域] 根面板与字体
-- [位置] PANEL:Init / PANEL:PerformLayout / EnsurePinvFonts / GAMEMODE:OpenInventoryPanel()
-- [作用] 屏幕居中主块（宽 0.48 屏宽、高 0.80 屏高）；Paint 采样每帧更新的全屏
--        毛玻璃 RT 并暗化；面板专属字体按 BetterScreenScale 懒创建
--        （标题 30 / 条目 20 / 行 17 / 小字 14）；ALT 松开自动关闭
-- [常改] 面板宽高比例、整体配色、字号层级、模糊与暗化强度
--
-- [区域] 顶部标题行
-- [位置] PANEL:BuildColumns() 内 header
-- [作用] 左「INVENTORY」右「ITEM INFO」大字标题（Paint 自绘），最右「重组机」+「返回」入口按钮
-- [常改] 标题字号、按钮宽度
--
-- [区域] 左栏背包列表
-- [位置] PANEL:BuildInventoryList() / PANEL:AddItemRow(entry)
-- [作用] 武器按 GetClass 去重、物品按前缀分四类折叠列表（分类头 33、行高 38、
--        无缝行 + 1px 分隔线），点击选中并联动右栏与切枪；选中行整行反白（浅灰底黑字）
-- [常改] 折叠头高度、行高、图标尺寸、反白配色、排序规则
--
-- [区域] 右栏物品信息
-- [位置] PANEL:BuildItemInfo() / PANEL:UpdateItemInfo(entry)
-- [作用] 变体行（顶部）→ 物品展示行（killicon + 名称 + 品质色 +N）→ STATS-DESCRIPTION
--        文字页签（左端白竖线）→ 属性/描述页；页内留白规则见 STATS 页
-- [常改] 各行高度、展示行名称起点、页签宽度
--
-- [区域] 变体行
-- [位置] PANEL:RebuildVariantRow(entry)
-- [作用] 右栏顶部 [标准] + 各分支按钮，当前分支高亮；按品质档选择 zs_upgrade 或
--        zs_quickremantle
-- [常改] 按钮宽度策略、分支显示名取法、灰置条件
--
-- [区域] 升级块（分段条 + 大字按钮）
-- [位置] PANEL:BuildUpgradeBlock() / PANEL:UpdateUpgradeBlock(entry)
-- [作用] 4 段品质分段条（亮段数 = 档位 + 1；无升级能力武器整条显示）+ 红色 UPGRADE
--        大字按钮（右侧数量 + 废料图标），位于动作行上方；满品质禁用换文案
-- [常改] 段数、亮暗颜色、大字配色
--
-- [区域] 动作切段行与拆解行
-- [位置] PANEL:RebuildActionRow(entry) / BuildItemInfo 内 DismantleButton
-- [作用] 丢弃|清空弹夹|给予 共享边框切段行 + 右端「选择附近人类」弹出列表（给予目标）；
--        拆解为独立全宽行（左标签右 +N 废料图标，返还数走 GM:GetDismantleScrap）
-- [常改] 按钮顺序、切段宽度、拆解返还取法
--
-- [区域] 弹药横栏挂载
-- [位置] PANEL:BuildAmmoBar()
-- [作用] vgui.Create("ZSAmmoBar", self) 并 Dock Bottom 挂载（开关行之下）
-- [常改] 挂载边距
--
-- [区域] 开关行
-- [位置] PANEL:BuildSwitchRow() / PANEL:UpdateSwitchRow()
-- [作用] 饰品排序/禁止拾取道具/自动购买废料三个复选框（暗红=关 绿=开）+ 返回按钮
-- [常改] 复选框顺序、绑定的 ConVar、按钮宽度
-- ============================================================================

local PANEL = {}

-- 性能局部化（仓库惯例）
local math = math
local pairs = pairs
local ipairs = ipairs
local string = string
local table = table
local tostring = tostring
local RealTime = RealTime
local draw = draw
local surface = surface
local render = render
local vgui = vgui
local IsValid = IsValid
local RunConsoleCommand = RunConsoleCommand

-- 字体常量（标题/条目/行/小字为本文件懒创建；正文与弹药行走 cl_init 现成字体）
local FONT_TITLE = "PINV_FontTitle"      -- 面板标题 / UPGRADE 大字（30 级）
local FONT_ITEM = "PINV_FontItem"        -- 右栏物品名 / 拆解行（20 级）
local FONT_ROW = "PINV_FontRow"          -- 列表行 / 切段按钮（17 级）
local FONT_SMALL = "PINV_FontSmall"      -- 变体标签 / 页签 / 描述 / 复选框（14 级）
local FONT_BODY = "ZSBodyTextFont"       -- 属性行与弹药行（现成）

-- 布局常量（全部经 BetterScreenScale() 换算，比例实测自 SUNRUST 靶子图 2560x1440）
local PANEL_WIDTH_RATIO = 0.48      -- 根面板宽 = 0.48 * ScrW（实测 1222/2560）
local PANEL_HEIGHT_RATIO = 0.80     -- 根面板高（实测 1150/1440，含标题行）
local LEFT_COLUMN_RATIO = 0.48      -- 左栏占内容区宽度比（实测 585:610）
local COLUMN_GAP = 20               -- 左右栏间距（实测 27px）
local HEADER_TALL = 34              -- 顶部标题行高（实测 45px）
local CAT_HEADER_TALL = 33          -- 分类折叠头行高（实测 44px）
local LIST_ROW_TALL = 38            -- 列表条目行高（实测 50px，无缝）
local LIST_REFRESH_TIME = 0.25      -- 手持/库存变化轮询间隔
local REMANTLER_POLL_TIME = 0.5     -- 拆解台距离轮询间隔
local KEYLOSE_DEBOUNCE = 0.1        -- ALT 丢失防抖（KeyRelease 丢失时兜底）
local ARROW_SIZE = 4                -- 折叠箭头半边长（基值）

-- 主题色（SUNRUST 透明度：栏底 alpha≈130，毛玻璃透出）
local colColumnBG = Color(8, 8, 10, 170)          -- 栏底色
local colHeaderBG = Color(5, 5, 6, 190)           -- 分类折叠头底色
local colRowBG = Color(15, 15, 17, 110)           -- 列表行底色
local colRowBGHover = Color(56, 56, 58, 215)      -- 列表行悬停底色
local colRowSelected = Color(213, 213, 213, 255)  -- 选中行反白底色
local colTextBright = Color(235, 235, 235)
local colTextDim = Color(150, 150, 156)
local colTextDisabled = Color(95, 95, 100)
local colTextDark = Color(18, 18, 18)             -- 反白行文字 / 选中变体文字
local colRowText = Color(224, 224, 224)           -- 未选中行名称
local colRowSep = Color(0, 0, 0, 200)             -- 行间 1px 分隔线
local colSegLit = Color(240, 240, 240, 255)       -- 分段条亮段
local colSegDark = Color(62, 62, 64, 220)         -- 分段条暗段
local colUpgradeRed = Color(206, 56, 46)          -- UPGRADE 大字红
local colUpgradeRedHover = Color(240, 92, 78)     -- UPGRADE 悬停红
local colUpgradeDisabled = Color(120, 56, 52)     -- UPGRADE 禁用红
local colBtnBG = Color(16, 16, 17, 225)           -- 通用按钮底
local colBtnBGHover = Color(46, 46, 48, 235)      -- 通用按钮悬停底
local colBtnDisabled = Color(24, 24, 26, 180)     -- 通用按钮禁用底
local colBtnBorder = Color(152, 152, 152, 220)    -- 按钮灰白 1px 边
local colBtnSelected = Color(190, 190, 192, 235)  -- 变体选中亮灰底
local colActionBG = Color(10, 10, 11, 235)        -- 动作切段底
local colActionBGHover = Color(50, 50, 52, 235)   -- 动作切段悬停底
local colCheckOn = Color(74, 168, 82, 240)        -- 复选框开启（绿）
local colCheckOff = Color(122, 36, 30, 235)       -- 复选框关闭（暗红）
local colDimSwitch = Color(0, 0, 0, 140)          -- 开关行毛玻璃上的暗化层
local colDimPane = Color(0, 0, 0, 120)            -- 页签内容区暗化层
local colDimUpgrade = Color(0, 0, 0, 130)         -- 升级按钮暗化层
local colNearbyBG = Color(8, 8, 10, 246)          -- 附近玩家弹出层底色

-- 背景毛玻璃（SUNRUST 式）：屏幕拷贝到全屏 RT 后做高斯模糊，面板按 UV 采样；
-- 面板可见期间每帧在 PostRender 更新（背景实时跟随游戏画面）
-- （pp/blurscreen 的固定 tap 会把背后文字拉出重影，弃用）
local blurRT = GetRenderTarget("pinv_blur_rt", ScrW(), ScrH())
local matBlurRT = CreateMaterial("pinv_blur_mat", "UnlitGeneric", {
    ["$basetexture"] = blurRT:GetName(),
    ["$ignorez"] = 1,
})

-- [DEBUG-PINV-PERF] 临时探针（定位完成后：删除本段与全文件 [DEBUG-PINV-PERF] 标记）
local PerfCvar = CreateClientConVar("pinv_perf", "1", true, false, "pinventory performance probes")
local PerfState = nil
local dbgChat = function(...) if PerfState and PerfState.enabled then chat.AddText(...) end end
local dbgColR = Color(255, 120, 120)   -- 警告红
local dbgColY = Color(255, 220, 120)   -- 计时黄
local dbgColG = Color(120, 255, 120)   -- 生命周期绿
local dbgColC = Color(120, 220, 255)   -- 汇总青
local dbgColV = Color(170, 170, 255)   -- 刷新紫

-- 面板专属字体（首次 Init 时按 BetterScreenScale 一次性创建，字号对齐靶子图层级）
local PinvFontsReady = false
local function EnsurePinvFonts()
    if PinvFontsReady then return end
    PinvFontsReady = true
    local scale = BetterScreenScale()
    -- 注意族名是 "HarmonyOS Sans SC"（无空格）；多一个空格的写法会静默回退 Tahoma，
    -- Tahoma 无 CJK 字形，绘制时逐字形回退查找是显著帧开销（探针实测证据）
    surface.CreateFont("PINV_FontTitle", {font = "HarmonyOS Sans SC", size = math.ceil(30 * scale), weight = 650, extended = true, antialias = true})
    surface.CreateFont("PINV_FontItem", {font = "HarmonyOS Sans SC", size = math.ceil(20 * scale), weight = 600, extended = true, antialias = true})
    surface.CreateFont("PINV_FontRow", {font = "HarmonyOS Sans SC", size = math.ceil(17 * scale), weight = 550, extended = true, antialias = true})
    surface.CreateFont("PINV_FontSmall", {font = "HarmonyOS Sans SC", size = math.ceil(14 * scale), weight = 500, extended = true, antialias = true})
end

-- 自动购买废料开关（契约③：客户端归档 + userinfo）
local cvBuyScrap = CreateClientConVar("zs_buyscrap", "0", true, true, "auto buy scrap with leftover points")

-- 分类常量（本地定义，避免依赖 INVCAT_* 全局的加载顺序）
local CATEGORY_WEAPONS = 0
local CATEGORY_TRINKETS = 1
local CATEGORY_COMPONENTS = 2
local CATEGORY_CONSUMABLES = 3

-- 分类顺序与折叠头翻译键
local CATEGORY_ORDER = { CATEGORY_WEAPONS, CATEGORY_TRINKETS, CATEGORY_COMPONENTS, CATEGORY_CONSUMABLES }
local CATEGORY_LABELS = {
    [CATEGORY_WEAPONS] = "pinv_cat_weapons",
    [CATEGORY_TRINKETS] = "pinv_cat_trinkets",
    [CATEGORY_COMPONENTS] = "pinv_cat_components",
    [CATEGORY_CONSUMABLES] = "pinv_cat_consumables",
}

-- 物品名前 4 字符前缀 → 分类（照 sh_inventory.lua 的 GM.ZSInventoryPrefix）
local ITEM_PREFIX_CATEGORIES = {
    trin = CATEGORY_TRINKETS,
    comp = CATEGORY_COMPONENTS,
    cons = CATEGORY_CONSUMABLES,
}

-- 行高亮用的向右渐变纹理（左实右虚），升级武器行品质色淡染用
local texGradH = surface.GetTextureID("gui/gradient")

-- ============================================================================
-- [区域] 条目工具
-- [位置] GetItemCategory / EntryKey / GetQualityColor / ResolveKillicon / CollectWeaponEntries / CollectItemEntries
-- [作用] 条目键名、分类前缀判定、品质染色、killicon 兜底与左右栏数据收集
-- [常改] 前缀映射、排序字段、killicon 兜底链
-- ============================================================================

-- 物品分类：按名称前 4 字符前缀
local function GetItemCategory(itemname)
    return ITEM_PREFIX_CATEGORIES[string.sub(itemname, 1, 4)]
end

-- 条目唯一键（用于选中高亮比较）
local function EntryKey(entry)
    if not entry then return "" end
    if entry.type == "weapon" then return "w:" .. entry.class end
    return "i:" .. entry.name
end

-- 品质文本色：WeaponQualityColors[tier][分支 and 2 or 1]，无品质回退亮白
local function GetQualityColor(sweptable)
    if not sweptable then return colTextBright end
    local tier = sweptable.QualityTier
    local colors = GAMEMODE.WeaponQualityColors
    if not tier or not colors or not colors[tier] then return colTextBright end
    return colors[tier][sweptable.Branch and 2 or 1] or colTextBright
end

-- 解析 killicon：{材质,颜色} 或 {字体,字符,颜色} 两种结构都支持
-- 物品兜底 craftables 图标，最后兜底 default
local function ResolveKillicon(classname, isitem)
    local kitbl = killicon.Get(classname)
    if not kitbl and isitem then
        kitbl = killicon.Get("weapon_zs_craftables")
    end
    return kitbl or killicon.Get("default")
end

-- weapons.Get 深拷贝缓存：weapons.Get 每次调用都整表深拷贝 SWEP（含 Base 继承链），
-- 打开面板/点分类时按行调用是卡顿尖峰。本文件所有消费方（PrintName/QualityTier/Branch/
-- Tier/IsMelee 等）均为只读，进程内缓存同一类名共享同一张表即可。
-- 注意：仅供本文件 UI 只读使用；需要可写副本的代码仍须自行 weapons.Get。
local SweptCache = {}
local function GetCachedSwept(classname)
    local tbl = SweptCache[classname]
    if tbl == nil then
        tbl = weapons.Get(classname) or false
        SweptCache[classname] = tbl
    end
    return tbl or nil
end

-- 画废料图标（升级/拆解行的数量用图标替代字体⚙；取弹药图标表 scrap 项，缺材质兜底齿轮字）
local function DrawScrapIcon(x, y, size)
    local kitbl = killicon.Get(GAMEMODE.AmmoIcons and GAMEMODE.AmmoIcons["scrap"] or "ammo_scrap")
    if kitbl and kitbl[1] then
        local mat = Material(kitbl[1])
        if mat and not mat:IsError() then
            if kitbl[2] then
                surface.SetDrawColor(kitbl[2].r, kitbl[2].g, kitbl[2].b, kitbl[2].a or 255)
            else
                surface.SetDrawColor(255, 255, 255, 255)
            end
            surface.SetMaterial(mat)
            surface.DrawTexturedRect(x, y, size, size)
            return
        end
    end

    draw.SimpleText("⚙", FONT_BODY, x + size * 0.5, y + size * 0.5, colTextBright, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- 收集手持武器条目：MySelf:GetWeapons() 按 GetClass 去重，按显示名排序
local function CollectWeaponEntries()
    local entries = {}
    if not IsValid(MySelf) then return entries end

    local seen = {}
    for _, wep in pairs(MySelf:GetWeapons()) do
        local class = wep:GetClass()
        if class ~= "" and not seen[class] then
            seen[class] = true
            local sweptable = GetCachedSwept(class)
            entries[#entries + 1] = {
                type = "weapon",
                class = class,
                pname = sweptable and sweptable.PrintName or class,
                index = 0,
            }
        end
    end

    table.sort(entries, function(a, b) return string.lower(a.pname) < string.lower(b.pname) end)
    return entries
end

-- 收集某类库存物品条目：GM.ZSInventory（键=物品名，值=数量）+ GM.ZSInventoryItemData
local function CollectItemEntries(cat)
    local entries = {}
    local inventory = GAMEMODE.ZSInventory
    local itemdata = GAMEMODE.ZSInventoryItemData
    if not inventory then return entries end

    for name, count in pairs(inventory) do
        if (count or 0) > 0 and type(name) == "string" and GetItemCategory(name) == cat then
            local datatbl = itemdata and itemdata[name] or nil
            entries[#entries + 1] = {
                type = "item",
                name = name,
                pname = datatbl and datatbl.PrintName or name,
                index = datatbl and datatbl.Index or 0,
            }
        end
    end

    return entries
end

-- ============================================================================
-- [区域] 通用子控件
-- [位置] MakeCheckBox / MakeTextButton / MakeSegmentButton / MakeTabButton
-- [作用] 自绘复选框（暗红/绿实心）、文字按钮（含禁用/选中态）、动作切段按钮与文字页签
-- [常改] 复选框尺寸、按钮配色、悬停效果
-- ============================================================================

-- 自绘复选框（DButton 底座，实心方块：暗红=关 / 绿=开，文本走 translate.Get）
local function MakeCheckBox(parent, labelkey, checked)
    local scale = BetterScreenScale()
    local box = vgui.Create("DButton", parent)
    box:SetText("")
    box.LabelKey = labelkey
    box.Checked = checked and true or false

    surface.SetFont(FONT_SMALL)
    local textw = surface.GetTextSize(translate.Get(labelkey))
    box:SetSize(textw + 34 * scale, 24 * scale)

    function box:SetChecked(value)
        value = value and true or false
        if self.Checked == value then return end
        self.Checked = value
        if self.OnChange then self.OnChange(self, value) end
    end

    function box:Paint(w, h)
        local scale = BetterScreenScale()
        local boxsize = 16 * scale
        local by = (h - boxsize) * 0.5
        draw.RoundedBox(0, 0, by, boxsize, boxsize, self.Checked and colCheckOn or colCheckOff)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, self:IsHovered() and 255 or 160)
        surface.DrawOutlinedRect(0, by, boxsize, boxsize)
        local col = self:IsHovered() and colTextBright or colTextDim
        draw.SimpleText(translate.Get(self.LabelKey), FONT_SMALL, boxsize + 8 * scale, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    function box:DoClick()
        self:SetChecked(not self.Checked)
    end

    return box
end

-- 自绘文字按钮（DButton 底座：直角 + 1px 灰白边；禁用不触发 DoClick，悬停提亮）
-- opts.Selected = true 时亮灰底深字（用于当前变体高亮）
local function MakeTextButton(parent, label, wide, tall, opts)
    opts = opts or {}
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.Label = label
    btn.Font = opts.font or FONT_ROW
    btn.ColBG = opts.bg or colBtnBG
    btn.ColBGHover = opts.hover or colBtnBGHover
    btn.ColText = opts.text or colTextBright
    btn.Selected = false
    if wide then btn:SetWide(wide) end
    if tall then btn:SetTall(tall) end

    function btn:SetLabel(text)
        self.Label = text
    end

    function btn:Paint(w, h)
        local enabled = self:IsEnabled()
        local bg = colBtnDisabled
        local border = colBtnBorder
        local textcol = colTextDisabled
        if enabled then
            if self.Selected then
                bg = colBtnSelected
                border = color_white
                textcol = colTextDark
            else
                bg = self:IsHovered() and self.ColBGHover or self.ColBG
                textcol = self.ColText
            end
        end
        draw.RoundedBox(0, 0, 0, w, h, bg)
        surface.SetDrawColor(border.r, border.g, border.b, enabled and border.a or 90)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(self.Label or "", self.Font, w * 0.5, h * 0.5, textcol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end

-- 动作切段按钮（与相邻切段共享 1px 边线，构成整行切分样式）
local function MakeSegmentButton(parent, label)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.Label = label

    function btn:Paint(w, h)
        local enabled = self:IsEnabled()
        draw.RoundedBox(0, 0, 0, w, h, enabled and self:IsHovered() and colActionBGHover or colActionBG)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, enabled and colBtnBorder.a or 90)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(self.Label or "", FONT_ROW, w * 0.5, h * 0.5, enabled and colTextBright or colTextDisabled, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end

-- 文字页签按钮（STATS / DESCRIPTION：无底框，激活白字 / 未激活灰字）
local function MakeTabButton(parent, labelkey, onclick)
    local btn = vgui.Create("DButton", parent)
    btn:SetText("")
    btn.LabelKey = labelkey
    btn.ActiveState = nil

    function btn:Paint(w, h)
        local active = self.ActiveState and self.ActiveState() or false
        -- 盒式页签：激活亮底深字，未激活深底灰字（两个按钮盒清晰可辨）
        draw.RoundedBox(0, 0, 0, w, h, active and colBtnSelected or colBtnBG)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, active and 255 or 110)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(translate.Get(self.LabelKey), FONT_SMALL, w * 0.5, h * 0.5, active and colTextDark or colTextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    function btn:DoClick()
        if self.DoClickEx then self.DoClickEx() end
    end

    btn.DoClickEx = onclick
    return btn
end

-- ============================================================================
-- [区域] 根面板
-- [位置] PANEL:Init / PANEL:PerformLayout / PANEL:Think
-- [作用] 尺寸与主题初始化、子区构建次序、居中、ALT 松开防抖关闭与周期刷新
-- [常改] 面板尺寸比例、默认展开分类、轮询间隔
-- ============================================================================

function PANEL:Init()
    EnsurePinvFonts()
    self:SetMouseInputEnabled(true)

    -- 面板状态
    -- 默认仅展开武器栏（用户设定）
    self.CatExpanded = {
        [CATEGORY_WEAPONS] = true,
        [CATEGORY_TRINKETS] = false,
        [CATEGORY_COMPONENTS] = false,
        [CATEGORY_CONSUMABLES] = false,
    }
    self.SortTrinketsByName = false
    self.NearRemantler = false
    self.SelectedEntry = nil
    self.SelectedEntryKey = ""
    self.ShowStatsPage = false
    self.ItemNameStr = ""
    self.ItemTierStr = ""
    self.ItemNameColor = colTextBright
    self.ItemTierColor = colTextBright
    self.LastSig = nil
    self.LastActiveClass = nil
    self.NextListCheck = 0
    self.NextRemantlerPoll = 0
    self.LoseKeyDeadline = nil

    self:SetSize(ScrW() * PANEL_WIDTH_RATIO, ScrH() * PANEL_HEIGHT_RATIO)

    -- 构建次序 = Dock 次序：开关行最底 → 弹药栏 → 标题行 + 内容双栏
    self:BuildSwitchRow()
    self:BuildAmmoBar()
    self:BuildColumns()
    self:BuildItemInfo()
end

function PANEL:PerformLayout()
    self:Center()
    if self.LeftColumn and self.LeftColumn:IsValid() then
        self.LeftColumn:SetWide(self:GetWide() * LEFT_COLUMN_RATIO)
    end
end

-- 毛玻璃说明：RT 在 PostRender 钩子中模糊好；各栏 Paint 各自采样自己区域的模糊，
-- 栏间间隙露出未模糊的游戏画面（对齐 SUNRUST）。
-- 注意：VGUI Paint 内严禁 CopyRenderTarget / SetRenderTarget 等 3D 操作——会打断当前帧
-- 的 2D 渲染流，表现为面板可见但完全不渲染任何内容

-- ============================================================================
-- [区域] 开关行
-- [位置] PANEL:BuildSwitchRow / PANEL:UpdateSwitchRow
-- [作用] 饰品排序 / zs_nopickupprops / zs_buyscrap 三个复选框（三等分行宽）
-- [常改] 复选框顺序与间距、绑定 ConVar、按钮宽度
-- ============================================================================

function PANEL:BuildSwitchRow()
    local scale = BetterScreenScale()
    local row = vgui.Create("Panel", self)
    row:SetTall(24 * scale)
    row:Dock(BOTTOM)
    row:DockMargin(0, 0, 0, 4 * scale)
    -- 黑色透明背景 + 毛玻璃采样（与其他栏体一致）
    row.Paint = function(me, w, h)
        local x, y = me:LocalToScreen(0, 0)
        surface.SetMaterial(matBlurRT)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRectUV(0, 0, w, h, x / ScrW(), y / ScrH(), (x + w) / ScrW(), (y + h) / ScrH())
        draw.RoundedBox(0, 0, 0, w, h, colDimSwitch)
    end
    self.SwitchRow = row

    -- 三个开关均分整行宽度（每项占 1/3，内容左对齐）
    local thirdw = self:GetWide() / 3

    -- ① 小饰品排序（面板状态：勾选按名称，否则按注册 Index）
    --    说明：物品获取时间未跟踪，注册 Index 只是获取顺序的近似
    local cbSort = MakeCheckBox(row, "pinv_sort_trinkets", self.SortTrinketsByName)
    cbSort:SetWide(thirdw)
    cbSort:Dock(LEFT)
    cbSort.OnChange = function(_, checked)
        self.SortTrinketsByName = checked
        self:BuildInventoryList()
    end
    self.CheckSortTrinkets = cbSort

    -- ② 禁止拾取道具（绑定 zs_nopickupprops，置 1/0）
    local cvNoPickup = GetConVar("zs_nopickupprops")
    local cbPickup = MakeCheckBox(row, "pinv_nopickupprops", cvNoPickup and cvNoPickup:GetBool() or false)
    cbPickup:SetWide(thirdw)
    cbPickup:Dock(LEFT)
    cbPickup.OnChange = function(_, checked)
        local cvar = GetConVar("zs_nopickupprops")
        if cvar then
            cvar:SetBool(checked)
        end
    end
    self.CheckNoPickupProps = cbPickup

    -- ③ 自动购买废料（zs_buyscrap，本文件创建）
    local cbBuy = MakeCheckBox(row, "pinv_buyscrap", cvBuyScrap:GetBool())
    cbBuy:SetWide(thirdw)
    cbBuy:Dock(LEFT)
    cbBuy.OnChange = function(_, checked)
        cvBuyScrap:SetBool(checked)
    end
    self.CheckBuyScrap = cbBuy
end

-- 重开面板时回读各开关状态（SetChecked 内部有等值守卫，不会触发多余 OnChange）
function PANEL:UpdateSwitchRow()
    local cvNoPickup = GetConVar("zs_nopickupprops")
    if self.CheckNoPickupProps then
        self.CheckNoPickupProps:SetChecked(cvNoPickup and cvNoPickup:GetBool() or false)
    end
    if self.CheckBuyScrap then
        self.CheckBuyScrap:SetChecked(cvBuyScrap:GetBool())
    end
    if self.CheckSortTrinkets then
        self.CheckSortTrinkets:SetChecked(self.SortTrinketsByName)
    end
end

-- ============================================================================
-- [区域] 弹药横栏挂载
-- [位置] PANEL:BuildAmmoBar()
-- [作用] 创建 dammobar.lua 交付的 ZSAmmoBar 并 Dock Bottom 挂载到开关行之上
-- [常改] Dock 边距
-- ============================================================================

function PANEL:BuildAmmoBar()
    local scale = BetterScreenScale()
    local bar = vgui.Create("ZSAmmoBar", self)
    bar:Dock(BOTTOM)
    bar:DockMargin(0, 6 * scale, 0, 6 * scale)
    self.AmmoBar = bar
end

-- ============================================================================
-- [区域] 双栏骨架与顶部标题行
-- [位置] PANEL:BuildColumns
-- [作用] 标题行（INVENTORY / ITEM INFO / 重组机入口）+ 左右栏容器，Dock 挤压布局
-- [常改] 左栏宽度比、栏间距、栏背景色、标题字号
-- ============================================================================

function PANEL:BuildColumns()
    local scale = BetterScreenScale()
    local content = vgui.Create("Panel", self)
    content:Dock(FILL)
    self.ContentRow = content

    -- 顶部标题行：左 INVENTORY、右栏上方 ITEM INFO（Paint 自绘），最右重组机入口
    -- 重组机入口点击藏起背包面板并打开改造菜单，改造窗口右上角「返回」经回调重开背包
    local header = vgui.Create("Panel", self)
    header:SetTall(HEADER_TALL * scale)
    header:Dock(TOP)
    header:DockMargin(0, 0, 0, 11 * scale)
    header.Paint = function(me, w, h)
        draw.SimpleText(translate.Get("pinv_title"), FONT_TITLE, 0, h, colTextBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        draw.SimpleText(translate.Get("pinv_iteminfo"), FONT_TITLE, w * LEFT_COLUMN_RATIO + COLUMN_GAP * scale, h, colTextBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end
    self.HeaderRow = header

    local btnRemantler = MakeTextButton(header, translate.Get("pinv_remantler"), 100 * scale, nil)
    btnRemantler:Dock(RIGHT)
    btnRemantler:DockMargin(0, 3 * scale, 0, 3 * scale)
    btnRemantler.DoClick = function()
        -- 灰置态兜底：拆解台范围外不响应
        if not (IsValid(MySelf) and MySelf:NearRemantler()) then return end
        self:SetVisible(false)
        GAMEMODE:OpenRemantlerMenu(MySelf:NearestRemantler(), function()
            GAMEMODE:OpenInventoryPanel()
        end)
    end
    self.ButtonRemantler = btnRemantler

    -- 栏体绘制：各自区域采样毛玻璃 RT（间隙露出未模糊的游戏画面，对齐 SUNRUST）
    local function PaintColumn(me, w, h)
        local x, y = me:LocalToScreen(0, 0)
        surface.SetMaterial(matBlurRT)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRectUV(0, 0, w, h, x / ScrW(), y / ScrH(), (x + w) / ScrW(), (y + h) / ScrH())
        draw.RoundedBox(0, 0, 0, w, h, colColumnBG)
    end

    local left = vgui.Create("Panel", content)
    left:SetWide(self:GetWide() * LEFT_COLUMN_RATIO)
    left:Dock(LEFT)
    left.Paint = PaintColumn
    self.LeftColumn = left

    local scroll = vgui.Create("DScrollPanel", left)
    scroll:Dock(FILL)
    self.ScrollPanel = scroll

    local right = vgui.Create("Panel", content)
    right:Dock(FILL)
    right:DockMargin(COLUMN_GAP * scale, 0, 0, 0)
    right.Paint = PaintColumn
    self.RightColumn = right
end

-- ============================================================================
-- [区域] 右栏物品信息
-- [位置] PANEL:BuildItemInfo / PANEL:UpdateItemInfo / PANEL:SetStatsPage / PANEL:UpdateDescription
-- [作用] 变体行（顶部）、物品展示行、双页签、STATS 属性行（对接 GM:ViewerStatBarUpdate）、
--        描述与弹药行、底部拆解行与动作切段行
-- [常改] 各行高度、展示行名称起点、属性列宽比例、弹药行画法
-- ============================================================================

function PANEL:BuildItemInfo()
    local scale = BetterScreenScale()
    local right = self.RightColumn

    -- 顶部：变体行（VARIANTS 小标签 + 分支按钮，靶子图中位于右栏最上方）
    local variantouter = vgui.Create("Panel", right)
    variantouter:SetTall(48 * scale)
    variantouter:Dock(TOP)
    variantouter:DockMargin(11 * scale, 10 * scale, 11 * scale, 0)
    variantouter.Paint = function(me, w, h)
        draw.SimpleText(translate.Get("pinv_variants"), FONT_SMALL, 0, 0, colTextBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
    self.VariantRow = variantouter

    local variantinner = vgui.Create("Panel", variantouter)
    variantinner:Dock(FILL)
    variantinner:DockMargin(0, 16 * scale, 0, 0)
    self.VariantRowInner = variantinner

    -- 物品展示行：killicon 图标 + 名称（白）+ 品质色 "+N"（品质信息保留在档位后缀）
    local showcase = vgui.Create("Panel", right)
    showcase:SetTall(98 * scale)
    showcase:Dock(TOP)
    showcase:DockMargin(11 * scale, 6 * scale, 11 * scale, 0)
    showcase.Paint = function(me, w, h)
        if self.ItemNameStr == "" then return end
        local scale = BetterScreenScale()
        local namey = h * 0.5
        draw.SimpleText(self.ItemNameStr, FONT_ITEM, 118 * scale, namey, self.ItemNameColor or colTextBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if self.ItemTierStr ~= "" then
            surface.SetFont(FONT_ITEM)
            local nw = surface.GetTextSize(self.ItemNameStr)
            draw.SimpleText(self.ItemTierStr, FONT_ITEM, 118 * scale + nw + 10 * scale, namey, self.ItemTierColor or colTextBright, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    self.ItemShowcase = showcase

    -- 图标框：killicon 挂载点（无底框，图内图标直接浮在栏底上）
    local iconframe = vgui.Create("Panel", showcase)
    iconframe:SetMouseInputEnabled(false)
    iconframe.Paint = function() end
    iconframe:SetPos(10 * scale, 8 * scale)
    iconframe:SetSize(96 * scale, 82 * scale)
    self.IconFrame = iconframe

    -- 页签行：STATS / DESCRIPTION 两个盒式按钮（并排，激活亮底）
    local tabrow = vgui.Create("Panel", right)
    tabrow:SetTall(26 * scale)
    tabrow:Dock(TOP)
    tabrow:DockMargin(11 * scale, 6 * scale, 11 * scale, 4 * scale)
    self.TabRow = tabrow

    self.TabStats = MakeTabButton(tabrow, "pinv_stats", function() self:SetStatsPage(true) end)
    self.TabStats:SetWide(140 * scale)
    self.TabStats:Dock(LEFT)

    self.TabDesc = MakeTabButton(tabrow, "pinv_description", function() self:SetStatsPage(false) end)
    self.TabDesc:SetWide(140 * scale)
    self.TabDesc:Dock(LEFT)
    self.TabDesc:DockMargin(6 * scale, 0, 0, 0)

    self.TabStats.ActiveState = function() return self.ShowStatsPage end
    self.TabDesc.ActiveState = function() return not self.ShowStatsPage end

    -- 底部锚定（Dock 次序自下而上）：拆解行 → 动作切段行 → 升级大字按钮 → 分段条
    local dbtn = vgui.Create("DButton", right)
    dbtn:SetText("")
    dbtn:SetTall(32 * scale)
    dbtn:Dock(BOTTOM)
    dbtn:DockMargin(11 * scale, 0, 11 * scale, 0)
    dbtn.RefundText = ""
    dbtn.Paint = function(me, w, h)
        local scale = BetterScreenScale()
        local enabled = me:IsEnabled()
        draw.RoundedBox(0, 0, 0, w, h, enabled and me:IsHovered() and colActionBGHover or colActionBG)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, enabled and colBtnBorder.a or 90)
        surface.DrawOutlinedRect(0, 0, w, h)
        local textcol = enabled and colTextBright or colTextDisabled
        draw.SimpleText(translate.Get("pinv_dismantle"), FONT_ITEM, 12 * scale, h * 0.5, textcol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if me.RefundText ~= "" then
            local iconsize = 18 * scale
            DrawScrapIcon(w - 12 * scale - iconsize, (h - iconsize) * 0.5, iconsize)
            draw.SimpleText(me.RefundText, FONT_ITEM, w - 12 * scale - iconsize - 4 * scale, h * 0.5, textcol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    dbtn.DoClick = function()
        if not dbtn:IsEnabled() then return end
        -- 武器条目无参（服务端回退手持），物品条目带物品键
        if self.DismantleItemKey then
            RunConsoleCommand("zs_dismantle", self.DismantleItemKey)
        else
            RunConsoleCommand("zs_dismantle")
        end
        surface.PlaySound("ui/buttonclick.wav")
    end
    self.DismantleButton = dbtn

    local actionrow = vgui.Create("Panel", right)
    actionrow:SetTall(32 * scale)
    actionrow:Dock(BOTTOM)
    actionrow:DockMargin(11 * scale, 0, 11 * scale, 10 * scale)
    self.ActionRow = actionrow

    self:BuildUpgradeBlock()

    -- STATS 页：10 行 属性名/条/数值（ViewerStatBarUpdate 需要的三组控件）
    -- 显隐规则：仅近战或带主弹药枪械填充属性行，其余条目该页留白
    local statviewer = vgui.Create("Panel", right)
    statviewer:Dock(FILL)
    statviewer:SetMouseInputEnabled(false)
    -- 黑色透明底 + 左侧 3px 白色竖线（与页签行样式一致）
    statviewer.Paint = function(me, w, h)
        local scale = BetterScreenScale()
        draw.RoundedBox(0, 0, 0, w, h, colDimPane)
        surface.SetDrawColor(colTextBright.r, colTextBright.g, colTextBright.b, 255)
        surface.DrawRect(0, 2 * scale, 3 * scale, h - 4 * scale)
    end
    self.StatViewer = statviewer

    statviewer.ItemStats = {}
    statviewer.ItemStatBars = {}
    statviewer.ItemStatValues = {}
    for i = 1, 10 do
        local statlabel = EasyLabel(statviewer, "", FONT_BODY, colTextDim)
        statlabel:SetContentAlignment(4)
        local bar = vgui.Create("ZSItemStatBar", statviewer)
        bar:SetVisible(false)
        local valuelabel = EasyLabel(statviewer, "", FONT_BODY, colTextBright)
        valuelabel:SetContentAlignment(6)
        statviewer.ItemStats[i] = statlabel
        statviewer.ItemStatBars[i] = bar
        statviewer.ItemStatValues[i] = valuelabel
    end

    statviewer.PerformLayout = function(me, w, h)
        local scale = BetterScreenScale()
        local rowh = math.min(26 * scale, h / 10)
        for i = 1, 10 do
            local y = (i - 1) * rowh + 4 * scale
            me.ItemStats[i]:SetPos(10 * scale, y)
            me.ItemStats[i]:SetSize(w * 0.24, rowh)
            me.ItemStatBars[i]:SetPos(w * 0.27, y + rowh * 0.3)
            me.ItemStatBars[i]:SetSize(w * 0.42, math.max(3, rowh * 0.4))
            me.ItemStatValues[i]:SetPos(w * 0.72, y)
            me.ItemStatValues[i]:SetSize(w * 0.26, rowh)
        end
    end

    -- DESCRIPTION 页：描述 + 弹药行（killicon 图标已上移至物品展示行）
    local descviewer = vgui.Create("Panel", right)
    descviewer:Dock(FILL)
    -- 黑色透明底 + 左侧 3px 白色竖线（与页签行样式一致）
    descviewer.Paint = function(me, w, h)
        local scale = BetterScreenScale()
        draw.RoundedBox(0, 0, 0, w, h, colDimPane)
        surface.SetDrawColor(colTextBright.r, colTextBright.g, colTextBright.b, 255)
        surface.DrawRect(0, 2 * scale, 3 * scale, h - 4 * scale)
    end
    self.DescViewer = descviewer

    local desclabel = EasyLabel(descviewer, "", FONT_SMALL, colTextDim)
    desclabel:SetContentAlignment(7)
    desclabel:SetWrap(true)
    self.DescLabel = desclabel

    -- 弹药行：仅文字（SUNRUST 描述页无弹药图标）
    local ammotype = EasyLabel(descviewer, "", FONT_BODY, colTextDim)
    ammotype:SetContentAlignment(4)
    self.AmmoTypeLabel = ammotype

    descviewer.PerformLayout = function(me, w, h)
        local scale = BetterScreenScale()
        -- 子控件存在 self（根面板）上，不能走 me.X（me=descviewer 上没有这些字段）
        self.DescLabel:SetPos(2 * scale, 2 * scale)
        self.DescLabel:SetSize(w - 4 * scale, h - 34 * scale)
        self.AmmoTypeLabel:SetPos(2 * scale, h - 26 * scale)
        self.AmmoTypeLabel:SetSize(w * 0.5, 22 * scale)
    end

    -- 默认页签：DESCRIPTION
    self:SetStatsPage(false)
end

-- 双页签切换：STATS 页与 DESCRIPTION 页互斥显示（Dock 布局自动回收空间）
function PANEL:SetStatsPage(stats)
    self.ShowStatsPage = stats and true or false
    if self.StatViewer then self.StatViewer:SetVisible(self.ShowStatsPage) end
    if self.DescViewer then self.DescViewer:SetVisible(not self.ShowStatsPage) end
end

-- 更新 DESCRIPTION 页：图标（挂到物品展示行）/ 描述 / 弹药行
function PANEL:UpdateDescription(iconclass, sweptable, isitem)
    -- 变更检测：同类名跳过图标重挂（字体型 killicon 每次重建会闪烁）
    if self.LastIconClass ~= iconclass then
        if self.ItemShowcase.m_Icon and self.ItemShowcase.m_Icon:IsValid() then
            self.ItemShowcase.m_Icon:Remove()
            self.ItemShowcase.m_Icon = nil
        end

        local kitbl = ResolveKillicon(iconclass, isitem)
        if kitbl then
            GAMEMODE:AttachKillicon(kitbl, self.ItemShowcase, self.IconFrame, false, false)
        end
        self.LastIconClass = iconclass
    end

    self.DescLabel:SetText(sweptable.Description or "")

    -- 弹药行：仅文字（HasPurchaseableAmmo + AmmoNames），不显示图标
    local hasammo = GAMEMODE:HasPurchaseableAmmo(sweptable)
    local lower = hasammo and string.lower(sweptable.Primary.Ammo) or nil
    local ammoinfo = lower and GAMEMODE.AmmoNames and GAMEMODE.AmmoNames[lower] or nil
    self.AmmoTypeLabel:SetText(ammoinfo or "")
end

-- 右栏主刷新：entry = {type="weapon", class=...} 或 {type="item", name=...} 或 nil
function PANEL:UpdateItemInfo(entry)
    self.SelectedEntry = entry
    self.SelectedEntryKey = EntryKey(entry)

    if not entry then
        self.ItemNameStr = ""
        self.ItemTierStr = ""
        self.DescLabel:SetText("")
        self.AmmoTypeLabel:SetText("")
        self.LastIconClass = nil
        if self.ItemShowcase.m_Icon and self.ItemShowcase.m_Icon:IsValid() then
            self.ItemShowcase.m_Icon:Remove()
            self.ItemShowcase.m_Icon = nil
        end
        GAMEMODE:ViewerStatBarUpdate(self.StatViewer, true, {})
        self:RebuildVariantRow(nil)
        self:UpdateUpgradeBlock(nil)
        self:RebuildActionRow(nil)
        return
    end

    if entry.type == "weapon" then
        local sweptable = GetCachedSwept(entry.class)
        if not sweptable then return end

        -- 标题：名称白字，品质档位以品质色 "+N" 跟随其后
        self.ItemNameStr = sweptable.PrintName or entry.class
        self.ItemNameColor = colTextBright
        local tier = sweptable.QualityTier
        self.ItemTierStr = tier and ("+" .. tostring(tier)) or ""
        self.ItemTierColor = GetQualityColor(sweptable)

        -- STATS 属性条：仅近战或带主弹药枪械显示（医疗包等非枪/近战该页留白）
        local hasstats = sweptable.IsMelee or (sweptable.Primary and sweptable.Primary.Ammo)
        GAMEMODE:ViewerStatBarUpdate(self.StatViewer, not hasstats, sweptable)
        self:UpdateDescription(entry.class, sweptable, false)
        self:SetStatsPage(true)
    else
        local datatbl = GAMEMODE.ZSInventoryItemData and GAMEMODE.ZSInventoryItemData[entry.name] or nil
        if not datatbl then return end

        self.ItemNameStr = datatbl.PrintName or entry.name
        self.ItemNameColor = colTextBright
        self.ItemTierStr = ""

        -- 物品隐藏属性行（display=true 仅清空并隐藏）
        GAMEMODE:ViewerStatBarUpdate(self.StatViewer, true, datatbl)
        self:UpdateDescription(entry.name, datatbl, true)
        self:SetStatsPage(false)
    end

    self:RebuildVariantRow(entry)
    self:UpdateUpgradeBlock(entry)
    self:RebuildActionRow(entry)
end

-- ============================================================================
-- [区域] 变体行
-- [位置] PANEL:RebuildVariantRow / PANEL:UpdateRemantlerButtons
-- [作用] 右栏顶部 [标准] + 各分支按钮（当前分支高亮）；nil 档走 zs_upgrade，一档走
--        zs_quickremantle，二档以上灰置；兼管升级按钮与标题行重组机入口可用态
-- [常改] 分支显示名取法、按钮宽度策略、指令参数
-- ============================================================================

function PANEL:RebuildVariantRow(entry)
    for _, child in pairs(self.VariantRowInner:GetChildren()) do
        child:Remove()
    end
    self.VariantButtons = {}

    if not (entry and entry.type == "weapon") then
        self.VariantRow:SetVisible(false)
        return
    end

    local sweptable = GetCachedSwept(entry.class)
    if not sweptable then
        self.VariantRow:SetVisible(false)
        return
    end

    self.VariantRow:SetVisible(true)

    -- 分支来源：基础武器表的 Branches（weapons.GetStored）
    local basetbl = weapons.GetStored(sweptable.BaseQuality or entry.class)
    local branches = basetbl and basetbl.Branches or nil
    local tier = sweptable.QualityTier
    local curbranch = sweptable.Branch or 0
    local scale = BetterScreenScale()

    -- 按钮定义：[标准] + 各分支（显示名优先 NewNames[1]，回退分支表 PrintName）
    local defs = {}
    defs[#defs + 1] = { label = translate.Get("pinv_variant_standard"), branch = 0 }
    if branches then
        local nos = {}
        for no in pairs(branches) do
            nos[#nos + 1] = no
        end
        table.sort(nos)
        for _, no in ipairs(nos) do
            local br = branches[no]
            local label = br and ((br.NewNames and br.NewNames[1]) or br.PrintName) or ("#" .. tostring(no))
            defs[#defs + 1] = { label = label, branch = no }
        end
    end

    local btnw = math.max(60 * scale, (self.VariantRowInner:GetWide() - 6 * scale * #defs) / #defs)
    for _, def in ipairs(defs) do
        local btn = MakeTextButton(self.VariantRowInner, def.label, btnw, self.VariantRowInner:GetTall())
        btn:Dock(LEFT)
        btn:DockMargin(0, 0, 6 * scale, 0)
        btn.BranchNo = def.branch
        local hasbranches = branches and next(branches) ~= nil
        if def.branch == 0 then
            -- 标准：无分支武器仅是当前形态（灰置不可点）；二档以上灰置；一档可回退退款
            btn.LockedAlways = (tier or 0) >= 2 or ((tier or 0) == 0 and not hasbranches)
        else
            btn.LockedAlways = (tier or 0) >= 2
        end
        -- 当前分支高亮（视觉标记，不影响点击规则）
        btn.Selected = def.branch == curbranch

        function btn:DoClick()
            if (tier or 0) >= 2 then return end
            if tier == 1 then
                -- 一档品质：快速重组（回退传 standard，换轨传分支号）
                RunConsoleCommand("zs_quickremantle", def.branch == 0 and "standard" or tostring(def.branch))
            else
                -- 基础武器：升一档（标准传 0，分支传分支号）
                RunConsoleCommand("zs_upgrade", def.branch == 0 and "0" or tostring(def.branch))
            end
            surface.PlaySound("ui/buttonclick.wav")
        end

        self.VariantButtons[#self.VariantButtons + 1] = btn
    end

    self:UpdateRemantlerButtons()
end

-- 依 NearRemantler 轮询结果统一刷新变体按钮与升级按钮的可用态
-- 拆解台范围外灰置 + tooltip pinv_need_remantler；二档以上变体恒灰置
function PANEL:UpdateRemantlerButtons()
    local near = self.NearRemantler

    for _, btn in pairs(self.VariantButtons or {}) do
        local locked = btn.LockedAlways or not near
        btn:SetEnabled(not locked)
        if locked and not btn.LockedAlways then
            btn:SetTooltip(translate.Get("pinv_need_remantler"))
        elseif btn.ToolTip then
            btn:SetTooltip(nil)
        end
    end

    local upbtn = self.UpgradeButton
    if upbtn and upbtn:IsValid() then
        local blocked = upbtn.Maxed or upbtn.NoUpgrade
        upbtn:SetEnabled(near and not blocked)
        if not near and not blocked then
            upbtn:SetTooltip(translate.Get("pinv_need_remantler"))
        elseif upbtn.ToolTip then
            upbtn:SetTooltip(nil)
        end
    end

    -- 标题行重组机入口：同一轮询状态，范围外灰置 + tooltip
    local rebtn = self.ButtonRemantler
    if rebtn and rebtn:IsValid() then
        rebtn:SetEnabled(near)
        if not near then
            rebtn:SetTooltip(translate.Get("pinv_need_remantler"))
        elseif rebtn.ToolTip then
            rebtn:SetTooltip(nil)
        end
    end
end

-- ============================================================================
-- [区域] 升级块（分段条 + 大字按钮）
-- [位置] PANEL:BuildUpgradeBlock / PANEL:UpdateUpgradeBlock
-- [作用] 4 段品质分段条（亮段数 = 档位 + 1）+ 红色 UPGRADE 大字按钮（右侧 N⚙）
-- [常改] 段数、亮暗色、大字配色、满品质文案
-- ============================================================================

function PANEL:BuildUpgradeBlock()
    local scale = BetterScreenScale()
    local right = self.RightColumn

    -- Dock 次序注意：BOTTOM 先建在最底，故先建升级大字按钮再建分段条，
    -- 最终视觉自下而上为 动作行 → UPGRADE → 分段条（对齐靶子图）

    -- 红色升级大字按钮：左 UPGRADE + 右 N⚙（满品质改 pinv_max_quality 并禁用）
    local upbtn = vgui.Create("DButton", right)
    upbtn:SetText("")
    upbtn:SetTall(44 * scale)
    upbtn:Dock(BOTTOM)
    upbtn:DockMargin(11 * scale, 0, 11 * scale, 6 * scale)
    upbtn.Maxed = false
    upbtn.CostText = ""
    upbtn.Paint = function(me, w, h)
        local scale = BetterScreenScale()
        -- 黑色透明底 + 左侧 3px 白色竖线（与页签/内容区样式一致）
        draw.RoundedBox(0, 0, 0, w, h, colDimUpgrade)
        surface.SetDrawColor(colTextBright.r, colTextBright.g, colTextBright.b, 255)
        surface.DrawRect(0, 2 * scale, 3 * scale, h - 4 * scale)
        if me.Maxed then
            draw.SimpleText(translate.Get("pinv_max_quality"), FONT_TITLE, 14 * scale, h * 0.5, colUpgradeDisabled, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end
        local enabled = me:IsEnabled()
        local col = enabled and (me:IsHovered() and colUpgradeRedHover or colUpgradeRed) or colUpgradeDisabled
        draw.SimpleText(translate.Get("pinv_upgrade"), FONT_TITLE, 14 * scale, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if me.CostText ~= "" then
            local iconsize = 18 * scale
            DrawScrapIcon(w - 8 * scale - iconsize, (h - iconsize) * 0.5, iconsize)
            draw.SimpleText(me.CostText, FONT_ITEM, w - 8 * scale - iconsize - 4 * scale, h * 0.5, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    function upbtn:DoClick()
        if self.Maxed or self.NoUpgrade then return end
        -- 无参升级：服务端回退到手持武器
        RunConsoleCommand("zs_upgrade")
        surface.PlaySound("ui/buttonclick.wav")
    end
    self.UpgradeButton = upbtn

    -- 4 段分段条：亮段数 = (QualityTier or 0) + 1，亮白暗深灰（靶子图中位于 UPGRADE 上方）
    local segrow = vgui.Create("Panel", right)
    segrow:SetTall(12 * scale)
    segrow:Dock(BOTTOM)
    segrow:DockMargin(11 * scale, 0, 11 * scale, 4 * scale)
    segrow:SetMouseInputEnabled(false)
    segrow.QualityTier = 0
    segrow.FullBar = false
    segrow.Paint = function(me, w, h)
        local scale = BetterScreenScale()
        local segh = 5 * scale
        local segy = (h - segh) * 0.5
        -- 无升级能力的武器：整条完整显示（不切分段）
        if me.FullBar then
            draw.RoundedBox(0, 0, segy, w, segh, colSegLit)
            return
        end
        local segs = 4
        local gap = 9 * scale
        local segw = (w - gap * (segs - 1)) / segs
        local lit = (me.QualityTier or 0) + 1
        for i = 0, segs - 1 do
            draw.RoundedBox(0, i * (segw + gap), segy, segw, segh, i < lit and colSegLit or colSegDark)
        end
    end
    self.SegRow = segrow
end

function PANEL:UpdateUpgradeBlock(entry)
    local sweptable = entry and entry.type == "weapon" and GetCachedSwept(entry.class) or nil
    if not sweptable then
        self.SegRow:SetVisible(false)
        self.UpgradeButton:SetVisible(false)
        return
    end

    self.SegRow:SetVisible(true)
    self.UpgradeButton:SetVisible(true)

    local tier = sweptable.QualityTier or 0
    self.SegRow.QualityTier = tier
    self.SegRow.FullBar = not sweptable.AllowQualityWeapons
    -- 无升级能力（AllowQualityWeapons 为假）时升级恒灰置
    self.UpgradeButton.NoUpgrade = not sweptable.AllowQualityWeapons

    if tier >= 3 then
        -- 满品质：禁用 + 换文案
        self.UpgradeButton.Maxed = true
        self.UpgradeButton.CostText = ""
    else
        self.UpgradeButton.Maxed = false
        local cost = GAMEMODE:GetUpgradeScrap(sweptable, tier + 1)
        self.UpgradeButton.CostText = tostring(cost)
    end

    self:UpdateRemantlerButtons()
end

-- ============================================================================
-- [区域] 动作切段行与拆解行
-- [位置] PANEL:RebuildActionRow
-- [作用] 丢弃|清空弹夹|给予 共享边框切段 + 右端装饰下拉段；拆解行更新物品键与返还数
-- [常改] 按钮顺序、指令名、参数规则、返还数取法
-- ============================================================================

function PANEL:RebuildActionRow(entry)
    for _, child in pairs(self.ActionRow:GetChildren()) do
        child:Remove()
    end

    if not entry then
        self.ActionRow:SetVisible(false)
        self.DismantleButton:SetVisible(false)
        self.DismantleItemKey = nil
        self.DismantleButton.RefundText = ""
        return
    end

    self.ActionRow:SetVisible(true)
    self.DismantleButton:SetVisible(true)

    local isweapon = entry.type == "weapon"
    local itemkey = entry.type == "item" and entry.name or nil
    local scale = BetterScreenScale()
    local roww = self.ActionRow:GetWide()
    local dropdownw = 34 * scale

    -- {翻译键, 控制台指令, 仅武器条目显示}
    local actions = {
        { "pinv_drop", "zsdropweapon", false },
        { "pinv_emptyclip", "zsemptyclip", true },
        { "pinv_give", "zsgiveweapon", false },
    }

    local segs = {}
    for _, act in ipairs(actions) do
        if isweapon or not act[3] then
            segs[#segs + 1] = act
        end
    end

    -- 切段等分剩余宽度（扣除右端下拉段），相邻边框重叠成整行切分样式
    local segw = (roww - dropdownw) / #segs
    for _, act in ipairs(segs) do
        local btn = MakeSegmentButton(self.ActionRow, translate.Get(act[1]))
        btn:SetWide(segw)
        btn:Dock(LEFT)

        btn.Host = self

        function btn:DoClick()
            -- 给予 + 武器条目 + 已选附近人类：目标索引放 arguments[2]（服务端锁定位，
            -- 非库存键时自动回退为给予手持武器）
            if act[1] == "pinv_give" and not itemkey and self.Host.SelectedGiveTarget then
                local targetindex = self.Host.SelectedGiveTarget
                local target = Entity(targetindex)
                if IsValid(target) and target:IsPlayer() and target:Alive() then
                    RunConsoleCommand("zsgiveweapon", "", tostring(targetindex))
                    surface.PlaySound("ui/buttonclick.wav")
                    return
                end
                self.Host.SelectedGiveTarget = nil
            end

            if itemkey then
                RunConsoleCommand(act[2], itemkey)
            else
                RunConsoleCommand(act[2])
            end
            surface.PlaySound("ui/buttonclick.wav")
        end
    end

    -- 右端选择附近人类按钮（SUNRUST 同款）：弹出附近人类列表，选中作为给予目标
    local deco = vgui.Create("DButton", self.ActionRow)
    deco:SetText("")
    deco:SetWide(dropdownw)
    deco:Dock(RIGHT)
    deco.Paint = function(me, w, h)
        draw.RoundedBox(0, 0, 0, w, h, me:IsHovered() and colActionBGHover or colActionBG)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, colBtnBorder.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        local s = 4 * BetterScreenScale()
        local cx = w * 0.5
        local cy = h * 0.5
        draw.NoTexture()
        surface.SetDrawColor(colTextDim.r, colTextDim.g, colTextDim.b, 255)
        surface.DrawPoly({
            { x = cx - s, y = cy - s * 0.5 },
            { x = cx + s, y = cy - s * 0.5 },
            { x = cx, y = cy + s * 0.6 },
        })
    end
    deco.DoClick = function()
        self:ToggleNearbyPlayersMenu(deco)
    end
    self.GiveTargetButton = deco

    -- 拆解行：更新物品键与返还数（武器全返 / 物品减半，走 GM:GetDismantleScrap）
    -- 灰置规则镜像服务端 zs_dismantle：武器需 AllowQualityWeapons 或 PermitDismantle；
    -- 物品需 PermitDismantle 且存在对应配方（Breakdowns）
    self.DismantleItemKey = itemkey
    local wtbl = nil
    if isweapon then
        wtbl = GetCachedSwept(entry.class)
    else
        wtbl = GAMEMODE.ZSInventoryItemData and GAMEMODE.ZSInventoryItemData[entry.name] or nil
    end

    local candismantle = false
    if isweapon then
        candismantle = wtbl and (wtbl.AllowQualityWeapons or wtbl.PermitDismantle) and true or false
    else
        candismantle = wtbl and wtbl.PermitDismantle and (GAMEMODE.Breakdowns and GAMEMODE.Breakdowns[entry.name]) and true or false
    end
    self.DismantleButton:SetEnabled(candismantle)

    local refund = ""
    if wtbl and GAMEMODE.GetDismantleScrap then
        refund = "+" .. tostring(GAMEMODE:GetDismantleScrap(wtbl, not isweapon))
    end
    self.DismantleButton.RefundText = refund
end

-- 收集附近人类（600 单位内，按距离升序）
function PANEL:CollectNearbyHumans()
    local list = {}
    if not IsValid(MySelf) then return list end

    local mypos = MySelf:GetPos()
    for _, pl in ipairs(player.GetAll()) do
        if pl ~= MySelf and pl:Alive() and pl:Team() == TEAM_HUMAN then
            local dist = pl:GetPos():Distance(mypos)
            if dist <= 600 then
                list[#list + 1] = { ply = pl, dist = dist, name = pl:Nick() }
            end
        end
    end

    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

-- 弹出/关闭「附近人类」列表（给予目标选择，SUNRUST 同款）
function PANEL:ToggleNearbyPlayersMenu(anchor)
    if self.NearbyMenu and self.NearbyMenu:IsValid() then
        self.NearbyMenu:Remove()
        self.NearbyMenu = nil
        return
    end

    local scale = BetterScreenScale()
    local menu = vgui.Create("Panel", self)
    self.NearbyMenu = menu

    local list = self:CollectNearbyHumans()
    local rowh = 26 * scale
    menu:SetWide(math.max(180 * scale, anchor:GetWide() * 3))
    menu:SetTall(math.max(#list, 1) * rowh + 8 * scale)

    -- 锚点屏幕坐标换算为面板本地坐标，弹出层悬在按钮上方
    local ax, ay = anchor:LocalToScreen(0, 0)
    local px, py = self:ScreenToLocal(ax, ay)
    menu:SetPos(px + anchor:GetWide() - menu:GetWide(), py - menu:GetTall() - 4 * scale)

    menu.Paint = function(me, w, h)
        draw.RoundedBox(0, 0, 0, w, h, colNearbyBG)
        surface.SetDrawColor(colBtnBorder.r, colBtnBorder.g, colBtnBorder.b, 210)
        surface.DrawOutlinedRect(0, 0, w, h)
    end

    if #list == 0 then
        local empty = EasyLabel(menu, "—", FONT_ROW, colTextDim)
        empty:Dock(TOP)
        empty:SetTall(rowh)
        empty:SetContentAlignment(5)
        return
    end

    for _, info in ipairs(list) do
        local btn = vgui.Create("DButton", menu)
        btn:SetText("")
        btn:Dock(TOP)
        btn:SetTall(rowh)
        btn.PlayerIndex = info.ply:EntIndex()
        btn.Info = info
        btn.Host = self

        function btn:Paint(w, h)
            local scale = BetterScreenScale()
            local selected = self.Host.SelectedGiveTarget == self.PlayerIndex
            draw.RoundedBox(0, 0, 0, w, h, selected and colRowSelected or (self:IsHovered() and colRowBGHover or colRowBG))
            local col = selected and colTextDark or colRowText
            draw.SimpleText(self.Info.name, FONT_ROW, 8 * scale, h * 0.5, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(math.floor(self.Info.dist)) .. "u", FONT_SMALL, w - 8 * scale, h * 0.5, colTextDim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        function btn:DoClick()
            self.Host.SelectedGiveTarget = self.PlayerIndex
            surface.PlaySound("ui/buttonclick.wav")
            if self.Host.NearbyMenu and self.Host.NearbyMenu:IsValid() then
                self.Host.NearbyMenu:Remove()
                self.Host.NearbyMenu = nil
            end
        end
    end
end

-- ============================================================================
-- [区域] 左栏背包列表
-- [位置] PANEL:BuildInventoryList / PANEL:GetCategoryEntries / PANEL:AddItemRow / PANEL:DrawArrow
-- [作用] 四类可折叠列表（分类头 33 / 行高 38 无缝 + 1px 分隔线）；选中行整行反白
-- [常改] 折叠默认态、行高、排序规则、反白配色
-- ============================================================================

-- 折叠箭头（三角 poly：向下=展开，向右=折叠），调用前需 SetDrawColor
function PANEL:DrawArrow(x, y, down)
    local s = ARROW_SIZE * BetterScreenScale()
    local poly
    if down then
        poly = {
            { x = x - s, y = y - s * 0.6 },
            { x = x + s, y = y - s * 0.6 },
            { x = x, y = y + s * 0.6 },
        }
    else
        poly = {
            { x = x - s * 0.6, y = y - s },
            { x = x + s * 0.6, y = y },
            { x = x - s * 0.6, y = y + s },
        }
    end
    surface.DrawPoly(poly)
end

-- 某分类的条目列表（含排序：小饰品可切名称排序，其余按注册 Index）
function PANEL:GetCategoryEntries(cat)
    local entries
    if cat == CATEGORY_WEAPONS then
        entries = CollectWeaponEntries()
    else
        entries = CollectItemEntries(cat)
    end

    -- 说明：物品获取时间未跟踪，注册 Index 只是获取顺序的近似
    if cat == CATEGORY_TRINKETS and self.SortTrinketsByName then
        table.sort(entries, function(a, b) return string.lower(a.pname) < string.lower(b.pname) end)
    else
        table.sort(entries, function(a, b) return (a.index or 0) < (b.index or 0) end)
    end

    return entries
end

function PANEL:AddItemRow(entry)
    local scale = BetterScreenScale()
    local row = vgui.Create("DButton", self.ScrollPanel:GetCanvas())
    row:SetText("")
    row.Key = EntryKey(entry)
    row.Entry = entry
    row.Host = self
    row.TierSuffix = ""

    if entry.type == "weapon" then
        local sweptable = GetCachedSwept(entry.class)
        local tier = sweptable and sweptable.QualityTier or nil
        row.DisplayName = (sweptable and sweptable.PrintName) or entry.class
        row.TierSuffix = tier and ("+" .. tostring(tier)) or ""
        row.QColor = GetQualityColor(sweptable)
        -- 升级武器行：品质色向右渐变高亮（对齐 SUNRUST 列表样式）
        if tier and tier > 0 then
            row.QTint = row.QColor
        end
        row.Kitbl = ResolveKillicon(entry.class, false)
    else
        local datatbl = GAMEMODE.ZSInventoryItemData and GAMEMODE.ZSInventoryItemData[entry.name] or nil
        row.DisplayName = (datatbl and datatbl.PrintName) or entry.name
        row.QColor = colTextBright
        row.Kitbl = ResolveKillicon(entry.name, true)
    end

    row:SetTall(LIST_ROW_TALL * scale)
    row:Dock(TOP)

    -- 行绘制：无缝行 + 底部 1px 分隔线；选中行整行反白（浅灰底 + 黑字）
    function row:Paint(w, h)
        local scale = BetterScreenScale()
        local selected = self.Host.SelectedEntryKey == self.Key
        local bg = colRowBG
        local namecol = colRowText
        local tiercol = self.QColor
        if selected then
            bg = colRowSelected
            namecol = colTextDark
            tiercol = colTextDark
        elseif self:IsHovered() then
            bg = colRowBGHover
            namecol = colTextBright
        end
        draw.RoundedBox(0, 0, 0, w, h, bg)
        -- 升级武器：品质色向右渐变淡染（选中反白时不叠加）
        if self.QTint and not selected then
            surface.SetDrawColor(self.QTint.r, self.QTint.g, self.QTint.b, 100)
            surface.SetTexture(texGradH)
            surface.DrawTexturedRect(0, 0, w, h)
        end
        surface.SetDrawColor(colRowSep.r, colRowSep.g, colRowSep.b, colRowSep.a)
        surface.DrawRect(0, h - 1, w, 1)
        -- 名称起点与图标区留白对齐靶子图（图标区 36 起，名称 100 起）
        draw.SimpleText(self.DisplayName or "", FONT_ROW, 100 * scale, h * 0.5, namecol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if self.TierSuffix ~= "" then
            draw.SimpleText(self.TierSuffix, FONT_ROW, w - 10 * scale, h * 0.5, tiercol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    function row:DoClick()
        self.Host:UpdateItemInfo(self.Entry)
        if self.Entry.type == "weapon" then
            -- 武器行点击 = 切到该武器
            if not IsValid(MySelf) then return end
            for _, wep in pairs(MySelf:GetWeapons()) do
                if wep:GetClass() == self.Entry.class then
                    input.SelectWeapon(wep)
                    break
                end
            end
        end
    end

    -- 行图标：killicon 两种结构经 AttachKillicon 统一处理，兜底 default
    if row.Kitbl then
        local iconframe = vgui.Create("Panel", row)
        iconframe:SetMouseInputEnabled(false)
        iconframe.Paint = function() end
        iconframe:SetSize(64 * scale, 34 * scale)
        iconframe:SetPos(8 * scale, (LIST_ROW_TALL * scale - 34 * scale) * 0.5)
        GAMEMODE:AttachKillicon(row.Kitbl, row, iconframe, false, false)
    end
end

function PANEL:BuildInventoryList()
    -- [DEBUG-PINV-PERF] 重建计数 + 计时
    local probe = PerfState ~= nil and PerfState.enabled
    local t0 = probe and SysTime() or nil

    local canvas = self.ScrollPanel:GetCanvas()
    for _, child in pairs(canvas:GetChildren()) do
        child:Remove()
    end

    local scale = BetterScreenScale()
    for idx, cat in ipairs(CATEGORY_ORDER) do
        local expanded = self.CatExpanded[cat] and true or false

        -- 折叠头（自绘：居中标题 + 三角箭头，点击展开/收起）
        local header = vgui.Create("DButton", canvas)
        header:SetText("")
        header.Category = cat
        header.Expanded = expanded
        header:SetTall(CAT_HEADER_TALL * scale)
        header:Dock(TOP)
        header:DockMargin(0, idx > 1 and 2 * scale or 0, 0, 0)

        function header:Paint(w, h)
            draw.RoundedBox(0, 0, 0, w, h, self:IsHovered() and colRowBGHover or colHeaderBG)
            surface.SetDrawColor(colTextDim.r, colTextDim.g, colTextDim.b, 255)
            self.Host:DrawArrow(w - 16 * BetterScreenScale(), h * 0.5, self.Expanded)
            local col = self:IsHovered() and colTextBright or colTextDim
            draw.SimpleText(translate.Get(CATEGORY_LABELS[self.Category]), FONT_ROW, w * 0.5, h * 0.5, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        function header:DoClick()
            self.Host.CatExpanded[self.Category] = not self.Host.CatExpanded[self.Category]
            surface.PlaySound("ui/buttonclick.wav")
            self.Host:BuildInventoryList()
        end
        header.Host = self

        if expanded then
            local entries = self:GetCategoryEntries(cat)
            for _, entrydata in ipairs(entries) do
                self:AddItemRow(entrydata)
            end
        end
    end

    canvas:InvalidateLayout(true)

    -- [DEBUG-PINV-PERF] 重建耗时 + 行数
    if probe then
        local dt = (SysTime() - t0) * 1000
        PerfState.rebuilds = PerfState.rebuilds + 1
        local rows = 0
        for _ in pairs(canvas:GetChildren()) do rows = rows + 1 end
        if rows > PerfState.rows_max then PerfState.rows_max = rows end
        chat.AddText(dbgColY, string.format("[DEBUG-PINV-PERF] BuildInventoryList %.2fms (%d children)", dt, rows))
    end
end

-- ============================================================================
-- [区域] 交互与状态同步
-- [位置] PANEL:Think / PANEL:BuildInventorySignature / PANEL:RefreshAll
-- [作用] ALT 防抖关闭、0.25s 手持与库存签名对比刷新、0.5s 拆解台距离轮询
-- [常改] 轮询间隔、防抖时长、联动规则
-- ============================================================================

-- 武器集签名：已拥有武器类名排序拼接（升级/换轨会变，切枪不会——避免列表无谓重建导致图标闪烁）
function PANEL:BuildWeaponSetSignature()
    local parts = {}
    if IsValid(MySelf) then
        for _, wep in pairs(MySelf:GetWeapons()) do
            parts[#parts + 1] = wep:GetClass()
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- 库存签名：物品名+数量拼接（用于 0.25s 轮询对比变化）
function PANEL:BuildInventorySignature()
    local parts = {}
    local inventory = GAMEMODE.ZSInventory
    if inventory then
        for name, count in pairs(inventory) do
            if (count or 0) > 0 and type(name) == "string" then
                parts[#parts + 1] = name .. tostring(count)
            end
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

-- 打开或强制全量刷新（OpenInventoryPanel 调用）
function PANEL:RefreshAll()
    -- [DEBUG-PINV-PERF] 刷新计数
    local probe = PerfState ~= nil and PerfState.enabled
    if probe then
        PerfState.refreshes = PerfState.refreshes + 1
        chat.AddText(dbgColV, string.format("[DEBUG-PINV-PERF] RefreshAll #%d", PerfState.refreshes))
    end

    self.LastSig = self:BuildWeaponSetSignature() .. "|" .. self:BuildInventorySignature()
    self:BuildInventoryList()

    local wep = IsValid(MySelf) and MySelf:GetActiveWeapon() or NULL
    self.LastActiveClass = IsValid(wep) and wep:GetClass() or nil
    if IsValid(wep) then
        self:UpdateItemInfo({type = "weapon", class = wep:GetClass()})
    else
        self:UpdateItemInfo(nil)
    end

    self.NearRemantler = IsValid(MySelf) and MySelf:NearRemantler() or false
    self:UpdateRemantlerButtons()
    self:UpdateSwitchRow()
end

function PANEL:Think()
    -- [DEBUG-PINV-PERF] Think 分段计时
    local t0, t1, t2, t3, t4
    local probe = PerfState ~= nil and PerfState.enabled
    if probe then t0 = SysTime() end

    if not self:IsVisible() then
        self.LoseKeyDeadline = nil
        return
    end

    -- ALT（MenuKey）松开检测：0.1s 防抖，KeyRelease 丢失时兜底关闭
    if not (IsValid(MySelf) and MySelf:KeyDown(GAMEMODE.MenuKey)) then
        if not self.LoseKeyDeadline then
            self.LoseKeyDeadline = RealTime() + KEYLOSE_DEBOUNCE
        elseif RealTime() >= self.LoseKeyDeadline then
            self.LoseKeyDeadline = nil
            self:SetVisible(false)
            if self.NearbyMenu and self.NearbyMenu:IsValid() then
                self.NearbyMenu:Remove()
                self.NearbyMenu = nil
            end
            -- [DEBUG-PINV-PERF] 关闭时输出汇总
            if probe then
                chat.AddText(dbgColC, string.format(
                    "[DEBUG-PINV-PERF] closed | opens=%d rebuilds=%d refreshes=%d thinks=%d think_max=%.2fms sig_max=%.2fms rows_max=%d blur_last=%.2fms",
                    PerfState.opens, PerfState.rebuilds, PerfState.refreshes, PerfState.thinks,
                    PerfState.think_max_ms, PerfState.sig_max_ms, PerfState.rows_max, PerfState.blur_last_ms))
            end
            return
        end
    else
        self.LoseKeyDeadline = nil
    end
    if probe then t1 = SysTime() end

    local now = RealTime()

    -- 0.5s 轮询拆解台距离，变化时刷新变体/升级按钮可用态
    if now >= (self.NextRemantlerPoll or 0) then
        self.NextRemantlerPoll = now + REMANTLER_POLL_TIME
        local near = IsValid(MySelf) and MySelf:NearRemantler() or false
        if near ~= self.NearRemantler then
            self.NearRemantler = near
            self:UpdateRemantlerButtons()
        end
    end
    if probe then t2 = SysTime() end

    -- 0.25s 对比手持武器与库存签名，变化时重建左栏并联动右栏
    if now < (self.NextListCheck or 0) then
        -- [DEBUG-PINV-PERF] 节流跳过帧也计入 think 峰值
        if probe then
            PerfState.thinks = PerfState.thinks + 1
            local dt = (SysTime() - t0) * 1000
            if dt > PerfState.think_max_ms then PerfState.think_max_ms = dt end
        end
        return
    end
    self.NextListCheck = now + LIST_REFRESH_TIME

    local activeclass = ""
    local wep = IsValid(MySelf) and MySelf:GetActiveWeapon() or NULL
    if IsValid(wep) then
        activeclass = wep:GetClass()
    end

    -- 列表仅在武器集/库存变化时重建（切枪不重建，左栏字体型 killicon 不闪）
    local sig = self:BuildWeaponSetSignature() .. "|" .. self:BuildInventorySignature()
    if probe then
        t3 = SysTime()
        local sigdt = (t3 - t2) * 1000
        if sigdt > PerfState.sig_max_ms then PerfState.sig_max_ms = sigdt end
    end
    if sig ~= self.LastSig then
        self.LastSig = sig
        self:BuildInventoryList()
    end
    if probe then t4 = SysTime() end

    local entry = self.SelectedEntry
    if entry and entry.type == "item" then
        -- 物品选中：仅在被消耗完时取消，否则保持
        if not (GAMEMODE.ZSInventory and GAMEMODE.ZSInventory[entry.name]) then
            self:UpdateItemInfo(nil)
        end
    elseif activeclass ~= (self.LastActiveClass or "") then
        -- 武器选中跟随手持（升级/换轨后类名变化自然吸附新武器；类名没变不重刷）
        self.LastActiveClass = activeclass
        self:UpdateItemInfo(activeclass ~= "" and {type = "weapon", class = activeclass} or nil)
    end

    -- [DEBUG-PINV-PERF] 帧级峰值：>4ms 发单行警告并计入汇总
    if probe then
        PerfState.thinks = PerfState.thinks + 1
        local dt = (SysTime() - t0) * 1000
        if dt > PerfState.think_max_ms then PerfState.think_max_ms = dt end
        if dt > 4 then
            chat.AddText(dbgColR, string.format(
                "[DEBUG-PINV-PERF] SLOW think %.2fms (sig %.2fms, rebuild %.2fms)",
                dt, (t3 - t2) * 1000, t4 and (t4 - t3) * 1000 or 0))
        end
    end
end

vgui.Register("ZSInventoryPanel", PANEL, "Panel")

-- ============================================================================
-- [区域] 对外接口与网络同步
-- [位置] GAMEMODE:OpenInventoryPanel / net.Receive(NET_MSG.REMANTLECONF)
-- [作用] 单例打开面板（照 dsidemenu 次序）与重铸回包后的右栏刷新
-- [常改] 单例字段名、鼠标居中位置
-- ============================================================================

-- 打开（或显示）双栏背包面板（单例存 GAMEMODE.InventoryPanel）
-- 次序照 dsidemenu.lua OpenMenu：显示 → MakePopup → 防抖时间戳 → 刷新 → 鼠标居中
-- 注意：文件顶层定义须用 GM（加载期别名），加载后引擎令 GAMEMODE=GM，运行期即可用 self 调用
function GM:OpenInventoryPanel()
    -- [DEBUG-PINV-PERF] 打开计数（首开时初始化会话统计）
    PerfState = PerfState or {enabled = PerfCvar:GetBool(), opens = 0, rebuilds = 0, refreshes = 0,
        thinks = 0, think_max_ms = 0, sig_max_ms = 0, rows_max = 0, blur_last_ms = 0}
    PerfState.enabled = PerfCvar:GetBool()
    PerfState.opens = PerfState.opens + 1
    chat.AddText(dbgColG, string.format("[DEBUG-PINV-PERF] panel open #%d (pinv_perf 1=探针开)", PerfState.opens))

    local panel = self.InventoryPanel
    if not (panel and panel:IsValid()) then
        panel = vgui.Create("ZSInventoryPanel")
        self.InventoryPanel = panel
    end

    panel:SetVisible(true)
    panel:MakePopup()
    -- 不吞移动键：ALT 通常按住移动时开启
    panel:SetKeyboardInputEnabled(false)
    panel.StartChecking = RealTime() + 0.1

    panel:RefreshAll()

    -- 首帧布局完成后：鼠标居中 + 二次刷新（修正首次打开时按 0 宽度计算的变体/动作按钮尺寸）
    timer.Simple(0, function()
        if not (panel and panel:IsValid() and panel:IsVisible()) then return end
        gui.SetMousePos(ScrW() * 0.5, ScrH() * 0.5)
        panel:RefreshAll()
    end)
end

-- 重铸/升级回包：武器类名已变，回到手持武器刷新右栏并重建左栏
net.Receive(NET_MSG.REMANTLECONF, function()
    local panel = GAMEMODE.InventoryPanel
    if not (panel and panel:IsValid() and panel:IsVisible()) then return end

    local wep = IsValid(MySelf) and MySelf:GetActiveWeapon() or NULL
    if IsValid(wep) then
        panel:UpdateItemInfo({type = "weapon", class = wep:GetClass()})
        panel.LastActiveClass = wep:GetClass()
    else
        panel:UpdateItemInfo(nil)
        panel.LastActiveClass = nil
    end
    panel.LastSig = nil
end)

-- 每帧在场景渲染完成后（VGUI 绘制之前）更新毛玻璃 RT：拷屏 + 高斯模糊，
-- Paint 内只做纹理采样绘制（面板可见期间每帧执行，背景实时跟随）
hook.Add("PostRender", "PINV_UpdateBlurRT", function()
    local panel = GAMEMODE.InventoryPanel
    if not (panel and panel:IsValid() and panel:IsVisible()) then return end

    -- [DEBUG-PINV-PERF] 计时：每帧拷屏 + 模糊（必打点，观察逐帧开销）
    local t0 = SysTime()
    render.CopyRenderTargetToTexture(blurRT)
    render.BlurRenderTarget(blurRT, 2, 2, 1)
    local dt = (SysTime() - t0) * 1000
    PerfState.blur_last_ms = dt
    PerfState.blur_count = (PerfState.blur_count or 0) + 1
    if dt > 2 and (PerfState.blur_count % 20 == 1) then
        chat.AddText(dbgColY, string.format(
            "[DEBUG-PINV-PERF] blur copy #%d: %.2fms (>2ms, 1/20 采样输出)", PerfState.blur_count, dt))
    end
end)

-- ============================================================================
-- [区域] 交互与状态同步
-- [位置] PANEL:Think / net.Receive(NET_MSG.REMANTLECONF)
-- [作用] ALT 松开 0.1s 防抖关闭、0.25s 手持与库存变化刷新、0.5s NearRemantler 轮询、重铸回包刷新右栏
-- [常改] 轮询间隔、防抖时长、刷新触发条件
-- ============================================================================
-- 翻译键清单（需在 languages/ 注册）：
--   pinv_title pinv_iteminfo pinv_remantler pinv_back
--   pinv_cat_weapons pinv_cat_trinkets pinv_cat_components pinv_cat_consumables
--   pinv_variants pinv_variant_standard pinv_stats pinv_description
--   pinv_upgrade pinv_max_quality pinv_drop pinv_emptyclip pinv_give pinv_dismantle
--   pinv_sort_trinkets pinv_nopickupprops pinv_buyscrap pinv_need_remantler
-- 集成注册行（留给集成代理）：
--   AddCSLuaFile("gamemode/vgui/pinventory.lua")
--   include("gamemode/vgui/pinventory.lua")
-- ============================================================================
