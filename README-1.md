# Soline v2

A general-purpose Roblox UI component library written in Luau. Single
ModuleScript, no external dependencies — just Roblox's built-in services
(`TweenService`, `UserInputService`).

**Components:** Window (draggable + resizable) · Tabs · Section · Accordion ·
Button · Toggle · Slider · Dropdown (single & multi-select) · TextBox (with
validation) · Color Picker (HSV + hex + presets) · Progress Bar · Loading
Spinner · Label · Notification / Toast system

**Theming:** built-in Dark and Light themes, live theme switching, and a
one-line custom accent color override — every open component retints
instantly, no rebuild required.

---

## 1. Installation

1. Create a `ModuleScript` named `Soline`, paste in `Soline.lua`. Place it
   somewhere shared, e.g. `ReplicatedStorage.Soline`.
2. From any **LocalScript** (client-side only), require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Soline = require(ReplicatedStorage:WaitForChild("Soline"))
```

That's it — see `Demo.client.lua` for a complete script exercising every
component.

---

## 2. Creating a window

```lua
local Window = Soline:CreateWindow({
    Title = "My App",
    Subtitle = "v1.0",
    Size = UDim2.fromOffset(640, 460),   -- default 620x420
    MinSize = Vector2.new(460, 320),     -- clamps manual resizing
    Resizable = true,                    -- shows a drag handle, bottom-right
})
```

The window is draggable by its title bar, resizable from the corner handle,
and has minimize (–) / close (×) controls built in.

```lua
Window:Toggle()   -- show/hide
Window:Close()    -- animated close
Window:Show()     -- force visible
Window:Destroy()  -- disconnects everything and removes the window for good
```

Always call `Window:Destroy()` when you're completely done with a window
(e.g. the player leaves that part of your UI permanently) — it walks every
tab and component and disconnects their listeners so nothing leaks over a
long play session.

---

## 3. Tabs

```lua
local MainTab = Window:CreateTab("Main")
local SettingsTab = Window:CreateTab("Settings")
```

Every component method below is called **on a tab** (or on an accordion,
which behaves like a nested tab — see §5).

---

## 4. Section headers

```lua
MainTab:CreateSection("Combat")
```

Plain, non-interactive grouping label.

---

## 5. Accordion (collapsible section)

```lua
local Advanced = MainTab:CreateAccordion({
    Title = "Advanced Options",
    Expanded = false,
})

-- Add any component to the accordion body the same way you would to a tab:
Advanced:CreateToggle({ Text = "Verbose Logging", Callback = function(v) end })
Advanced:CreateSlider({ Text = "Cache Size", Min = 16, Max = 512, Default = 128 })
```

---

## 6. Button

```lua
local Btn = MainTab:CreateButton({
    Text = "Do the thing",
    Disabled = false,
    Callback = function()
        print("Button pressed")
    end,
})

Btn:SetText("New label")
Btn:SetDisabled(true)
```

---

## 7. Toggle

```lua
local MyToggle = MainTab:CreateToggle({
    Text = "Enable Feature",
    Default = false,
    Callback = function(state) print("Toggled to", state) end,
})

MyToggle:Set(true)
print(MyToggle:Get())
```

---

## 8. Slider

```lua
local VolumeSlider = MainTab:CreateSlider({
    Text = "Volume",
    Min = 0,
    Max = 100,
    Step = 1,          -- optional, defaults to 1
    Default = 50,
    Suffix = "%",      -- optional, appended to the displayed value
    Callback = function(value) print("Volume:", value) end,
})

VolumeSlider:Set(75)
print(VolumeSlider:Get())
```

---

## 9. Dropdown

Single-select:

```lua
local QualityDropdown = MainTab:CreateDropdown({
    Text = "Quality",
    Options = { "Low", "Medium", "High", "Ultra" },
    Default = "Medium",
    Callback = function(choice) print("Selected", choice) end,
})
```

Multi-select — `Callback` receives an array of the currently-selected
options:

```lua
local ModulesDropdown = MainTab:CreateDropdown({
    Text = "Active Modules",
    Options = { "Physics", "Audio", "Networking" },
    MultiSelect = true,
    Default = { "Physics" },
    Callback = function(choices) print(table.concat(choices, ", ")) end,
})
```

```lua
QualityDropdown:Set("High")
print(QualityDropdown:Get())
```

---

## 10. TextBox

Supports an optional `Validator(text) -> ok, message` function. On invalid
input the field's border turns to the theme's error color and an inline
message appears underneath.

```lua
MainTab:CreateTextBox({
    Text = "Display Name",
    Placeholder = "Enter a name...",
    Default = "",
    Validator = function(text)
        if #text < 3 then
            return false, "Must be at least 3 characters"
        end
        return true
    end,
    Callback = function(text, isValid, enterPressed)
        print(text, isValid, enterPressed)
    end,
})
```

---

## 11. Color Picker

Click the swatch to expand an HSV field, hue strip, hex input, and a row of
preset swatches.

```lua
local Accent = MainTab:CreateColorPicker({
    Text = "Accent Color",
    Default = Color3.fromRGB(108, 123, 255),
    Presets = { Color3.fromRGB(248,113,113), Color3.fromRGB(74,222,128) }, -- optional
    Callback = function(color) print(color) end,
})

Accent:Set(Color3.fromRGB(255, 0, 0))
print(Accent:Get())
```

---

## 12. Progress Bar

```lua
local Progress = MainTab:CreateProgressBar({
    Text = "Download Progress",
    Min = 0,
    Max = 100,
    Default = 0,
    ShowPercent = true,
})

Progress:Set(75)   -- animates the fill
print(Progress:Get())
```

---

## 13. Loading Spinner

```lua
local Spinner = MainTab:CreateLoadingSpinner({ Text = "Loading..." })

Spinner:SetText("Almost done...")
Spinner:Stop()   -- stops animating and removes it
```

---

## 14. Label

```lua
MainTab:CreateLabel("Settings are saved automatically.")
```

---

## 15. Notifications (toasts)

Callable from anywhere, not tied to a tab — a stacking tray appears in the
bottom-right corner.

```lua
Soline:Notify({
    Title = "Saved",
    Message = "Your changes were saved.",
    Duration = 4,        -- seconds, optional (default 4)
    Type = "Success",    -- "Info" | "Success" | "Warning" | "Error"
})
```

Click a toast to dismiss it early, or let it auto-dismiss after `Duration`.

---

## 16. Theming

Switch the whole UI between the built-in Dark/Light themes, or apply a
custom accent color, at any time — every open window/tab/component retints
live:

```lua
Soline:SetTheme("Light")          -- or "Dark"
Soline:SetAccent(Color3.fromRGB(255, 90, 90))
print(Soline:GetTheme().Name)
```

To build a fully custom theme, copy the shape of `Soline.Themes.Dark` (see
the top of `Soline.lua`) and pass the table directly to `SetTheme`.

---

## 17. Memory management

Every component connects its event listeners through the owning tab's
internal janitor. Calling `Window:Destroy()` disconnects all of them and
destroys every Instance in one call — always do this when a window is
permanently done being used, especially if your game creates and discards
Soline windows repeatedly (e.g. a shop menu instantiated per NPC).

---

## 18. Notes on scope

Soline only creates and animates `Instance`s (Frames, TextButtons, etc.)
under a `ScreenGui` in the LocalPlayer's `PlayerGui`. It has no networking,
no automation, and no game-specific logic — what each `Callback` actually
*does* is entirely up to the code you write around it, same as any other UI
library.
