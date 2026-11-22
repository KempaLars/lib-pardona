-- luacheck configuration for LibPardona-1.0 (WoW Forever, Lua 5.1)
std = "lua51"
max_line_length = false
-- WoW callbacks receive parameters (self, event, button, ...) that are often unused
unused_args = false
-- LibStub is the official, unmodified public-domain file and is not linted
exclude_files = { "LibStub/", ".release" }

-- /pardona slash command (LibPardona-1.0.lua)
globals = {
    "SLASH_PARDONA1",
    "SlashCmdList",
}

read_globals = {
    -- namespaces and objects
    "AddonCompartmentFrame",
    "BackdropTemplateMixin",
    "C_AddOns",
    "C_EventUtils",
    "GameTooltip",
    "LibStub",
    "Minimap",
    "Settings",
    "UIParent",
    "UISpecialFrames",
    -- functions
    "CreateColor",
    "CreateFrame",
    "GameTooltip_SetBackdropStyle",
    "geterrorhandler",
    "GetCursorPosition",
    "GetLocale",
    "GetMinimapShape",
    "hooksecurefunc",
    "InCombatLockdown",
    "IsLoggedIn",
    "issecretvalue",
    "SharedTooltip_SetBackdropStyle",
    "time",
}

-- In-game test addon (developer tool, not packaged)
files["tools/LibPardonaTest/LibPardonaTest.lua"] = {
    globals = {
        "LibPardonaTestDB",
        "SLASH_LPTEST1",
        "SlashCmdList",
    },
}
