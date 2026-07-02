# Soline

A general-purpose Roblox UI component library written in Luau. Ships as a
single ModuleScript with no external dependencies — just Roblox's built-in
services (`TweenService`, `UserInputService`).

Components: **Window · Tabs · Section · Button · Toggle · Slider · Dropdown · Label**

---

## 1. Installation

1. Create a `ModuleScript` named `Soline` and paste in the contents of
   `Soline.lua`. Place it somewhere shared, e.g. `ReplicatedStorage.Soline`.
2. From any **LocalScript** (client-side only — this is a GUI library, it
   does not run on the server), require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Soline = require(ReplicatedStorage:WaitForChild("Soline"))
```

That's it. No other setup.

---

## 2. Creating a window

```lua
local Window = Soline:CreateWindow({
    Title = "My App",       -- shown in the title bar
    Subtitle = "v1.0",       -- optional, shown under the title
    Size = UDim2.fromOffset(560, 380), -- optional, defaults to 560x380
})
```

The window is draggable by its title bar and has minimize (–) and close (×)
buttons built in. Calling `CreateWindow` again in the same session reuses
the same `ScreenGui` (named `SolineUI`) rather than creating duplicates.

To show/hide it in code (e.g. bound to a keypress):

```lua
Window:Toggle()
```

---

## 3. Adding tabs

Tabs live in the left sidebar. The first tab created is selected by default.

```lua
local MainTab = Window:CreateTab("Main")
local SettingsTab = Window:CreateTab("Settings")
```

Every component below is added by calling a method **on a tab**, and it
appears in that tab's scrolling page, top to bottom, in the order you call
them.

---

## 4. Adding a section header

Use this to visually group related components.

```lua
MainTab:CreateSection("Combat")
```

---

## 5. Adding a button

```lua
MainTab:CreateButton({
    Text = "Do the thing",
    Callback = function()
        print("Button pressed")
    end,
})
```

`Callback` fires once per click.

---

## 6. Adding a toggle

```lua
local MyToggle = MainTab:CreateToggle({
    Text = "Enable Feature",
    Default = false,          -- starting state
    Callback = function(state)
        print("Toggled to", state)
    end,
})
```

The returned table lets you read/set it from code:

```lua
MyToggle:Set(true)      -- flips the switch and fires Callback
print(MyToggle:Get())   -- true
```

---

## 7. Adding a slider

```lua
local VolumeSlider = MainTab:CreateSlider({
    Text = "Volume",
    Min = 0,
    Max = 100,
    Default = 50,
    Callback = function(value)
        print("Volume is now", value)
    end,
})
```

Drag anywhere on the track, or click a point to jump to it. Values are
integers between `Min` and `Max`.

```lua
VolumeSlider:Set(75)
print(VolumeSlider:Get())
```

---

## 8. Adding a dropdown

```lua
local QualityDropdown = MainTab:CreateDropdown({
    Text = "Quality",
    Options = { "Low", "Medium", "High", "Ultra" },
    Default = "Medium",
    Callback = function(choice)
        print("Selected", choice)
    end,
})
```

```lua
QualityDropdown:Set("High")
print(QualityDropdown:Get())
```

---

## 9. Adding a label

For static or informational text, not interactive.

```lua
MainTab:CreateLabel("Settings are saved automatically.")
```

---

## 10. Full example

See `Demo.client.lua` for a complete LocalScript that builds a window with
three tabs and one of every component.

---

## 11. Theming

All colors live in one table at the top of `Soline.lua`:

```lua
local Theme = {
    Background = Color3.fromRGB(21, 22, 28),
    Panel      = Color3.fromRGB(29, 30, 39),
    PanelLight = Color3.fromRGB(37, 38, 49),
    Border     = Color3.fromRGB(46, 48, 61),
    Text       = Color3.fromRGB(230, 231, 235),
    SubText    = Color3.fromRGB(138, 141, 156),
    Accent     = Color3.fromRGB(108, 123, 255),
    ...
}
```

Edit these values to re-skin every component at once — nothing else in the
file needs to change.

---

## 12. Notes on scope

Soline only creates and animates `Instance`s (Frames, TextButtons, etc.)
under a `ScreenGui` in the LocalPlayer's `PlayerGui`. It has no networking,
no automation, and no game-specific logic — what each `Callback` actually
*does* is entirely up to the code you write around it, same as any other
UI library.
