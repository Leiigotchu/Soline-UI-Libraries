--[[
	================================================================
	 Soline UI Library  —  v2.0
	================================================================
	A general-purpose, premium-styled Roblox interface library.

	Components:
		Window, Tab, Section / Accordion, Button, Toggle, Slider,
		Dropdown, TextBox, ColorPicker, ProgressBar, LoadingSpinner,
		Label, Notification (toast) system

	Design goals:
		- Single ModuleScript, zero external dependencies
		- Clean OOP structure, one section per component
		- Consistent animation language (fade / scale / slide)
		- Theming system: swap the whole palette live, light or dark,
		  or drop in a custom accent color
		- Proper `:Destroy()` / cleanup on every object so nothing
		  leaks connections when a window is torn down

	Usage:
		local Soline = require(path.to.Soline)
		local Window = Soline:CreateWindow({ Title = "My App" })
		local Tab = Window:CreateTab("Main")
		Tab:CreateButton({ Text = "Click me", Callback = function() end })

	This module only builds, styles, and parents ordinary GUI Instances.
	It has no networking and no automation — it's a visual component
	kit. What you wire each Callback up to is entirely up to your own
	project.
	================================================================
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Soline = {}
Soline.__index = Soline
Soline._version = "2.0.0"

-- ================================================================
-- SECTION 1 : THEME SYSTEM
-- ================================================================
-- Themes are plain tables of Color3 / font values. Swapping the
-- active theme walks a registry of every live component and retints
-- it, so a whole window can flip from dark to light (or to a custom
-- accent) without rebuilding anything.

local Themes = {}

Themes.Dark = {
	Name         = "Dark",
	Background   = Color3.fromRGB(21, 22, 28),
	Panel        = Color3.fromRGB(29, 30, 39),
	PanelLight   = Color3.fromRGB(37, 38, 49),
	PanelLighter = Color3.fromRGB(46, 48, 61),
	Border       = Color3.fromRGB(46, 48, 61),
	Text         = Color3.fromRGB(230, 231, 235),
	SubText      = Color3.fromRGB(138, 141, 156),
	Disabled     = Color3.fromRGB(80, 82, 94),
	Accent       = Color3.fromRGB(108, 123, 255),
	AccentDim    = Color3.fromRGB(70, 80, 170),
	AccentText   = Color3.fromRGB(255, 255, 255),
	Success      = Color3.fromRGB(74, 222, 128),
	Warning      = Color3.fromRGB(250, 204, 21),
	Error        = Color3.fromRGB(248, 113, 113),
	Shadow       = Color3.fromRGB(0, 0, 0),
}

Themes.Light = {
	Name         = "Light",
	Background   = Color3.fromRGB(246, 247, 250),
	Panel        = Color3.fromRGB(255, 255, 255),
	PanelLight   = Color3.fromRGB(237, 239, 244),
	PanelLighter = Color3.fromRGB(224, 227, 234),
	Border       = Color3.fromRGB(219, 222, 230),
	Text         = Color3.fromRGB(30, 32, 40),
	SubText      = Color3.fromRGB(108, 112, 128),
	Disabled     = Color3.fromRGB(180, 183, 192),
	Accent       = Color3.fromRGB(89, 101, 232),
	AccentDim    = Color3.fromRGB(160, 168, 245),
	AccentText   = Color3.fromRGB(255, 255, 255),
	Success      = Color3.fromRGB(34, 168, 92),
	Warning      = Color3.fromRGB(202, 152, 15),
	Error        = Color3.fromRGB(214, 68, 68),
	Shadow       = Color3.fromRGB(60, 62, 70),
}

-- Shared, non-color tokens (fonts, corner radii, animation timings)
local Tokens = {
	Font           = Enum.Font.GothamMedium,
	FontBold       = Enum.Font.GothamBold,
	FontMono       = Enum.Font.Code,
	CornerSmall    = 6,
	CornerMedium   = 8,
	CornerLarge    = 10,
	AnimFast       = 0.12,
	AnimNormal     = 0.18,
	AnimSlow       = 0.28,
}
Soline.Tokens = Tokens
Soline.Themes = Themes

-- ================================================================
-- SECTION 2 : LOW-LEVEL HELPERS
-- ================================================================

--- Builds an Instance from a class name, a property table, and an
--- optional array of children. This is the single constructor every
--- component in this file is built from.
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

--- Shorthand for a one-shot property tween. Returns the Tween object
--- so callers can :Cancel() it if the component is destroyed mid-flight.
local function tween(inst, props, time, style, dir)
	local info = TweenInfo.new(
		time or Tokens.AnimNormal,
		style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or Tokens.CornerSmall) })
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	})
end

local function padding(all)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
	})
end

--- Generic "connection bag" used by every component so its Destroy()
--- can disconnect everything it hooked up in one call.
local function newJanitor()
	local conns = {}
	return {
		Add = function(_, conn)
			table.insert(conns, conn)
			return conn
		end,
		Clean = function(_)
			for _, c in ipairs(conns) do
				if typeof(c) == "RBXScriptConnection" then
					c:Disconnect()
				elseif typeof(c) == "table" and c.Disconnect then
					c:Disconnect()
				elseif typeof(c) == "Instance" then
					c:Destroy()
				end
			end
			table.clear(conns)
		end,
	}
end

--- Clamp + round helper used by sliders and color picker.
local function round(n, step)
	step = step or 1
	return math.floor(n / step + 0.5) * step
end

--- Makes `handle` drag `target` (a Frame with Position) around the
--- screen. Returns a disconnect function.
local function makeDraggable(handle, target, onDragStart, onDragEnd)
	local dragging, dragStart, startPos
	local conns = {}

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			if onDragStart then onDragStart() end
			local changedConn
			changedConn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if onDragEnd then onDragEnd() end
					changedConn:Disconnect()
				end
			end)
		end
	end))

	table.insert(conns, handle.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end))

	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end
end

--- Makes `handle` resize `target` by dragging, clamped to a min size.
local function makeResizable(handle, target, minSize, onResize)
	local resizing, dragStart, startSize
	local conns = {}

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			dragStart = input.Position
			startSize = target.Size
			local changedConn
			changedConn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					changedConn:Disconnect()
				end
			end)
		end
	end))

	table.insert(conns, handle.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			local newX = math.max(minSize.X, startSize.X.Offset + delta.X)
			local newY = math.max(minSize.Y, startSize.Y.Offset + delta.Y)
			target.Size = UDim2.new(0, newX, 0, newY)
			if onResize then onResize(newX, newY) end
		end
	end))

	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
	end
end

-- ================================================================
-- SECTION 3 : ROOT SCREENGUI
-- ================================================================

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

-- Expose helpers on the module table so later sections (and users
-- extending the library) can reach them without re-declaring locals.
Soline._create = create
Soline._tween = tween
Soline._corner = corner
Soline._stroke = stroke
Soline._padding = padding
Soline._newJanitor = newJanitor
Soline._round = round
Soline._makeDraggable = makeDraggable
Soline._makeResizable = makeResizable
Soline._getScreenGui = getScreenGui

-- ================================================================
-- SECTION 4 : NOTIFICATION / TOAST SYSTEM
-- ================================================================
-- A single stacking toast tray, bottom-right of the screen. Any part
-- of the library (or user code) can call Soline:Notify{} at any time;
-- the tray is created lazily on first use.

local NotifyState = {
	Holder = nil,
}

local function ensureNotifyHolder()
	if NotifyState.Holder and NotifyState.Holder.Parent then
		return NotifyState.Holder
	end

	local screenGui = getScreenGui()
	local holder = create("Frame", {
		Name = "NotificationTray",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.new(0, 300, 1, -40),
		BackgroundTransparency = 1,
		Parent = screenGui,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 8),
	}).Parent = holder

	NotifyState.Holder = holder
	return holder
end

local NotifyAccentByType = {
	Success = "Success",
	Warning = "Warning",
	Error = "Error",
}

--- Soline:Notify({ Title, Message, Duration, Type })
--- Type is one of "Info" | "Success" | "Warning" | "Error".
function Soline:Notify(config)
	config = config or {}
	local title = config.Title or "Notice"
	local message = config.Message or ""
	local duration = config.Duration or 4
	local kind = config.Type or "Info"

	local theme = self:GetTheme()
	local accentKey = NotifyAccentByType[kind]
	local accentColor = accentKey and theme[accentKey] or theme.Accent

	local holder = ensureNotifyHolder()

	local card = create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = -math.floor(os.clock() * 1000),
		Parent = holder,
	}, {
		corner(Tokens.CornerMedium),
		stroke(theme.Border, 1),
		padding(12),
	})

	local accentBar = create("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Parent = card,
	}, { corner(2) })

	local textHolder = create("Frame", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -14, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = card,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}).Parent = textHolder

	create("TextLabel", {
		Text = title,
		Font = Tokens.FontBold,
		TextSize = 13,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = textHolder,
	})

	if message ~= "" then
		create("TextLabel", {
			Text = message,
			Font = Tokens.Font,
			TextSize = 12,
			TextColor3 = theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = textHolder,
		})
	end

	-- entrance: slide + fade in
	card.Position = UDim2.new(0, 40, 0, 0)
	for _, child in ipairs(card:GetDescendants()) do
		if child:IsA("TextLabel") then child.TextTransparency = 1 end
	end
	card.BackgroundTransparency = 1
	local outline = card:FindFirstChildOfClass("UIStroke")
	if outline then outline.Transparency = 1 end
	accentBar.BackgroundTransparency = 1

	tween(card, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0 }, Tokens.AnimSlow, Enum.EasingStyle.Back)
	if outline then tween(outline, { Transparency = 0 }, Tokens.AnimSlow) end
	tween(accentBar, { BackgroundTransparency = 0 }, Tokens.AnimSlow)
	for _, child in ipairs(card:GetDescendants()) do
		if child:IsA("TextLabel") then
			tween(child, { TextTransparency = child.LayoutOrder == 2 and 0.15 or 0 }, Tokens.AnimSlow)
		end
	end

	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		tween(card, { Position = UDim2.new(0, 40, 0, 0), BackgroundTransparency = 1 }, Tokens.AnimNormal)
		if outline then tween(outline, { Transparency = 1 }, Tokens.AnimNormal) end
		tween(accentBar, { BackgroundTransparency = 1 }, Tokens.AnimNormal)
		for _, child in ipairs(card:GetDescendants()) do
			if child:IsA("TextLabel") then
				tween(child, { TextTransparency = 1 }, Tokens.AnimNormal)
			end
		end
		task.delay(Tokens.AnimNormal, function()
			if card and card.Parent then card:Destroy() end
		end)
	end

	local clickToDismiss = create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 10,
		Parent = card,
	})
	clickToDismiss.MouseButton1Click:Connect(dismiss)

	task.delay(duration, dismiss)

	return { Dismiss = dismiss }
end

-- ================================================================
-- SECTION 5 : THEME REGISTRY (get / set / subscribe)
-- ================================================================
-- Every component that cares about theme changes registers a
-- "repaint" callback here. Soline:SetTheme() walks the registry and
-- calls each one with the new theme table, so a live UI can flip
-- from dark to light (or to a custom accent) instantly.

local ActiveTheme = Themes.Dark
local ThemeListeners = {}

function Soline:GetTheme()
	return ActiveTheme
end

--- Accepts either a theme name ("Dark" / "Light") or a full custom
--- theme table (see Themes.Dark for the required keys).
function Soline:SetTheme(themeOrName)
	local newTheme
	if type(themeOrName) == "string" then
		newTheme = Themes[themeOrName]
		assert(newTheme, "Unknown theme name: " .. tostring(themeOrName))
	else
		newTheme = themeOrName
	end
	ActiveTheme = newTheme
	for _, listener in ipairs(ThemeListeners) do
		local ok = pcall(listener, newTheme)
		if not ok then
			-- listener belonged to a destroyed component; ignore
		end
	end
end

--- Applies a custom accent color on top of whichever base theme
--- (Dark/Light) is currently active, without touching anything else.
function Soline:SetAccent(color3)
	local base = ActiveTheme
	local newTheme = table.clone(base)
	newTheme.Accent = color3
	newTheme.AccentDim = base.Accent:Lerp(Color3.new(0, 0, 0), 0.35)
	self:SetTheme(newTheme)
end

local function onThemeChanged(fn)
	table.insert(ThemeListeners, fn)
	return function()
		local idx = table.find(ThemeListeners, fn)
		if idx then table.remove(ThemeListeners, idx) end
	end
end

Soline._onThemeChanged = onThemeChanged

-- ================================================================
-- SECTION 6 : WINDOW
-- ================================================================

local Window = {}
Window.__index = Window

function Soline:CreateWindow(config)
	config = config or {}
	local title = config.Title or "Soline"
	local subtitle = config.Subtitle or ""
	local size = config.Size or UDim2.fromOffset(620, 420)
	local minSize = config.MinSize or Vector2.new(420, 300)
	local resizable = config.Resizable
	if resizable == nil then resizable = true end

	local theme = self:GetTheme()
	local screenGui = getScreenGui()

	local self_ = setmetatable({}, Window)
	self_.Tabs = {}
	self_._activeTab = nil
	self_._janitor = newJanitor()
	self_._minSize = minSize

	-- ---- root frame ----
	self_.Root = create("Frame", {
		Name = "Window",
		Size = size,
		Position = UDim2.new(0.5, -size.X.Offset / 2, 0.5, -size.Y.Offset / 2),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Parent = screenGui,
	}, {
		corner(Tokens.CornerLarge),
	})
	local rootStroke = stroke(theme.Border, 1)
	rootStroke.Parent = self_.Root

	-- soft drop shadow behind the window
	local shadow = create("ImageLabel", {
		Name = "Shadow",
		Image = "rbxassetid://1316045217",
		ImageColor3 = theme.Shadow,
		ImageTransparency = 0.6,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(10, 10, 118, 118),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(1, 40, 1, 40),
		ZIndex = -1,
		Parent = self_.Root,
	})

	-- ---- title bar ----
	self_.TitleBar = create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = self_.Root,
	}, { corner(Tokens.CornerLarge) })

	create("Frame", { -- masks bottom corners of the title bar
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.new(0, 0, 1, -12),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = self_.TitleBar,
	})

	local titleLabel = create("TextLabel", {
		Text = title,
		Font = Tokens.FontBold,
		TextSize = 15,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 7),
		Size = UDim2.new(1, -100, 0, 18),
		Parent = self_.TitleBar,
	})

	local subtitleLabel = create("TextLabel", {
		Text = subtitle,
		Font = Tokens.Font,
		TextSize = 12,
		TextColor3 = theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 25),
		Size = UDim2.new(1, -100, 0, 14),
		Parent = self_.TitleBar,
	})

	-- signature: animated accent line along the top edge, glides to
	-- sit under whichever tab is active
	self_.AccentLine = create("Frame", {
		Name = "AccentLine",
		Size = UDim2.new(0, 40, 0, 2),
		Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = self_.Root,
	}, { corner(2) })

	-- window control buttons (close / minimize)
	local function makeControlButton(glyph, xOffset)
		local btn = create("TextButton", {
			Text = glyph,
			Font = Tokens.FontBold,
			TextSize = 18,
			TextColor3 = theme.SubText,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.new(1, xOffset, 0, 7),
			Parent = self_.TitleBar,
		})
		self_._janitor:Add(btn.MouseEnter:Connect(function()
			tween(btn, { TextColor3 = self:GetTheme().Text }, Tokens.AnimFast)
		end))
		self_._janitor:Add(btn.MouseLeave:Connect(function()
			tween(btn, { TextColor3 = self:GetTheme().SubText }, Tokens.AnimFast)
		end))
		return btn
	end

	local closeBtn = makeControlButton("×", -40)
	self_._janitor:Add(closeBtn.MouseButton1Click:Connect(function()
		self_:Close()
	end))

	local minBtn = makeControlButton("–", -72)
	local minimized = false
	self_._janitor:Add(minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		self_.Body.Visible = not minimized
		tween(self_.Root, {
			Size = minimized and UDim2.new(size.X.Scale, size.X.Offset, 0, 46) or self_._lastSize or size,
		}, Tokens.AnimNormal)
	end))

	local dragDisconnect = makeDraggable(self_.TitleBar, self_.Root)
	self_._janitor:Add({ Disconnect = dragDisconnect })

	-- ---- body: sidebar + content ----
	self_.Body = create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -46),
		Position = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		Parent = self_.Root,
	})

	self_.Sidebar = create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 150, 1, 0),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Parent = self_.Body,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = self_.Sidebar

	create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}).Parent = self_.Sidebar

	self_.Content = create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -150, 1, 0),
		Position = UDim2.fromOffset(150, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = self_.Body,
	})

	-- ---- resize handle (bottom-right corner) ----
	if resizable then
		local resizeHandle = create("Frame", {
			Name = "ResizeHandle",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -2, 1, -2),
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			Parent = self_.Root,
		})
		create("TextLabel", {
			Text = "⋰",
			Font = Tokens.FontBold,
			TextSize = 14,
			Rotation = 0,
			TextColor3 = theme.SubText,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Parent = resizeHandle,
		})
		local resizeDisconnect = makeResizable(resizeHandle, self_.Root, minSize, function(w, h)
			self_._lastSize = UDim2.new(0, w, 0, h)
			self_:_repositionAccentLine()
		end)
		self_._janitor:Add({ Disconnect = resizeDisconnect })
	end

	self_._lastSize = size

	-- ---- theme reactivity ----
	local unsubscribe = onThemeChanged(function(newTheme)
		self_.Root.BackgroundColor3 = newTheme.Background
		rootStroke.Color = newTheme.Border
		self_.TitleBar.BackgroundColor3 = newTheme.Panel
		titleLabel.TextColor3 = newTheme.Text
		subtitleLabel.TextColor3 = newTheme.SubText
		self_.AccentLine.BackgroundColor3 = newTheme.Accent
		self_.Sidebar.BackgroundColor3 = newTheme.Panel
		shadow.ImageColor3 = newTheme.Shadow
		for _, child in ipairs(self_.TitleBar:GetChildren()) do
			if child:IsA("Frame") and child ~= self_.Sidebar then
				child.BackgroundColor3 = newTheme.Panel
			end
		end
	end)
	self_._janitor:Add({ Disconnect = unsubscribe })

	return self_
end

function Window:_repositionAccentLine()
	if not self._activeTab then return end
	local pos = self._activeTab.Button.AbsolutePosition
	local rootPos = self.Root.AbsolutePosition
	self.AccentLine.Position = UDim2.fromOffset(math.max(0, pos.X - rootPos.X), 0)
	self.AccentLine.Size = UDim2.new(0, self._activeTab.Button.AbsoluteSize.X, 0, 2)
end

function Window:Close()
	tween(self.Root, { Size = UDim2.new(0, 0, 0, 0) }, Tokens.AnimNormal, Enum.EasingStyle.Back)
	task.delay(Tokens.AnimNormal, function()
		self.Root.Visible = false
		self.Root.Size = self._lastSize
	end)
end

function Window:Toggle()
	self.Root.Visible = not self.Root.Visible
end

function Window:Show()
	self.Root.Visible = true
end

--- Fully tears down the window: disconnects every listener created
--- by the window itself and every component parented under it, then
--- destroys the Instances. Call this when you're done with a window
--- (e.g. the player closes a menu for good) to avoid leaking
--- connections across a long play session.
function Window:Destroy()
	for _, tab in ipairs(self.Tabs) do
		if tab._janitor then tab._janitor:Clean() end
	end
	self._janitor:Clean()
	self.Root:Destroy()
end

-- ================================================================
-- SECTION 7 : TABS
-- ================================================================

function Window:CreateTab(name, config)
	config = config or {}
	local theme = Soline:GetTheme()
	local janitor = newJanitor()

	local tabButton = create("TextButton", {
		Name = name .. "TabButton",
		Text = "",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = theme.PanelLight,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = self.Sidebar,
	}, { corner(Tokens.CornerSmall) })

	local label = create("TextLabel", {
		Text = name,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tabButton,
	})

	-- page is a ScrollingFrame; content slides/fades in on select
	local page = create("ScrollingFrame", {
		Name = name .. "Page",
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(12, 10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self.Content,
	})

	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = page

	local tab = setmetatable({
		Button = tabButton,
		Page = page,
		Name = name,
		_window = self,
		_janitor = janitor,
	}, { __index = Soline.TabMethods })

	janitor:Add(tabButton.MouseEnter:Connect(function()
		if self._activeTab ~= tab then
			tween(tabButton, { BackgroundTransparency = 0.85 }, Tokens.AnimFast)
		end
	end))
	janitor:Add(tabButton.MouseLeave:Connect(function()
		if self._activeTab ~= tab then
			tween(tabButton, { BackgroundTransparency = 1 }, Tokens.AnimFast)
		end
	end))
	janitor:Add(tabButton.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end))

	local unsubscribe = onThemeChanged(function(newTheme)
		if self._activeTab ~= tab then
			label.TextColor3 = newTheme.SubText
		end
		page.ScrollBarImageColor3 = newTheme.Accent
	end)
	janitor:Add({ Disconnect = unsubscribe })

	table.insert(self.Tabs, tab)

	if not self._activeTab then
		self:SelectTab(tab)
	end

	return tab
end

function Window:SelectTab(tab)
	local theme = Soline:GetTheme()

	for _, t in ipairs(self.Tabs) do
		local isActive = t == tab
		local activeLabel = t.Button:FindFirstChildOfClass("TextLabel")

		if isActive then
			-- fade + slight rise-in for the newly active page
			t.Page.Visible = true
			for _, child in ipairs(t.Page:GetChildren()) do
				if child:IsA("GuiObject") then
					child.Position = child.Position + UDim2.fromOffset(0, 6)
					tween(child, { Position = child.Position - UDim2.fromOffset(0, 6) }, Tokens.AnimNormal, Enum.EasingStyle.Quint)
				end
			end
			tween(t.Button, { BackgroundTransparency = 0 }, Tokens.AnimFast)
			if activeLabel then tween(activeLabel, { TextColor3 = theme.Text }, Tokens.AnimFast) end
		else
			if t.Page ~= tab.Page then
				t.Page.Visible = false
			end
			tween(t.Button, { BackgroundTransparency = 1 }, Tokens.AnimFast)
			if activeLabel then tween(activeLabel, { TextColor3 = theme.SubText }, Tokens.AnimFast) end
		end
	end

	self._activeTab = tab
	self:_repositionAccentLine()
end

-- ================================================================
-- SECTION 8 : TAB METHODS — shared registry
-- ================================================================
-- Every `Tab:CreateX()` component method is added to this table.
-- Components register a theme-listener via the tab's janitor so they
-- retint live and get cleaned up when the tab/window is destroyed.

Soline.TabMethods = {}

--- Plain (non-collapsible) section header, used to visually group
--- components under a heading.
function Soline.TabMethods:CreateSection(text)
	local theme = Soline:GetTheme()
	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.FontBold,
		TextSize = 12,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Page,
	})
	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		lbl.TextColor3 = t.SubText
	end) })
	return lbl
end

--- Collapsible section (accordion). Returns a handle with a nested
--- tab-like object so components can be added *inside* it using the
--- same CreateButton/CreateToggle/etc. methods.
function Soline.TabMethods:CreateAccordion(config)
	config = config or {}
	local title = config.Title or "Section"
	local expanded = config.Expanded or false
	local theme = Soline:GetTheme()

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local header = create("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = holder,
	})

	local chevron = create("TextLabel", {
		Text = "▸",
		Font = Tokens.FontBold,
		TextSize = 12,
		TextColor3 = theme.SubText,
		Rotation = expanded and 90 or 0,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20, 36),
		Position = UDim2.fromOffset(8, 0),
		Parent = header,
	})

	create("TextLabel", {
		Text = title,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.fromOffset(30, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	local body = create("Frame", {
		Position = UDim2.fromOffset(8, 36),
		Size = UDim2.new(1, -16, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = expanded,
		Parent = holder,
	})
	create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = body
	create("UIPadding", { PaddingBottom = UDim.new(0, 8) }).Parent = body

	local isExpanded = expanded
	header.MouseButton1Click:Connect(function()
		isExpanded = not isExpanded
		body.Visible = isExpanded
		tween(chevron, { Rotation = isExpanded and 90 or 0 }, Tokens.AnimFast)
	end)

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
	end) })

	-- Return a tab-shaped object so all the usual CreateX methods work
	-- inside an accordion body exactly like they do on a page.
	return setmetatable({
		Page = body,
		_window = self._window,
		_janitor = self._janitor,
	}, { __index = Soline.TabMethods })
end

function Soline.TabMethods:CreateLabel(text)
	local theme = Soline:GetTheme()
	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.Page,
	})
	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		lbl.TextColor3 = t.SubText
	end) })
	return lbl
end

-- ================================================================
-- SECTION 9 : BUTTON
-- ================================================================

function Soline.TabMethods:CreateButton(config)
	config = config or {}
	local text = config.Text or "Button"
	local callback = config.Callback or function() end
	local disabled = config.Disabled or false
	local theme = Soline:GetTheme()

	local btn = create("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not disabled,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local btnStroke = stroke(theme.Border, 1)
	btnStroke.Parent = btn

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = disabled and theme.Disabled or theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	if not disabled then
		self._janitor:Add(btn.MouseEnter:Connect(function()
			tween(btn, { BackgroundColor3 = Soline:GetTheme().Accent }, Tokens.AnimFast)
		end))
		self._janitor:Add(btn.MouseLeave:Connect(function()
			tween(btn, { BackgroundColor3 = Soline:GetTheme().PanelLight }, Tokens.AnimFast)
		end))
		self._janitor:Add(btn.MouseButton1Down:Connect(function()
			tween(btn, { BackgroundColor3 = Soline:GetTheme().AccentDim, Size = UDim2.new(1, 0, 0, 35) }, Tokens.AnimFast)
		end))
		self._janitor:Add(btn.MouseButton1Up:Connect(function()
			tween(btn, { BackgroundColor3 = Soline:GetTheme().Accent, Size = UDim2.new(1, 0, 0, 36) }, Tokens.AnimFast)
		end))
		self._janitor:Add(btn.MouseButton1Click:Connect(function()
			local ok, err = pcall(callback)
			if not ok then
				Soline:Notify({ Title = "Button callback error", Message = tostring(err), Type = "Error" })
			end
		end))
	end

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		btnStroke.Color = t.Border
		lbl.TextColor3 = disabled and t.Disabled or t.Text
		if not disabled then
			btn.BackgroundColor3 = t.PanelLight
		end
	end) })

	local api = {}
	function api:SetText(newText)
		lbl.Text = newText
	end
	function api:SetDisabled(state)
		disabled = state
		btn.Active = not disabled
		lbl.TextColor3 = disabled and Soline:GetTheme().Disabled or Soline:GetTheme().Text
	end
	return api
end

-- ================================================================
-- SECTION 10 : TOGGLE
-- ================================================================

function Soline.TabMethods:CreateToggle(config)
	config = config or {}
	local text = config.Text or "Toggle"
	local default = config.Default or false
	local callback = config.Callback or function() end
	local theme = Soline:GetTheme()

	local state = default

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local track = create("Frame", {
		Size = UDim2.fromOffset(38, 20),
		Position = UDim2.new(1, -50, 0.5, -10),
		BackgroundColor3 = state and theme.Accent or theme.Border,
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(10) })

	local knob = create("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
		BackgroundColor3 = theme.AccentText,
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
		local t = Soline:GetTheme()
		tween(track, { BackgroundColor3 = state and t.Accent or t.Border }, Tokens.AnimFast)
		tween(knob, { Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) }, Tokens.AnimFast, Enum.EasingStyle.Back)
	end

	self._janitor:Add(clickArea.MouseButton1Click:Connect(function()
		state = not state
		render()
		callback(state)
	end))

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		render()
	end) })

	return {
		Set = function(_, value)
			state = value
			render()
			callback(state)
		end,
		Get = function() return state end,
	}
end

-- ================================================================
-- SECTION 11 : SLIDER
-- ================================================================

function Soline.TabMethods:CreateSlider(config)
	config = config or {}
	local text = config.Text or "Slider"
	local min = config.Min or 0
	local max = config.Max or 100
	local step = config.Step or 1
	local default = config.Default or min
	local suffix = config.Suffix or ""
	local callback = config.Callback or function() end
	local theme = Soline:GetTheme()

	local value = round(math.clamp(default, min, max), step)

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 20),
		Position = UDim2.fromOffset(12, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local valueLabel = create("TextLabel", {
		Text = tostring(value) .. suffix,
		Font = Tokens.FontBold,
		TextSize = 13,
		TextColor3 = theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(58, 20),
		Position = UDim2.new(1, -68, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	local track = create("Frame", {
		Size = UDim2.new(1, -24, 0, 6),
		Position = UDim2.fromOffset(12, 30),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		Parent = holder,
	}, { corner(3) })

	local fill = create("Frame", {
		Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(3) })

	local handle = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
		BackgroundColor3 = theme.AccentText,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	}, { corner(7) })
	local handleStroke = stroke(theme.Accent, 2)
	handleStroke.Parent = handle

	local dragging = false

	local function setFromX(xPos)
		local rel = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		value = round(min + (max - min) * rel, step)
		value = math.clamp(value, min, max)
		local visualRel = (value - min) / (max - min)
		fill.Size = UDim2.new(visualRel, 0, 1, 0)
		handle.Position = UDim2.new(visualRel, 0, 0.5, 0)
		valueLabel.Text = tostring(value) .. suffix
		callback(value)
	end

	self._janitor:Add(track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			tween(handle, { Size = UDim2.fromOffset(18, 18) }, Tokens.AnimFast)
			setFromX(input.Position.X)
		end
	end))
	self._janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end))
	self._janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			tween(handle, { Size = UDim2.fromOffset(14, 14) }, Tokens.AnimFast)
		end
	end))

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		valueLabel.TextColor3 = t.Accent
		track.BackgroundColor3 = t.Border
		fill.BackgroundColor3 = t.Accent
		handleStroke.Color = t.Accent
	end) })

	return {
		Set = function(_, v)
			value = round(math.clamp(v, min, max), step)
			local rel = (value - min) / (max - min)
			fill.Size = UDim2.new(rel, 0, 1, 0)
			handle.Position = UDim2.new(rel, 0, 0.5, 0)
			valueLabel.Text = tostring(value) .. suffix
			callback(value)
		end,
		Get = function() return value end,
	}
end

-- ================================================================
-- SECTION 12 : DROPDOWN
-- ================================================================

function Soline.TabMethods:CreateDropdown(config)
	config = config or {}
	local text = config.Text or "Dropdown"
	local options = config.Options or {}
	local default = config.Default or options[1]
	local multiSelect = config.MultiSelect or false
	local callback = config.Callback or function() end
	local theme = Soline:GetTheme()

	local selected = multiSelect and {} or default
	if multiSelect and default then
		if type(default) == "table" then
			for _, v in ipairs(default) do selected[v] = true end
		end
	end
	local open = false

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 2,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, 0, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local function summaryText()
		if multiSelect then
			local count = 0
			for _ in pairs(selected) do count += 1 end
			return count == 0 and "None" or (count .. " selected")
		end
		return tostring(selected or "—")
	end

	local selectedLabel = create("TextLabel", {
		Text = summaryText(),
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -30, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	local chevron = create("TextLabel", {
		Text = "▾",
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.SubText,
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

	local listHeight = math.min(#options * 28, 168)
	local list = create("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 1, 4),
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(0, 0, 0, #options * 28),
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 5,
		Parent = holder,
	}, { corner(Tokens.CornerSmall) })
	local listStroke = stroke(theme.Border, 1)
	listStroke.Parent = list

	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }).Parent = list

	local optionRows = {}

	local function refreshChecks()
		for opt, row in pairs(optionRows) do
			local isSelected = multiSelect and selected[opt] or (opt == selected)
			row.Check.TextTransparency = isSelected and 0 or 1
		end
		selectedLabel.Text = summaryText()
	end

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
			Font = Tokens.Font,
			TextSize = 13,
			TextColor3 = theme.Text,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -34, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
			Parent = optBtn,
		})
		local check = create("TextLabel", {
			Text = "✓",
			Font = Tokens.FontBold,
			TextSize = 13,
			TextColor3 = theme.Accent,
			TextTransparency = 1,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(24, 28),
			Position = UDim2.new(1, -28, 0, 0),
			ZIndex = 5,
			Parent = optBtn,
		})
		optionRows[option] = { Button = optBtn, Check = check }

		self._janitor:Add(optBtn.MouseEnter:Connect(function()
			tween(optBtn, { BackgroundTransparency = 0.85 }, Tokens.AnimFast)
		end))
		self._janitor:Add(optBtn.MouseLeave:Connect(function()
			tween(optBtn, { BackgroundTransparency = 1 }, Tokens.AnimFast)
		end))
		self._janitor:Add(optBtn.MouseButton1Click:Connect(function()
			if multiSelect then
				selected[option] = not selected[option] or nil
				refreshChecks()
				local out = {}
				for k in pairs(selected) do table.insert(out, k) end
				callback(out)
			else
				selected = option
				refreshChecks()
				open = false
				list.Visible = false
				tween(chevron, { Rotation = 0 }, Tokens.AnimFast)
				callback(selected)
			end
		end))
	end
	refreshChecks()

	self._janitor:Add(clickArea.MouseButton1Click:Connect(function()
		open = not open
		list.Visible = open
		tween(list, { Size = UDim2.new(1, 0, 0, open and listHeight or 0) }, Tokens.AnimNormal)
		tween(chevron, { Rotation = open and 180 or 0 }, Tokens.AnimFast)
	end))

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		selectedLabel.TextColor3 = t.Accent
		chevron.TextColor3 = t.SubText
		list.BackgroundColor3 = t.Panel
		listStroke.Color = t.Border
		list.ScrollBarImageColor3 = t.Accent
		for _, row in pairs(optionRows) do
			row.Check.TextColor3 = t.Accent
		end
	end) })

	return {
		Set = function(_, v)
			if multiSelect then
				selected = {}
				for _, val in ipairs(v) do selected[val] = true end
			else
				selected = v
			end
			refreshChecks()
			callback(selected)
		end,
		Get = function() return selected end,
	}
end

-- ================================================================
-- SECTION 13 : TEXTBOX
-- ================================================================
-- Supports a Validator function: (text) -> boolean, errorMessage.
-- On invalid input the border turns to the theme's Error color and
-- an inline message appears under the field; it clears on focus.

function Soline.TabMethods:CreateTextBox(config)
	config = config or {}
	local text = config.Text or "Input"
	local placeholder = config.Placeholder or ""
	local default = config.Default or ""
	local clearOnFocus = config.ClearOnFocus or false
	local validator = config.Validator -- function(text) -> ok:boolean, message:string?
	local callback = config.Callback or function() end
	local theme = Soline:GetTheme()

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = holder,
	})

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.4, 0, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local box = create("TextBox", {
		Text = default,
		PlaceholderText = placeholder,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		PlaceholderColor3 = theme.SubText,
		ClearTextOnFocus = clearOnFocus,
		BackgroundColor3 = theme.PanelLighter,
		BorderSizePixel = 0,
		Size = UDim2.new(0.6, -20, 0, 26),
		Position = UDim2.new(0.4, 0, 0.5, -13),
		Parent = row,
	}, { corner(6), padding(8) })
	local boxStroke = stroke(theme.Border, 1)
	boxStroke.Parent = box

	local errorLabel = create("TextLabel", {
		Text = "",
		Font = Tokens.Font,
		TextSize = 11,
		TextColor3 = theme.Error,
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -24, 0, 0),
		Position = UDim2.fromOffset(12, 36),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = holder,
	})

	local function runValidation(value)
		if not validator then return true end
		local ok, message = validator(value)
		if ok then
			boxStroke.Color = Soline:GetTheme().Border
			errorLabel.Visible = false
			errorLabel.Text = ""
		else
			boxStroke.Color = Soline:GetTheme().Error
			errorLabel.Visible = true
			errorLabel.Text = message or "Invalid input"
		end
		return ok
	end

	self._janitor:Add(box.Focused:Connect(function()
		tween(boxStroke, { Color = Soline:GetTheme().Accent }, Tokens.AnimFast)
	end))

	self._janitor:Add(box.FocusLost:Connect(function(enterPressed)
		local ok = runValidation(box.Text)
		if not ok then
			tween(boxStroke, { Color = Soline:GetTheme().Error }, Tokens.AnimFast)
		else
			tween(boxStroke, { Color = Soline:GetTheme().Border }, Tokens.AnimFast)
		end
		callback(box.Text, ok, enterPressed)
	end))

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		box.BackgroundColor3 = t.PanelLighter
		box.TextColor3 = t.Text
		box.PlaceholderColor3 = t.SubText
		errorLabel.TextColor3 = t.Error
		if errorLabel.Visible then
			boxStroke.Color = t.Error
		else
			boxStroke.Color = t.Border
		end
	end) })

	return {
		Set = function(_, v) box.Text = v end,
		Get = function() return box.Text end,
		Validate = function() return runValidation(box.Text) end,
	}
end

-- ================================================================
-- SECTION 14 : COLOR PICKER
-- ================================================================
-- Compact swatch that expands into an HSV field + hue strip + RGB/hex
-- text entry + a row of preset swatches, matching the visual language
-- used by most professional color tools.

function Soline.TabMethods:CreateColorPicker(config)
	config = config or {}
	local text = config.Text or "Color"
	local default = config.Default or Color3.fromRGB(108, 123, 255)
	local presets = config.Presets or {
		Color3.fromRGB(248, 113, 113), Color3.fromRGB(250, 204, 21),
		Color3.fromRGB(74, 222, 128), Color3.fromRGB(96, 165, 250),
		Color3.fromRGB(192, 132, 252), Color3.fromRGB(255, 255, 255),
	}
	local callback = config.Callback or function() end
	local theme = Soline:GetTheme()

	local h, s, v = Color3.toHSV(default)
	local currentColor = default
	local open = false

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local header = create("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = holder,
	})

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	local swatch = create("Frame", {
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, -40, 0.5, -12),
		BackgroundColor3 = currentColor,
		BorderSizePixel = 0,
		Parent = header,
	}, { corner(6) })
	create("UIStroke", { Color = theme.Border, Thickness = 1 }).Parent = swatch

	local panel = create("Frame", {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = holder,
	})
	create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }).Parent = panel
	create("UIPadding", { PaddingBottom = UDim.new(0, 10) }).Parent = panel

	-- SV field
	local svField = create("Frame", {
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = panel,
	}, { corner(6) })
	create("UIGradient", { -- white → transparent (saturation axis)
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}).Parent = svField
	local blackGradientFrame = create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = svField,
	})
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}).Parent = blackGradientFrame
	create("UICorner", { CornerRadius = UDim.new(0, 6) }).Parent = blackGradientFrame

	local svCursor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.new(s, 0, 1 - v, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = svField,
	}, { corner(5), stroke(Color3.new(0, 0, 0), 1.5) })

	-- Hue strip
	local hueStrip = create("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = panel,
	}, { corner(7) })
	local hueSequence = {}
	for i = 0, 10 do
		table.insert(hueSequence, ColorSequenceKeypoint.new(i / 10, Color3.fromHSV(i / 10, 1, 1)))
	end
	create("UIGradient", { Color = ColorSequence.new(hueSequence) }).Parent = hueStrip

	local hueCursor = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(6, 18),
		Position = UDim2.new(h, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = hueStrip,
	}, { corner(3), stroke(Color3.new(0, 0, 0), 1.5) })

	-- Hex input + preset row
	local hexRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = panel,
	})
	local hexBox = create("TextBox", {
		Text = string.format("#%02X%02X%02X", currentColor.R * 255, currentColor.G * 255, currentColor.B * 255),
		Font = Tokens.FontMono,
		TextSize = 12,
		TextColor3 = theme.Text,
		BackgroundColor3 = theme.PanelLighter,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = hexRow,
	}, { corner(6), padding(8) })
	create("UIStroke", { Color = theme.Border, Thickness = 1 }).Parent = hexBox

	local presetRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = panel,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = presetRow

	local function applyColor(newColor)
		currentColor = newColor
		swatch.BackgroundColor3 = newColor
		callback(newColor)
	end

	local function updateFromHSV()
		local color = Color3.fromHSV(h, s, v)
		svField.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
		hueCursor.Position = UDim2.new(h, 0, 0.5, 0)
		hexBox.Text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
		applyColor(color)
	end

	local draggingSV, draggingHue = false, false

	self._janitor:Add(svField.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = true
		end
	end))
	self._janitor:Add(hueStrip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingHue = true
		end
	end))
	self._janitor:Add(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = false
			draggingHue = false
		end
	end))
	self._janitor:Add(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if draggingSV then
			local rel = svField.AbsolutePosition
			local size = svField.AbsoluteSize
			s = math.clamp((input.Position.X - rel.X) / size.X, 0, 1)
			v = 1 - math.clamp((input.Position.Y - rel.Y) / size.Y, 0, 1)
			updateFromHSV()
		elseif draggingHue then
			local rel = hueStrip.AbsolutePosition
			local size = hueStrip.AbsoluteSize
			h = math.clamp((input.Position.X - rel.X) / size.X, 0, 1)
			updateFromHSV()
		end
	end))

	self._janitor:Add(hexBox.FocusLost:Connect(function()
		local hex = hexBox.Text:gsub("#", "")
		if #hex == 6 and hex:match("^%x+$") then
			local r = tonumber(hex:sub(1, 2), 16) / 255
			local g = tonumber(hex:sub(3, 4), 16) / 255
			local b = tonumber(hex:sub(5, 6), 16) / 255
			local color = Color3.new(r, g, b)
			h, s, v = Color3.toHSV(color)
			updateFromHSV()
		else
			hexBox.Text = string.format("#%02X%02X%02X", currentColor.R * 255, currentColor.G * 255, currentColor.B * 255)
		end
	end))

	for _, presetColor in ipairs(presets) do
		local swatchBtn = create("TextButton", {
			Text = "",
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = presetColor,
			Parent = presetRow,
		}, { corner(5), stroke(theme.Border, 1) })
		self._janitor:Add(swatchBtn.MouseButton1Click:Connect(function()
			h, s, v = Color3.toHSV(presetColor)
			updateFromHSV()
		end))
	end

	self._janitor:Add(header.MouseButton1Click:Connect(function()
		open = not open
		panel.Visible = open
	end))

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		hexBox.BackgroundColor3 = t.PanelLighter
		hexBox.TextColor3 = t.Text
	end) })

	return {
		Set = function(_, color)
			h, s, v = Color3.toHSV(color)
			updateFromHSV()
		end,
		Get = function() return currentColor end,
	}
end

-- ================================================================
-- SECTION 15 : PROGRESS BAR
-- ================================================================

function Soline.TabMethods:CreateProgressBar(config)
	config = config or {}
	local text = config.Text or "Progress"
	local min = config.Min or 0
	local max = config.Max or 100
	local default = config.Default or min
	local showPercent = config.ShowPercent
	if showPercent == nil then showPercent = true end
	local theme = Soline:GetTheme()

	local value = math.clamp(default, min, max)

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 12,
		TextColor3 = theme.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -60, 0, 16),
		Position = UDim2.fromOffset(12, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local percentLabel = create("TextLabel", {
		Text = showPercent and (math.floor((value - min) / (max - min) * 100) .. "%") or "",
		Font = Tokens.FontBold,
		TextSize = 12,
		TextColor3 = theme.Accent,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(48, 16),
		Position = UDim2.new(1, -58, 0, 4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = holder,
	})

	local track = create("Frame", {
		Size = UDim2.new(1, -24, 0, 8),
		Position = UDim2.fromOffset(12, 24),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = holder,
	}, { corner(4) })

	local fill = create("Frame", {
		Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { corner(4) })

	-- subtle animated sheen sweeping across the fill, standard in
	-- premium progress indicators
	local sheen = create("Frame", {
		Size = UDim2.new(0.3, 0, 1, 0),
		Position = UDim2.new(-0.3, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = fill,
	})

	local sheenActive = true
	task.spawn(function()
		while sheenActive and fill.Parent do
			tween(sheen, { Position = UDim2.new(1, 0, 0, 0) }, 1.2, Enum.EasingStyle.Linear)
			task.wait(1.2)
			sheen.Position = UDim2.new(-0.3, 0, 0, 0)
			task.wait(0.4)
		end
	end)
	self._janitor:Add({ Disconnect = function() sheenActive = false end })

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		lbl.TextColor3 = t.Text
		percentLabel.TextColor3 = t.Accent
		track.BackgroundColor3 = t.Border
		fill.BackgroundColor3 = t.Accent
	end) })

	return {
		Set = function(_, v)
			value = math.clamp(v, min, max)
			local rel = (value - min) / (max - min)
			tween(fill, { Size = UDim2.new(rel, 0, 1, 0) }, Tokens.AnimNormal)
			if showPercent then
				percentLabel.Text = math.floor(rel * 100) .. "%"
			end
		end,
		Get = function() return value end,
	}
end

-- ================================================================
-- SECTION 16 : LOADING SPINNER
-- ================================================================

function Soline.TabMethods:CreateLoadingSpinner(config)
	config = config or {}
	local text = config.Text or "Loading..."
	local theme = Soline:GetTheme()

	local holder = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = theme.PanelLight,
		BorderSizePixel = 0,
		Parent = self.Page,
	}, { corner(Tokens.CornerSmall) })
	local holderStroke = stroke(theme.Border, 1)
	holderStroke.Parent = holder

	local ring = create("ImageLabel", {
		Image = "rbxassetid://4965945816", -- circular ring shape
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		ImageColor3 = theme.Accent,
		Parent = holder,
	})

	local lbl = create("TextLabel", {
		Text = text,
		Font = Tokens.Font,
		TextSize = 13,
		TextColor3 = theme.SubText,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})

	local spinning = true
	task.spawn(function()
		while spinning and ring.Parent do
			ring.Rotation = (ring.Rotation + 6) % 360
			task.wait()
		end
	end)
	self._janitor:Add({ Disconnect = function() spinning = false end })

	self._janitor:Add({ Disconnect = onThemeChanged(function(t)
		holder.BackgroundColor3 = t.PanelLight
		holderStroke.Color = t.Border
		ring.ImageColor3 = t.Accent
		lbl.TextColor3 = t.SubText
	end) })

	return {
		SetText = function(_, newText) lbl.Text = newText end,
		Stop = function(_) spinning = false; holder:Destroy() end,
	}
end

-- ================================================================
-- SECTION 17 : MODULE RETURN
-- ================================================================

return Soline
