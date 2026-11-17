-- LibPardona-1.0
-- Shared "Pardona" entry point for all Pardona addons: one settings category, one addon
-- compartment entry, one minimap button and one LibDataBroker launcher.
-- Embedded library (LibStub). The highest MINOR wins and takes over the existing state.
-- License: MIT

local MAJOR, MINOR = "LibPardona-1.0", 3

assert(LibStub, MAJOR .. " requires LibStub")
local LP, oldMinor = LibStub:NewLibrary(MAJOR, MINOR)
if not LP then return end

---------------------------------------------------------------------------
-- Persistent state (kept across upgrades to a newer MINOR)
---------------------------------------------------------------------------
LP.entries = LP.entries or {}             -- id -> { id, info, addon (= info.addon or nil) }
LP.order = LP.order or {}                 -- ids in registration order
LP.subcategories = LP.subcategories or {} -- id -> { category, layout }
LP.frames = LP.frames or {}               -- events, minimap, menu, overview
-- LP.category, LP.compartmentRegistered, LP.compartmentData, LP.ldbObject, LP.loggedIn, LP.synced
-- LP.texturePath of MINOR 1/2 was derived from debugstack, whose paths WoW shortens with "...";
-- it is no longer used.
LP.texturePath = nil

---------------------------------------------------------------------------
-- Locale
---------------------------------------------------------------------------
local L = {
    TITLE = "Pardona's Addons",
    SETTINGS = "Pardona settings",
    OPEN = "Open",
    SHOW_MINIMAP = "Show minimap button",
    DESC = "All installed Pardona addons in one place.",
    NO_ADDONS = "No Pardona addon is registered.",
    COL_ADDON = "Addon",
    COL_VERSION = "Version",
    COL_STATUS = "Status",
    HINT_LEFT_ONE = "Left-click: open %s",
    HINT_LEFT_MENU = "Left-click: choose addon",
    HINT_RIGHT = "Right-click: overview",
    HINT_DRAG = "Drag: move button",
}

local locale = (type(GetLocale) == "function") and GetLocale() or "enUS"
if locale == "deDE" then
    L.SETTINGS = "Pardona-Einstellungen"
    L.OPEN = "Öffnen"
    L.SHOW_MINIMAP = "Minimap-Button anzeigen"
    L.DESC = "Alle installierten Pardona-Addons an einem Ort."
    L.NO_ADDONS = "Kein Pardona-Addon registriert."
    L.COL_STATUS = "Status"
    L.HINT_LEFT_ONE = "Linksklick: %s öffnen"
    L.HINT_LEFT_MENU = "Linksklick: Addon wählen"
    L.HINT_RIGHT = "Rechtsklick: Übersicht"
    L.HINT_DRAG = "Ziehen: Button verschieben"
end

---------------------------------------------------------------------------
-- Constants and small helpers
---------------------------------------------------------------------------
local DEFAULT_ANGLE = 225
local MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RADIUS_OFFSET = 5 -- centres the 31x31 button on the Mainline minimap edge (LibDBIcon)
local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0

local PARDONA_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function ApplyPardonaBackdrop(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(PARDONA_BACKDROP)
    frame:SetBackdropColor(0.12, 0.05, 0.18, 0.96)
    frame:SetBackdropBorderColor(GOLD_R, GOLD_G, GOLD_B, 1)
end

local function ReportError(err)
    if type(geterrorhandler) == "function" then
        local handler = geterrorhandler()
        if type(handler) == "function" then handler(err) end
    end
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) == true
end

local function Now()
    return (type(time) == "function") and time() or 0
end

local function AddSpecialFrame(name)
    if type(UISpecialFrames) ~= "table" then return end
    for _, existing in ipairs(UISpecialFrames) do
        if existing == name then return end
    end
    table.insert(UISpecialFrames, name)
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

local function SafeUnregisterEvent(frame, event)
    pcall(frame.UnregisterEvent, frame, event)
end

local function SettingsAvailable()
    return type(Settings) == "table"
        and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
end

---------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------
-- Convention: every Pardona addon embeds the library under Libs\lib-pardona, so the textures of
-- the first registered addon that declares info.addon (its folder name) are used.
local function TextureDir()
    for _, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        local addon = entry and entry.addon
        if type(addon) == "string" and addon ~= "" then
            return "Interface\\AddOns\\" .. addon .. "\\Libs\\lib-pardona\\LibPardona-1.0\\Textures\\"
        end
    end
    return nil
end

local function FirstIcon()
    local id = LP.order[1]
    local entry = id and LP.entries[id]
    return entry and entry.info.icon or nil
end

local function EmblemTexture()
    local dir = TextureDir()
    if dir then return dir .. "Pardona" end
    return FirstIcon() or FALLBACK_ICON
end

local function MinimapTexture()
    local dir = TextureDir()
    if dir then return dir .. "PardonaMinimap" end
    return FirstIcon() or FALLBACK_ICON
end

---------------------------------------------------------------------------
-- Entry helpers
---------------------------------------------------------------------------
local function GetStatus(entry)
    local fn = entry.info.status
    if type(fn) ~= "function" then return nil end
    local ok, status = pcall(fn)
    if not ok then
        ReportError(status)
        return nil
    end
    if IsSecret(status) or type(status) ~= "string" or status == "" then return nil end
    return status
end

-- nil without info.addon (shown as "-"); unreplaced packager tokens such as @project-version@ -> "dev"
local function GetVersion(entry)
    if type(entry.addon) ~= "string" or entry.addon == "" then return nil end
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnMetadata) ~= "function" then return nil end
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, entry.addon, "Version")
    if not ok or IsSecret(version) or type(version) ~= "string" or version == "" then return nil end
    if version:sub(1, 1) == "@" then return "dev" end
    return version
end

local function CallOnClick(entry, button)
    local ok, err = pcall(entry.info.onClick, button or "LeftButton")
    if not ok then ReportError(err) end
end

---------------------------------------------------------------------------
-- Saved settings (db.minimap in every registered addon)
---------------------------------------------------------------------------
local function NormalizeMinimap(db, migrated)
    local mm = db.minimap
    if type(mm) ~= "table" then
        mm = {}
        db.minimap = mm
        migrated = false
    end
    if type(mm.hide) ~= "boolean" then mm.hide = false end
    if type(mm.angle) ~= "number" then mm.angle = DEFAULT_ANGLE end
    -- migrated values without a timestamp beat untouched defaults, but not real changes
    if type(mm.changed) ~= "number" then mm.changed = migrated and 1 or 0 end
    return mm
end

-- Calls migrate() where db.minimap is missing, then copies the newest record to all dbs.
local function SyncAll()
    local best
    for _, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        local db = entry.info.db
        local migrated = false
        if db.minimap == nil and type(entry.info.migrate) == "function" then
            local ok, err = pcall(entry.info.migrate, db)
            if not ok then ReportError(err) end
            migrated = type(db.minimap) == "table"
        end
        local mm = NormalizeMinimap(db, migrated)
        if not best or mm.changed > best.changed then best = mm end
    end
    if best then
        local hide, angle, changed = best.hide, best.angle, best.changed
        for _, id in ipairs(LP.order) do
            local mm = LP.entries[id].info.db.minimap
            mm.hide, mm.angle, mm.changed = hide, angle, changed
        end
    end
    LP.synced = true
end

local function WriteMinimap(field, value)
    local now = Now()
    for _, id in ipairs(LP.order) do
        local mm = NormalizeMinimap(LP.entries[id].info.db)
        mm[field] = value
        mm.changed = now
    end
end

local function MinimapState()
    local id = LP.order[1]
    local entry = id and LP.entries[id]
    local mm = entry and entry.info.db.minimap
    if type(mm) == "table" then return mm end
    return { hide = false, angle = DEFAULT_ANGLE, changed = 0 }
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
-- mode: "minimap" (all hints), "launcher" (click hints only)
local function FillTooltip(tooltip, mode)
    tooltip:AddLine(L.TITLE, GOLD_R, GOLD_G, GOLD_B)
    if #LP.order == 0 then
        tooltip:AddLine(L.NO_ADDONS, 0.7, 0.7, 0.7)
    end
    for _, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        local status = GetStatus(entry)
        if status then
            tooltip:AddLine(entry.info.name .. ": " .. status, 1, 1, 1)
        else
            tooltip:AddLine(entry.info.name, 1, 1, 1)
        end
    end
    if mode then
        tooltip:AddLine(" ")
        if #LP.order == 1 then
            tooltip:AddLine(L.HINT_LEFT_ONE:format(LP.entries[LP.order[1]].info.name), 0.7, 0.7, 0.7)
        else
            tooltip:AddLine(L.HINT_LEFT_MENU, 0.7, 0.7, 0.7)
        end
        tooltip:AddLine(L.HINT_RIGHT, 0.7, 0.7, 0.7)
        if mode == "minimap" then tooltip:AddLine(L.HINT_DRAG, 0.7, 0.7, 0.7) end
    end
end

local function ShowTooltip(owner, mode)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    FillTooltip(GameTooltip, mode)
    GameTooltip:Show()
end

local function HideTooltip(owner)
    if type(GameTooltip) == "table" and GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Addon menu (Pardona style: dark purple, gold border)
---------------------------------------------------------------------------
local MENU_ROW_HEIGHT = 22
local MENU_PADDING = 8

local function EnsureMenu()
    local menu = LP.frames.menu
    if not menu then
        menu = CreateFrame("Frame", "LibPardonaMenu", UIParent, BACKDROP_TEMPLATE)
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:Hide()
        menu.lpRows = {}
        AddSpecialFrame("LibPardonaMenu")
        LP.frames.menu = menu
    end
    ApplyPardonaBackdrop(menu)
    menu:SetScript("OnShow", function(self) SafeRegisterEvent(self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self)
        SafeUnregisterEvent(self, "GLOBAL_MOUSE_DOWN")
        self.lpOwner = nil
    end)
    menu:SetScript("OnEvent", function(self)
        local owner = self.lpOwner
        if self:IsMouseOver() or (owner and owner.IsMouseOver and owner:IsMouseOver()) then return end
        self:Hide()
    end)
    return menu
end

local function HideMenu()
    local menu = LP.frames.menu
    if menu then menu:Hide() end
end

local function GetMenuRow(menu, index)
    local row = menu.lpRows[index]
    if not row then
        row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetJustifyH("LEFT")
        menu.lpRows[index] = row
    end
    return row
end

local function AnchorMenu(menu, owner)
    menu:ClearAllPoints()
    local x, y = owner:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not x or not ux then
        menu:SetPoint("CENTER", UIParent, "CENTER")
        return
    end
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    x, y = x * scale, y * scale
    local horizontal = (x > ux) and "RIGHT" or "LEFT"
    if y > uy then
        menu:SetPoint("TOP" .. horizontal, owner, "BOTTOM" .. horizontal, 0, -2)
    else
        menu:SetPoint("BOTTOM" .. horizontal, owner, "TOP" .. horizontal, 0, 2)
    end
end

local function ToggleMenu(owner)
    local menu = EnsureMenu()
    if menu:IsShown() and menu.lpOwner == owner then
        menu:Hide()
        return
    end

    local items = {}
    for _, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        items[#items + 1] = {
            icon = entry.info.icon,
            text = entry.info.name,
            func = function(button) CallOnClick(entry, button) end,
        }
    end
    items[#items + 1] = {
        icon = EmblemTexture(),
        text = L.SETTINGS,
        func = function() LP:OpenSettings() end,
    }

    local width = 140
    for index, item in ipairs(items) do
        local row = GetMenuRow(menu, index)
        row.icon:SetTexture(item.icon)
        row.text:SetText(item.text)
        row:SetScript("OnClick", function(_, button)
            menu:Hide()
            item.func(button)
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PADDING, -MENU_PADDING - (index - 1) * MENU_ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -MENU_PADDING, -MENU_PADDING - (index - 1) * MENU_ROW_HEIGHT)
        row:Show()
        width = math.max(width, row.text:GetStringWidth() + 34)
    end
    for index = #items + 1, #menu.lpRows do
        menu.lpRows[index]:Hide()
    end

    menu:SetSize(width + 2 * MENU_PADDING, #items * MENU_ROW_HEIGHT + 2 * MENU_PADDING)
    AnchorMenu(menu, owner)
    menu.lpOwner = owner
    menu:Show()
end

---------------------------------------------------------------------------
-- Click handling shared by minimap button, compartment and broker
---------------------------------------------------------------------------
local function HandleClick(owner, button)
    if button == "RightButton" then
        HideMenu()
        LP:OpenSettings()
        return
    end
    local count = #LP.order
    if count == 0 then
        LP:OpenSettings()
    elseif count == 1 then
        HideMenu()
        CallOnClick(LP.entries[LP.order[1]], "LeftButton")
    else
        ToggleMenu(owner)
    end
end

---------------------------------------------------------------------------
-- Overview page (settings canvas; standalone window if the Settings API is missing)
---------------------------------------------------------------------------
local OVERVIEW_ROW_HEIGHT = 32
local OVERVIEW_LIST_TOP = -112

local function RefreshOverview()
    local frame = LP.frames.overview
    local content = frame and frame.lpContent
    if not content then return end

    local y = OVERVIEW_LIST_TOP
    for index, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        local row = content.lpRows[index]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(OVERVIEW_ROW_HEIGHT)
            row.stripe = row:CreateTexture(nil, "BACKGROUND")
            row.stripe:SetAllPoints(row)
            row.stripe:SetColorTexture(1, 1, 1, 0.04)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("LEFT", row, "LEFT", 40, 0)
            row.name:SetWidth(170)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.version = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.version:SetPoint("LEFT", row, "LEFT", 215, 0)
            row.version:SetWidth(90)
            row.version:SetJustifyH("LEFT")
            row.version:SetWordWrap(false)
            row.open = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.open:SetSize(90, 22)
            row.open:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.status:SetPoint("LEFT", row, "LEFT", 315, 0)
            row.status:SetPoint("RIGHT", row.open, "LEFT", -8, 0)
            row.status:SetJustifyH("LEFT")
            row.status:SetWordWrap(false)
            content.lpRows[index] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, y)
        row.stripe:SetShown(index % 2 == 1)
        row.icon:SetTexture(entry.info.icon)
        row.name:SetText(entry.info.name)
        row.version:SetText(GetVersion(entry) or "-")
        row.status:SetText(GetStatus(entry) or "")
        row.open:SetText(L.OPEN)
        row.open:SetScript("OnClick", function() CallOnClick(entry, "LeftButton") end)
        row:Show()
        y = y - OVERVIEW_ROW_HEIGHT
    end
    for index = #LP.order + 1, #content.lpRows do
        content.lpRows[index]:Hide()
    end

    content.lpEmpty:SetShown(#LP.order == 0)
    if #LP.order == 0 then y = y - 24 end

    local check = content.lpMinimapCheck
    check:ClearAllPoints()
    check:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 12)
    check:SetChecked(not MinimapState().hide)
    if LP.frames.minimap then check:Enable() else check:Disable() end

    content.lpEmblem:SetTexture(EmblemTexture())
end

local function BuildOverviewContent(frame)
    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    content.lpRows = {}
    frame.lpContent = content

    local emblem = content:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(64, 64)
    emblem:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -16)
    content.lpEmblem = emblem

    local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 12, -8)
    title:SetText(L.TITLE)

    local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText(L.DESC)

    local function Header(text, x)
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 16 + x, OVERVIEW_LIST_TOP + 16)
        header:SetText(text)
    end
    Header(L.COL_ADDON, 40)
    Header(L.COL_VERSION, 215)
    Header(L.COL_STATUS, 315)

    local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", content, "TOPLEFT", 24, OVERVIEW_LIST_TOP - 4)
    empty:SetText(L.NO_ADDONS)
    content.lpEmpty = empty

    local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(L.SHOW_MINIMAP)
    check:SetScript("OnClick", function(self)
        LP:SetMinimapHidden(not self:GetChecked())
    end)
    content.lpMinimapCheck = check
end

local function EnsureOverview()
    local frame = LP.frames.overview
    if not frame then
        frame = CreateFrame("Frame", "LibPardonaOverview", nil, BACKDROP_TEMPLATE)
        frame:Hide()
        LP.frames.overview = frame
    end
    if frame.lpMinor ~= MINOR then
        if frame.lpContent then frame.lpContent:Hide() end
        BuildOverviewContent(frame)
        frame.lpMinor = MINOR
    end
    frame:SetScript("OnShow", RefreshOverview)
    -- optional canvas callbacks of the Settings panel
    frame.OnCommit = function() end
    frame.OnDefault = function() end
    frame.OnRefresh = RefreshOverview
    return frame
end

local function ToggleStandaloneOverview()
    local frame = EnsureOverview()
    if not frame.lpStandalone then
        frame.lpStandalone = true
        frame:SetParent(UIParent)
        frame:SetSize(620, 360)
        frame:SetPoint("CENTER", UIParent, "CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", frame.StartMoving)
        frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        ApplyPardonaBackdrop(frame)
        local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
        AddSpecialFrame("LibPardonaOverview")
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

---------------------------------------------------------------------------
-- Settings category
---------------------------------------------------------------------------
local function EnsureCategory()
    if LP.category then return LP.category end
    if not SettingsAvailable() then return nil end
    local frame = EnsureOverview()
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, frame, L.TITLE)
    if not ok or not category then return nil end
    if not pcall(Settings.RegisterAddOnCategory, category) then return nil end
    LP.category = category
    return category
end

local function RegisterSubcategory(apiName, id, ...)
    if type(id) ~= "string" or id == "" then
        error(MAJOR .. ": id must be a non-empty string", 3)
    end
    local existing = LP.subcategories[id]
    if existing then return existing.category, existing.layout end
    local parent = EnsureCategory()
    if not parent or type(Settings[apiName]) ~= "function" then return nil end
    local ok, category, layout = pcall(Settings[apiName], parent, ...)
    if not ok or not category then return nil end
    LP.subcategories[id] = { category = category, layout = layout }
    return category, layout
end

---------------------------------------------------------------------------
-- Minimap button (layout as Mainline LibDBIcon)
---------------------------------------------------------------------------
local function SetIconPressed(button, pressed)
    local icon = button.lpIcon
    icon:ClearAllPoints()
    if pressed then
        icon:SetPoint("CENTER", button, "CENTER", 1, -1)
        icon:SetVertexColor(0.75, 0.75, 0.75)
    else
        icon:SetPoint("CENTER", button, "CENTER")
        icon:SetVertexColor(1, 1, 1)
    end
end

local function UpdateMinimapButton()
    local button = LP.frames.minimap
    if not button then return end
    if not LP.synced or #LP.order == 0 then
        button:Hide()
        return
    end
    local state = MinimapState()
    local rad = math.rad(state.angle)
    local x, y = math.cos(rad), math.sin(rad)
    local w = Minimap:GetWidth() / 2 + RADIUS_OFFSET
    local h = Minimap:GetHeight() / 2 + RADIUS_OFFSET
    local shape = (type(GetMinimapShape) == "function") and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    else
        x, y = x * w, y * h
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    button.lpIcon:SetTexture(MinimapTexture())
    if state.hide then button:Hide() else button:Show() end
end

local function DragUpdate()
    if type(GetCursorPosition) ~= "function" then return end
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    WriteMinimap("angle", math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360)
    UpdateMinimapButton()
end

local function EnsureMinimapButton()
    if type(Minimap) ~= "table" then return nil end
    local button = LP.frames.minimap
    if not button then
        button = CreateFrame("Button", "LibPardonaMinimapButton", Minimap)
        button:SetSize(31, 31)
        button:SetFrameStrata("MEDIUM")
        button:SetFrameLevel(8)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

        local function RoundMask(texture)
            local mask = button:CreateMaskTexture()
            mask:SetTexture(MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(texture)
            texture:AddMaskTexture(mask)
        end

        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetSize(24, 24)
        background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        background:SetPoint("CENTER", button, "CENTER")
        RoundMask(background)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER", button, "CENTER")
        RoundMask(icon)
        button.lpIcon = icon

        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetSize(50, 50)
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetPoint("TOPLEFT", button, "TOPLEFT")

        button:Hide()
        LP.frames.minimap = button
    end

    -- scripts are (re)assigned so that a newer MINOR takes over an existing button
    button:SetScript("OnMouseDown", function(self) SetIconPressed(self, true) end)
    button:SetScript("OnMouseUp", function(self) SetIconPressed(self, false) end)
    button:SetScript("OnClick", function(self, mouseButton) HandleClick(self, mouseButton) end)
    button:SetScript("OnEnter", function(self) ShowTooltip(self, "minimap") end)
    button:SetScript("OnLeave", function(self) HideTooltip(self) end)
    button:SetScript("OnDragStart", function(self)
        HideMenu()
        HideTooltip(self)
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        SetIconPressed(self, false)
        LP:RefreshStatus()
    end)
    button:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        SetIconPressed(self, false)
    end)
    button:SetScript("OnUpdate", nil)
    return button
end

---------------------------------------------------------------------------
-- Addon compartment
---------------------------------------------------------------------------
-- The compartment keeps the registered closures, so they dispatch through LP and
-- always reach the code of the newest MINOR.
function LP:_CompartmentClick(_, inputData)
    local buttonName = (type(inputData) == "table" and inputData.buttonName) or "LeftButton"
    HandleClick(AddonCompartmentFrame, buttonName)
end

function LP:_CompartmentEnter(owner)
    if type(owner) ~= "table" or type(owner.GetCenter) ~= "function" then owner = AddonCompartmentFrame end
    ShowTooltip(owner, "launcher")
end

function LP:_CompartmentLeave()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

local function EnsureCompartment()
    if LP.compartmentRegistered then return end
    local compartment = AddonCompartmentFrame
    if type(compartment) ~= "table" or type(compartment.RegisterAddon) ~= "function" then return end
    local data = {
        text = L.TITLE,
        icon = EmblemTexture(),
        notCheckable = true,
        registerForAnyClick = true,
        func = function(...) LP:_CompartmentClick(...) end,
        funcOnEnter = function(...) LP:_CompartmentEnter(...) end,
        funcOnLeave = function(...) LP:_CompartmentLeave(...) end,
    }
    local ok = pcall(compartment.RegisterAddon, compartment, data)
    if ok then
        LP.compartmentRegistered = true
        LP.compartmentData = data
    end
end

---------------------------------------------------------------------------
-- LibDataBroker launcher (only if LibDataBroker-1.1 is loaded by someone else)
---------------------------------------------------------------------------
local function BrokerText()
    local parts = {}
    for _, id in ipairs(LP.order) do
        local status = GetStatus(LP.entries[id])
        if status then parts[#parts + 1] = status end
    end
    if #parts == 0 then return L.TITLE end
    return table.concat(parts, " | ")
end

local function EnsureLDB()
    local ldb = LibStub("LibDataBroker-1.1", true)
    if not ldb then return end
    local obj = LP.ldbObject
    if not obj then
        local ok, created = pcall(ldb.NewDataObject, ldb, "Pardona", {
            type = "launcher",
            label = L.TITLE,
            icon = MinimapTexture(),
            text = L.TITLE,
        })
        if not ok or not created then return end
        obj = created
        LP.ldbObject = obj
    end
    obj.icon = MinimapTexture()
    obj.OnClick = function(frame, button) HandleClick(frame, button) end
    obj.OnTooltipShow = function(tooltip) FillTooltip(tooltip, "launcher") end
end

---------------------------------------------------------------------------
-- Texture refresh of already created elements (an addon with info.addon may register later)
---------------------------------------------------------------------------
local function UpdateTextures()
    local button = LP.frames.minimap
    if button and button.lpIcon then button.lpIcon:SetTexture(MinimapTexture()) end
    local overview = LP.frames.overview
    local content = overview and overview.lpContent
    if content and content.lpEmblem then content.lpEmblem:SetTexture(EmblemTexture()) end
    if LP.ldbObject then LP.ldbObject.icon = MinimapTexture() end
    if LP.compartmentData then LP.compartmentData.icon = EmblemTexture() end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function LP:RegisterAddon(id, info)
    if type(id) ~= "string" or id == "" then error(MAJOR .. ": id must be a non-empty string", 2) end
    if type(info) ~= "table" then error(MAJOR .. ": info must be a table", 2) end
    if type(info.name) ~= "string" then error(MAJOR .. ": info.name must be a string", 2) end
    if type(info.icon) ~= "string" and type(info.icon) ~= "number" then error(MAJOR .. ": info.icon must be a texture path", 2) end
    if type(info.onClick) ~= "function" then error(MAJOR .. ": info.onClick must be a function", 2) end
    if type(info.db) ~= "table" then error(MAJOR .. ": info.db must be a table", 2) end
    if info.status ~= nil and type(info.status) ~= "function" then error(MAJOR .. ": info.status must be a function", 2) end
    if info.migrate ~= nil and type(info.migrate) ~= "function" then error(MAJOR .. ": info.migrate must be a function", 2) end
    if info.addon ~= nil and type(info.addon) ~= "string" then error(MAJOR .. ": info.addon must be a string", 2) end

    local entry = self.entries[id]
    if not entry then
        entry = { id = id }
        self.entries[id] = entry
        table.insert(self.order, id)
    end
    entry.info = info
    entry.addon = info.addon

    EnsureCategory()
    EnsureMinimapButton()
    if self.loggedIn then
        EnsureCompartment()
        SyncAll()
        EnsureLDB()
        UpdateMinimapButton()
    end
    UpdateTextures()
    self:RefreshStatus()
    return true
end

function LP:GetSettingsCategory()
    return EnsureCategory()
end

function LP:RegisterSettingsCanvas(id, frame, name)
    if type(frame) ~= "table" then error(MAJOR .. ": frame must be a frame", 2) end
    return RegisterSubcategory("RegisterCanvasLayoutSubcategory", id, frame, name or id)
end

function LP:RegisterSettingsVertical(id, name)
    return RegisterSubcategory("RegisterVerticalLayoutSubcategory", id, name or id)
end

-- Opens the addon's subcategory (id) or the overview (nil). Returns true if something opened.
function LP:OpenSettings(id)
    HideMenu()
    local category
    if id ~= nil then
        local sub = self.subcategories[id]
        category = sub and sub.category
    end
    category = category or EnsureCategory()
    if category then
        if type(Settings) == "table" and type(Settings.OpenToCategory) == "function" then
            local okId, categoryID = pcall(category.GetID, category)
            if okId and categoryID and pcall(Settings.OpenToCategory, categoryID) then return true end
        end
        return false
    end
    if id == nil then
        ToggleStandaloneOverview()
        return true
    end
    return false
end

-- Writes hide into every registered db (changed = time()) and updates button, overview and tooltip.
-- Returns the new hidden state.
function LP:SetMinimapHidden(hide)
    if IsSecret(hide) then error(MAJOR .. ": hide must not be a secret value", 2) end
    hide = hide and true or false
    WriteMinimap("hide", hide)
    self:RefreshStatus()
    return self:IsMinimapHidden()
end

function LP:IsMinimapHidden()
    return MinimapState().hide == true
end

function LP:ToggleMinimap()
    return self:SetMinimapHidden(not self:IsMinimapHidden())
end

function LP:RefreshStatus()
    local overview = self.frames.overview
    if overview and overview:IsVisible() then RefreshOverview() end
    UpdateMinimapButton()
    local button = self.frames.minimap
    if button and type(GameTooltip) == "table" and GameTooltip:GetOwner() == button then
        if button:IsShown() then ShowTooltip(button, "minimap") else GameTooltip:Hide() end
    end
    local menu = self.frames.menu
    if button and menu and menu.lpOwner == button and not button:IsShown() then menu:Hide() end
    if self.ldbObject then self.ldbObject.text = BrokerText() end
end

---------------------------------------------------------------------------
-- Login and upgrade handling
---------------------------------------------------------------------------
local function OnLogin()
    LP.loggedIn = true
    SyncAll()
    EnsureMinimapButton()
    EnsureCompartment()
    EnsureLDB()
    UpdateTextures()
    LP:RefreshStatus()
end

local events = LP.frames.events
if not events then
    events = CreateFrame("Frame")
    LP.frames.events = events
end
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        SafeUnregisterEvent(self, "PLAYER_LOGIN")
        OnLogin()
    end
end)

if not LP.loggedIn then
    if type(IsLoggedIn) == "function" and IsLoggedIn() then
        OnLogin()
    else
        SafeRegisterEvent(events, "PLAYER_LOGIN")
    end
end

-- A newer MINOR takes over frames created by an older copy.
if oldMinor then
    -- MINOR 1/2 guessed entry.addon from debugstack (or fell back to the id); only info.addon counts now.
    for _, id in ipairs(LP.order) do
        local entry = LP.entries[id]
        if entry and type(entry.info) == "table" then
            entry.addon = type(entry.info.addon) == "string" and entry.info.addon or nil
        end
    end
    -- MINOR 1/2 did not keep the compartment data table; find it so its icon can be updated.
    if LP.compartmentRegistered and not LP.compartmentData and type(AddonCompartmentFrame) == "table" then
        local registered = AddonCompartmentFrame.registeredAddons
        if type(registered) == "table" then
            for _, data in ipairs(registered) do
                if type(data) == "table" and not IsSecret(data.text) and data.text == L.TITLE then
                    LP.compartmentData = data
                    break
                end
            end
        end
    end
    if LP.frames.menu then EnsureMenu() end
    if LP.frames.overview then EnsureOverview() end
    if #LP.order > 0 then EnsureMinimapButton() end
    if LP.loggedIn then EnsureLDB() end
    UpdateTextures()
    if LP.loggedIn then LP:RefreshStatus() end
end
