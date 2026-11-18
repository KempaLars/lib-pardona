-- LibPardona-1.0 – Style API ("Pardona" look)
-- Loaded by lib-pardona.xml after LibPardona-1.0.lua. A separate file keeps both chunks below the
-- Lua 5.1 limits of 200 locals and 60 upvalues per function.
-- Only the copy that has just taken over the library runs this file, and only once.
-- License: MIT

local STYLE_FILE_MINOR = 4 -- always equal to MINOR in LibPardona-1.0.lua
local LP = LibStub and LibStub("LibPardona-1.0", true)
if not LP or LP.minor ~= STYLE_FILE_MINOR or LP.styleLoadedMinor == STYLE_FILE_MINOR then return end
LP.styleLoadedMinor = STYLE_FILE_MINOR

LP.STYLE_VERSION = 1

---------------------------------------------------------------------------
-- Persistent state (kept across upgrades to a newer MINOR)
---------------------------------------------------------------------------
-- styled object -> record { v = 1, variant, ... }; FontStrings get records with variant "font"
LP.styleRegistry = LP.styleRegistry or setmetatable({}, { __mode = "k" })
-- object -> { action = "apply" | "remove", method, opts, border } (queued during combat)
LP.stylePending = LP.stylePending or setmetatable({}, { __mode = "k" })
-- object -> own parts kept for reuse after RemoveStyle
LP.styleSpare = LP.styleSpare or setmetatable({}, { __mode = "k" })
-- hook name -> true once installed
LP.styleHooks = LP.styleHooks or {}
LP.frames = LP.frames or {}

local registry = LP.styleRegistry
local pending = LP.stylePending
local spare = LP.styleSpare

local RECORD_VERSION = 1
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

---------------------------------------------------------------------------
-- Small helpers (local copies; no new globals)
---------------------------------------------------------------------------
local function ReportError(err)
    if type(geterrorhandler) == "function" then
        local handler = geterrorhandler()
        if type(handler) == "function" then handler(err) end
    end
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

-- Events are only registered after C_EventUtils.IsEventValid, and always via pcall.
local function SafeRegisterEvent(frame, event)
    if type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function" then
        local okValid, valid = pcall(C_EventUtils.IsEventValid, event)
        if not okValid or not valid then return false end
    end
    local okRegister = pcall(frame.RegisterEvent, frame, event)
    return okRegister
end

local function Index(t, key)
    return t[key]
end

-- Reads t[key] protected; secret values count as missing.
local function GetField(t, key)
    local ok, value = pcall(Index, t, key)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function IsNumber(value)
    return not IsSecret(value) and type(value) == "number"
end

-- {r, g, b, a} (or {r = , g = , b = , a = }) -> new {r, g, b, a}; nil if invalid or secret
local function CopyColor(color)
    if IsSecret(color) or type(color) ~= "table" then return nil end
    local r, g, b, a = color[1], color[2], color[3], color[4]
    if not IsSecret(r) and r == nil then r, g, b, a = color.r, color.g, color.b, color.a end
    if not IsNumber(r) or not IsNumber(g) or not IsNumber(b) then return nil end
    if not IsSecret(a) and a == nil then a = 1 end
    if not IsNumber(a) then return nil end
    return { r, g, b, a }
end

local function Clamp01(value, default)
    if not IsNumber(value) then return default end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

-- false for non-tables and forbidden objects
local function IsUsable(obj)
    if IsSecret(obj) or type(obj) ~= "table" then return false end
    if type(obj.IsForbidden) == "function" then
        local ok, forbidden = pcall(obj.IsForbidden, obj)
        if not ok or IsSecret(forbidden) or forbidden then return false end
    end
    return true
end

-- true if the call must wait for PLAYER_REGEN_ENABLED (protected frame during combat)
local function NeedsQueue(obj)
    if type(InCombatLockdown) ~= "function" then return false end
    local okCombat, inCombat = pcall(InCombatLockdown)
    if not okCombat or IsSecret(inCombat) or not inCombat then return false end
    if type(obj.IsProtected) ~= "function" then return false end
    local ok, protected = pcall(obj.IsProtected, obj)
    if not ok then return false end
    if IsSecret(protected) then return true end
    return protected and true or false
end

local function ShallowCopy(t)
    if type(t) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(t) do copy[key] = value end
    return copy
end

---------------------------------------------------------------------------
-- LP.Style (read-only for callers; values of the Buff Reminder style "pardona")
---------------------------------------------------------------------------
local Style = LP.Style or {}
LP.Style = Style

local colors = {
    bgTop = { 0.20, 0.09, 0.30, 0.94 },
    bgBottom = { 0.08, 0.03, 0.13, 0.94 },
    border = { 0.85, 0.68, 0.25, 1 },
    title = { 1, 0.82, 0.25, 1 },
    text = { 0.95, 0.93, 1, 1 },
    hint = { 0.66, 0.58, 0.76, 1 },
    label = { 0.85, 0.68, 0.25, 1 },
    separator = { 0.85, 0.68, 0.25, 0.35 },
    buttonBg = { 0.28, 0.14, 0.40, 0.9 },
    buttonBorder = { 0.85, 0.68, 0.25, 0.8 },
    accent = { 0.45, 0.25, 0.65, 1 },
    positive = { 0.35, 0.8, 0.3, 1 },
    negative = { 0.9, 0.15, 0.15, 1 },
}
colors.background = colors.bgBottom
colors.gold = colors.border
colors.value = colors.text
colors.section = colors.label

Style.colors = colors
Style.edge = { file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 12, inset = 3 }
Style.thin = { file = "Interface\\Buttons\\WHITE8X8", size = 1 }
Style.textures = {
    white = "Interface\\Buttons\\WHITE8X8",
    edge = Style.edge.file,
    highlight = "Interface\\QuestFrame\\UI-QuestTitleHighlight",
}
Style.fonts = {
    title = { font = "GameFontNormal", color = colors.title },
    text = { font = "GameFontHighlight", color = colors.text },
    hint = { font = "GameFontDisableSmall", color = colors.hint },
    number = { font = "NumberFontNormal", color = colors.text },
}

-- Variant definitions (colour names refer to LP.Style.colors)
local VARIANTS = {
    panel = { bgTop = "bgTop", bgBottom = "bgBottom", border = "border", rounded = true },
    tooltip = { bgTop = "bgTop", bgBottom = "bgBottom", border = "border", rounded = true },
    thin = { bgBottom = "background", border = "border", rounded = false },
    button = { bgBottom = "buttonBg", border = "buttonBorder", rounded = true, highlight = true },
    icon = { border = "border", rounded = false, fixedThin = true, outset = 1 },
    statusbar = { bgBottom = "background", border = "border", rounded = false, fixedThin = true, outset = 1 },
}

---------------------------------------------------------------------------
-- Hidden regions (only SetAlpha; the original alpha is remembered once)
---------------------------------------------------------------------------
local function HideRegion(rec, region)
    if rec.hidden[region] == nil then
        local ok, alpha = pcall(region.GetAlpha, region)
        if not ok or IsSecret(alpha) or type(alpha) ~= "number" then return end
        rec.hidden[region] = alpha
    end
    pcall(region.SetAlpha, region, 0)
end

local function RestoreRegion(region, alpha)
    pcall(region.SetAlpha, region, alpha)
end

-- opts.hide plus frame.NineSlice (if present) -> list of regions
local function CollectHide(frame, list, rec)
    local out, seen = {}, {}
    local own = rec.parts
    local function Add(region)
        if IsSecret(region) or type(region) ~= "table" or seen[region] or region == frame then return end
        if region == own.bg or region == own.border or region == own.highlight then return end
        if type(region.SetAlpha) ~= "function" or type(region.GetAlpha) ~= "function" then return end
        seen[region] = true
        out[#out + 1] = region
    end
    Add(GetField(frame, "NineSlice"))
    if not IsSecret(list) and type(list) == "table" then
        for _, region in ipairs(list) do Add(region) end
    end
    return out
end

-- Hides everything in rec.hideList and restores regions that are no longer listed.
local function UpdateHidden(rec)
    local wanted = {}
    for _, region in ipairs(rec.hideList) do wanted[region] = true end
    for region, alpha in pairs(rec.hidden) do
        if not wanted[region] then
            RestoreRegion(region, alpha)
            rec.hidden[region] = nil
        end
    end
    for _, region in ipairs(rec.hideList) do HideRegion(rec, region) end
end

---------------------------------------------------------------------------
-- Own parts
---------------------------------------------------------------------------
local function Scaled(color, alpha)
    return color[1], color[2], color[3], color[4] * alpha
end

-- Vertical gradient (bottom -> top); flat bottom colour if SetGradient/CreateColor are missing.
local function SetBackground(texture, bottom, top, alpha)
    local br, bg, bb, ba = Scaled(bottom, alpha)
    local tr, tg, tb, ta = Scaled(top, alpha)
    if type(CreateColor) == "function" and type(texture.SetGradient) == "function" then
        texture:SetColorTexture(1, 1, 1, 1)
        local ok = pcall(texture.SetGradient, texture, "VERTICAL", CreateColor(br, bg, bb, ba), CreateColor(tr, tg, tb, ta))
        if ok then return end
    end
    texture:SetColorTexture(br, bg, bb, ba)
end

local function Anchor(region, target, left, right, top, bottom)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", target, "TOPLEFT", left, -top)
    region:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", -right, bottom)
end

local function ReadOffsets(offsets)
    local o = (not IsSecret(offsets) and type(offsets) == "table") and offsets or {}
    local function Pick(key, index)
        local value = o[key]
        if not IsSecret(value) and value == nil then value = o[index] end
        return IsNumber(value) and value or 0
    end
    return { left = Pick("left", 1), right = Pick("right", 2), top = Pick("top", 3), bottom = Pick("bottom", 4) }
end

local function DefaultBorderColor(variant)
    local def = VARIANTS[variant]
    return colors[def and def.border or "border"]
end

local function ApplyBorderColor(rec)
    local border = rec.parts.border
    if not border or type(border.SetBackdropBorderColor) ~= "function" then return end
    local color = rec.borderColor or DefaultBorderColor(rec.variant)
    border:SetBackdropBorderColor(color[1], color[2], color[3], color[4])
end

local function BuildParts(frame, rec)
    local def = VARIANTS[rec.variant]
    local parts = rec.parts
    local off = rec.offsets
    local target = rec.iconTex or frame
    local edge = rec.rounded and Style.edge or Style.thin
    local inset = rec.rounded and Style.edge.inset or 0
    local outset = def.outset or 0

    -- background
    if def.bgBottom then
        local bg = parts.bg
        if not bg then
            bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            parts.bg = bg
        end
        Anchor(bg, target, off.left + inset, off.right + inset, off.top + inset, off.bottom + inset)
        local bottom = colors[def.bgBottom]
        SetBackground(bg, bottom, colors[def.bgTop or def.bgBottom] or bottom, rec.alpha)
        bg:Show()
    elseif parts.bg then
        parts.bg:Hide()
    end

    -- border
    local border = parts.border
    if not border then
        border = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
        parts.border = border
    end
    border:EnableMouse(false)
    Anchor(border, target, off.left - outset, off.right - outset, off.top - outset, off.bottom - outset)
    local okLevel, level = pcall(frame.GetFrameLevel, frame)
    if okLevel and IsNumber(level) then
        border:SetFrameLevel(math.max(0, level + 1 + rec.levelOffset))
    end
    if type(border.SetBackdrop) == "function" then
        border:SetBackdrop({ edgeFile = edge.file, edgeSize = edge.size })
    end
    ApplyBorderColor(rec)
    border:Show()

    -- highlight (button)
    if def.highlight then
        local highlight = parts.highlight
        if not highlight then
            highlight = frame:CreateTexture(nil, "HIGHLIGHT")
            parts.highlight = highlight
        end
        highlight:SetTexture(Style.textures.highlight)
        highlight:SetBlendMode("ADD")
        Anchor(highlight, target, off.left + inset, off.right + inset, off.top + inset, off.bottom + inset)
        highlight:Show()
    elseif parts.highlight then
        parts.highlight:Hide()
    end
end

local function HideParts(parts)
    if parts.bg then parts.bg:Hide() end
    if parts.border then parts.border:Hide() end
    if parts.highlight then parts.highlight:Hide() end
end

---------------------------------------------------------------------------
-- Icon (StyleIconBorder) and status bar (StyleStatusBar) extras
---------------------------------------------------------------------------
local CROP = 0.08

local function RestoreIcon(rec)
    local icon, coords = rec.iconTex, rec.iconCoords
    if icon and coords then
        pcall(icon.SetTexCoord, icon, coords[1], coords[2], coords[3], coords[4], coords[5], coords[6], coords[7], coords[8])
    end
    rec.iconCoords = nil
end

local function ReadTexCoords(icon)
    local result = { pcall(icon.GetTexCoord, icon) }
    if not result[1] then return nil end
    local coords = {}
    for i = 1, 8 do
        local value = result[i + 1]
        if not IsNumber(value) then return nil end
        coords[i] = value
    end
    return coords
end

local function ConfigureIcon(frame, rec, opts)
    local icon = opts.icon
    if not IsSecret(icon) and icon == nil then icon = GetField(frame, "Icon") or GetField(frame, "icon") end
    if IsSecret(icon) or type(icon) ~= "table" or type(icon.SetTexCoord) ~= "function" then icon = nil end
    if rec.iconTex ~= icon then
        RestoreIcon(rec)
        rec.iconTex = icon
    end
    if icon and opts.crop ~= false then
        if not rec.iconCoords then rec.iconCoords = ReadTexCoords(icon) end
        -- unreadable (secret) coords: no crop, so RemoveStyle can always restore exactly
        if rec.iconCoords then pcall(icon.SetTexCoord, icon, CROP, 1 - CROP, CROP, 1 - CROP) end
    elseif rec.iconCoords then
        RestoreIcon(rec)
    end
end

local function GetBarTexture(bar)
    local texture = bar:GetStatusBarTexture()
    if not texture then return nil end
    return texture:GetTexture()
end

local function RestoreBarColor(bar, rec)
    local c = rec.barColor
    if c then pcall(bar.SetStatusBarColor, bar, c[1], c[2], c[3], c[4]) end
    rec.barColor = nil
end

local function RestoreBarTexture(bar, rec)
    if rec.barTexture ~= nil then pcall(bar.SetStatusBarTexture, bar, rec.barTexture) end
    rec.barTexture = nil
end

local function RestoreBar(bar, rec)
    RestoreBarColor(bar, rec)
    RestoreBarTexture(bar, rec)
end

-- Never touches values (no GetValue/SetValue/GetMinMaxValues/SetMinMaxValues).
local function ConfigureBar(bar, rec, opts)
    local fill = CopyColor(opts.fill)
    if fill then
        if not rec.barColor then
            local ok, r, g, b, a = pcall(bar.GetStatusBarColor, bar)
            if not IsSecret(a) and a == nil then a = 1 end
            if ok and IsNumber(r) and IsNumber(g) and IsNumber(b) and IsNumber(a) then
                rec.barColor = { r, g, b, a }
            end
        end
        if rec.barColor then pcall(bar.SetStatusBarColor, bar, fill[1], fill[2], fill[3], fill[4]) end
    elseif rec.barColor then
        RestoreBarColor(bar, rec)
    end

    local texture = opts.texture
    if not IsSecret(texture) and (type(texture) == "string" or type(texture) == "number") then
        if rec.barTexture == nil then
            local ok, original = pcall(GetBarTexture, bar)
            if ok and not IsSecret(original) and original ~= nil then rec.barTexture = original end
        end
        if rec.barTexture ~= nil then pcall(bar.SetStatusBarTexture, bar, texture) end
    elseif rec.barTexture ~= nil then
        RestoreBarTexture(bar, rec)
    end
end

---------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------
local function ReadFont(fs)
    local orig = {}
    local okObject, fontObject = pcall(fs.GetFontObject, fs)
    if okObject and not IsSecret(fontObject) and type(fontObject) == "table" then
        orig.fontObject = fontObject
    else
        local ok, path, size, flags = pcall(fs.GetFont, fs)
        if not ok or IsSecret(path) or IsSecret(size) or IsSecret(flags) or path == nil then return nil end
        orig.font = { path, size, flags }
    end
    local ok, r, g, b, a = pcall(fs.GetTextColor, fs)
    if not IsSecret(a) and a == nil then a = 1 end
    if not ok or not IsNumber(r) or not IsNumber(g) or not IsNumber(b) or not IsNumber(a) then return nil end
    orig.color = { r, g, b, a }
    return orig
end

local function RestoreFont(fs, rec)
    local orig = rec.orig
    if orig.fontObject then
        fs:SetFontObject(orig.fontObject)
    elseif orig.font then
        fs:SetFont(orig.font[1], orig.font[2], orig.font[3])
    end
    local c = orig.color
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

local function OwnedFonts(owner)
    local list = {}
    for fs, rec in pairs(registry) do
        if rec.variant == "font" and rec.owner == owner and fs ~= owner then list[#list + 1] = fs end
    end
    return list
end

---------------------------------------------------------------------------
-- Apply / remove
---------------------------------------------------------------------------
local function TakeRecord(frame)
    local rec = registry[frame]
    if not rec then
        rec = { v = RECORD_VERSION, hidden = {}, parts = spare[frame] or {} }
        spare[frame] = nil
        registry[frame] = rec
    end
    rec.v = RECORD_VERSION
    rec.hidden = rec.hidden or {}
    rec.parts = rec.parts or {}
    return rec
end

local function DoStyle(frame, variant, opts)
    local def = VARIANTS[variant]
    if not def then return false end
    local rec = TakeRecord(frame)

    if rec.variant == "icon" and variant ~= "icon" then
        RestoreIcon(rec)
        rec.iconTex = nil
    end
    if rec.variant == "statusbar" and variant ~= "statusbar" then RestoreBar(frame, rec) end

    rec.variant = variant
    rec.alpha = Clamp01(opts.alpha, 1)
    rec.offsets = ReadOffsets(opts.offsets)
    rec.borderColor = CopyColor(opts.borderColor)
    rec.levelOffset = IsNumber(opts.frameLevelOffset) and opts.frameLevelOffset or 0
    if def.fixedThin then
        rec.rounded = false
    elseif not IsSecret(opts.rounded) and type(opts.rounded) == "boolean" then
        rec.rounded = opts.rounded
    else
        rec.rounded = def.rounded
    end

    if variant == "icon" then ConfigureIcon(frame, rec, opts) end
    if variant == "statusbar" then ConfigureBar(frame, rec, opts) end

    rec.hideList = CollectHide(frame, opts.hide, rec)
    UpdateHidden(rec)
    BuildParts(frame, rec)
    if variant == "tooltip" then LP:_EnsureStyleHooks() end
    return true
end

local function RestoreFrame(frame, rec)
    for region, alpha in pairs(rec.hidden) do RestoreRegion(region, alpha) end
    rec.hidden = {}
    if rec.variant == "icon" then RestoreIcon(rec) end
    if rec.variant == "statusbar" then RestoreBar(frame, rec) end
    HideParts(rec.parts)
    spare[frame] = rec.parts
end

local function DoRemove(obj)
    local removed = false
    local rec = registry[obj]
    if rec then
        registry[obj] = nil
        removed = true
        local ok, err
        if rec.variant == "font" then
            ok, err = pcall(RestoreFont, obj, rec)
        else
            ok, err = pcall(RestoreFrame, obj, rec)
        end
        if not ok then ReportError(err) end
    end
    for _, fs in ipairs(OwnedFonts(obj)) do
        local fontRec = registry[fs]
        registry[fs] = nil
        removed = true
        local ok, err = pcall(RestoreFont, fs, fontRec)
        if not ok then ReportError(err) end
    end
    return removed
end

local function Queue(obj, action, method, opts)
    pending[obj] = { action = action, method = method, opts = ShallowCopy(opts) }
    return "queued"
end

-- Shared entry point of ApplyStyle, StyleIconBorder and StyleStatusBar.
local function StyleEntry(method, frame, variant, opts, requiredMethod)
    if not IsUsable(frame) or type(frame.CreateTexture) ~= "function" then return false end
    if requiredMethod and type(frame[requiredMethod]) ~= "function" then return false end
    if opts ~= nil and (IsSecret(opts) or type(opts) ~= "table") then return false end
    opts = opts or {}
    if NeedsQueue(frame) then return Queue(frame, "apply", method, opts) end
    pending[frame] = nil
    local current = registry[frame]
    if current and current.variant == "font" then return false end
    local ok, result = pcall(DoStyle, frame, variant, opts)
    if not ok then
        ReportError(result)
        return false
    end
    return result
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function LP:ApplyStyle(frame, opts)
    local variant = "panel"
    if type(opts) == "table" and not IsSecret(opts) and (IsSecret(opts.variant) or opts.variant ~= nil) then
        variant = opts.variant
        if IsSecret(variant) or type(variant) ~= "string" or variant == "icon" or variant == "statusbar"
            or not VARIANTS[variant] then
            return false
        end
    end
    return StyleEntry("ApplyStyle", frame, variant, opts)
end

function LP:StyleIconBorder(button, opts)
    return StyleEntry("StyleIconBorder", button, "icon", opts)
end

function LP:StyleStatusBar(bar, opts)
    return StyleEntry("StyleStatusBar", bar, "statusbar", opts, "GetStatusBarTexture")
end

function LP:RemoveStyle(obj)
    if not IsUsable(obj) then return false end
    local rec = registry[obj]
    local hasFonts = #OwnedFonts(obj) > 0
    if not rec and not hasFonts then
        if pending[obj] then
            pending[obj] = nil
            return true
        end
        return false
    end
    if not (rec and rec.variant == "font") and NeedsQueue(obj) then
        return Queue(obj, "remove")
    end
    pending[obj] = nil
    return DoRemove(obj)
end

function LP:IsStyled(obj)
    if IsSecret(obj) or type(obj) ~= "table" then return nil, false end
    local rec = registry[obj]
    return rec and rec.variant or nil, pending[obj] ~= nil
end

-- r = nil resets to the variant's default colour. Returns true / "queued" / false.
function LP:SetStyleBorderColor(frame, r, g, b, a)
    if not IsUsable(frame) then return false end
    local color
    if r ~= nil then
        color = CopyColor({ r, g, b, a })
        if not color then return false end
    end
    local rec = registry[frame]
    if NeedsQueue(frame) then
        local p = pending[frame]
        if p and p.action == "remove" then return "queued" end
        if not p and not (rec and rec.variant ~= "font") then return false end
        if not p then
            p = {}
            pending[frame] = p
        end
        p.border = { color = color }
        return "queued"
    end
    if not rec or rec.variant == "font" then return false end
    rec.borderColor = color
    local ok, err = pcall(ApplyBorderColor, rec)
    if not ok then
        ReportError(err)
        return false
    end
    return true
end

function LP:StyleFontString(fs, role, owner)
    if not IsUsable(fs) then return false end
    if type(fs.SetFontObject) ~= "function" or type(fs.SetTextColor) ~= "function" then return false end
    local okType, objectType = pcall(fs.GetObjectType, fs)
    if not okType or IsSecret(objectType) or objectType ~= "FontString" then return false end
    if IsSecret(role) or type(role) ~= "string" then return false end
    local def = Style.fonts[role]
    if not def then return false end
    if owner ~= nil and (IsSecret(owner) or type(owner) ~= "table") then return false end
    local fontObject = _G[def.font]
    if type(fontObject) ~= "table" then return false end

    local rec = registry[fs]
    if rec and rec.variant ~= "font" then return false end
    if not rec then
        local okRead, orig = pcall(ReadFont, fs)
        if not okRead or not orig then return false end
        rec = { v = RECORD_VERSION, variant = "font", orig = orig }
        registry[fs] = rec
    end
    rec.role = role
    rec.owner = owner

    local c = def.color
    local ok, err = pcall(function()
        fs:SetFontObject(fontObject)
        fs:SetTextColor(c[1], c[2], c[3], c[4])
    end)
    if not ok then
        ReportError(err)
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Tooltip hook (installed once across all copies and MINORs; dispatches through LP)
---------------------------------------------------------------------------
local function ReapplyTooltip(tooltip, rec)
    -- the NineSlice may have been replaced; keep it in the list
    local nineSlice = GetField(tooltip, "NineSlice")
    if type(nineSlice) == "table" and type(nineSlice.SetAlpha) == "function" then
        local listed = false
        for _, region in ipairs(rec.hideList) do
            if region == nineSlice then listed = true end
        end
        if not listed then rec.hideList[#rec.hideList + 1] = nineSlice end
    end
    for _, region in ipairs(rec.hideList) do HideRegion(rec, region) end
    ApplyBorderColor(rec)
end

function LP:_OnTooltipBackdropStyle(tooltip)
    if IsSecret(tooltip) or type(tooltip) ~= "table" then return end
    local rec = registry[tooltip]
    if not rec or rec.variant ~= "tooltip" then return end
    local ok, err = pcall(ReapplyTooltip, tooltip, rec)
    if not ok then ReportError(err) end
end

function LP:_EnsureStyleHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local hooks = self.styleHooks
    if not hooks.sharedTooltipBackdrop and type(SharedTooltip_SetBackdropStyle) == "function" then
        if pcall(hooksecurefunc, "SharedTooltip_SetBackdropStyle", function(tooltip, ...)
            LP:_OnTooltipBackdropStyle(tooltip, ...)
        end) then
            hooks.sharedTooltipBackdrop = true
        end
    end
    if not hooks.gameTooltipBackdrop and type(GameTooltip_SetBackdropStyle) == "function"
        and GameTooltip_SetBackdropStyle ~= SharedTooltip_SetBackdropStyle then
        if pcall(hooksecurefunc, "GameTooltip_SetBackdropStyle", function(tooltip, ...)
            LP:_OnTooltipBackdropStyle(tooltip, ...)
        end) then
            hooks.gameTooltipBackdrop = true
        end
    end
end

---------------------------------------------------------------------------
-- Combat queue
---------------------------------------------------------------------------
local function RunPending(obj, p)
    if p.action == "remove" then
        LP:RemoveStyle(obj)
        return
    end
    if p.action == "apply" and type(LP[p.method]) == "function" then
        LP[p.method](LP, obj, p.opts)
    end
    if p.border then
        local c = p.border.color
        if c then
            LP:SetStyleBorderColor(obj, c[1], c[2], c[3], c[4])
        else
            LP:SetStyleBorderColor(obj, nil)
        end
    end
end

function LP:_ProcessStylePending()
    local list = {}
    for obj, p in pairs(pending) do list[#list + 1] = { obj, p } end
    for _, item in ipairs(list) do pending[item[1]] = nil end
    for _, item in ipairs(list) do
        local ok, err = pcall(RunPending, item[1], item[2])
        if not ok then ReportError(err) end
    end
end

local styleEvents = LP.frames.styleEvents
if not styleEvents and type(CreateFrame) == "function" then
    styleEvents = CreateFrame("Frame")
    LP.frames.styleEvents = styleEvents
end
if styleEvents then
    styleEvents:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then LP:_ProcessStylePending() end
    end)
    SafeRegisterEvent(styleEvents, "PLAYER_REGEN_ENABLED")
end

LP:_EnsureStyleHooks()

-- The library's own windows (menu, standalone overview) switch to the panel style.
if type(LP._StyleOwnFrames) == "function" then LP:_StyleOwnFrames() end
