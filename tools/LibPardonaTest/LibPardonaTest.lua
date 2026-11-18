-- LibPardonaTest – in-game test addon for the LibPardona-1.0 style API.
-- Developer tool (English only), not packaged. Install with tools\install-test.ps1.

local ADDON = ...
local LP = LibStub and LibStub("LibPardona-1.0", true)
if not LP then return end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local PREFIX = "|cffd9ad40LibPardona Test:|r"

local function Print(...)
    local parts = { PREFIX }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print(table.concat(parts, " "))
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function Index(t, key)
    return t[key]
end

-- Protected field read; secret values and non-tables count as missing.
local function Field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, value = pcall(Index, t, key)
    if not ok or IsSecret(value) then return nil end
    return value
end

-- Global frame by name (nil if it does not exist in this client).
local function G(name)
    local value = _G[name]
    if IsSecret(value) or type(value) ~= "table" then return nil end
    return value
end

local function SafeRegisterEvent(frame, event)
    if type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function" then
        local okValid, valid = pcall(C_EventUtils.IsEventValid, event)
        if not okValid or not valid then return false end
    end
    return (pcall(frame.RegisterEvent, frame, event))
end

local HELP = {
    "/lptest demo - demo window (1st: create and style, 2nd: RemoveStyle, 3rd: style again)",
    "/lptest char - panel style on CharacterFrame on/off",
    "/lptest tip - tooltip style on the game tooltips on/off",
    "/lptest border <r> <g> <b> | border reset - border colour of GameTooltip and ItemRefTooltip",
    "/lptest alpha <0-1> - reapply the tooltip style with this alpha",
    "/lptest bar - StyleStatusBar on GameTooltipStatusBar on/off",
    "/lptest combat - thin style on PlayerFrame on/off (prints true / queued / false)",
    "/lptest minimap - RefreshMinimapButton and print GetMinimapShape()",
    "/lptest status - LP.minor, LP.STYLE_VERSION and IsStyled of all test targets",
}

local function PrintHelp()
    Print("commands:")
    for _, line in ipairs(HELP) do Print(line) end
end

---------------------------------------------------------------------------
-- demo
---------------------------------------------------------------------------
local demo -- { frame, box, button, bar, icon, fonts }
local demoStyled = false

local function BuildDemo()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(360, 250)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local fonts = {}
    local function Font(role, text, y)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
        fs:SetText(text)
        fonts[role] = fs
    end
    Font("title", "LibPardona style demo", -16)
    Font("text", "Text: panel, thin, button, status bar, icon", -36)
    Font("hint", "Hint: drag to move, /lptest demo toggles", -54)
    Font("number", "12345", -72)

    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(150, 60)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -100)

    local button = CreateFrame("Button", nil, frame)
    button:SetSize(150, 26)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -100)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER", button, "CENTER")
    label:SetText("Button")
    button:SetScript("OnClick", function() Print("button clicked") end)

    local icon = CreateFrame("Button", nil, frame)
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 190, -136)
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetAllPoints(icon)
    icon.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    -- the test addon owns this bar, so it may set its value; the library never does
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetSize(324, 14)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -200)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(65)

    return { frame = frame, box = box, button = button, icon = icon, bar = bar, fonts = fonts }
end

local function StyleDemo()
    Print("ApplyStyle panel:", LP:ApplyStyle(demo.frame, { variant = "panel" }))
    Print("ApplyStyle thin:", LP:ApplyStyle(demo.box, { variant = "thin" }))
    Print("ApplyStyle button:", LP:ApplyStyle(demo.button, { variant = "button" }))
    Print("StyleStatusBar:", LP:StyleStatusBar(demo.bar, { fill = LP.Style.colors.gold }))
    Print("StyleIconBorder:", LP:StyleIconBorder(demo.icon))
    for _, role in ipairs({ "title", "text", "hint", "number" }) do
        Print("StyleFontString " .. role .. ":", LP:StyleFontString(demo.fonts[role], role, demo.frame))
    end
end

local function UnstyleDemo()
    Print("RemoveStyle panel (+ fonts):", LP:RemoveStyle(demo.frame))
    Print("RemoveStyle thin:", LP:RemoveStyle(demo.box))
    Print("RemoveStyle button:", LP:RemoveStyle(demo.button))
    Print("RemoveStyle status bar:", LP:RemoveStyle(demo.bar))
    Print("RemoveStyle icon:", LP:RemoveStyle(demo.icon))
end

local function CmdDemo()
    if not demo then demo = BuildDemo() end
    demo.frame:Show()
    if demoStyled then
        UnstyleDemo()
    else
        StyleDemo()
    end
    demoStyled = not demoStyled
end

---------------------------------------------------------------------------
-- char
---------------------------------------------------------------------------
local function CmdChar()
    local frame = G("CharacterFrame")
    if not frame then
        Print("CharacterFrame does not exist")
        return
    end
    if LP:IsStyled(frame) then
        Print("CharacterFrame RemoveStyle:", LP:RemoveStyle(frame))
        return
    end
    local hide = {}
    for _, key in ipairs({ "Bg", "Background", "TopTileStreaks" }) do
        local region = Field(frame, key)
        if type(region) == "table" then hide[#hide + 1] = region end
    end
    local insetBg = Field(Field(frame, "Inset"), "Bg")
    if type(insetBg) == "table" then hide[#hide + 1] = insetBg end
    Print("CharacterFrame ApplyStyle panel (" .. #hide .. " hidden):", LP:ApplyStyle(frame, { variant = "panel", hide = hide }))
end

---------------------------------------------------------------------------
-- tooltips
---------------------------------------------------------------------------
local TOOLTIP_NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
local tipOn = false
local tipAlpha = 1

local function ForEachTooltip(fn)
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tooltip = G(name)
        if tooltip then fn(name, tooltip) end
    end
end

local function CmdTip()
    tipOn = not tipOn
    ForEachTooltip(function(name, tooltip)
        if tipOn then
            Print(name .. " ApplyStyle tooltip:", LP:ApplyStyle(tooltip, { variant = "tooltip", alpha = tipAlpha }))
        else
            Print(name .. " RemoveStyle:", LP:RemoveStyle(tooltip))
        end
    end)
end

local function CmdBorder(args)
    local r, g, b
    if args[1] ~= "reset" then
        r, g, b = tonumber(args[1] or ""), tonumber(args[2] or ""), tonumber(args[3] or "")
        if not r or not g or not b then
            Print("usage: /lptest border <r> <g> <b> | /lptest border reset")
            return
        end
    end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tooltip = G(name)
        if tooltip then
            if r then
                Print(name .. " SetStyleBorderColor:", LP:SetStyleBorderColor(tooltip, r, g, b, 1))
            else
                Print(name .. " SetStyleBorderColor reset:", LP:SetStyleBorderColor(tooltip, nil))
            end
        end
    end
end

local function CmdAlpha(args)
    local alpha = tonumber(args[1] or "")
    if not alpha or alpha < 0 or alpha > 1 then
        Print("usage: /lptest alpha <0-1>")
        return
    end
    tipAlpha = alpha
    tipOn = true
    ForEachTooltip(function(name, tooltip)
        Print(name .. " ApplyStyle tooltip alpha " .. alpha .. ":", LP:ApplyStyle(tooltip, { variant = "tooltip", alpha = alpha }))
    end)
end

local function CmdBar()
    local bar = G("GameTooltipStatusBar")
    if not bar then
        Print("GameTooltipStatusBar does not exist")
        return
    end
    if LP:IsStyled(bar) then
        Print("GameTooltipStatusBar RemoveStyle:", LP:RemoveStyle(bar))
    else
        Print("GameTooltipStatusBar StyleStatusBar:", LP:StyleStatusBar(bar))
    end
end

---------------------------------------------------------------------------
-- combat, minimap, status
---------------------------------------------------------------------------
local combatOn = false

local function CmdCombat()
    local frame = G("PlayerFrame")
    if not frame then
        Print("PlayerFrame does not exist")
        return
    end
    local inCombat = type(InCombatLockdown) == "function" and InCombatLockdown() or false
    combatOn = not combatOn
    if combatOn then
        Print("PlayerFrame ApplyStyle thin (combat " .. tostring(inCombat) .. "):", LP:ApplyStyle(frame, { variant = "thin" }))
    else
        Print("PlayerFrame RemoveStyle (combat " .. tostring(inCombat) .. "):", LP:RemoveStyle(frame))
    end
end

local function CmdMinimap()
    LP:RefreshMinimapButton()
    local shape = "(GetMinimapShape missing)"
    if type(GetMinimapShape) == "function" then shape = tostring(GetMinimapShape()) end
    Print("RefreshMinimapButton done, GetMinimapShape():", shape)
end

local function StatusTargets()
    local list = {}
    if demo then
        list[#list + 1] = { "demo panel", demo.frame }
        list[#list + 1] = { "demo thin", demo.box }
        list[#list + 1] = { "demo button", demo.button }
        list[#list + 1] = { "demo status bar", demo.bar }
        list[#list + 1] = { "demo icon", demo.icon }
        for _, role in ipairs({ "title", "text", "hint", "number" }) do
            list[#list + 1] = { "demo font " .. role, demo.fonts[role] }
        end
    end
    for _, name in ipairs({ "CharacterFrame", "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
        "ShoppingTooltip2", "EmbeddedItemTooltip", "GameTooltipStatusBar", "PlayerFrame" }) do
        local frame = G(name)
        if frame then list[#list + 1] = { name, frame } end
    end
    return list
end

local function CmdStatus()
    Print("LP.minor:", LP.minor, "LP.STYLE_VERSION:", LP.STYLE_VERSION)
    for _, target in ipairs(StatusTargets()) do
        local variant, queued = LP:IsStyled(target[2])
        Print(target[1] .. ":", variant, queued)
    end
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
local COMMANDS = {
    demo = CmdDemo,
    char = CmdChar,
    tip = CmdTip,
    border = CmdBorder,
    alpha = CmdAlpha,
    bar = CmdBar,
    combat = CmdCombat,
    minimap = CmdMinimap,
    status = CmdStatus,
}

local function OnSlash(msg)
    if type(msg) ~= "string" then msg = "" end
    local args = {}
    for word in msg:gmatch("%S+") do args[#args + 1] = word:lower() end
    local cmd = table.remove(args, 1)
    local handler = cmd and COMMANDS[cmd]
    if not handler then
        PrintHelp()
        return
    end
    local ok, err = pcall(handler, args)
    if not ok then Print("error:", err) end
end

if type(SlashCmdList) == "table" then
    SLASH_LPTEST1 = "/lptest"
    SlashCmdList.LPTEST = OnSlash
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, name)
    if event ~= "ADDON_LOADED" or name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    if type(LibPardonaTestDB) ~= "table" then LibPardonaTestDB = {} end
    LP:RegisterAddon("LibPardonaTest", {
        name = "LibPardona Test",
        addon = "LibPardonaTest",
        icon = "Interface\\Icons\\INV_Misc_QuestionMark",
        db = LibPardonaTestDB,
        onClick = function() PrintHelp() end,
    })
end)
SafeRegisterEvent(events, "ADDON_LOADED")
