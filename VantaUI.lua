--[[
    VantaUI (Beta)
    Standalone Roblox Luau UI framework.
    Designed for loadstring usage:
        local Library = loadstring(game:HttpGet("URL"))()

    Architecture:
      1) Utility helpers (signals, cleanup/maid, clamping, tween wrappers)
      2) Theme system (runtime theme updates + subscriptions)
      3) Core systems (root ScreenGui, window registry, notification queue)
      4) Window + tab layout
      5) Component factory methods
      6) Public API surface and return value
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local Library = {}
Library.__index = Library
Library.Name = "VantaUI"
Library.Version = "Beta"

--// ---------------------------------------------------------------------
--// Utility helpers
--// ---------------------------------------------------------------------

local function deepMerge(base, override)
    local out = {}
    for key, value in pairs(base) do
        if type(value) == "table" then
            out[key] = deepMerge(value, {})
        else
            out[key] = value
        end
    end

    if override then
        for key, value in pairs(override) do
            if type(value) == "table" and type(out[key]) == "table" then
                out[key] = deepMerge(out[key], value)
            else
                out[key] = value
            end
        end
    end

    return out
end

local function create(className, props)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    return obj
end

local function tween(instance, tweenInfo, goal)
    local t = TweenService:Create(instance, tweenInfo, goal)
    t:Play()
    return t
end

local function fastTween(instance, duration, goal, easingStyle, easingDirection)
    return tween(
        instance,
        TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
        goal
    )
end

local function clamp(v, minV, maxV)
    return math.max(minV, math.min(maxV, v))
end

local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(task)
    self._tasks[#self._tasks + 1] = task
    return task
end

function Maid:Clean()
    for i = #self._tasks, 1, -1 do
        local task = self._tasks[i]
        if typeof(task) == "RBXScriptConnection" then
            if task.Connected then
                task:Disconnect()
            end
        elseif type(task) == "function" then
            task()
        elseif typeof(task) == "Instance" then
            task:Destroy()
        elseif type(task) == "thread" then
            pcall(task.cancel, task)
        elseif type(task) == "table" and task.Destroy then
            task:Destroy()
        end
        self._tasks[i] = nil
    end
end

local function addRound(target, radius)
    local corner = create("UICorner", {
        CornerRadius = radius or UDim.new(0, 10),
        Parent = target,
    })
    return corner
end

local function addStroke(target, thickness, transparency)
    local stroke = create("UIStroke", {
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = target,
    })
    return stroke
end

--// ---------------------------------------------------------------------
--// Theme system
--// ---------------------------------------------------------------------

local DefaultTheme = {
    Background = Color3.fromRGB(26, 29, 37),
    Surface = Color3.fromRGB(35, 39, 50),
    SurfaceAlt = Color3.fromRGB(46, 52, 66),
    Accent = Color3.fromRGB(109, 90, 255),
    AccentSoft = Color3.fromRGB(134, 117, 255),
    TextPrimary = Color3.fromRGB(245, 246, 250),
    TextSecondary = Color3.fromRGB(210, 215, 225),
    Border = Color3.fromRGB(88, 98, 121),
    Danger = Color3.fromRGB(255, 99, 108),
    Success = Color3.fromRGB(76, 200, 120),
    Shadow = Color3.fromRGB(0, 0, 0),
}

Library.Theme = deepMerge(DefaultTheme)
Library._themeBindings = {}

function Library:_bindTheme(instance, property, themeKey)
    if not (instance and property and themeKey) then
        return
    end

    local entry = { Instance = instance, Property = property, Key = themeKey }
    table.insert(self._themeBindings, entry)

    instance[property] = self.Theme[themeKey]
end

function Library:_applyTheme()
    for i = #self._themeBindings, 1, -1 do
        local entry = self._themeBindings[i]
        if not entry.Instance or entry.Instance.Parent == nil then
            table.remove(self._themeBindings, i)
        else
            entry.Instance[entry.Property] = self.Theme[entry.Key]
        end
    end
end

function Library:SetTheme(themePatch)
    self.Theme = deepMerge(self.Theme, themePatch or {})
    self:_applyTheme()
end

--// ---------------------------------------------------------------------
--// Core root and responsive base
--// ---------------------------------------------------------------------

Library._rootMaid = Maid.new()
Library._windows = {}
Library._notifications = {}
Library._maxNotifications = 4
Library._uiScale = nil

local function getGuiParent()
    -- Prefer PlayerGui for compatibility and visibility across executors.
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
    if playerGui then
        return playerGui
    end

    -- Fallback for edge cases.
    local coreGui = game:GetService("CoreGui")
    return coreGui
end

function Library:_ensureRoot()
    if self._root and self._root.Parent then
        return self._root
    end

    local root = create("ScreenGui", {
        Name = "VantaUIRoot",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100,
        Enabled = true,
        Parent = getGuiParent(),
    })

    local scale = create("UIScale", { Parent = root })
    self._uiScale = scale

    local rootContainer = create("Frame", {
        Name = "RootContainer",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = root,
    })

    local notificationContainer = create("Frame", {
        Name = "NotificationContainer",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -20, 0, 20),
        Size = UDim2.new(0, 360, 1, -40),
        Parent = rootContainer,
    })

    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 10),
        Parent = notificationContainer,
    })

    self:_bindTheme(rootContainer, "BackgroundColor3", "Background")
    rootContainer.BackgroundTransparency = 1

    self._root = root
    self._rootContainer = rootContainer
    self._notificationContainer = notificationContainer

    self._rootMaid:Give(root)

    self._rootMaid:Give(UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
        self:_updateScale()
    end))

    self._rootMaid:Give(UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(function()
        self:_updateScale()
    end))

    self._rootMaid:Give(RunService.RenderStepped:Connect(function()
        self:_updateScale()
    end))

    self:_updateScale()

    return root
end

function Library:_updateScale()
    if not self._uiScale then
        return
    end

    local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
    local minAxis = math.min(viewport.X, viewport.Y)

    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        self._uiScale.Scale = clamp(minAxis / 760, 0.85, 1.2)
    else
        self._uiScale.Scale = clamp(minAxis / 900, 0.9, 1.15)
    end
end

--// ---------------------------------------------------------------------
--// Notification system
--// ---------------------------------------------------------------------

function Library:_trimNotifications()
    while #self._notifications > self._maxNotifications do
        local oldest = table.remove(self._notifications, 1)
        if oldest and oldest.Destroy then
            oldest:Destroy(true)
        end
    end
end

function Library:Notify(config)
    self:_ensureRoot()

    config = config or {}
    local title = config.Title or "Notification"
    local message = config.Message or ""
    local duration = config.Duration or 4

    local notifMaid = Maid.new()
    local card = create("Frame", {
        Name = "Notification",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 0.02,
        Parent = self._notificationContainer,
    })
    addRound(card, UDim.new(0, 10))
    local stroke = addStroke(card, 1, 0.15)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = card,
    })

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = card,
    })

    local titleLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -26, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Parent = card,
    })

    local messageLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, -26, 0, 0),
        Font = Enum.Font.Gotham,
        Text = message,
        TextWrapped = true,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })

    local dismiss = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -4, 0, 4),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        Text = "✕",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = card,
    })

    self:_bindTheme(card, "BackgroundColor3", "Surface")
    self:_bindTheme(stroke, "Color", "Border")
    self:_bindTheme(titleLabel, "TextColor3", "TextPrimary")
    self:_bindTheme(messageLabel, "TextColor3", "TextSecondary")
    self:_bindTheme(dismiss, "TextColor3", "TextSecondary")

    card.Position = UDim2.new(1, 35, 0, 0)
    card.BackgroundTransparency = 0.15

    fastTween(card, 0.35, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.02 }, Enum.EasingStyle.Quint)

    local alive = true
    local notifObj = {}
    local libraryRef = self

    function notifObj:Destroy(immediate)
        if not alive then
            return
        end
        alive = false

        local function cleanup()
            notifMaid:Clean()
            for i = #libraryRef._notifications, 1, -1 do
                if libraryRef._notifications[i] == notifObj then
                    table.remove(libraryRef._notifications, i)
                    break
                end
            end
            if card.Parent then
                card:Destroy()
            end
        end

        if immediate then
            cleanup()
            return
        end

        local outTween = fastTween(card, 0.22, { Position = UDim2.new(1, 30, 0, 0), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
        outTween.Completed:Once(cleanup)
    end

    notifMaid:Give(dismiss.MouseButton1Click:Connect(function()
        notifObj:Destroy()
    end))

    notifMaid:Give(task.delay(duration, function()
        notifObj:Destroy()
    end))

    table.insert(self._notifications, notifObj)
    self:_trimNotifications()

    return notifObj
end

--// ---------------------------------------------------------------------
--// Window and tab system
--// ---------------------------------------------------------------------

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local function trackConnection(maid, connection)
    if maid and connection then
        maid:Give(connection)
    end
    return connection
end

local function styleInteractive(lib, btn, baseKey, hoverKey)
    baseKey = baseKey or "SurfaceAlt"
    hoverKey = hoverKey or "AccentSoft"

    lib:_bindTheme(btn, "BackgroundColor3", baseKey)

    local maid = Maid.new()
    local hovered = false

    local function refresh()
        local key = hovered and hoverKey or baseKey
        fastTween(btn, 0.16, { BackgroundColor3 = lib.Theme[key] }, Enum.EasingStyle.Quad)
    end

    maid:Give(btn.MouseEnter:Connect(function()
        hovered = true
        refresh()
    end))

    maid:Give(btn.MouseLeave:Connect(function()
        hovered = false
        refresh()
    end))

    return maid
end

function Library:CreateWindow(config)
    self:_ensureRoot()

    config = config or {}
    local windowMaid = Maid.new()

    local window = setmetatable({
        _maid = windowMaid,
        _tabs = {},
        _activeTab = nil,
        _collapsed = false,
        _minSize = config.MinSize or Vector2.new(360, 320),
    }, Window)

    local frame = create("Frame", {
        Name = "Window",
        Size = config.Size or UDim2.fromOffset(560, 420),
        Position = config.Position or UDim2.new(0.5, -280, 0.5, -210),
        BackgroundTransparency = 0.02,
        Parent = self._rootContainer,
    })

    addRound(frame, UDim.new(0, 12))
    local frameStroke = addStroke(frame, 1, 0.08)

    local shadow = create("Frame", {
        Name = "Shadow",
        BackgroundTransparency = 0.8,
        Size = UDim2.new(1, 20, 1, 20),
        Position = UDim2.new(0, 0, 0, 10),
        ZIndex = frame.ZIndex - 1,
        Parent = frame,
    })
    addRound(shadow, UDim.new(0, 14))

    create("UISizeConstraint", {
        MinSize = window._minSize,
        Parent = frame,
    })

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = frame,
    })

    local titleBar = create("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 44),
        BorderSizePixel = 0,
        Parent = frame,
    })

    create("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 8),
        Parent = titleBar,
    })

    local titleLabel = create("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -120, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = config.Title or "VantaUI Window",
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar,
    })

    local buttonRow = create("Frame", {
        Name = "Controls",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(90, 30),
        BackgroundTransparency = 1,
        Parent = titleBar,
    })

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        Parent = buttonRow,
    })

    local collapseButton = create("TextButton", {
        Size = UDim2.fromOffset(30, 24),
        BackgroundTransparency = 0.1,
        Text = "–",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        Parent = buttonRow,
    })
    addRound(collapseButton, UDim.new(0, 7))
    addStroke(collapseButton, 1, 0.35)

    local closeButton = create("TextButton", {
        Size = UDim2.fromOffset(30, 24),
        BackgroundTransparency = 0.1,
        Text = "✕",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = buttonRow,
    })
    addRound(closeButton, UDim.new(0, 7))
    addStroke(closeButton, 1, 0.35)

    local body = create("Frame", {
        Name = "Body",
        Size = UDim2.new(1, 0, 1, -44),
        BackgroundTransparency = 0,
        Parent = frame,
    })

    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        Parent = body,
    })

    local tabButtons = create("Frame", {
        Name = "TabButtons",
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Parent = body,
    })

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabButtons,
    })

    local tabPages = create("Frame", {
        Name = "TabPages",
        Position = UDim2.new(0, 0, 0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })

    local resizeGrip = create("TextButton", {
        Name = "ResizeGrip",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 0, 1, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })

    local gripIcon = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(12, 12),
        BackgroundTransparency = 1,
        Parent = resizeGrip,
    })

    for i = 0, 2 do
        local line = create("Frame", {
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -i * 4, 1, 0),
            Size = UDim2.fromOffset(2, 2 + i * 4),
            BorderSizePixel = 0,
            Parent = gripIcon,
        })
        self:_bindTheme(line, "BackgroundColor3", "Border")
    end

    self:_bindTheme(frame, "BackgroundColor3", "Background")
    self:_bindTheme(shadow, "BackgroundColor3", "Shadow")
    self:_bindTheme(frameStroke, "Color", "Border")
    self:_bindTheme(titleBar, "BackgroundColor3", "Surface")
    self:_bindTheme(body, "BackgroundColor3", "SurfaceAlt")
    self:_bindTheme(titleLabel, "TextColor3", "TextPrimary")
    self:_bindTheme(collapseButton, "TextColor3", "TextSecondary")
    self:_bindTheme(closeButton, "TextColor3", "Danger")

    local collapseFx = styleInteractive(self, collapseButton, "SurfaceAlt", "Surface")
    local closeFx = styleInteractive(self, closeButton, "SurfaceAlt", "Danger")
    windowMaid:Give(function()
        collapseFx:Clean()
        closeFx:Clean()
    end)

    window._library = self
    window._frame = frame
    window._title = titleLabel
    window._body = body
    window._tabButtons = tabButtons
    window._tabPages = tabPages
    window._shadow = shadow

    -- Dragging support (mouse + touch)
    do
        local dragging = false
        local dragStart, startPos, dragInput

        local function setClampedPosition(position)
            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
            local size = frame.AbsoluteSize
            local minX = -math.floor(size.X * 0.35)
            local maxX = viewport.X - math.floor(size.X * 0.65)
            local minY = 0
            local maxY = viewport.Y - 44

            local clampedX = clamp(position.X.Offset, minX, maxX)
            local clampedY = clamp(position.Y.Offset, minY, maxY)
            frame.Position = UDim2.new(position.X.Scale, clampedX, position.Y.Scale, clampedY)
        end

        windowMaid:Give(titleBar.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            if input.Position and buttonRow.AbsolutePosition.X <= input.Position.X and input.Position.X <= (buttonRow.AbsolutePosition.X + buttonRow.AbsoluteSize.X) then
                return
            end

            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            dragInput = input
        end))

        windowMaid:Give(titleBar.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end))

        windowMaid:Give(UserInputService.InputChanged:Connect(function(input)
            if not dragging then
                return
            end

            local isExpected = input == dragInput
                or (dragInput and dragInput.UserInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch)

            if isExpected then
                local delta = input.Position - dragStart
                setClampedPosition(UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                ))
            end
        end))

        windowMaid:Give(UserInputService.InputEnded:Connect(function(input)
            if input == dragInput or (dragInput and dragInput.UserInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                dragInput = nil
            end
        end))
    end

    -- Resize support
    do
        local resizing = false
        local dragStart, startSize, resizeInput

        windowMaid:Give(resizeGrip.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            resizing = true
            dragStart = input.Position
            startSize = frame.AbsoluteSize
            resizeInput = input
        end))

        windowMaid:Give(UserInputService.InputChanged:Connect(function(input)
            if not resizing then
                return
            end

            local isExpected = input == resizeInput
                or (resizeInput and resizeInput.UserInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch)

            if isExpected then
                local delta = input.Position - dragStart
                local targetSize = Vector2.new(
                    math.max(window._minSize.X, startSize.X + delta.X),
                    math.max(window._minSize.Y, startSize.Y + delta.Y)
                )

                frame.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
            end
        end))

        windowMaid:Give(UserInputService.InputEnded:Connect(function(input)
            if input == resizeInput or (resizeInput and resizeInput.UserInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch) then
                resizing = false
                resizeInput = nil
            end
        end))
    end

    windowMaid:Give(collapseButton.MouseButton1Click:Connect(function()
        window:SetCollapsed(not window._collapsed)
    end))

    windowMaid:Give(closeButton.MouseButton1Click:Connect(function()
        window:Destroy()
    end))

    table.insert(self._windows, window)
    return window
end

function Window:SetTitle(text)
    self._title.Text = tostring(text or "Window")
end

function Window:SetCollapsed(state)
    state = state and true or false
    if self._collapsed == state then
        return
    end

    self._collapsed = state

    if state then
        self._storedHeight = self._frame.Size.Y.Offset
        fastTween(self._body, 0.25, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, Enum.EasingStyle.Quint)
        fastTween(self._frame, 0.28, { Size = UDim2.new(self._frame.Size.X.Scale, self._frame.Size.X.Offset, 0, 44) }, Enum.EasingStyle.Back)
    else
        local restore = self._storedHeight or 420
        fastTween(self._frame, 0.28, { Size = UDim2.new(self._frame.Size.X.Scale, self._frame.Size.X.Offset, 0, restore) }, Enum.EasingStyle.Quint)
        task.delay(0.02, function()
            fastTween(self._body, 0.2, { Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
        end)
    end
end

function Window:_activateTab(tabObj)
    if self._activeTab == tabObj then
        return
    end

    local old = self._activeTab
    self._activeTab = tabObj

    if old and old._page then
        old._button.AutoButtonColor = false
        fastTween(old._buttonIndicator, 0.2, { Size = UDim2.new(0, 0, 0, 2), BackgroundTransparency = 0.2 }, Enum.EasingStyle.Quad)
        fastTween(old._page, 0.15, { GroupTransparency = 1 }, Enum.EasingStyle.Quad)
        task.delay(0.16, function()
            if old._page then
                old._page.Visible = false
            end
        end)
    end

    tabObj._page.Visible = true
    tabObj._page.GroupTransparency = 1
    fastTween(tabObj._buttonIndicator, 0.25, { Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0 }, Enum.EasingStyle.Quint)
    fastTween(tabObj._page, 0.2, { GroupTransparency = 0 }, Enum.EasingStyle.Quint)
end

function Window:AddTab(config)
    config = config or {}

    local tab = setmetatable({
        _window = self,
        _maid = Maid.new(),
    }, Tab)

    self._maid:Give(function()
        tab._maid:Clean()
    end)

    local button = create("TextButton", {
        Size = UDim2.fromOffset(config.Width or 120, 30),
        BackgroundTransparency = 0.08,
        Text = config.Title or "Tab",
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        AutoButtonColor = false,
        Parent = self._tabButtons,
    })

    addRound(button, UDim.new(0, 8))
    local btnStroke = addStroke(button, 1, 0.25)

    local indicator = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -1),
        Size = UDim2.new(0, 0, 0, 2),
        BorderSizePixel = 0,
        BackgroundTransparency = 0.2,
        Parent = button,
    })

    addRound(indicator, UDim.new(1, 0))

    local page = create("CanvasGroup", {
        Name = (config.Title or "Tab") .. "Page",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self._tabPages,
    })

    create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = page,
    })

    local scroll = create("ScrollingFrame", {
        Name = "Content",
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = page,
    })

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = scroll,
    })

    create("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 6),
        Parent = scroll,
    })

    self._library:_bindTheme(button, "BackgroundColor3", "SurfaceAlt")
    self._library:_bindTheme(btnStroke, "Color", "Border")
    self._library:_bindTheme(button, "TextColor3", "TextSecondary")
    self._library:_bindTheme(indicator, "BackgroundColor3", "Accent")

    local btnFx = styleInteractive(self._library, button, "SurfaceAlt", "Surface")
    self._maid:Give(function()
        btnFx:Clean()
    end)

    self._maid:Give(button.MouseButton1Click:Connect(function()
        self:_activateTab(tab)
    end))

    tab._button = button
    tab._buttonIndicator = indicator
    tab._page = page
    tab._container = scroll

    table.insert(self._tabs, tab)

    if not self._activeTab then
        self:_activateTab(tab)
    end

    return tab
end

local function componentBase(tab, height)
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, height or 44),
        BackgroundTransparency = 0.06,
        Parent = tab._container,
    })
    addRound(holder, UDim.new(0, 10))
    local stroke = addStroke(holder, 1, 0.18)

    tab._window._library:_bindTheme(holder, "BackgroundColor3", "Surface")
    tab._window._library:_bindTheme(stroke, "Color", "Border")

    local componentMaid = Maid.new()
    componentMaid:Give(holder)
    if tab._maid then
        tab._maid:Give(function()
            componentMaid:Clean()
        end)
    end

    return holder, componentMaid
end

function Tab:AddLabel(config)
    config = config or {}
    local holder, maid = componentBase(self, 40)

    local text = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        Font = Enum.Font.Gotham,
        Text = config.Text or "Label",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    self._window._library:_bindTheme(text, "TextColor3", "TextSecondary")

    return {
        SetText = function(_, v)
            text.Text = tostring(v)
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddSection(config)
    config = config or {}
    local holder, maid = componentBase(self, 34)

    local title = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = string.upper(config.Text or "SECTION"),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    local divider = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.55, 0, 0, 1),
        BorderSizePixel = 0,
        Parent = holder,
    })

    local lib = self._window._library
    lib:_bindTheme(title, "TextColor3", "TextSecondary")
    lib:_bindTheme(divider, "BackgroundColor3", "Border")

    return {
        SetText = function(_, v)
            title.Text = string.upper(tostring(v))
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddButton(config)
    config = config or {}
    local holder, maid = componentBase(self, 46)

    local button = create("TextButton", {
        Size = UDim2.new(1, -12, 1, -12),
        Position = UDim2.new(0, 6, 0, 6),
        BackgroundTransparency = 0.04,
        Text = config.Text or "Button",
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        AutoButtonColor = false,
        Parent = holder,
    })

    addRound(button, UDim.new(0, 8))
    local stroke = addStroke(button, 1, 0.2)

    local lib = self._window._library
    lib:_bindTheme(button, "BackgroundColor3", "SurfaceAlt")
    lib:_bindTheme(button, "TextColor3", "TextPrimary")
    lib:_bindTheme(stroke, "Color", "Border")

    local fx = styleInteractive(lib, button, "SurfaceAlt", "AccentSoft")
    maid:Give(function()
        fx:Clean()
    end)

    local callback = config.Callback or function() end
    trackConnection(maid, button.MouseButton1Click:Connect(function()
        callback()
        fastTween(button, 0.08, { Size = UDim2.new(1, -14, 1, -14), Position = UDim2.new(0, 7, 0, 7) }, Enum.EasingStyle.Quad)
        task.delay(0.08, function()
            fastTween(button, 0.08, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6) }, Enum.EasingStyle.Back)
        end)
    end))

    return {
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddToggle(config)
    config = config or {}
    local holder, maid = componentBase(self, 48)

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        Font = Enum.Font.Gotham,
        Text = config.Text or "Toggle",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(48, 24),
        BackgroundColor3 = Color3.fromRGB(50, 50, 58),
        Text = "",
        AutoButtonColor = false,
        Parent = holder,
    })

    addRound(button, UDim.new(1, 0))
    local knob = create("Frame", {
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.new(0, 2, 0.5, -10),
        Parent = button,
    })
    addRound(knob, UDim.new(1, 0))

    local lib = self._window._library
    lib:_bindTheme(label, "TextColor3", "TextPrimary")
    lib:_bindTheme(knob, "BackgroundColor3", "TextPrimary")

    local value = config.Default == true
    local callback = config.Callback or function() end

    local function refresh(instant)
        local bg = value and lib.Theme.Accent or lib.Theme.SurfaceAlt
        local pos = value and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
        if instant then
            button.BackgroundColor3 = bg
            knob.Position = pos
        else
            fastTween(button, 0.18, { BackgroundColor3 = bg }, Enum.EasingStyle.Quad)
            fastTween(knob, 0.18, { Position = pos }, Enum.EasingStyle.Quint)
        end
    end

    refresh(true)

    trackConnection(maid, button.MouseButton1Click:Connect(function()
        value = not value
        refresh(false)
        callback(value)
    end))

    return {
        SetValue = function(_, v)
            value = v and true or false
            refresh(false)
            callback(value)
        end,
        GetValue = function()
            return value
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddSlider(config)
    config = config or {}
    local holder, maid = componentBase(self, 64)

    local min = tonumber(config.Min) or 0
    local max = tonumber(config.Max) or 100
    if min > max then
        min, max = max, min
    end
    local step = tonumber(config.Step) or 1
    if step <= 0 then
        step = 1
    end
    local value = clamp(tonumber(config.Default) or min, min, max)

    local title = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -90, 0, 22),
        Position = UDim2.new(0, 12, 0, 4),
        Font = Enum.Font.Gotham,
        Text = config.Text or "Slider",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(64, 22),
        Position = UDim2.new(1, -76, 0, 4),
        Font = Enum.Font.GothamSemibold,
        Text = tostring(value),
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = holder,
    })

    local track = create("Frame", {
        Size = UDim2.new(1, -24, 0, 8),
        Position = UDim2.new(0, 12, 1, -20),
        BorderSizePixel = 0,
        Parent = holder,
    })
    addRound(track, UDim.new(1, 0))

    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BorderSizePixel = 0,
        Parent = track,
    })
    addRound(fill, UDim.new(1, 0))

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 0, 0.5, 0),
        BorderSizePixel = 0,
        Parent = track,
    })
    addRound(knob, UDim.new(1, 0))

    local lib = self._window._library
    lib:_bindTheme(title, "TextColor3", "TextPrimary")
    lib:_bindTheme(valueLabel, "TextColor3", "TextSecondary")
    lib:_bindTheme(track, "BackgroundColor3", "SurfaceAlt")
    lib:_bindTheme(fill, "BackgroundColor3", "Accent")
    lib:_bindTheme(knob, "BackgroundColor3", "TextPrimary")

    local callback = config.Callback or function() end

    local function snap(v)
        local snapped = math.floor((v - min) / step + 0.5) * step + min
        return clamp(snapped, min, max)
    end

    local function setVisual(v)
        local range = (max - min)
        local alpha = range == 0 and 0 or (v - min) / range
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = string.format(config.Format or "%s", tostring(v))
    end

    local function setValue(v, trigger)
        value = snap(v)
        setVisual(value)
        if trigger then
            callback(value)
        end
    end

    setValue(value, false)

    local dragging = false

    local function updateFromInput(positionX)
        local rel = clamp((positionX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local raw = min + (max - min) * rel
        setValue(raw, true)
    end

    trackConnection(maid, track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromInput(input.Position.X)
        end
    end))

    trackConnection(maid, track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    trackConnection(maid, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input.Position.X)
        end
    end))

    return {
        SetValue = function(_, v)
            setValue(v, true)
        end,
        GetValue = function()
            return value
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddDropdown(config)
    config = config or {}
    local holder, maid = componentBase(self, 50)

    local values = config.Values or {}
    local current = config.Default or values[1]

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.45, -12, 1, 0),
        Position = UDim2.new(0, 12, 0, 0),
        Font = Enum.Font.Gotham,
        Text = config.Text or "Dropdown",
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.52, 0, 0, 32),
        BackgroundTransparency = 0.04,
        Text = tostring(current or "Select"),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        AutoButtonColor = false,
        Parent = holder,
    })

    addRound(button, UDim.new(0, 8))
    local btnStroke = addStroke(button, 1, 0.25)

    local popup = create("Frame", {
        Visible = false,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 1, -2),
        Size = UDim2.new(0.52, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 0.03,
        ClipsDescendants = true,
        Parent = holder,
        ZIndex = holder.ZIndex + 3,
    })

    addRound(popup, UDim.new(0, 8))
    local popStroke = addStroke(popup, 1, 0.15)

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = popup,
    })

    create("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6),
        PaddingRight = UDim.new(0, 6),
        Parent = popup,
    })

    local lib = self._window._library
    lib:_bindTheme(label, "TextColor3", "TextPrimary")
    lib:_bindTheme(button, "BackgroundColor3", "SurfaceAlt")
    lib:_bindTheme(button, "TextColor3", "TextSecondary")
    lib:_bindTheme(btnStroke, "Color", "Border")
    lib:_bindTheme(popup, "BackgroundColor3", "Surface")
    lib:_bindTheme(popStroke, "Color", "Border")

    local callback = config.Callback or function() end

    local opened = false

    local function setOpen(v)
        opened = v
        popup.Visible = true
        local target = v and UDim2.new(0.52, 0, 0, math.min(#values * 28 + 12, 160)) or UDim2.new(0.52, 0, 0, 0)
        local t = fastTween(popup, 0.2, { Size = target }, Enum.EasingStyle.Quint)
        if not v then
            t.Completed:Once(function()
                popup.Visible = false
            end)
        end
    end

    local function select(v)
        current = v
        button.Text = tostring(v)
        callback(v)
    end

    for _, v in ipairs(values) do
        local opt = create("TextButton", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 0.06,
            Text = tostring(v),
            Font = Enum.Font.Gotham,
            TextSize = 12,
            AutoButtonColor = false,
            Parent = popup,
        })

        addRound(opt, UDim.new(0, 6))
        local optionFx = styleInteractive(lib, opt, "SurfaceAlt", "AccentSoft")
        lib:_bindTheme(opt, "TextColor3", "TextSecondary")

        trackConnection(maid, opt.MouseButton1Click:Connect(function()
            select(v)
            setOpen(false)
        end))

        maid:Give(function()
            optionFx:Clean()
        end)
    end

    trackConnection(maid, button.MouseButton1Click:Connect(function()
        setOpen(not opened)
    end))

    return {
        SetValue = function(_, v)
            select(v)
        end,
        GetValue = function()
            return current
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Tab:AddInput(config)
    config = config or {}
    local holder, maid = componentBase(self, 54)

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 18),
        Position = UDim2.new(0, 12, 0, 5),
        Font = Enum.Font.Gotham,
        Text = config.Text or "Input",
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = holder,
    })

    local box = create("TextBox", {
        Size = UDim2.new(1, -24, 0, 26),
        Position = UDim2.new(0, 12, 1, -31),
        BackgroundTransparency = 0.06,
        Text = config.Default or "",
        PlaceholderText = config.Placeholder or "Type...",
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = holder,
    })

    addRound(box, UDim.new(0, 7))
    local stroke = addStroke(box, 1, 0.22)

    local lib = self._window._library
    lib:_bindTheme(label, "TextColor3", "TextSecondary")
    lib:_bindTheme(box, "BackgroundColor3", "SurfaceAlt")
    lib:_bindTheme(box, "TextColor3", "TextPrimary")
    lib:_bindTheme(box, "PlaceholderColor3", "TextSecondary")
    lib:_bindTheme(stroke, "Color", "Border")

    local callback = config.Callback or function() end
    trackConnection(maid, box.FocusLost:Connect(function(enterPressed)
        callback(box.Text, enterPressed)
    end))

    return {
        SetValue = function(_, v)
            box.Text = tostring(v)
        end,
        GetValue = function()
            return box.Text
        end,
        Destroy = function()
            maid:Clean()
        end,
    }
end

function Window:Destroy()
    self._maid:Clean()
    if self._frame and self._frame.Parent then
        self._frame:Destroy()
    end

    local windows = self._library._windows
    for i = #windows, 1, -1 do
        if windows[i] == self then
            table.remove(windows, i)
            break
        end
    end
end

--// ---------------------------------------------------------------------
--// Convenience helpers + example APIs
--// ---------------------------------------------------------------------

function Library:CreateDemo()
    local win = self:CreateWindow({
        Title = "VantaUI Beta - Demo",
        Size = UDim2.fromOffset(600, 430),
    })

    local tabMain = win:AddTab({ Title = "Main" })
    local tabSettings = win:AddTab({ Title = "Settings" })

    tabMain:AddLabel({ Text = "Modern Roblox UI framework with fluid animations." })
    tabMain:AddSection({ Text = "Actions" })
    tabMain:AddButton({
        Text = "Show Notification",
        Callback = function()
            self:Notify({ Title = "VantaUI", Message = "Button callback fired.", Duration = 3 })
        end,
    })
    tabMain:AddToggle({
        Text = "Enable Feature",
        Default = true,
        Callback = function(v)
            self:Notify({ Title = "Toggle", Message = "State: " .. tostring(v), Duration = 2 })
        end,
    })

    tabSettings:AddSlider({ Text = "Volume", Min = 0, Max = 100, Default = 45, Step = 1 })
    tabSettings:AddDropdown({ Text = "Mode", Values = { "Easy", "Normal", "Hard" }, Default = "Normal" })
    tabSettings:AddInput({ Text = "Username", Placeholder = "Enter name" })

    return win
end

function Library:Destroy()
    for i = #self._windows, 1, -1 do
        local w = self._windows[i]
        if w and w.Destroy then
            w:Destroy()
        end
    end

    for i = #self._notifications, 1, -1 do
        local n = self._notifications[i]
        if n and n.Destroy then
            n:Destroy(true)
        end
    end

    self._rootMaid:Clean()
    self._themeBindings = {}
    self._notifications = {}
end

return Library
