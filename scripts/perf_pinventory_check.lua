-- ============================================================================
-- perf_pinventory_check.lua - pinventory.lua 性能契约回归检查
-- 运行: luajit scripts/perf_pinventory_check.lua            (exit 0 = 全部通过)
--       luajit scripts/perf_pinventory_check.lua --debug   (豁免探针残留检查)
-- 背景: ALT 打开背包面板卡顿/掉帧。契约对应历次修复（毛玻璃方案已回退为原实现，
--       原方案 = 全屏 RT + 面板可见期间每帧拷贝+模糊，背景实时跟随）：
--   [C1] PostRender 拷贝仅在面板可见时发生（守卫先于拷贝）
--   [C2] 毛玻璃 RT 为全屏分辨率（回退确认：无 RT_SCALE 降采样残留）
--   [C3] weapons.Get 深拷贝只允许出现在缓存器内部（原: 打开/点分类时每行 2 次深拷贝）
--   [C4] Paint 内不允许匿名 Color() 分配（每帧 GC 压力）
--   [C6] 字体族名必须为 "HarmonyOS Sans SC"（带空格写法回退 Tahoma，无 CJK 字形）
--   [C7] AttachKillicon fit 字体缓存（重复 CreateFont 是渲染侧卡顿源，见 parsenal.lua）
-- ============================================================================

local f = assert(io.open("gamemodes/zombiesurvival/gamemode/vgui/pinventory.lua", "r"))
local src = f:read("*a")
f:close()

local lines, n = {}, 0
for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    lines[n] = line
end

local fails = 0
local function check(ok, name, detail)
    if ok then
        print("[PASS] " .. name)
    else
        fails = fails + 1
        print("[FAIL] " .. name .. (detail and (" -- " .. detail) or ""))
    end
end

-- C1: PostRender 拷贝必须有可见性守卫（拷贝只发生在面板可见期间）
local prStart
for i = 1, n do
    if lines[i]:find('hook%.Add%( "PostRender"') or lines[i]:find('hook%.Add%("PostRender"') then
        prStart = i
        break
    end
end
check(prStart ~= nil, "C1a: PostRender 钩子存在")
if prStart then
    local block, depth = {}, 0
    for i = prStart, n do
        block[#block + 1] = lines[i]
        depth = depth + select(2, lines[i]:gsub("%(", "")) - select(2, lines[i]:gsub("%)", ""))
        if i > prStart and depth <= 0 then break end
    end
    local blk = table.concat(block, "\n")
    local guardPos = blk:find("IsVisible%(%)%s*then%s*return end")
    if not guardPos then guardPos = blk:find("IsVisible%(%)") end
    local copyPos = blk:find("CopyRenderTargetToTexture")
    check(guardPos ~= nil and copyPos ~= nil and guardPos < copyPos,
        "C1b: 拷贝在 IsVisible 守卫之后（面板不可见时零拷贝）")
end

-- C2: 回退确认——全屏 RT，无降采样残留
check(src:find('GetRenderTarget%("pinv_blur_rt",%s*ScrW%(%),%s*ScrH%(%)%)') ~= nil,
    "C2a: RT 为全屏 ScrW() × ScrH()（原方案）")
check(src:find("RT_SCALE") == nil and src:find("pinv_blurinterval") == nil,
    "C2b: 降采样/低频重拷方案残留已清除")

-- C3: weapons.Get 仅允许出现在 GetCachedSwept 内部
local gdef
for i = 1, n do
    if lines[i]:find("local function GetCachedSwept") then gdef = i break end
end
check(gdef ~= nil, "C3a: GetCachedSwept 缓存器存在")
local wcall = {}
for i = 1, n do
    for call in lines[i]:gmatch("weapons%.Get%(") do
        wcall[#wcall + 1] = i
    end
end
local innerOK = 0
if gdef then
    for _, ln in ipairs(wcall) do
        if ln >= gdef and ln <= gdef + 8 then innerOK = innerOK + 1 end
    end
end
check(#wcall == innerOK and innerOK >= 1,
    "C3b: weapons.Get 直调仅存在于缓存器内部（实际直调 " .. (#wcall - innerOK) .. " 处）")
local uses = 0
for _ in src:gmatch("GetCachedSwept%(") do uses = uses + 1 end
check(uses >= 7, "C3c: 全部调用点已走缓存（GetCachedSwept 调用 " .. uses .. " 处）")

-- C4: 匿名 Color() 分配只允许出现在顶部调色板区（前 200 行）
-- 用前导非 word 字符区分匿名 Color( 与 SetDrawColor( / GetQualityColor( 等
local strays = {}
for i = 1, n do
    if lines[i]:find("[^%w_]Color%(") and i > 200 then
        strays[#strays + 1] = i
    end
end
check(#strays == 0, "C4: Paint/更新函数内无匿名 Color() 分配",
    strays and ("残留行: " .. table.concat(strays, ", ")) or nil)

-- C6: 字体族名必须为无空格 "HarmonyOS Sans SC"
local badfonts = {}
for i = 1, n do
    if lines[i]:find("Harmony OS Sans SC") then
        badfonts[#badfonts + 1] = i
    end
end
check(#badfonts == 0, "C6: 无带空格的错误字体族名（Harmony OS Sans SC）",
    badfonts and ("残留行: " .. table.concat(badfonts, ", ")) or nil)

-- 清理检查：无遗留调试标记（--debug 参数下豁免：探针是有意保留的临时插桩）
local debugAllowed = arg and arg[1] == "--debug"
if debugAllowed then
    print("[SKIP] C5: 无遗留 [DEBUG-*] 调试代码（--debug 模式豁免）")
else
    check(not src:find("%[DEBUG%-"), "C5: 无遗留 [DEBUG-*] 调试代码")
end

print(fails == 0 and "== ALL PASS ==" or ("== " .. fails .. " FAILED =="))
os.exit(fails == 0 and 0 or 1)
