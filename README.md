# LibPardona-1.0

Small embedded library that groups all Pardona addons (Pardona's Buff Reminder, Pardona's ToolTips, …)
under one shared **"Pardona's Addons"** entry point. It is not an addon of its own – every Pardona addon
ships a copy, and thanks to [LibStub](https://www.wowace.com/projects/libstub) only one copy runs: the
highest MINOR version wins and takes over the existing state (registrations, frames, settings category).

Target client: WoW Forever (Mainline API). Texts: English and German.

## What it provides

- **Settings category "Pardona's Addons"** (registered once). Its overview page shows the Pardona emblem,
  every registered addon (icon, name, version from the TOC, library MINOR, short status, *Open* button),
  a *Show minimap button* checkbox and a diagnostics footer. Each addon can add its own subpage below it.
- **Suite diagnostics** (MINOR 6): `/pardona` and `LP:GetDiagnostics()` – see
  [Diagnostics (MINOR 6)](#diagnostics-minor-6).
- **Addon compartment**: one entry "Pardona's Addons" (only if the client has `AddonCompartmentFrame`).
- **One shared minimap button** (Mainline LibDBIcon layout, draggable along the minimap edge).
  - Left-click: with one registered addon without menu entries its `onClick`; otherwise a small menu
    (one row per addon, its menu entries below it, plus "Pardona settings").
  - Right-click: overview page.
  - Tooltip: "Pardona's Addons" and one line `Name: Status` per addon.
- **LibDataBroker launcher "Pardona"** – only if `LibDataBroker-1.1` is already loaded by another addon
  (e.g. Titan Panel, ChocolateBar). LibDataBroker is not embedded.
- **Style API "Pardona"** (MINOR 4): one shared look for your own and Blizzard frames, tooltips, icons,
  status bars and FontStrings – see [Style API (MINOR 4)](#style-api-minor-4).

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

`lib-pardona.xml` loads `LibStub\LibStub.lua`, then `LibPardona-1.0\LibPardona-1.0.lua` and then
`LibPardona-1.0\Style.lua` (the style API, see below). Always embed the whole `lib-pardona` folder and load it
through `lib-pardona.xml`; listing only `LibPardona-1.0.lua` in a TOC leaves out the style API.

**Convention:** every Pardona addon embeds the library at exactly `Libs\lib-pardona` inside its own
folder. The textures (`Pardona.tga`, `PardonaMinimap.tga` in `LibPardona-1.0\Textures`) are then
addressed by convention as

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
| `LP:RefreshMinimapButton()` | Re-anchors the shared minimap button on the minimap edge (follows `GetMinimapShape()`, including `"SQUARE"`). The library calls it itself when the minimap changes its size (`OnSizeChanged` hook, installed once); call it after changing the minimap shape. (MINOR 4) |
| Style API | `LP:ApplyStyle`, `LP:RemoveStyle`, … – see [Style API (MINOR 4)](#style-api-minor-4). |

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
| `menu` | `function() -> entries` or list of entries | optional – entries below the addon's row in the Pardona menu, see [Menu entries (MINOR 6)](#menu-entries-minor-6). Any other type is ignored. |

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
  addon's `onClick` directly – unless the addon has menu entries (`info.menu` returns at least one valid
  entry); then the Pardona menu opens. The settings tree shows "Pardona's Addons" with one subpage.
- **Several addons**: left-click opens the Pardona menu; right-click always opens the overview.
- Minimap button, compartment entry and broker launcher share one click handler and always behave the same.
- **Titan Panel / other LDB displays**: the "Pardona" launcher behaves like the minimap button; its text
  lists the addon statuses. Hide the minimap button via the overview checkbox if you prefer the panel.
- The Pardona menu and the standalone overview window use the style API's `"panel"` variant (since MINOR 4).

## Menu entries (MINOR 6)

An addon can add its own entries to the shared Pardona menu with `info.menu`. They appear indented
below the addon's row (icon and name, which still calls `onClick`).

### Entry

```lua
{
    text = "Lock frames",                 -- string or function() -> string; required, not empty
    onClick = function(button) ... end,   -- required
    checked = function() return db.locked end, -- optional: bool or function; check mark only for exactly true
    disabled = false,                     -- optional: bool or function; disabled only for exactly true
    tooltip = "Locks all frames.",        -- optional: string or function() -> string
}
```

- `info.menu` is either a **function** that returns the list of entries or the **list** itself.
- It is evaluated again **every time the menu opens** – nothing is cached, so texts and check marks are
  always current. Field functions are called the same way.
- Errors in `info.menu` or in a field function are reported through `geterrorhandler()`; the field then
  counts as missing (an error in `info.menu` itself means no entries). Secret values count as missing.
- Entries without a non-empty `text` or without an `onClick` function are skipped. At most 12 entries per
  addon are shown.
- Calling `RegisterAddon` again with the same id replaces `info.menu` together with the other fields.

### Display

- Entries are indented, without icon, in `GameFontHighlightSmall`.
- `checked`: a check mark before the text; unchecked entries keep the same indent.
- `disabled`: grey text, no highlight, no click; the menu stays open.
- `tooltip`: shown on mouse-over (right of the entry, wrapped).
- A click closes the menu first and then calls `onClick(button)`. Errors in `onClick` are reported
  through `geterrorhandler()`.
- When at least one addon has entries, the addon groups are separated by a small gap.

### Behaviour

- **One addon** with at least one entry: left-click opens the menu (instead of calling `onClick`).
  Without entries the addon's `onClick` is still called directly. The tooltip hint follows this
  ("Left-click: <name> menu" instead of "Left-click: open <name>").
- **Several addons**: the menu as before, now with the entries of each addon below its row.
- Minimap button, addon compartment and LibDataBroker launcher behave the same.
- The menu is a plain frame: entries cannot run secure actions (casting, targeting, protected frames).
  Combat restrictions are the addon's responsibility – e.g. return `disabled = true` while
  `InCombatLockdown()` is true, or check it in `onClick`.

### Version check

`LP.MENU_VERSION` is `1` since MINOR 6. Older copies of the library ignore `info.menu`, so passing it is
always safe; check the version only if your addon needs to know whether the entries are shown:

```lua
if LP.MENU_VERSION then
    -- menu entries are available
end
```

### Example

```lua
LP:RegisterAddon("BuffReminder", {
    name = "Buff Reminder",
    addon = ADDON,
    icon = "Interface\\AddOns\\PardonasBuffReminder\\Textures\\Icon",
    db = BuffReminderDB,
    onClick = function() LP:OpenSettings("BuffReminder") end,
    menu = function()
        return {
            {
                text = function() return BuffReminderDB.locked and "Unlock (move)" or "Lock" end,
                checked = function() return BuffReminderDB.locked == true end,
                tooltip = "Lock or move the reminder frame.",
                onClick = function() ToggleLock() end,
            },
            {
                text = "Test",
                tooltip = "Shows all reminders for a few seconds.",
                disabled = function() return InCombatLockdown() end,
                onClick = function() ShowTestReminders() end,
            },
        }
    end,
})
```

## Diagnostics (MINOR 6)

Shows at a glance which library copy is active, which Pardona addons are loaded with which library
MINOR, and which other copies are loaded (e.g. the test addon).

### What is recorded

- Every copy of `LibPardona-1.0.lua` reads the folder name of its embedding addon from the file vararg
  (`local ADDON_NAME = ...`, first value; `"?"` if it is not a non-empty string).
- Right after `LibStub:NewLibrary`, **every** copy records itself as `{ addon, minor }` in `LP.copies` of
  the active library – also copies that do not win. The same `addon`/`minor` pair is recorded only once.
- The winning copy sets `LP.activeFrom` to its folder name.
- Copies with **MINOR ≤ 5** do not know this mechanism and never record themselves; addons that ship
  such a copy are shown with `Lib < 6`.
- The library MINOR of a registered addon is matched via `info.addon`; an addon without `info.addon`
  is always shown as `< 6`.

### Chat command

- `/pardona` – prints the diagnostics in the chat:

  ```
  Pardona: Active library: MINOR 6 (from LibPardonaTest), style 1, menu 1
  Pardona: Buff Reminder 1.3.0 – Lib 6
  Pardona: ToolTips dev – Lib < 6
  Pardona: Other copies: LibPardonaTest (6)
  ```

  One line per registered addon (name, version as in the overview, library MINOR). The last line only
  appears if copies of addons that are not registered are loaded. A missing `STYLE_VERSION` or
  `MENU_VERSION` is shown as `-`. German clients: `Lib aktiv: MINOR 6 (aus …), Stil 1, Menü 1` and
  `Weitere Kopien: …`.
- `/pardona show` – opens the overview (case does not matter).

The slash command is set again by every winning copy and dispatches through `LP`, so it always runs the
code of the newest MINOR.

### Overview

The addon table of "Pardona's Addons" has a **Lib** column (library MINOR or `< 6`). Below the
*Show minimap button* checkbox a footer (`GameFontDisableSmall`, colour `LP.Style.colors.hint`) shows the
first chat line and, if there are any, the other copies. Column and footer are updated on every refresh,
also in the standalone window without Settings API (which grows with its content). Overview frames
created by an older MINOR are rebuilt or get the missing parts retrofitted.

### `LP:GetDiagnostics()`

Returns a new table on every call:

```lua
{
    minor = 6,                      -- LP.minor of the active copy
    from = "LibPardonaTest",        -- folder of the active copy, or "?"
    styleVersion = 1, menuVersion = 1, diagnosticsVersion = 1,
    addons = {                      -- in registration order
        { id = "BuffReminder", name = "Buff Reminder", addon = "PardonasBuffReminder",
          version = "1.3.0",        -- as in the overview, also "dev" or "-"
          libMinor = 6 },           -- highest recorded MINOR of info.addon, nil if unknown (< 6)
    },
    copies = {                      -- all recorded copies, sorted by addon
        { addon = "LibPardonaTest", minor = 6, registered = true },
    },
}
```

`registered` is `true` if a registered addon passes this folder as `info.addon`.

Example – debug output of an addon (older copies have no `GetDiagnostics`):

```lua
if LP.GetDiagnostics then
    local diag = LP:GetDiagnostics()
    print("LibPardona MINOR " .. diag.minor .. " from " .. diag.from)
    for _, info in ipairs(diag.addons) do
        print(info.name, info.version, info.libMinor or "< 6")
    end
end
```

### Version check

`LP.DIAGNOSTICS_VERSION` is `1` since MINOR 6.

## Conventions for Pardona addons

- **Key bindings** go into the addon's `Bindings.xml` with `category="Pardona's Addons"` (exactly this
  text) and the header token `PARDONAS<ADDON>`, e.g. from the Buff Reminder:

  ```xml
  <Binding name="CLICK PardonasBuffReminderKeyButton:LeftButton" category="Pardona's Addons" header="PARDONASBUFFREMINDER"></Binding>
  ```

  Define the header text as `BINDING_HEADER_PARDONAS<ADDON>` and, as fallback, also as
  `BINDING_NAME_HEADER_PARDONAS<ADDON>`.
- **Visible texts** use only characters from Windows-1252 (e.g. no `→`; write `->` instead).

## Style API (MINOR 4)

A shared "Pardona" look (dark purple gradient, gold border) for any frame – your own frames as well as
Blizzard frames. It lives in `LibPardona-1.0\Style.lua`, which `lib-pardona.xml` loads automatically.

### Version check

`LP.STYLE_VERSION` is `1` since MINOR 4. Older copies of the library (MINOR ≤ 3) have no style API, and
LibStub may hand you such a copy if another addon ships an older version. Always check first:

```lua
local LP = LibStub("LibPardona-1.0")
if LP.STYLE_VERSION then
    LP:ApplyStyle(myFrame, { variant = "panel" })
end
```

### `LP.Style` (read only)

Colours are `{ r, g, b, a }`. The values are those of the Buff Reminder style "pardona".

| Key | Value |
| --- | --- |
| `colors.bgTop` | `{ 0.20, 0.09, 0.30, 0.94 }` |
| `colors.bgBottom` / `colors.background` | `{ 0.08, 0.03, 0.13, 0.94 }` |
| `colors.border` / `colors.gold` | `{ 0.85, 0.68, 0.25, 1 }` |
| `colors.title` | `{ 1, 0.82, 0.25, 1 }` |
| `colors.text` / `colors.value` | `{ 0.95, 0.93, 1, 1 }` |
| `colors.hint` | `{ 0.66, 0.58, 0.76, 1 }` |
| `colors.label` / `colors.section` | `{ 0.85, 0.68, 0.25, 1 }` |
| `colors.separator` | `{ 0.85, 0.68, 0.25, 0.35 }` |
| `colors.buttonBg` | `{ 0.28, 0.14, 0.40, 0.9 }` |
| `colors.buttonBorder` | `{ 0.85, 0.68, 0.25, 0.8 }` |
| `colors.accent` | `{ 0.45, 0.25, 0.65, 1 }` |
| `colors.positive` | `{ 0.35, 0.8, 0.3, 1 }` |
| `colors.negative` | `{ 0.9, 0.15, 0.15, 1 }` |
| `edge` | `{ file = "Interface\\Tooltips\\UI-Tooltip-Border", size = 12, inset = 3 }` (rounded edge) |
| `thin` | `{ file = "Interface\\Buttons\\WHITE8X8", size = 1 }` (1-px edge) |
| `textures` | `white` = `Interface\Buttons\WHITE8X8`, `edge` = `edge.file`, `highlight` = `Interface\QuestFrame\UI-QuestTitleHighlight` |
| `fonts.title` | `{ font = "GameFontNormal", color = colors.title }` |
| `fonts.text` | `{ font = "GameFontHighlight", color = colors.text }` |
| `fonts.hint` | `{ font = "GameFontDisableSmall", color = colors.hint }` |
| `fonts.number` | `{ font = "NumberFontNormal", color = colors.text }` |

Aliases (`background`, `gold`, `value`, `section`) are the same table as their source colour.

### Functions

| Call | Returns | Description |
| --- | --- | --- |
| `LP:ApplyStyle(frame, opts)` | `true` / `"queued"` / `false` | Styles a frame (variants `panel`, `tooltip`, `thin`, `button`). |
| `LP:RemoveStyle(obj)` | `true` / `"queued"` / `false` | Restores everything exactly; `obj` is a frame or a FontString. Also restores all FontStrings styled with this `owner`. `false` if nothing was styled. |
| `LP:IsStyled(obj)` | `variant` or `nil`, `queued` | Variant (`"panel"`, `"tooltip"`, `"thin"`, `"button"`, `"icon"`, `"statusbar"`, `"font"`) and `true` as second value if a call is queued for combat end. |
| `LP:SetStyleBorderColor(frame, r, g, b, a)` | `true` / `"queued"` / `false` | Recolours the border without rebuilding (all variants incl. icon and status bar). `r = nil` resets to the variant's default. Does nothing (`false`) on frames that are not styled. |
| `LP:StyleIconBorder(button, opts)` | `true` / `"queued"` / `false` | Variant `"icon"`: square 1-px border around the icon, optional crop. |
| `LP:StyleStatusBar(bar, opts)` | `true` / `"queued"` / `false` | Variant `"statusbar"`: own background behind the bar and a thin border; optional fill colour / texture. |
| `LP:StyleFontString(fs, role, owner)` | `true` / `false` | Sets font object and colour of `role` (`title`, `text`, `hint`, `number`). With `owner`, `RemoveStyle(owner)` also restores `fs`; without, use `RemoveStyle(fs)`. Never queued. |

`false` means: invalid argument, forbidden frame (`IsForbidden`), unknown variant or an error (reported
through `geterrorhandler()`).

### `ApplyStyle` options

| Field | Default | |
| --- | --- | --- |
| `variant` | `"panel"` | `"panel"`: vertical gradient `bgTop` → `bgBottom`, rounded edge (`edge`, size 12), background inset by `edge.inset`. `"tooltip"`: like panel; never changes fonts or scale. `"thin"`: flat `colors.background`, 1-px border. `"button"`: `buttonBg`, `buttonBorder`, rounded edge and a highlight texture (`textures.highlight`, blend mode `ADD`) in the `HIGHLIGHT` layer. |
| `alpha` | `1` | Factor 0–1 on the background alpha. |
| `rounded` | `true` for panel, tooltip, button; `false` for thin | `false`: square 1-px border (`WHITE8X8`). |
| `borderColor` | variant default | `{ r, g, b, a }`. |
| `offsets` | all `0` | `{ left = , right = , top = , bottom = }` (or `{ left, right, top, bottom }`); positive values move background and border inwards. |
| `hide` | – | List of regions / child frames to hide. `frame.NineSlice` is always included when present. |
| `frameLevelOffset` | `0` | The border frame gets the target's frame level + 1 + offset (at least 0). |

### `StyleIconBorder` options

| Field | Default | |
| --- | --- | --- |
| `icon` | `button.Icon` or `button.icon` | The icon texture the border is drawn around. Without an icon the border surrounds the button. |
| `crop` | `true` | `SetTexCoord(0.08, 0.92, 0.08, 0.92)`; the original coords are read with `GetTexCoord` and restored by `RemoveStyle`. Unreadable (secret) coords: no crop. |
| `borderColor` | `colors.border` | `{ r, g, b, a }`. |
| `hide`, `frameLevelOffset` | – | As for `ApplyStyle`. |

### `StyleStatusBar` options

| Field | Default | |
| --- | --- | --- |
| `fill` | – | `{ r, g, b, a }`: `SetStatusBarColor`; the original colour (`GetStatusBarColor`) is restored by `RemoveStyle`. Without `fill` the fill colour stays untouched. |
| `texture` | – | `SetStatusBarTexture`; the original (`GetStatusBarTexture():GetTexture()`) is restored by `RemoveStyle`. |
| `alpha` | `1` | Factor on the background alpha (`colors.background`). |
| `borderColor`, `hide`, `offsets`, `frameLevelOffset` | – | As for `ApplyStyle`. |

The library never reads or sets status bar values (`GetValue`, `SetValue`, `GetMinMaxValues`,
`SetMinMaxValues`) – they may be secret values. It works on `GameTooltipStatusBar` as well.

### Rules

- **Foreign frames are fine.** The library only adds its own parts: background textures on the target
  (layer `BACKGROUND`, sublevel -8, anchored with `SetPoint`, no fixed size), a plain child frame for
  the border (mouse disabled) and, for buttons, a `HIGHLIGHT` texture.
- **Border from own textures, no size maths.** The border is built from the library's own textures
  (8 pieces of `edge.file` for the rounded edge, 4 one-pixel lines for the thin one) in the `BORDER`
  layer of that child frame, placed with anchors only. There is no `BackdropTemplate`, no
  `OnSizeChanged` script and no `GetWidth` / `GetHeight` / `GetSize` / `GetRect` on target or border,
  so it also works on frames with secret sizes (tooltips with secret content). Edges are stretched,
  not tiled. Since MINOR 5; borders built by MINOR 4 with `BackdropTemplate` are replaced on upgrade.
- **Only `SetAlpha`.** Hidden parts are set to alpha 0 after remembering their original alpha; there is no
  `Hide`/`Show` on foreign parts. Regions whose alpha is a secret value are skipped.
- **No fields in Blizzard frames.** All data lives in the library's registry (`LP.styleRegistry`, weak keys).
- **Never changed on the target:** position, size, scale, parent, strata, scripts, secure attributes.
  Blizzard functions are never replaced; only `hooksecurefunc` / `HookScript` are used.
- **Idempotent.** Calling `ApplyStyle` (or `StyleIconBorder` / `StyleStatusBar`) again updates variant,
  colours, alpha, offsets and `hide` of the existing record without creating anything twice; regions that
  are no longer listed in `hide` are restored. `opts.borderColor` of the latest call replaces a colour set
  with `SetStyleBorderColor`.
- **Exact restore.** `RemoveStyle` restores the original alpha of every hidden part, icon tex coords, status
  bar colour/texture and font object/colour of the owned FontStrings. The library's own parts are hidden
  and kept for reuse. Works on visible frames too.

### Combat

If `frame:IsProtected()` and `InCombatLockdown()` are both true, `ApplyStyle`, `RemoveStyle`,
`SetStyleBorderColor`, `StyleIconBorder` and `StyleStatusBar` do nothing yet and return `"queued"`.
The call runs at `PLAYER_REGEN_ENABLED`. The last call per frame wins (a `RemoveStyle` replaces a queued
apply). `LP:IsStyled(frame)` returns `true` as second value while a call is queued. `StyleFontString`
is never queued (FontStrings are not protected).

### Tooltip hook

The library installs `hooksecurefunc("SharedTooltip_SetBackdropStyle", …)` exactly once – across all
embedded copies and MINOR upgrades – and also hooks `GameTooltip_SetBackdropStyle` if the client has it
as a separate function. When Blizzard re-applies a tooltip backdrop, a tooltip styled with
`variant = "tooltip"` gets its `NineSlice` and `hide` parts hidden again and its stored border colour
(`SetStyleBorderColor`) re-applied. The hook always calls the code of the newest MINOR.

### Examples

Field names of Blizzard frames differ between client versions – check them before use.

```lua
local LP = LibStub("LibPardona-1.0")
if not LP.STYLE_VERSION then return end

-- Loot window: panel, hide the default background (NineSlice is hidden automatically)
if LootFrame then
    local hide = {}
    if LootFrame.Bg then hide[#hide + 1] = LootFrame.Bg end
    LP:ApplyStyle(LootFrame, { variant = "panel", hide = hide })
    -- LP:RemoveStyle(LootFrame)
end

-- Game tooltip: tooltip variant, border in the item's quality colour
LP:ApplyStyle(GameTooltip, { variant = "tooltip" })
if TooltipDataProcessor and Enum and Enum.TooltipDataType and C_Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip then return end
        local id = data and data.id
        local quality = id and not issecretvalue(id) and C_Item.GetItemQualityByID(id)
        if quality and not issecretvalue(quality) then
            local r, g, b = C_Item.GetItemQualityColor(quality)
            LP:SetStyleBorderColor(tooltip, r, g, b, 1)
        else
            LP:SetStyleBorderColor(tooltip, nil) -- back to gold
        end
    end)
end
-- LP:RemoveStyle(GameTooltip)

-- Aura button: 1-px icon border with cropped icon
local aura = BuffFrame and BuffFrame.auraFrames and BuffFrame.auraFrames[1]
if aura then
    LP:StyleIconBorder(aura, { icon = aura.Icon })
    -- LP:RemoveStyle(aura)
end

-- Loot roll timer: status bar in gold (the value is never touched)
local timer = GroupLootFrame1 and GroupLootFrame1.Timer
if timer then
    LP:StyleStatusBar(timer, { fill = LP.Style.colors.gold })
    -- LP:RemoveStyle(timer)
end

-- FontString with owner: restored together with the owner
local title = LootFrame and LootFrame.TitleContainer and LootFrame.TitleContainer.TitleText
if title then
    LP:StyleFontString(title, "title", LootFrame)
    -- LP:RemoveStyle(LootFrame) restores LootFrame and its title
end
```

## Development

- Branches: `develop` holds the next version, `main` is stable. Library tags are only created for stable
  versions (`X.Y.Z`); there are no beta tags.
- `luacheck .` must report 0 warnings / 0 errors (`LibStub/` is the unmodified official file and excluded).
  CI additionally compiles every own `.lua` file with `luac5.1 -p` (Lua 5.1 compiler limits).
- Bump `MINOR` in `LibPardona-1.0.lua` with every behaviour change and keep `STYLE_FILE_MINOR` in
  `Style.lua` equal to it; a newer MINOR must keep working with state created by older copies.
- Source artwork is in `media/` (not packaged).

### Test addon

`tools/LibPardonaTest` is an in-game test addon for the style API, the menu entries and the diagnostics (English only, not
packaged). It registers five menu entries: *Demo window* (like `/lptest demo`), *Tooltip style* (like
`/lptest tip`, checked while the tooltip style is on), *Click counter: N* (dynamic text), *Disabled entry*
and *Error test* (raises a Lua error on purpose). Install it
together with the current library checkout:

```powershell
.\tools\install-test.ps1
```

Without parameters it installs into the default WoW Forever folder
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`. For a different installation pass
the AddOns folder explicitly:

```powershell
.\tools\install-test.ps1 -AddOnsPath "<…>\Interface\AddOns"
```

The script deletes and recreates only `<AddOnsPath>\LibPardonaTest` and copies `lib-pardona.xml`,
`LibStub\` and `LibPardona-1.0\` to `LibPardonaTest\Libs\lib-pardona\`. If it gets "access denied"
(Program Files), it stops with a message: start PowerShell as administrator or check the write
permissions for the WoW folder.

| Command | |
| --- | --- |
| `/lptest` | Help. |
| `/lptest demo` | Own window (panel) with a thin box, a button, a status bar (`fill = colors.gold`), an icon and four FontStrings. Second call: `RemoveStyle` on everything, third: style again. |
| `/lptest char` | Panel style on `CharacterFrame` on/off. |
| `/lptest tip` | Tooltip style on `GameTooltip`, `ItemRefTooltip`, `ShoppingTooltip1/2`, `EmbeddedItemTooltip` on/off. |
| `/lptest border <r> <g> <b>` / `border reset` | `SetStyleBorderColor` on `GameTooltip` and `ItemRefTooltip`. |
| `/lptest alpha <0-1>` | Re-applies the tooltip style with this alpha. |
| `/lptest bar` | `StyleStatusBar` on `GameTooltipStatusBar` on/off (no fill). |
| `/lptest combat` | Thin style on `PlayerFrame` on/off; prints `true` / `queued` / `false`. |
| `/lptest minimap` | Calls `LP:RefreshMinimapButton()` and prints `GetMinimapShape()`. |
| `/lptest status` | `LP.minor`, `LP.STYLE_VERSION`, `LP.MENU_VERSION`, `LP.DIAGNOSTICS_VERSION`, `LP.activeFrom` and both `IsStyled` values of all test targets. |
| `/lptest diag` | Prints `LP:GetDiagnostics()` field by field: `minor`, `from`, the three versions, `id`/`addon`/`version`/`libMinor` of every addon and `addon`/`minor`/`registered` of every recorded copy. Shows the folder names read from the file vararg. |
| `/lptest audit` | Lists every entry of `LP.styleRegistry` with its variant and whether its border frame has a `SetBackdrop` method or a `backdropInfo` field (both expected: no). Ends with `audit ok` or the number of findings. |
| `/lptest nomenu` | Toggles whether the test addon passes `menu` and registers again with the same id; prints `menu entries on` / `menu entries off`. |

## Changelog

- **1.2.0 (MINOR 6)**: Per-addon menu entries (`info.menu`, `LP.MENU_VERSION`); one addon with entries
  opens the menu; minimap button hide/show also applied when the minimap size is secret. Suite
  diagnostics: every copy records its embedding addon, `/pardona` chat output, *Lib* column and footer
  in the overview, `LP:GetDiagnostics()`, `LP.DIAGNOSTICS_VERSION`.
- **1.1.1 (MINOR 5)**: Style borders without `BackdropTemplate`; fixes the taint error in
  `Backdrop.lua` (arithmetic on a secret frame size, e.g. tooltips). Secret-value guard for the minimap size.
- **1.1.0 (MINOR 4)**: Style API.
- **1.0.2 (MINOR 3)**: `info.addon` for version and emblem textures.

## License

MIT – see [LICENSE](LICENSE). LibStub is in the public domain.
