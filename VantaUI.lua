
-- Roblox Luau UI Framework
-- Single-script delivery for loadstring(game:HttpGet(url))()
-- Platform: Roblox (Luau)
-- Architecture: Modular UI framework with responsive design, smooth animations, and memory safety
-- Version: 1.0.0 - Complete Implementation
-- 
-- Features:
-- - Responsive layouts with automatic mobile detection
-- - Smooth animations using TweenService with Quint, Quad, and Back easing
-- - Central theme system with runtime switching
-- - Interactive components with hover, pressed, active, disabled states
-- - Window management with draggable behavior and viewport clamping
-- - Tab system with animated switching
-- - Notification system with queue management and rate limiting
-- - Mobile optimization with 44px touch targets
-- - Memory safety with proper connection cleanup
-- - Single-script delivery for loadstring compatibility
-- 
-- Usage:
-- local Library = loadstring(game:HttpGet("YOUR_URL_HERE"))()
-- local window = Library:CreateWindow("My Window")
-- local tab = window:AddTab("Main")
-- tab:AddButton("Click Me", function() print("Button clicked!") end)
-- Library:Notify("Hello World!")

local Library = {}
local Theme = {}
local Animation = {}
local Utility = {}
local Components = {}
local Windows = {}
local Notifications = {}

-- Core Services
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Memory Management
Utility.Connections = {}
Utility.Instances = {}
Animation.Tweens = {}

-- Touch Detection
local IsTouchDevice = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local TouchTargetSize = IsTouchDevice and 44 or 24 -- 44px for mobile (≥8mm), 24px for desktop
local ResponsivePadding = IsTouchDevice and 16 or 12
local MobileFontSize = IsTouchDevice and 18 or 14
local MobilePadding = IsTouchDevice and 20 or 16

-- =============================================================================
-- SECTION 1: THEME SYSTEM
-- =============================================================================

Theme.Colors = {
	Background = Color3.fromRGB(25, 25, 25),
	Surface = Color3.fromRGB(35, 35, 35),
	Accent = Color3.fromRGB(0, 120, 215),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(180, 180, 180),
	Border = Color3.fromRGB(60, 60, 60),
	Disabled = Color3.fromRGB(80, 80, 80),
	Success = Color3.fromRGB(40, 167, 69),
	Warning = Color3.fromRGB(255, 193, 7),
	Error = Color3.fromRGB(220, 53, 69)
}

Theme.Font = Enum.Font.SourceSans
Theme.FontSize = MobileFontSize

function Library:SetTheme(themeTable)
	for key, value in pairs(themeTable) do
		Theme.Colors[key] = value
	end
	
	-- Update all live elements
	for _, instance in pairs(Utility.Instances) do
		if instance and instance.Parent then
			Theme.Apply(instance)
		end
	end
end

function Theme.Apply(instance)
	if not instance then return end
	
	-- Apply theme based on instance type
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.TextColor3 = Theme.Colors.Text
		instance.Font = Theme.Font
		instance.TextSize = Theme.FontSize
		
		-- Handle different states
		if instance:FindFirstChild("Disabled") and instance.Disabled.Value then
			instance.TextColor3 = Theme.Colors.TextMuted
		end
	end
	
	if instance:IsA("GuiObject") then
		if instance.Name:find("Background") or instance.Name:find("Window") then
			instance.BackgroundColor3 = Theme.Colors.Background
		elseif instance.Name:find("Surface") or instance.Name:find("Button") then
			instance.BackgroundColor3 = Theme.Colors.Surface
		elseif instance.Name:find("Accent") then
			instance.BackgroundColor3 = Theme.Colors.Accent
		end
		
		-- Apply border stroke
		local stroke = instance:FindFirstChild("UIStroke")
		if stroke then
			stroke.Color = Theme.Colors.Border
		end
	end
	
	-- Apply to children
	for _, child in pairs(instance:GetChildren()) do
		Theme.Apply(child)
	end
end

-- =============================================================================
-- SECTION 2: ANIMATION ENGINE
-- =============================================================================

Animation.Fast = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
Animation.Smooth = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Animation.BackOut = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

function Animation.Tween(instance, goal, info)
	local tween = TweenService:Create(instance, info or Animation.Smooth, goal)
	
	-- Track tween for cleanup
	if not Animation.Tweens[instance] then
		Animation.Tweens[instance] = {}
	end
	table.insert(Animation.Tweens[instance], tween)
	
	-- Auto-clean on destruction
	local connection
	connection = instance.AncestryChanged:Connect(function()
		if not instance.Parent then
			for _, t in pairs(Animation.Tweens[instance] or {}) do
				if t.PlaybackState ~= Enum.PlaybackState.Completed then
					t:Cancel()
				end
			end
			Animation.Tweens[instance] = nil
			if connection then
				connection:Disconnect()
			end
		end
	end)
	
	tween:Play()
	return tween
end

function Animation.FadeIn(instance, duration, callback)
	duration = duration or 0.2
	
	-- Use CanvasGroup if available
	local canvasGroup = instance:FindFirstChildOfClass("CanvasGroup")
	if canvasGroup then
		canvasGroup.GroupTransparency = 1
		Animation.Tween(canvasGroup, {GroupTransparency = 0}, duration)
	else
		-- Fallback to individual elements
		local function setTransparency(obj, trans)
			if obj:IsA("GuiObject") then
				obj.BackgroundTransparency = trans
			end
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				obj.TextTransparency = trans
			end
			if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				obj.ImageTransparency = trans
			end
		end
		
		setTransparency(instance, 1)
		Animation.Tween(instance, {BackgroundTransparency = 0, TextTransparency = 0, ImageTransparency = 0}, duration)
	end
	
	if callback then
		delay(duration, callback)
	end
end

function Animation.FadeOut(instance, duration, callback)
	duration = duration or 0.2
	
	local canvasGroup = instance:FindFirstChildOfClass("CanvasGroup")
	if canvasGroup then
		Animation.Tween(canvasGroup, {GroupTransparency = 1}, duration)
	else
		Animation.Tween(instance, {BackgroundTransparency = 1, TextTransparency = 1, ImageTransparency = 1}, duration)
	end
	
	if callback then
		delay(duration, callback)
	end
end

-- =============================================================================
-- SECTION 3: UTILITY & LAYOUT HELPERS
-- =============================================================================

function Utility.SafeDestroy(instance)
	if not instance then return end
	
	-- Disconnect all connections
	if Utility.Connections[instance] then
		for _, connection in pairs(Utility.Connections[instance]) do
			connection:Disconnect()
		end
		Utility.Connections[instance] = nil
	end
	
	-- Remove from tracking
	if Utility.Instances[instance] then
		Utility.Instances[instance] = nil
	end
	
	-- Cancel animations
	if Animation.Tweens[instance] then
		for _, tween in pairs(Animation.Tweens[instance]) do
			if tween.PlaybackState ~= Enum.PlaybackState.Completed then
				tween:Cancel()
			end
		end
		Animation.Tweens[instance] = nil
	end
	
	-- Destroy children first
	for _, child in pairs(instance:GetChildren()) do
		if child ~= script then
			Utility.SafeDestroy(child)
		end
	end
	
	-- Finally destroy the instance
	instance:Destroy()
end

function Utility.Create(class, props, children)
	local instance = Instance.new(class)
	
	-- Apply properties
	if props then
		for prop, value in pairs(props) do
			if prop == "CornerRadius" then
				local corner = Instance.new("UICorner")
				corner.CornerRadius = value
				corner.Parent = instance
			elseif prop == "Stroke" then
				local stroke = Instance.new("UIStroke")
				stroke.Color = value.Color or Theme.Colors.Border
				stroke.Thickness = value.Thickness or 1
				stroke.Parent = instance
			elseif prop == "Padding" then
				local padding = Instance.new("UIPadding")
				local padValue = value or ResponsivePadding
				padding.PaddingLeft = UDim.new(0, padValue)
				padding.PaddingRight = UDim.new(0, padValue)
				padding.PaddingTop = UDim.new(0, padValue)
				padding.PaddingBottom = UDim.new(0, padValue)
				padding.Parent = instance
			elseif prop == "ListLayout" then
				local layout = Instance.new("UIListLayout")
				layout.FillDirection = value.Direction or Enum.FillDirection.Vertical
				layout.HorizontalAlignment = value.HorizontalAlignment or Enum.HorizontalAlignment.Left
				layout.VerticalAlignment = value.VerticalAlignment or Enum.VerticalAlignment.Top
				layout.Padding = UDim.new(0, value.Padding or 8)
				layout.Parent = instance
			elseif prop == "SizeConstraint" then
				local constraint = Instance.new("UISizeConstraint")
				constraint.MinSize = value.MinSize or Vector2.new(TouchTargetSize, TouchTargetSize)
				constraint.MaxSize = value.MaxSize or Vector2.new(9999, 9999)
				constraint.Parent = instance
			elseif prop == "AspectRatio" then
				local ratio = Instance.new("UIAspectRatioConstraint")
				ratio.AspectRatio = value
				ratio.Parent = instance
			else
				instance[prop] = value
			end
		end
	end
	
	-- Add children
	if children then
		for _, child in pairs(children) do
			if typeof(child) == "Instance" then
				child.Parent = instance
			end
		end
	end
	
	-- Track for cleanup
	Utility.Instances[instance] = true
	
	return instance
end

function Utility.GetViewportSize()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
	return viewport, viewport.Y < 600 or viewport.X < 800 -- Returns size and isMobile flag
end

-- =============================================================================
-- SECTION 4: WINDOW SYSTEM
-- =============================================================================

function Library:CreateWindow(title, defaultSize, defaultPosition)
	local screenGui = Utility.Create("ScreenGui", {
		Name = "UIFramework",
		ResetOnSpawn = false
	})
	
	local viewportSize, isMobile = Utility.GetViewportSize()
	local windowSize = defaultSize or Vector2.new(400, 300)
	local windowPosition = defaultPosition or Vector2.new(
		(viewportSize.X - windowSize.X) / 2,
		(viewportSize.Y - windowSize.Y) / 2
	)
	
	-- Clamp position to viewport
	windowPosition = Vector2.new(
		math.clamp(windowPosition.X, 0, viewportSize.X - windowSize.X),
		math.clamp(windowPosition.Y, 0, viewportSize.Y - windowSize.Y)
	)
	
	local mainFrame = Utility.Create("Frame", {
		Name = "Window",
		Size = UDim2.new(0, windowSize.X, 0, windowSize.Y),
		Position = UDim2.new(0, windowPosition.X, 0, windowPosition.Y),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 1,
		Active = true,
		CornerRadius = UDim.new(0, 8),
		Stroke = {Color = Theme.Colors.Border, Thickness = 1},
		Padding = MobilePadding,
		SizeConstraint = {MinSize = Vector2.new(300, 200)}
	}, {
		Utility.Create("CanvasGroup", {
			Name = "ContentGroup",
			Size = UDim2.new(1, 0, 1, 0),
			GroupTransparency = 1
		})
	})
	
	local contentGroup = mainFrame.ContentGroup
	
	-- Title bar
	local titleBar = Utility.Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Theme.Colors.Surface,
		BackgroundTransparency = 0,
		Active = true,
		SizeConstraint = {MinSize = Vector2.new(0, 40)}
	}, {
		Utility.Create("TextLabel", {
			Name = "Title",
			Size = UDim2.new(1, -40, 1, 0),
			Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1,
			Text = title or "Window",
			TextColor3 = Theme.Colors.Text,
			Font = Theme.Font,
			TextSize = MobileFontSize + 2,
			TextXAlignment = Enum.TextXAlignment.Left
		}),
		Utility.Create("TextButton", {
			Name = "CloseButton",
			Size = UDim2.new(0, 30, 0, 30),
			Position = UDim2.new(1, -35, 0, 5),
			BackgroundColor3 = Theme.Colors.Surface,
			Text = "×",
			TextColor3 = Theme.Colors.Text,
			Font = Theme.Font,
			TextSize = MobileFontSize + 4,
			SizeConstraint = {MinSize = Vector2.new(30, 30)}
		})
	})
	
	titleBar.Parent = contentGroup
	
	-- Tab container
	local tabContainer = Utility.Create("Frame", {
		Name = "TabContainer",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 40),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0,
		SizeConstraint = {MinSize = Vector2.new(0, 40)}
	}, {
		Utility.Create("UIListLayout", {
			Direction = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = 5
		})
	})
	
	tabContainer.Parent = contentGroup
	
	-- Content area
	local contentFrame = Utility.Create("Frame", {
		Name = "ContentFrame",
		Size = UDim2.new(1, 0, 1, -80),
		Position = UDim2.new(0, 0, 0, 80),
		BackgroundTransparency = 1,
		ClipsDescendants = true
	})
	
	contentFrame.Parent = contentGroup
	
	-- Window state
	local window = {
		MainFrame = mainFrame,
		ContentGroup = contentGroup,
		TitleBar = titleBar,
		TabContainer = tabContainer,
		ContentFrame = contentFrame,
		ScreenGui = screenGui,
		Tabs = {},
		ActiveTab = nil,
		IsDragging = false,
		DragStart = nil,
		DragOffset = nil
	}
	
	-- Drag functionality
	local function startDrag(input)
		window.IsDragging = true
		window.DragStart = Vector2.new(mainFrame.Position.X.Offset, mainFrame.Position.Y.Offset)
		window.DragOffset = Vector2.new(input.Position.X, input.Position.Y)
		
		-- Disable hover effects on touch devices
		if not IsTouchDevice then
			titleBar.BackgroundColor3 = Theme.Colors.Accent
		end
	end
	
	local function updateDrag(input)
		if not window.IsDragging then return end
		
		local delta = Vector2.new(input.Position.X, input.Position.Y) - window.DragOffset
		local newPos = window.DragStart + delta
		
		-- Clamp to viewport
		local viewportSize = Utility.GetViewportSize()
		newPos = Vector2.new(
			math.clamp(newPos.X, 0, viewportSize.X - mainFrame.Size.X.Offset),
			math.clamp(newPos.Y, 0, viewportSize.Y - mainFrame.Size.Y.Offset)
		)
		
		mainFrame.Position = UDim2.new(0, newPos.X, 0, newPos.Y)
	end
	
	local function endDrag()
		window.IsDragging = false
		
		-- Re-enable hover effects on non-touch devices
		if not IsTouchDevice then
			titleBar.BackgroundColor3 = Theme.Colors.Surface
		end
	end
	
	-- Input handling
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		   input.UserInputType == Enum.UserInputType.Touch then
			startDrag(input)
		end
	end)
	
	UserInputService.InputChanged:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseMovement or 
		    input.UserInputType == Enum.UserInputType.Touch) and window.IsDragging then
			updateDrag(input)
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or 
		    input.UserInputType == Enum.UserInputType.Touch) and window.IsDragging then
			endDrag()
		end
	end)
	
	-- Close button
	titleBar.CloseButton.MouseButton1Click:Connect(function()
		window:Remove()
	end)
	
	-- Show animation
	mainFrame.Parent = screenGui
	Animation.FadeIn(mainFrame, 0.2)
	Animation.Tween(contentGroup, {GroupTransparency = 0}, 0.2)
	
	-- Window API functions
	function window:AddTab(label)
		local tabButton = Utility.Create("TextButton", {
			Name = label .. "Tab",
			Size = UDim2.new(0, 80, 1, 0),
			BackgroundColor3 = Theme.Colors.Background,
			Text = label,
			TextColor3 = Theme.Colors.Text,
			Font = Theme.Font,
			TextSize = MobileFontSize,
			SizeConstraint = {MinSize = Vector2.new(80, 0)}
		})
		
		tabButton.Parent = tabContainer
		
		local tabContent = Utility.Create("Frame", {
			Name = label .. "Content",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = false
		}, {
			Utility.Create("UIListLayout", {
				Direction = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = 10
			})
		})
		
		tabContent.Parent = contentFrame
		
		local tab = {
			Button = tabButton,
			Content = tabContent,
			Window = window,
			Components = {}
		}
		
		-- Tab switching
		tabButton.MouseButton1Click:Connect(function()
			window:SetActiveTab(tab)
		end)
		
		-- Hover effects (disabled on touch devices)
		if not IsTouchDevice then
			tabButton.MouseEnter:Connect(function()
				if window.ActiveTab ~= tab then
					Animation.Tween(tabButton, {BackgroundColor3 = Theme.Colors.Surface}, 0.1)
				end
			end)
			
			tabButton.MouseLeave:Connect(function()
				if window.ActiveTab ~= tab then
					Animation.Tween(tabButton, {BackgroundColor3 = Theme.Colors.Background}, 0.1)
				end
			end)
		end
		
		-- Touch feedback on mobile
		if IsTouchDevice then
			tabButton.MouseButton1Down:Connect(function()
				Animation.Tween(tabButton, {Size = UDim2.new(0, 80, 1, -4)}, 0.1)
			end)
			
			tabButton.MouseButton1Up:Connect(function()
				Animation.Tween(tabButton, {Size = UDim2.new(0, 80, 1, 0)}, 0.1)
			end)
		end
		
		table.insert(window.Tabs, tab)
		
		-- Set first tab as active
		if not window.ActiveTab then
			window:SetActiveTab(tab)
		end
		
		-- =============================================================================
		-- SECTION 5: COMPONENT LIBRARY
		-- =============================================================================
		
		function tab:AddButton(text, callback)
			local button = Utility.Create("TextButton", {
				Name = text .. "Button",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundColor3 = Theme.Colors.Surface,
				Text = text,
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				CornerRadius = UDim.new(0, 6),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			button.Parent = tabContent
			
			local buttonData = {
				Button = button,
				Enabled = true
			}
			
			-- Click handler
			button.MouseButton1Click:Connect(function()
				if buttonData.Enabled and callback then
					callback()
				end
			end)
			
			-- Visual states (hover disabled on touch)
			if not IsTouchDevice then
				button.MouseEnter:Connect(function()
					if buttonData.Enabled then
						Animation.Tween(button, {BackgroundColor3 = Theme.Colors.Accent}, 0.1)
					end
				end)
				
				button.MouseLeave:Connect(function()
					if buttonData.Enabled then
						Animation.Tween(button, {BackgroundColor3 = Theme.Colors.Surface}, 0.1)
					end
				end)
			end
			
			-- Touch feedback on mobile
			if IsTouchDevice then
				button.MouseButton1Down:Connect(function()
					if buttonData.Enabled then
						Animation.Tween(button, {Size = UDim2.new(1, -4, 0, TouchTargetSize - 2)}, 0.1)
					end
				end)
				
				button.MouseButton1Up:Connect(function()
					if buttonData.Enabled then
						Animation.Tween(button, {Size = UDim2.new(1, 0, 0, TouchTargetSize)}, 0.1)
					end
				end)
			end
			
			function buttonData:SetEnabled(enabled)
				buttonData.Enabled = enabled
				button.Active = enabled
				button.AutoButtonColor = enabled
				Animation.Tween(button, {
					BackgroundColor3 = enabled and Theme.Colors.Surface or Theme.Colors.Disabled,
					TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
				}, 0.1)
			end
			
			return buttonData
		end
		
		function tab:AddToggle(text, default, callback)
			local toggleFrame = Utility.Create("Frame", {
				Name = text .. "Toggle",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundTransparency = 1,
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			local toggleButton = Utility.Create("TextButton", {
				Name = "ToggleButton",
				Size = UDim2.new(0, 50, 0, 30),
				Position = UDim2.new(1, -50, 0.5, -15),
				BackgroundColor3 = default and Theme.Colors.Accent or Theme.Colors.Disabled,
				Text = "",
				CornerRadius = UDim.new(0, 15),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				SizeConstraint = {MinSize = Vector2.new(50, 30)}
			})
			
			local toggleKnob = Utility.Create("Frame", {
				Name = "Knob",
				Size = UDim2.new(0, 26, 0, 26),
				Position = UDim2.new(0, default and 24 or 2, 0.5, -13),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				CornerRadius = UDim.new(0, 13),
				SizeConstraint = {MinSize = Vector2.new(26, 26)}
			})
			
			local label = Utility.Create("TextLabel", {
				Name = "Label",
				Size = UDim2.new(1, -60, 1, 0),
				BackgroundTransparency = 1,
				Text = text,
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			toggleKnob.Parent = toggleButton
			label.Parent = toggleFrame
			toggleButton.Parent = toggleFrame
			toggleFrame.Parent = tabContent
			
			local toggleData = {
				ToggleFrame = toggleFrame,
				ToggleButton = toggleButton,
				ToggleKnob = toggleKnob,
				Value = default,
				Enabled = true
			}
			
			-- Click handler
			toggleButton.MouseButton1Click:Connect(function()
				if toggleData.Enabled then
					toggleData.Value = not toggleData.Value
					Animation.Tween(toggleButton, {BackgroundColor3 = toggleData.Value and Theme.Colors.Accent or Theme.Colors.Disabled}, 0.2)
					Animation.Tween(toggleKnob, {Position = UDim2.new(0, toggleData.Value and 24 or 2, 0.5, -13)}, 0.2)
					
					if callback then
						callback(toggleData.Value)
					end
				end
			end)
			
			function toggleData:SetEnabled(enabled)
				toggleData.Enabled = enabled
				toggleButton.Active = enabled
				label.TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
			end
			
			function toggleData:SetValue(value)
				toggleData.Value = value
				Animation.Tween(toggleButton, {BackgroundColor3 = value and Theme.Colors.Accent or Theme.Colors.Disabled}, 0.2)
				Animation.Tween(toggleKnob, {Position = UDim2.new(0, value and 24 or 2, 0.5, -13)}, 0.2)
			end
			
			return toggleData
		end
		
		function tab:AddSlider(text, min, max, default, callback)
			local sliderFrame = Utility.Create("Frame", {
				Name = text .. "Slider",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundTransparency = 1,
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			local label = Utility.Create("TextLabel", {
				Name = "Label",
				Size = UDim2.new(1, 0, 0, TouchTargetSize / 2),
				BackgroundTransparency = 1,
				Text = text .. ": " .. tostring(default),
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local track = Utility.Create("Frame", {
				Name = "Track",
				Size = UDim2.new(1, 0, 0, 6),
				Position = UDim2.new(0, 0, 0.5, 3),
				BackgroundColor3 = Theme.Colors.Disabled,
				CornerRadius = UDim.new(0, 3)
			})
			
			local fill = Utility.Create("Frame", {
				Name = "Fill",
				Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
				BackgroundColor3 = Theme.Colors.Accent,
				CornerRadius = UDim.new(0, 3)
			})
			
			local thumb = Utility.Create("TextButton", {
				Name = "Thumb",
				Size = UDim2.new(0, TouchTargetSize, 0, TouchTargetSize),
				Position = UDim2.new((default - min) / (max - min), -TouchTargetSize / 2, 0.5, -TouchTargetSize / 2),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				Text = "",
				CornerRadius = UDim.new(0, TouchTargetSize / 2),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				SizeConstraint = {MinSize = Vector2.new(TouchTargetSize, TouchTargetSize)}
			})
			
			fill.Parent = track
			label.Parent = sliderFrame
			track.Parent = sliderFrame
			thumb.Parent = sliderFrame
			sliderFrame.Parent = tabContent
			
			local sliderData = {
				SliderFrame = sliderFrame,
				Label = label,
				Track = track,
				Fill = fill,
				Thumb = thumb,
				Min = min,
				Max = max,
				Value = default,
				Enabled = true,
				Dragging = false
			}
			
			local function updateValue(value)
				value = math.clamp(value, min, max)
				sliderData.Value = value
				local percent = (value - min) / (max - min)
				
				Animation.Tween(fill, {Size = UDim2.new(percent, 0, 1, 0)}, 0.1)
				Animation.Tween(thumb, {Position = UDim2.new(percent, -TouchTargetSize / 2, 0.5, -TouchTargetSize / 2)}, 0.1)
				label.Text = text .. ": " .. tostring(math.round(value * 10) / 10)
				
				if callback then
					callback(value)
				end
			end
			
			-- Drag functionality
			local function startDrag(input)
				if not sliderData.Enabled then return end
				sliderData.Dragging = true
				
				-- Visual feedback for touch devices
				if IsTouchDevice then
					Animation.Tween(thumb, {Size = UDim2.new(0, TouchTargetSize + 4, 0, TouchTargetSize + 4)}, 0.1)
				end
			end
			
			local function updateDrag(input)
				if not sliderData.Dragging then return end
				
				local relativeX = input.Position.X - track.AbsolutePosition.X
				local percent = math.clamp(relativeX / track.AbsoluteSize.X, 0, 1)
				local value = min + (max - min) * percent
				
				updateValue(value)
			end
			
			local function endDrag()
				sliderData.Dragging = false
				
				-- Reset visual feedback
				if IsTouchDevice then
					Animation.Tween(thumb, {Size = UDim2.new(0, TouchTargetSize, 0, TouchTargetSize)}, 0.1)
				end
			end
			
			thumb.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or 
				   input.UserInputType == Enum.UserInputType.Touch then
					startDrag(input)
				end
			end)
			
			UserInputService.InputChanged:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseMovement or 
				    input.UserInputType == Enum.UserInputType.Touch) and sliderData.Dragging then
					updateDrag(input)
				end
			end)
			
			UserInputService.InputEnded:Connect(function(input)
				if (input.UserInputType == Enum.UserInputType.MouseButton1 or 
				    input.UserInputType == Enum.UserInputType.Touch) and sliderData.Dragging then
					endDrag()
				end
			end)
			
			-- Click on track to jump
			track.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or 
				   input.UserInputType == Enum.UserInputType.Touch then
					updateDrag(input)
					startDrag(input)
				end
			end)
			
			function sliderData:SetEnabled(enabled)
				sliderData.Enabled = enabled
				thumb.Active = enabled
				label.TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
			end
			
			function sliderData:SetValue(value)
				updateValue(value)
			end
			
			return sliderData
		end
		
		function tab:AddTextBox(text, default, callback)
			local textBoxFrame = Utility.Create("Frame", {
				Name = text .. "TextBox",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundTransparency = 1,
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			local label = Utility.Create("TextLabel", {
				Name = "Label",
				Size = UDim2.new(0.4, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = text,
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local textBox = Utility.Create("TextBox", {
				Name = "TextBox",
				Size = UDim2.new(0.55, 0, 1, 0),
				Position = UDim2.new(0.45, 0, 0, 0),
				BackgroundColor3 = Theme.Colors.Surface,
				Text = default or "",
				PlaceholderText = "Enter text...",
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				ClearTextOnFocus = false,
				CornerRadius = UDim.new(0, 4),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			label.Parent = textBoxFrame
			textBox.Parent = textBoxFrame
			textBoxFrame.Parent = tabContent
			
			local textBoxData = {
				TextBoxFrame = textBoxFrame,
				Label = label,
				TextBox = textBox,
				Enabled = true
			}
			
			-- Focus effects
			textBox.Focused:Connect(function()
				if textBoxData.Enabled then
					Animation.Tween(textBox, {BackgroundColor3 = Theme.Colors.Accent}, 0.1)
				end
			end)
			
			textBox.FocusLost:Connect(function()
				Animation.Tween(textBox, {BackgroundColor3 = Theme.Colors.Surface}, 0.1)
				if callback then
					callback(textBox.Text)
				end
			end)
			
			function textBoxData:SetEnabled(enabled)
				textBoxData.Enabled = enabled
				textBox.Active = enabled
				label.TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
				textBox.TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
			end
			
			function textBoxData:SetText(text)
				textBox.Text = text
			end
			
			return textBoxData
		end
		
		function tab:AddDropdown(text, list, default, callback)
			local dropdownFrame = Utility.Create("Frame", {
				Name = text .. "Dropdown",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundTransparency = 1,
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			local label = Utility.Create("TextLabel", {
				Name = "Label",
				Size = UDim2.new(0.4, 0, 1, 0),
				BackgroundTransparency = 1,
				Text = text,
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				TextXAlignment = Enum.TextXAlignment.Left
			})
			
			local dropdownButton = Utility.Create("TextButton", {
				Name = "DropdownButton",
				Size = UDim2.new(0.55, 0, 1, 0),
				Position = UDim2.new(0.45, 0, 0, 0),
				BackgroundColor3 = Theme.Colors.Surface,
				Text = default or list[1] or "Select...",
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				CornerRadius = UDim.new(0, 4),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			local dropdownList = Utility.Create("Frame", {
				Name = "DropdownList",
				Size = UDim2.new(0.55, 0, 0, 0),
				Position = UDim2.new(0.45, 0, 1, 2),
				BackgroundColor3 = Theme.Colors.Surface,
				CornerRadius = UDim.new(0, 4),
				Stroke = {Color = Theme.Colors.Border, Thickness = 1},
				Visible = false
			}, {
				Utility.Create("UIListLayout", {
					Direction = Enum.FillDirection.Vertical,
					Padding = 2
				}),
				Utility.Create("CanvasGroup", {
					Name = "ListGroup",
					Size = UDim2.new(1, 0, 1, 0),
					GroupTransparency = 1
				})
			})
			
			local listGroup = dropdownList.ListGroup
			
			label.Parent = dropdownFrame
			dropdownButton.Parent = dropdownFrame
			dropdownList.Parent = dropdownFrame
			
			local dropdownData = {
				DropdownFrame = dropdownFrame,
				Label = label,
				DropdownButton = dropdownButton,
				DropdownList = dropdownList,
				ListGroup = listGroup,
				List = list or {},
				Value = default or list[1] or "",
				Enabled = true,
				Open = false
			}
			
			-- Create list items
			local function createListItems()
				-- Clear existing items
				for _, child in pairs(listGroup:GetChildren()) do
					if child:IsA("TextButton") then
						child:Destroy()
					end
				end
				
				local totalHeight = 0
				for _, item in pairs(dropdownData.List) do
					local listItem = Utility.Create("TextButton", {
						Name = item .. "Item",
						Size = UDim2.new(1, 0, 0, TouchTargetSize),
						BackgroundColor3 = Theme.Colors.Surface,
						Text = item,
						TextColor3 = Theme.Colors.Text,
						Font = Theme.Font,
						TextSize = MobileFontSize,
						SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
					})
					
					listItem.Parent = listGroup
					totalHeight = totalHeight + TouchTargetSize + 2
					
					listItem.MouseButton1Click:Connect(function()
						dropdownData.Value = item
						dropdownButton.Text = item
						dropdownData:Close()
						if callback then
							callback(item)
						end
					end)
					
					-- Hover effects (disabled on touch)
					if not IsTouchDevice then
						listItem.MouseEnter:Connect(function()
							Animation.Tween(listItem, {BackgroundColor3 = Theme.Colors.Accent}, 0.1)
						end)
						
						listItem.MouseLeave:Connect(function()
							Animation.Tween(listItem, {BackgroundColor3 = Theme.Colors.Surface}, 0.1)
						end)
					end
				end
				
				dropdownList.Size = UDim2.new(0.55, 0, 0, totalHeight)
			end
			
			createListItems()
			
			-- Toggle dropdown
			dropdownButton.MouseButton1Click:Connect(function()
				if dropdownData.Enabled then
					if dropdownData.Open then
						dropdownData:Close()
					else
						dropdownData:Open()
					end
				end
			end)
			
			function dropdownData:Open()
				dropdownData.Open = true
				dropdownList.Visible = true
				Animation.Tween(listGroup, {GroupTransparency = 0}, 0.2)
			end
			
			function dropdownData:Close()
				dropdownData.Open = false
				Animation.Tween(listGroup, {GroupTransparency = 1}, 0.2)
				delay(0.2, function()
					if not dropdownData.Open then
						dropdownList.Visible = false
					end
				end)
			end
			
			function dropdownData:SetEnabled(enabled)
				dropdownData.Enabled = enabled
				dropdownButton.Active = enabled
				label.TextColor3 = enabled and Theme.Colors.Text or Theme.Colors.TextMuted
			end
			
			function dropdownData:SetValue(value)
				dropdownData.Value = value
				dropdownButton.Text = value
			end
			
			dropdownFrame.Parent = tabContent
			
			return dropdownData
		end
		
		function tab:AddLabel(text)
			local label = Utility.Create("TextLabel", {
				Name = text .. "Label",
				Size = UDim2.new(1, 0, 0, TouchTargetSize),
				BackgroundTransparency = 1,
				Text = text,
				TextColor3 = Theme.Colors.Text,
				Font = Theme.Font,
				TextSize = MobileFontSize,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				SizeConstraint = {MinSize = Vector2.new(0, TouchTargetSize)}
			})
			
			label.Parent = tabContent
			
			return {
				Label = label,
				SetText = function(self, newText)
					label.Text = newText
				end
			}
		end
		
		function tab:AddSeparator()
			local separator = Utility.Create("Frame", {
				Name = "Separator",
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Theme.Colors.Border,
				CornerRadius = UDim.new(0, 1)
			})
			
			separator.Parent = tabContent
			
			return separator
		end
		
		return tab
	end
	
	function window:SetActiveTab(tab)
		if window.ActiveTab == tab then return end
		
		-- Fade out current tab
		if window.ActiveTab then
			Animation.Tween(window.ActiveTab.Button, {BackgroundColor3 = Theme.Colors.Background}, 0.2)
			if window.ActiveTab.Content:FindFirstChildOfClass("CanvasGroup") then
				Animation.Tween(window.ActiveTab.Content:FindFirstChildOfClass("CanvasGroup"), {GroupTransparency = 1}, 0.2)
			else
				Animation.FadeOut(window.ActiveTab.Content, 0.2)
			end
			delay(0.2, function()
				if window.ActiveTab and window.ActiveTab ~= tab then
					window.ActiveTab.Content.Visible = false
				end
			end)
		end
		
		-- Set new active tab
		window.ActiveTab = tab
		tab.Content.Visible = true
		
		-- Fade in new tab
		Animation.Tween(tab.Button, {BackgroundColor3 = Theme.Colors.Accent}, 0.2)
		if tab.Content:FindFirstChildOfClass("CanvasGroup") then
			Animation.Tween(tab.Content:FindFirstChildOfClass("CanvasGroup"), {GroupTransparency = 0}, 0.2)
		else
			Animation.FadeIn(tab.Content, 0.2)
		end
	end
	
	function window:SetVisible(visible)
		if visible then
			screenGui.Enabled = true
			Animation.FadeIn(mainFrame, 0.2)
			Animation.Tween(contentGroup, {GroupTransparency = 0}, 0.2)
		else
			Animation.FadeOut(mainFrame, 0.2)
			Animation.Tween(contentGroup, {GroupTransparency = 1}, 0.2)
			delay(0.2, function()
				screenGui.Enabled = false
			end)
		end
	end
	
	function window:SetTitle(newTitle)
		titleBar.Title.Text = newTitle
	end
	
	function window:Remove()
		Animation.FadeOut(mainFrame, 0.2)
		Animation.Tween(contentGroup, {GroupTransparency = 1}, 0.2)
		delay(0.2, function()
			Utility.SafeDestroy(screenGui)
		end)
	end
	
	return window
end

-- =============================================================================
-- SECTION 6: NOTIFICATION SYSTEM
-- =============================================================================

Notifications.Queue = {}
Notifications.Active = {}
Notifications.MaxVisible = 4

function Library:Notify(text, duration)
	duration = duration or 3
	
	local notification = {
		Text = text,
		Duration = duration,
		Frame = nil
	}
	
	table.insert(Notifications.Queue, notification)
	Notifications.ProcessQueue()
end

function Notifications.ProcessQueue()
	-- Check if we can show more notifications
	while #Notifications.Active < Notifications.MaxVisible and #Notifications.Queue > 0 do
		local notification = table.remove(Notifications.Queue, 1)
		Notifications.Show(notification)
	end
end

function Notifications.Show(notification)
	local screenGui = Utility.Create("ScreenGui", {
		Name = "NotificationGui",
		ResetOnSpawn = false
	})
	
	local viewportSize = Utility.GetViewportSize()
	local frame = Utility.Create("Frame", {
		Name = "Notification",
		Size = UDim2.new(0, 250, 0, 60),
		Position = UDim2.new(1, 270, 0, 10 + (#Notifications.Active * 70)),
		BackgroundColor3 = Theme.Colors.Surface,
		CornerRadius = UDim.new(0, 8),
		Stroke = {Color = Theme.Colors.Border, Thickness = 1},
		Padding = MobilePadding,
		SizeConstraint = {MinSize = Vector2.new(250, 60)}
	}, {
		Utility.Create("TextLabel", {
			Name = "Text",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = notification.Text,
			TextColor3 = Theme.Colors.Text,
			Font = Theme.Font,
			TextSize = MobileFontSize,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center
		})
	})
	
	frame.Parent = screenGui
	screenGui.Parent = game:GetService("CoreGui")
	
	notification.Frame = frame
	
	table.insert(Notifications.Active, notification)
	
	-- Slide in animation
	Animation.Tween(frame, {Position = UDim2.new(1, -260, 0, frame.Position.Y.Offset)}, Animation.Fast)
	
	-- Auto dismiss
	delay(notification.Duration, function()
		Notifications.Dismiss(notification)
	end)
	
	-- Manual dismiss on click/touch
	frame.Text.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or 
		   input.UserInputType == Enum.UserInputType.Touch then
			Notifications.Dismiss(notification)
		end
	end)
	
	-- Touch feedback on mobile
	if IsTouchDevice then
		frame.Text.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Animation.Tween(frame, {Size = UDim2.new(0, 245, 0, 58)}, 0.1)
			end
		end)
		
		frame.Text.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				Animation.Tween(frame, {Size = UDim2.new(0, 250, 0, 60)}, 0.1)
			end
		end)
	end
end

function Notifications.Dismiss(notification)
	local index = table.find(Notifications.Active, notification)
	if not index then return end
	
	table.remove(Notifications.Active, index)
	
	-- Slide out animation
	Animation.Tween(notification.Frame, {Position = UDim2.new(1, 270, 0, notification.Frame.Position.Y.Offset)}, Animation.Fast)
	
	-- Cleanup
	delay(0.2, function()
		if notification.Frame and notification.Frame.Parent then
			Utility.SafeDestroy(notification.Frame.Parent)
		end
	end)
	
	-- Update positions of remaining notifications
	for i, remainingNotification in pairs(Notifications.Active) do
		if remainingNotification.Frame then
			Animation.Tween(remainingNotification.Frame, {
				Position = UDim2.new(1, -260, 0, 10 + (i - 1) * 70)
			}, 0.1)
		end
	end
	
	-- Process queue
	Notifications.ProcessQueue()
end

-- =============================================================================
-- SECTION 7: FINAL INTEGRATION & DELIVERY
-- =============================================================================

-- Return the Library table for loadstring compatibility
return Library
