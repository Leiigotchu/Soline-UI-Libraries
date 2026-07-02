--[[
	Soline Demo — LocalScript

	Setup:
	1. Put Soline.lua as a ModuleScript, e.g. ReplicatedStorage.Soline
	2. Put this file as a LocalScript in StarterPlayerScripts (or anywhere client-side)
	3. Update the `require` path below to match where you placed the module
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Soline = require(ReplicatedStorage:WaitForChild("Soline"))

-- 1. Create a window
local Window = Soline:CreateWindow({
	Title = "Soline",
	Subtitle = "Component demo",
	Size = UDim2.fromOffset(560, 380),
})

-- 2. Create tabs
local MainTab = Window:CreateTab("Main")
local SettingsTab = Window:CreateTab("Settings")
local AboutTab = Window:CreateTab("About")

-- 3. Add components to the Main tab
MainTab:CreateSection("Actions")

MainTab:CreateButton({
	Text = "Say Hello",
	Callback = function()
		print("Hello from Soline!")
	end,
})

MainTab:CreateToggle({
	Text = "Enable Feature",
	Default = false,
	Callback = function(state)
		print("Feature enabled:", state)
	end,
})

MainTab:CreateSection("Values")

MainTab:CreateSlider({
	Text = "Volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Callback = function(value)
		print("Volume set to", value)
	end,
})

MainTab:CreateDropdown({
	Text = "Quality",
	Options = { "Low", "Medium", "High", "Ultra" },
	Default = "Medium",
	Callback = function(choice)
		print("Quality set to", choice)
	end,
})

-- 4. Settings tab
SettingsTab:CreateSection("Preferences")

SettingsTab:CreateToggle({
	Text = "Auto-Save",
	Default = true,
	Callback = function(state)
		print("Auto-save:", state)
	end,
})

SettingsTab:CreateLabel("Changes are applied immediately and do not require a restart.")

-- 5. About tab
AboutTab:CreateLabel("Soline is a general-purpose UI component library for Roblox.")
AboutTab:CreateLabel("Built with: Window, Tabs, Button, Toggle, Slider, Dropdown.")
