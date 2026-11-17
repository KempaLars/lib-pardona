# LibPardona-1.0

Small embedded library that groups all Pardona addons (Pardona's Buff Reminder, Pardona's ToolTips, …)
under one shared **"Pardona's Addons"** entry point. It is not an addon of its own – every Pardona addon
ships a copy, and thanks to [LibStub](https://www.wowace.com/projects/libstub) only one copy runs: the
highest MINOR version wins and takes over the existing state (registrations, frames, settings category).

Target client: WoW Forever (Mainline API). Texts: English and German.

## What it provides

- **Settings category "Pardona's Addons"** (registered once). Its overview page shows the Pardona emblem,
  every registered addon (icon, name, version from the TOC, short status, *Open* button) and a
  *Show minimap button* checkbox. Each addon can add its own subpage below it.
- **Addon compartment**: one entry "Pardona's Addons" (only if the client has `AddonCompartmentFrame`).
- **One shared minimap button** (Mainline LibDBIcon layout, draggable along the minimap edge).
  - Left-click: with one registered addon its `onClick`; with several a small menu (one row per addon
    plus "Pardona settings").
  - Right-click: overview page.
  - Tooltip: "Pardona's Addons" and one line `Name: Status` per addon.
- **LibDataBroker launcher "Pardona"** – only if `LibDataBroker-1.1` is already loaded by another addon
  (e.g. Titan Panel, ChocolateBar). LibDataBroker is not embedded.

If the Settings API is missing, everything still works without it: the minimap button and compartment
entry remain, and the overview opens as a small standalone window.

## Embedding

`.pkgmeta` of the addon:

```yaml
externals:
  Libs/lib-pardona:
    url: https://github.com/KempaLars/lib-pardona
```

TOC (before the addon's own files):

```
Libs\lib-pardona\lib-pardona.xml
```

`lib-pardona.xml` loads `LibStub\LibStub.lua` and then `LibPardona-1.0\LibPardona-1.0.lua`.

**Convention:** every Pardona addon embeds the library at exactly `Libs\lib-pardona` inside its own
folder. The textures (`Pardona.tga`, `PardonaMinimap.tga`) are then addressed by convention as

```
Interface\AddOns\<info.addon>\Libs\lib-pardona\LibPardona-1.0\Textures\Pardona
Interface\AddOns\<info.addon>\Libs\lib-pardona\LibPardona-1.0\Textures\PardonaMinimap
```

using the first registered addon that passes `info.addon`. If no registered addon passes `info.addon`,
the icon of the first registered addon is used (or a question-mark icon if none is registered).
Minimap button, overview emblem, compartment entry and LibDataBroker icon are updated after every
registration, so an addon with `info.addon` that registers later still switches them to the emblem.

## API

```lua
local LP = LibStub("LibPardona-1.0")
```

| Call | Description |
| --- | --- |
| `LP:RegisterAddon(id, info)` | Registers an addon (`id` e.g. `"BuffReminder"`). Calling it again with the same id replaces `info`. |
| `LP:GetSettingsCategory()` | Parent category "Pardona's Addons" (or `nil` without Settings API). |
| `LP:RegisterSettingsCanvas(id, frame, name)` | Canvas subcategory via `Settings.RegisterCanvasLayoutSubcategory`; returns `category, layout`. |
| `LP:RegisterSettingsVertical(id, name)` | Vertical-layout subcategory via `Settings.RegisterVerticalLayoutSubcategory`; returns `category, layout`. |
| `LP:OpenSettings(id)` | Opens the addon's subpage, or the overview when `id` is `nil`. Returns `true` if something was opened. |
| `LP:RefreshStatus()` | Updates overview, minimap tooltip and broker text (call it when a status changes). |
| `LP:SetMinimapHidden(hide)` | Hides (`true`) or shows (`false`) the shared minimap button. Writes `hide` into **all** registered dbs with `changed = time()` and updates button, overview checkbox and tooltip. Returns the new hidden state. |
| `LP:IsMinimapHidden()` | `true` if the shared minimap button is hidden (current synchronized state; `false` while no addon is registered). |
| `LP:ToggleMinimap()` | Shortcut for `LP:SetMinimapHidden(not LP:IsMinimapHidden())`; returns the new hidden state. |

`info` fields:

| Field | Type | |
| --- | --- | --- |
| `name` | string (localized) | required |
| `icon` | texture path | required |
| `onClick` | `function(button)` | required – opens the addon's options / main function |
| `db` | table | required – a table inside the addon's SavedVariables; the library stores its fields there |
| `status` | `function() -> string\|nil` | optional – short status for tooltip and overview |
| `migrate` | `function(db)` | optional – one-time import of old settings (e.g. an old minimap position) |
| `addon` | string | optional, **recommended for every addon** – the addon's folder name as in its TOC (e.g. `"PardonasToolTips"`, usually `local ADDON = ...`) |

`info.addon` is used for two things:

- **Version** in the overview: `C_AddOns.GetAddOnMetadata(info.addon, "Version")`. An unreplaced packager
  token (a value starting with `@`, e.g. `@project-version@` in a development checkout) is shown as `dev`.
  Without `info.addon` the version column shows `-`.
- **Emblem textures**: see the embedding convention above. An addon without `info.addon` only gets the
  Pardona emblem if another registered addon passes `info.addon`.

The *Show minimap button* checkbox of the overview uses `SetMinimapHidden` internally, so e.g. an addon's
slash command can simply call `LP:ToggleMinimap()`. Calls before `PLAYER_LOGIN` are kept: their `changed`
timestamp wins the login synchronization.

All Settings calls are protected; without the Settings API the settings functions return `nil`.
Subcategory functions return the existing category if the same `id` is registered twice.
The compartment entry is created at `PLAYER_LOGIN` (or immediately for registrations after login).

### Example

SavedVariables are only available from `ADDON_LOADED` on, so register there:

```lua
local ADDON = ...
local LP = LibStub("LibPardona-1.0")

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    BuffReminderDB = BuffReminderDB or {}

    LP:RegisterAddon("BuffReminder", {
        name = "Buff Reminder",
        addon = ADDON, -- folder name, e.g. "PardonasBuffReminder"
        icon = "Interface\\AddOns\\PardonasBuffReminder\\Textures\\Icon",
        db = BuffReminderDB,
        onClick = function(button) LP:OpenSettings("BuffReminder") end,
        status = function() return missingCount > 0 and (missingCount .. " missing") or "OK" end,
        migrate = function(db)
            if db.minimapAngle then
                db.minimap = { hide = db.minimapHide == true, angle = db.minimapAngle }
            end
        end,
    })

    LP:RegisterSettingsCanvas("BuffReminder", myOptionsFrame, "Buff Reminder")
end)
```

## Saved fields

Every registered `info.db` receives:

```lua
db.minimap = { hide = false, angle = 225, changed = 0 }
```

- `hide` – minimap button hidden; `angle` – position in degrees on the minimap edge;
  `changed` – `time()` of the last change.
- On `PLAYER_LOGIN` (all addons loaded) `migrate(db)` is called for every db without `db.minimap`.
  A migrated record without `changed` gets `changed = 1`, so it beats untouched defaults but not real changes.
- Then the record with the highest `changed` is copied into all registered dbs.
- Every change (dragging, show/hide, `SetMinimapHidden`) is written to **all** registered dbs with `changed = time()`.
  Uninstalling one Pardona addon therefore never loses the shared position.
- Addons registered after login (load-on-demand) are synchronized immediately.

## Behaviour

- **One addon installed**: left-click on minimap button, compartment entry or broker launcher calls that
  addon's `onClick` directly; the settings tree shows "Pardona's Addons" with one subpage.
- **Several addons**: left-click opens the Pardona menu; right-click always opens the overview.
- **Titan Panel / other LDB displays**: the "Pardona" launcher behaves like the minimap button; its text
  lists the addon statuses. Hide the minimap button via the overview checkbox if you prefer the panel.

## Development

- `luacheck .` must report 0 warnings / 0 errors (`LibStub/` is the unmodified official file and excluded).
  CI additionally compiles every own `.lua` file with `luac5.1 -p` (Lua 5.1 compiler limits).
- Bump `MINOR` in `LibPardona-1.0.lua` with every behaviour change; a newer MINOR must keep working with
  state created by older copies.
- Source artwork is in `media/` (not packaged).

## License

MIT – see [LICENSE](LICENSE). LibStub is in the public domain.
