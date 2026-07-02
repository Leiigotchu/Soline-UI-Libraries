--[[
	Soline Demo — LocalScript

	Setup:
	1. Put Soline.lua as a ModuleScript, e.g. ReplicatedStorage.Soline
	2. Put this file as a LocalScript in StarterPlayerScripts (or anywhere client-side)
	3. Update the `require` path below to match where you placed the module
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Soline = require(ReplicatedStorage:WaitForChild("Soline"))

-- ============================================================
-- Window
-- ============================================================
local Window = Soline:CreateWindow({
	Title = "Soline",
	Subtitle = "v2.0 component demo",
	Size = UDim2.fromOffset(640, 460),
	MinSize = Vector2.new(460, 320),
	Resizable = true,
})

local MainTab = Window:CreateTab("Main")
local InputsTab = Window:CreateTab("Inputs")
local FeedbackTab = Window:CreateTab("Feedback")
local ThemeTab = Window:CreateTab("Theme")

-- ============================================================
-- Main tab: buttons, toggles, accordion
-- ============================================================
MainTab:CreateSection("Actions")

MainTab:CreateButton({
	Text = "Say Hello",
	Callback = function()
		print("Hello from Soline!")
		Soline:Notify({ Title = "Hello", Message = "Button was pressed.", Type = "Info" })
	end,
})

MainTab:CreateButton({
	Text = "Disabled Button",
	Disabled = true,
	Callback = function() end,
})

local featureToggle = MainTab:CreateToggle({
	Text = "Enable Feature",
	Default = false,
	Callback = function(state)
		print("Feature enabled:", state)
	end,
})

local advanced = MainTab:CreateAccordion({ Title = "Advanced Options", Expanded = false })
advanced:CreateToggle({
	Text = "Verbose Logging",
	Default = false,
	Callback = function(state)
		print("Verbose logging:", state)
	end,
})
advanced:CreateSlider({
	Text = "Cache Size",
	Min = 16,
	Max = 512,
	Default = 128,
	Suffix = " MB",
	Callback = function(v) print("Cache size:", v) end,
})

-- ============================================================
-- Inputs tab: slider, dropdown, textbox, color picker
-- ============================================================
InputsTab:CreateSection("Values")

InputsTab:CreateSlider({
	Text = "Volume",
	Min = 0,
	Max = 100,
	Default = 50,
	Suffix = "%",
	Callback = function(value)
		print("Volume set to", value)
	end,
})

InputsTab:CreateDropdown({
	Text = "Quality",
	Options = { "Low", "Medium", "High", "Ultra" },
	Default = "Medium",
	Callback = function(choice)
		print("Quality set to", choice)
	end,
})

InputsTab:CreateDropdown({
	Text = "Active Modules",
	Options = { "Physics", "Audio", "Networking", "Rendering" },
	MultiSelect = true,
	Default = { "Physics" },
	Callback = function(choices)
		print("Modules enabled:", table.concat(choices, ", "))
	end,
})

InputsTab:CreateSection("Text & Color")

InputsTab:CreateTextBox({
	Text = "Display Name",
	Placeholder = "Enter a name...",
	Validator = function(text)
		if #text < 3 then
			return false, "Must be at least 3 characters"
		end
		return true
	end,
	Callback = function(text, valid)
		print("Display name:", text, "valid:", valid)
	end,
})

InputsTab:CreateColorPicker({
	Text = "Accent Color",
	Default = Color3.fromRGB(108, 123, 255),
	Callback = function(color)
		print("Color picked:", color)
	end,
})

-- ============================================================
-- Feedback tab: progress bar, spinner, notifications
-- ============================================================
FeedbackTab:CreateSection("Progress")

local progress = FeedbackTab:CreateProgressBar({
	Text = "Download Progress",
	Min = 0,
	Max = 100,
	Default = 0,
})

FeedbackTab:CreateButton({
	Text = "Simulate Progress",
	Callback = function()
		task.spawn(function()
			for i = 0, 100, 10 do
				progress:Set(i)
				task.wait(0.15)
			end
			Soline:Notify({ Title = "Download complete", Type = "Success" })
		end)
	end,
})

FeedbackTab:CreateSection("Notifications")

FeedbackTab:CreateButton({
	Text = "Show Info Toast",
	Callback = function()
		Soline:Notify({ Title = "Heads up", Message = "This is an info notification.", Type = "Info" })
	end,
})

FeedbackTab:CreateButton({
	Text = "Show Success Toast",
	Callback = function()
		Soline:Notify({ Title = "Saved", Message = "Your changes were saved.", Type = "Success" })
	end,
})

FeedbackTab:CreateButton({
	Text = "Show Warning Toast",
	Callback = function()
		Soline:Notify({ Title = "Careful", Message = "This action can't be undone.", Type = "Warning" })
	end,
})

FeedbackTab:CreateButton({
	Text = "Show Error Toast",
	Callback = function()
		Soline:Notify({ Title = "Something went wrong", Message = "Please try again.", Type = "Error" })
	end,
})

-- ============================================================
-- Theme tab: live theme switching
-- ============================================================
ThemeTab:CreateSection("Appearance")

ThemeTab:CreateDropdown({
	Text = "Theme",
	Options = { "Dark", "Light" },
	Default = "Dark",
	Callback = function(choice)
		Soline:SetTheme(choice)
	end,
})

ThemeTab:CreateColorPicker({
	Text = "Custom Accent",
	Default = Color3.fromRGB(108, 123, 255),
	Callback = function(color)
		Soline:SetAccent(color)
	end,
})

ThemeTab:CreateLabel("Theme changes apply instantly to every open tab and component.")
