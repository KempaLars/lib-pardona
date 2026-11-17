-- luacheck configuration for LibPardona-1.0 (WoW Forever, Lua 5.1)
std = "lua51"
max_line_length = false
-- WoW callbacks receive parameters (self, event, button, ...) that are often unused
unused_args = false
-- LibStub is the official, unmodified public-domain file and is not linted
exclude_files = { "LibStub/", ".release" }

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
    "CreateFrame",
    "geterrorhandler",
    "GetCursorPosition",
    "GetLocale",
    "GetMinimapShape",
    "IsLoggedIn",
    "issecretvalue",
    "time",
}
