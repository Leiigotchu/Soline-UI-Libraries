--[[
	Soline UI Library
	A general-purpose Roblox interface library (window, tabs, button, toggle, slider, dropdown).

	Usage:
		local Soline = require(path.to.Soline)
		local Window = Soline:CreateWindow({ Title = "My App" })
		local Tab = Window:CreateTab("Main")
		Tab:CreateButton({ Text = "Click me", Callback = function() end })

	This module only builds and parents GUI Instances. It has no game-specific
	logic, no networking, and no automation — it is a visual component kit,
	nothing more. Wire it up to whatever your own project needs.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Soline = {}
Soline.__index = Soline

-- ============================================================
-- THEME
-- ============================================================
local Theme = {
	Background   = Color3.fromRGB(21, 22, 28),
	Panel        = Color3.fromRGB(29, 30, 39),
	PanelLight   = Color3.fromRGB(37, 38, 49),
	Border       = Color3.fromRGB(46, 48, 61),
	Text         = Color3.fromRGB(230, 231, 235),
	SubText      = Color3.fromRGB(138, 141, 156),
	Accent       = Color3.fromRGB(108, 123, 255),
	AccentDim    = Color3.fromRGB(70, 80, 170),
	Success      = Color3.fromRGB(74, 222, 128),
	Font         = Enum.Font.GothamMedium,
	FontBold     = Enum.Font.GothamBold,
}

Soline.Theme = Theme

-- ============================================================
-- HELPERS
-- ============================================================
local function create(className, props, children)
	local inst = Instance.new(className)
	for prop, value in pairs(props or {}) do
		inst[prop] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function tween(inst, props, time, style, dir)
	local info = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function stroke(color, thickness)
	return create("UIStroke", {
		Color = color or Theme.Border,
		Thickness = thickness or 1,
	})
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- ============================================================
-- ROOT SCREENGUI
-- ============================================================
local function getScreenGui()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local existing = playerGui:FindFirstChild("SolineUI")
	if existing then
		return existing
	end

	return create("ScreenGui", {
		Name = "SolineUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

-- ============================================================
-- WINDOW
-- ============================================================
local Window = {}
Window.__index = Window

function Soline:CreateWindow(config)
	config = config or {}
	local title = config.Title or "Soline"
	local subtitle = config.Subtitle or ""
	local size = config.Size or UDim2.fromOffset(560, 380)

	local screenGui = getScreenGui()

	local self = setmetatable({}, Window)
	self.Tabs = {}
	self._activeTab = nil

	self.Root = create("Frame", {
		Name = "Window",
		Size = size,
		Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		Parent = screenGui,
	}, {
		corner(10),
		stroke(Theme.Border, 1),
	})

	-- Title bar
	self.TitleBar = create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = self.Root,
	}, { corner(10) })

	-- mask the bottom corners of the title bar so it looks flush
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -10),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = self.TitleBar,
	})

	create("TextLabel", {
		Text = title,
		Font = Theme.FontBold,
		TextSize = 15,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 6),
		Size = UDim2.new(1, -80, 0, 18),
		Parent = self.TitleBar,
	})

	create("TextLabel", {
		Text = subtitle,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 24),
		Size = UDim2.new(1, -80, 0, 14),
		Parent = self.TitleBar,
	})

	-- signature accent line (top edge, animates to active tab's proportional position)
	self.AccentLine = create("Frame", {
		Name = "AccentLine",
		Size = UDim2.new(0, 40, 0, 2),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = self.Root,
	}, { corner(2) })

	local closeBtn = create("TextButton", {
		Text = "×",
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -38, 0, 6),
		Parent = self.TitleBar,
	})
	closeBtn.MouseEnter:Connect(function() tween(closeBtn, { TextColor3 = Theme.Text }, 0.15) end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, { TextColor3 = Theme.SubText }, 0.15) end)
	closeBtn.MouseButton1Click:Connect(function()
		self.Root.Visible = false
	end)

	local minBtn = create("TextButton", {
		Text = "–",
		Font = Theme.FontBold,
		TextSize = 20,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -70, 0, 6),
		Parent = self.TitleBar,
	})
	local minimized = false
	minBtn.MouseEnter:Connect(function() tween(minBtn, { TextColor3 = Theme.Text }, 0.15) end)
	minBtn.MouseLeave:Connect(function() tween(minBtn, { TextColor3 = Theme.SubText }, 0.15) end)
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		self.Body.Visible = not minimized
		tween(self.Root, { Size = minimized and UDim2.new(size.X.Scale, size.X.Offset, 0, 44) or size }, 0.2)
	end)

	makeDraggable(self.TitleBar, self.Root)

	-- Body: sidebar + content
	self.Body = create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 1,
		Parent = self.Root,
	})

	self.Sidebar = create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 140, 1, 0),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Parent = self.Body,
	})

	local sidebarList = create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	sidebarList.Parent = self.Sidebar

	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = self.Sidebar,
	})

	self.Content = create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(140, 0),
		BackgroundTransparency = 1,
		Parent = self.Body,
	})

	return self
end

function Window:CreateTab(name, icon)
	local tabButton = create("TextButton", {
		Name = name .. "TabButton",
		Text = "",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Theme.PanelLight,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = self.Sidebar,
	}, { corner(6) })

	create("TextLabel", {
		Text = name,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tabButton,
	})

	local page = create("ScrollingFrame", {
		Name = name .. "Page",
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self.Content,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = page

	local tab = {
		Button = tabButton,
		Page = page,
		Name = name,
	}

	tabButton.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	table.insert(self.Tabs, tab)

	if not self._activeTab then
		self:SelectTab(tab)
	end

	return setmetatable(tab, { __index = Soline.TabMethods })
end

function Window:SelectTab(tab)
	for _, t in ipairs(self.Tabs) do
		local isActive = t == tab
		t.Page.Visible = isActive
		tween(t.Button, { BackgroundTransparency = isActive and 0 or 1 }, 0.15)
		local label = t.Button:FindFirstChildOfClass("TextLabel")
		if label then
			tween(label, { TextColor3 = isActive and Theme.Text or Theme.SubText }, 0.15)
		end
	end
	self._activeTab = tab

	-- slide accent line under the active tab button
	local pos = tab.Button.AbsolutePosition
	local rootPos = self.Root.AbsolutePosition
	tween(self.AccentLine, {
		Position = UDim2.fromOffset(math.max(0, pos.X - rootPos.X), 0),
		Size = UDim2.new(0, tab.Button.AbsoluteSize.X, 0, 2),
	}, 0.25, Enum.EasingStyle.Quint)
end

function Window:Toggle()
	self.Root.Visible = not self.Root.Visible
end

-- ============================================================
-- TAB METHODS (components)
-- ============================================================
Soline.TabMethods = {}

function Soline.TabMethods:CreateSection(text)
	create("TextLabel", {
		Text = text,
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Page,
	})
end

function Soline.TabMethods:CreateButton(config)
	config = config or {}
	local text = config.Text or "Button"
	local callback = config.Callback or function() end

	local btn = create("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = self.Page,
	}, { corner(6), stroke(Theme.Border, 1) })

	create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	btn.MouseEnter:Connect(function() tween(btn, { BackgroundColor3 = Theme.Accent }, 0.15) end)
	btn.MouseLeave:Connect(function() tween(btn, { BackgroundColor3 = Theme.PanelLight }, 0.15) end)
	btn.MouseButton1Click:Connect(function()
		tween(btn, { BackgroundColor3 = Theme.AccentDim }, 0.08)
		task.wait(0.08)
		tween(btn, { BackgroundColor3 = Theme.Accent }, 0.15)
		callback()
	end)

	return btn
end

function Soline.TabMethods:CreateToggle(config)
	config = config or {}
	local text = config.Text or "Toggle"
	local default = config.Default or false
	local callback = config.Callback or function() end

	local state = default

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(6), stroke(Theme.Border, 1) })

	create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local track = create("Frame", {
		Size = UDim2.fromOffset(38, 20),
		Position = UDim2.new(1, -50, 0.5, -10),
		BackgroundColor3 = state and Theme.Accent or Theme.Border,
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(10) })

	local knob = create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(8) })

	local clickArea = create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = holder,
	})

	local function render()
		tween(track, { BackgroundColor3 = state and Theme.Accent or Theme.Border }, 0.15)
		tween(knob, { Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) }, 0.15)
	end

	clickArea.MouseButton1Click:Connect(function()
		state = not state
		render()
		callback(state)
	end)

	return {
		Set = function(_, value)
			state = value
			render()
			callback(state)
		end,
		Get = function() return state end,
	}
end

function Soline.TabMethods:CreateSlider(config)
	config = config or {}
	local text = config.Text or "Slider"
	local min = config.Min or 0
	local max = config.Max or 100
	local default = config.Default or min
	local callback = config.Callback or function() end

	local value = math.clamp(default, min, max)

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(6), stroke(Theme.Border, 1) })

	create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 20),
		Position = UDim2.fromOffset(12, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local valueLabel = create("TextLabel", {
		Text = tostring(value),
		Font = Theme.FontBold,
		TextSize = 13,
		TextColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(48, 20),
		Position = UDim2.new(1, -58, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	local track = create("Frame", {
		Size = UDim2.new(1, -24, 0, 6),
		Position = UDim2.fromOffset(12, 30),
		BackgroundColor3 = Theme.Border,
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(3) })

	local fill = create("Frame", {
		Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(3) })

	local dragging = false

	local function setFromX(xPos)
		local rel = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		value = math.floor(min + (max - min) * rel + 0.5)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		valueLabel.Text = tostring(value)
		callback(value)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return {
		Set = function(_, v)
			value = math.clamp(v, min, max)
			local rel = (value - min) / (max - min)
			fill.Size = UDim2.new(rel, 0, 1, 0)
			valueLabel.Text = tostring(value)
			callback(value)
		end,
		Get = function() return value end,
	}
end

function Soline.TabMethods:CreateDropdown(config)
	config = config or {}
	local text = config.Text or "Dropdown"
	local options = config.Options or {}
	local default = config.Default or options[1]
	local callback = config.Callback or function() end

	local selected = default
	local open = false

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.PanelLight,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 2,
		Parent = self.Page,
	}, { corner(6), stroke(Theme.Border, 1) })

	create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local selectedLabel = create("TextLabel", {
		Text = tostring(selected or "—"),
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -30, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	create("TextLabel", {
		Text = "▾",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 36),
		Position = UDim2.new(1, -24, 0, 0),
		Parent = holder,
	})

	local clickArea = create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 2,
		Parent = holder,
	})

	local list = create("Frame", {
		Size = UDim2.new(1, 0, 0, #options * 28),
		Position = UDim2.new(0, 0, 1, 4),
		BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
		Parent = holder,
	}, { corner(6), stroke(Theme.Border, 1) })

	local listLayout = create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	listLayout.Parent = list

	for _, option in ipairs(options) do
		local optBtn = create("TextButton", {
			Text = "",
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			ZIndex = 5,
			Parent = list,
		})
		create("TextLabel", {
			Text = tostring(option),
			Font = Theme.Font,
			TextSize = 13,
			TextColor3 = Theme.Text,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Parent = optBtn,
		})
		optBtn.MouseEnter:Connect(function() tween(optBtn, { BackgroundTransparency = 0.85 }, 0.1) end)
		optBtn.MouseLeave:Connect(function() tween(optBtn, { BackgroundTransparency = 1 }, 0.1) end)
		optBtn.MouseButton1Click:Connect(function()
			selected = option
			selectedLabel.Text = tostring(option)
			list.Visible = false
			open = false
			callback(selected)
		end)
	end

	clickArea.MouseButton1Click:Connect(function()
		open = not open
		list.Visible = open
	end)

	return {
		Set = function(_, v)
			selected = v
			selectedLabel.Text = tostring(v)
			callback(selected)
		end,
		Get = function() return selected end,
	}
end

function Soline.TabMethods:CreateLabel(text)
	return create("TextLabel", {
		Text = text,
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		BackgroundTransparency = 1,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Page,
	})
end

return Soline
