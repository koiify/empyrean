--[[
    Empyrean UI Library
    Standalone Drawing API interface.

    This is a direct replacement for the previous UI source. It does not
    fetch, patch, convert, or execute another UI library.

    Design goals:
      * No image Drawing objects are created.
      * No external image URLs.
      * No PNG cache dependency.
      * Procedural HSV color picker.
      * Procedural hue strip and transparency checkerboard.
      * Native Roblox cursor preserved.
      * Window dragging updates once per rendered frame.
      * Compatible with the existing Empyrean integration's public surface:
          Library:New
          Window:Page / Initialize / Fade / Unload
          Page:Section / MultiSection
          Section:Label / Toggle / Slider / Button / ButtonHolder
          Section:Dropdown / Multibox / Keybind / Colorpicker / ConfigBox
          Toggle:Keybind / Toggle:Colorpicker
          Colorpicker:Colorpicker
      * Existing section.visibleContent/currentAxis/page.open behavior retained.
--]]

--==============================================================
-- SERVICES
--==============================================================

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")

--==============================================================
-- LIBRARY STATE
--==============================================================

local library = {
    drawings = {},
    hidden = {},
    connections = {},
    pointers = {},
    began = {},
    ended = {},
    changed = {},

    -- Live appearance bindings. These let theme changes recolor existing
    -- Drawing objects immediately instead of only affecting newly-created UI.
    themeBindings = {},
    textSizeBindings = {},
    fontBindings = {},

    folders = {
        main = "empyrean",
        assets = "empyrean/assets",
        configs = "empyrean/configs",
    },

    shared = {
        initialized = false,
        fps = 0,
        ping = 0,
        opacity = 1,
    },
}

local utility = {}
local pages = {}
local sections = {}

library.__index = library
pages.__index = pages
sections.__index = sections

--==============================================================
-- FOLDERS
--==============================================================

local function ensureFolder(path)
    if not isfolder or not makefolder then
        return
    end

    local ok, exists = pcall(isfolder, path)

    if ok and not exists then
        pcall(makefolder, path)
    end
end

ensureFolder(library.folders.main)
ensureFolder(library.folders.assets)
ensureFolder(library.folders.configs)

--==============================================================
-- THEME
--==============================================================

local theme = {
    accent = Color3.fromRGB(125, 95, 255),
    light_contrast = Color3.fromRGB(30, 30, 30),
    dark_contrast = Color3.fromRGB(20, 20, 20),
    outline = Color3.fromRGB(0, 0, 0),
    inline = Color3.fromRGB(50, 50, 50),
    textcolor = Color3.fromRGB(255, 255, 255),
    textborder = Color3.fromRGB(0, 0, 0),
    cursoroutline = Color3.fromRGB(10, 10, 10),
    font = 2,
    textsize = 13,
}

local THEME_COLOR_KEYS = {
    "accent",
    "light_contrast",
    "dark_contrast",
    "outline",
    "inline",
    "textcolor",
    "textborder",
    "cursoroutline",
}

for _, key in ipairs(THEME_COLOR_KEYS) do
    library.themeBindings[key] = {}
end

local function removeBindingFromList(list, object, property)
    for index = #list, 1, -1 do
        local binding = list[index]

        if
            binding.object == object
            and (
                property == nil
                or binding.property == property
            )
        then
            table.remove(list, index)
        end
    end
end

local function removeAppearanceBindings(object)
    for _, key in ipairs(THEME_COLOR_KEYS) do
        removeBindingFromList(
            library.themeBindings[key],
            object
        )
    end

    removeBindingFromList(
        library.textSizeBindings,
        object
    )

    removeBindingFromList(
        library.fontBindings,
        object
    )
end

local function bindThemeProperty(
    object,
    property,
    key
)
    if
        not object
        or not property
        or not key
        or not library.themeBindings[key]
    then
        return
    end

    -- A Drawing property belongs to exactly one theme slot at a time.
    for _, otherKey in ipairs(THEME_COLOR_KEYS) do
        removeBindingFromList(
            library.themeBindings[otherKey],
            object,
            property
        )
    end

    table.insert(
        library.themeBindings[key],
        {
            object = object,
            property = property,
        }
    )
end

local function resolveSquareThemeKey(color)
    if typeof(color) ~= "Color3" then
        return nil
    end

    -- These are the theme slots used as Square/Triangle/etc. fill colors.
    -- Text-only keys are intentionally excluded so duplicate colors such as
    -- outline/textborder remain independently customizable.
    for _, key in ipairs({
        "accent",
        "light_contrast",
        "dark_contrast",
        "outline",
        "inline",
        "cursoroutline",
    }) do
        if theme[key] == color then
            return key
        end
    end

    return nil
end

function utility:SetThemeProperty(
    object,
    property,
    key
)
    if
        not object
        or not library.themeBindings[key]
    then
        return
    end

    pcall(function()
        object[property] = theme[key]
    end)

    bindThemeProperty(
        object,
        property,
        key
    )
end

function library:SetThemeColor(key, color)
    key = tostring(key or "")

    if
        not library.themeBindings[key]
        or typeof(color) ~= "Color3"
    then
        return false
    end

    theme[key] = color

    local bindings =
        library.themeBindings[key]

    for index = #bindings, 1, -1 do
        local binding =
            bindings[index]

        local ok =
            pcall(function()
                binding.object[binding.property] =
                    color
            end)

        if not ok then
            table.remove(
                bindings,
                index
            )
        end
    end

    return true
end

function library:SetTheme(values)
    if type(values) ~= "table" then
        return false
    end

    for key, color in pairs(values) do
        if
            library.themeBindings[key]
            and typeof(color) == "Color3"
        then
            self:SetThemeColor(
                key,
                color
            )
        end
    end

    return true
end

function library:GetTheme()
    local result = {}

    for _, key in ipairs(THEME_COLOR_KEYS) do
        result[key] =
            theme[key]
    end

    result.font =
        theme.font

    result.textsize =
        theme.textsize

    result.opacity =
        library.shared.opacity

    return result
end

function library:SetTextSize(value)
    value =
        math.clamp(
            math.floor(
                tonumber(value)
                or theme.textsize
            ),
            8,
            24
        )

    theme.textsize =
        value

    for index = #library.textSizeBindings, 1, -1 do
        local binding =
            library.textSizeBindings[index]

        local ok =
            pcall(function()
                binding.object.Size =
                    value
            end)

        if not ok then
            table.remove(
                library.textSizeBindings,
                index
            )
        end
    end

    return value
end

function library:SetFont(value)
    value =
        math.clamp(
            math.floor(
                tonumber(value)
                or theme.font
            ),
            0,
            3
        )

    theme.font =
        value

    for index = #library.fontBindings, 1, -1 do
        local binding =
            library.fontBindings[index]

        local ok =
            pcall(function()
                binding.object.Font =
                    value
            end)

        if not ok then
            table.remove(
                library.fontBindings,
                index
            )
        end
    end

    return value
end

function library:SetOpacity(value)
    value =
        math.clamp(
            tonumber(value)
            or library.shared.opacity
            or 1,
            0.1,
            1
        )

    library.shared.opacity =
        value

    local window =
        library.currentWindow

    if
        window
        and window.isVisible
    then
        for _, entry in ipairs(library.drawings) do
            pcall(function()
                entry[1].Transparency =
                    (entry[3] or 1)
                    * value
            end)
        end
    end

    return value
end

--==============================================================
-- INTERNAL HELPERS
--==============================================================

local function removeFromArray(array, value)
    for index = #array, 1, -1 do
        local entry = array[index]

        if entry == value or (type(entry) == "table" and entry[1] == value) then
            table.remove(array, index)
            return true
        end
    end

    return false
end

local function safeRemoveDrawing(object)
    if not object then
        return
    end

    pcall(function()
        object.Visible = false
    end)

    local removed = pcall(function()
        object:Remove()
    end)

    if not removed then
        pcall(function()
            object:Destroy()
        end)
    end
end

local function getDrawingType(object)
    for _, entry in ipairs(library.drawings) do
        if entry[1] == object then
            return entry.kind
        end
    end

    for _, entry in ipairs(library.hidden) do
        if entry[1] == object then
            return entry.kind
        end
    end

    return nil
end

local function shiftDrawing(object, delta, kind)
    if not object then
        return
    end

    kind = kind or getDrawingType(object)

    if kind == "Triangle" then
        pcall(function()
            object.PointA = object.PointA + delta
            object.PointB = object.PointB + delta
            object.PointC = object.PointC + delta
        end)

        return
    end

    if kind == "Line" then
        pcall(function()
            object.From = object.From + delta
            object.To = object.To + delta
        end)

        return
    end

    pcall(function()
        object.Position = object.Position + delta
    end)
end

local function pointInside(position, size, mouse)
    return
        mouse.X >= position.X
        and mouse.X <= position.X + size.X
        and mouse.Y >= position.Y
        and mouse.Y <= position.Y + size.Y
end

local function getBaseTransparency(object)
    for _, entry in ipairs(library.drawings) do
        if entry[1] == object then
            return entry[3] or 1
        end
    end

    return 1
end

local function setDrawingTransparency(object, value)
    pcall(function()
        object.Transparency = value
    end)
end

local function resolveEnumTable(value)
    if type(value) ~= "table" then
        return nil
    end

    if not value[1] or not value[2] then
        return nil
    end

    local enumType = Enum[value[1]]

    if not enumType then
        return nil
    end

    return enumType[value[2]]
end

local function shortenKeyName(name)
    local replacements = {
        MouseButton1 = "MB1",
        MouseButton2 = "MB2",
        MouseButton3 = "MB3",
        LeftAlt = "LAlt",
        RightAlt = "RAlt",
        LeftControl = "LCtrl",
        RightControl = "RCtrl",
        LeftShift = "LShift",
        RightShift = "RShift",
        CapsLock = "Caps",
        Insert = "Ins",
    }

    return replacements[name] or name
end

--==============================================================
-- UTILITY: SIZE / POSITION
--==============================================================

function utility:Size(xScale, xOffset, yScale, yOffset, instance)
    if instance then
        return Vector2.new(
            xScale * instance.Size.X + xOffset,
            yScale * instance.Size.Y + yOffset
        )
    end

    local viewport = Workspace.CurrentCamera.ViewportSize

    return Vector2.new(
        xScale * viewport.X + xOffset,
        yScale * viewport.Y + yOffset
    )
end

function utility:Position(xScale, xOffset, yScale, yOffset, instance)
    if instance then
        return Vector2.new(
            instance.Position.X + xScale * instance.Size.X + xOffset,
            instance.Position.Y + yScale * instance.Size.Y + yOffset
        )
    end

    local viewport = Workspace.CurrentCamera.ViewportSize

    return Vector2.new(
        xScale * viewport.X + xOffset,
        yScale * viewport.Y + yOffset
    )
end

--==============================================================
-- UTILITY: DRAWING CREATION
--==============================================================

function utility:Create(instanceType, instanceOffset, instanceProperties, instanceParent)
    instanceType = instanceType or "Frame"
    instanceOffset = instanceOffset or {Vector2.new(0, 0)}
    instanceProperties = instanceProperties or {}

    local normalized = string.lower(instanceType)
    local object
    local kind

    if normalized == "frame" or normalized == "image" then
        -- "Image" intentionally maps to a normal Square for compatibility.
        -- The library itself never relies on image bytes.
        object = Drawing.new("Square")
        kind = "Square"

        object.Visible = true
        object.Filled = true
        object.Thickness = 0
        object.Color = Color3.fromRGB(255, 255, 255)
        object.Size = Vector2.new(100, 100)
        object.Position = Vector2.new(0, 0)
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0

    elseif normalized == "textlabel" then
        object = Drawing.new("Text")
        kind = "Text"

        object.Font = 3
        object.Visible = true
        object.Outline = true
        object.Center = false
        object.Color = Color3.fromRGB(255, 255, 255)
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0

    elseif normalized == "triangle" then
        object = Drawing.new("Triangle")
        kind = "Triangle"

        object.Visible = true
        object.Filled = true
        object.Thickness = 0
        object.Color = Color3.fromRGB(255, 255, 255)
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0
        object.PointA = Vector2.new(0, 0)
        object.PointB = Vector2.new(0, 0)
        object.PointC = Vector2.new(0, 0)

    elseif normalized == "circle" then
        object = Drawing.new("Circle")
        kind = "Circle"

        object.Visible = true
        object.Color = Color3.fromRGB(255, 255, 255)
        object.Thickness = 1
        object.NumSides = 30
        object.Filled = true
        object.Radius = 50
        object.Position = Vector2.new(0, 0)
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0

    elseif normalized == "quad" then
        object = Drawing.new("Quad")
        kind = "Quad"

        object.Visible = true
        object.Color = Color3.fromRGB(255, 255, 255)
        object.Thickness = 1
        object.Filled = false
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0

    elseif normalized == "line" then
        object = Drawing.new("Line")
        kind = "Line"

        object.Visible = true
        object.Color = Color3.fromRGB(255, 255, 255)
        object.Thickness = 1
        object.From = Vector2.new(0, 0)
        object.To = Vector2.new(0, 0)
        object.ZIndex = 50
        object.Transparency = library.shared.initialized and 1 or 0
    end

    if not object then
        return nil
    end

    local hidden = false
    local requestedTransparency = instanceProperties.Transparency

    for property, value in pairs(instanceProperties) do
        if property == "Hidden" or property == "hidden" then
            hidden = value == true
        else
            if library.shared.initialized or property ~= "Transparency" then
                pcall(function()
                    object[property] = value
                end)
            end
        end
    end

    if
        library.shared.initialized
        and not hidden
    then
        pcall(function()
            object.Transparency =
                (requestedTransparency == nil and 1 or requestedTransparency)
                * (library.shared.opacity or 1)
        end)
    end

    local entry = {
        object,
        instanceOffset,
        requestedTransparency == nil and 1 or requestedTransparency,
        kind = kind,
    }

    if hidden then
        table.insert(library.hidden, entry)
    else
        table.insert(library.drawings, entry)
    end

    if instanceParent then
        table.insert(instanceParent, object)
    end

    return object
end

function utility:UpdateOffset(instance, instanceOffset)
    for _, entry in ipairs(library.drawings) do
        if entry[1] == instance then
            entry[2] = instanceOffset
            return
        end
    end
end

function utility:UpdateTransparency(instance, instanceTransparency)
    for _, entry in ipairs(library.drawings) do
        if entry[1] == instance then
            entry[3] = instanceTransparency

            if
                library.currentWindow
                and library.currentWindow.isVisible
            then
                pcall(function()
                    instance.Transparency =
                        (instanceTransparency or 1)
                        * (library.shared.opacity or 1)
                end)
            end

            return
        end
    end
end

function utility:Remove(instance, hidden)
    if not instance then
        return
    end

    removeFromArray(hidden and library.hidden or library.drawings, instance)
    removeAppearanceBindings(instance)
    safeRemoveDrawing(instance)
end

function utility:GetSubPrefix(value)
    local stringValue = tostring(value):gsub(" ", "")

    if #stringValue ~= 2 then
        return ""
    end

    local ending = string.sub(stringValue, #stringValue, #stringValue)

    if ending == "1" then
        return "st"
    elseif ending == "2" then
        return "nd"
    elseif ending == "3" then
        return "rd"
    end

    return "th"
end

function utility:Connection(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(library.connections, connection)
    return connection
end

function utility:Disconnect(connection)
    if not connection then
        return
    end

    removeFromArray(library.connections, connection)
    pcall(function()
        connection:Disconnect()
    end)
end

function utility:MouseLocation()
    return UserInputService:GetMouseLocation()
end

function utility:MouseOverDrawing(values, valuesAdd)
    valuesAdd = valuesAdd or {}

    local left = (values[1] or 0) + (valuesAdd[1] or 0)
    local top = (values[2] or 0) + (valuesAdd[2] or 0)
    local right = (values[3] or 0) + (valuesAdd[3] or 0)
    local bottom = (values[4] or 0) + (valuesAdd[4] or 0)
    local mouse = utility:MouseLocation()

    return
        mouse.X >= left
        and mouse.X <= right
        and mouse.Y >= top
        and mouse.Y <= bottom
end

function utility:GetTextBounds(text, textSize, font)
    local label = utility:Create("TextLabel", nil, {
        Text = tostring(text),
        Size = textSize,
        Font = font,
        Hidden = true,
        Visible = false,
    })

    local bounds = label.TextBounds
    utility:Remove(label, true)
    return bounds
end

function utility:GetScreenSize()
    return Workspace.CurrentCamera.ViewportSize
end

function utility:LoadImage(instance, imageName, imageLink)
    -- Compatibility no-op. Empyrean intentionally has no image pipeline.
    -- Existing callers may still invoke this method without causing errors.
    return instance, imageName, imageLink
end

function utility:Lerp(instance, target, duration)
    duration = math.max(tonumber(duration) or 0, 0)

    if duration <= 0 then
        for property, value in pairs(target) do
            pcall(function()
                instance[property] = value
            end)
        end

        return
    end

    local starting = {}

    for property in pairs(target) do
        starting[property] = instance[property]
    end

    local elapsed = 0
    local connection

    connection = RunService.RenderStepped:Connect(function(delta)
        elapsed = elapsed + delta
        local alpha = math.clamp(elapsed / duration, 0, 1)

        for property, targetValue in pairs(target) do
            local initialValue = starting[property]

            pcall(function()
                instance[property] = initialValue + (targetValue - initialValue) * alpha
            end)
        end

        if alpha >= 1 then
            connection:Disconnect()
        end
    end)
end

function utility:Combine(first, second)
    local result = {}

    for _, value in ipairs(first or {}) do
        table.insert(result, value)
    end

    for _, value in ipairs(second or {}) do
        table.insert(result, value)
    end

    return result
end

--==============================================================
-- PROCEDURAL UI HELPERS
--==============================================================

local function createText(parentList, text, position, properties)
    properties = properties or {}

    local color =
        properties.Color
        or theme.textcolor

    local outlineColor =
        properties.OutlineColor
        or theme.textborder

    local object =
        utility:Create("TextLabel", nil, {
            Text = text,
            Size = properties.Size or theme.textsize,
            Font = properties.Font or theme.font,
            Color = color,
            OutlineColor = outlineColor,
            Outline = properties.Outline == nil and true or properties.Outline,
            Center = properties.Center or false,
            Position = position,
            ZIndex = properties.ZIndex or 55,
            Transparency = properties.Transparency == nil and 1 or properties.Transparency,
            Visible = properties.Visible == nil and true or properties.Visible,
        }, parentList)

    if object then
        local colorKey =
            properties.ThemeColorKey

        if colorKey == nil then
            if properties.Color == nil then
                colorKey = "textcolor"
            elseif color == theme.accent then
                colorKey = "accent"
            elseif color == theme.textcolor then
                colorKey = "textcolor"
            end
        elseif colorKey == false then
            colorKey = nil
        end

        local outlineKey =
            properties.ThemeOutlineKey

        if outlineKey == nil then
            if properties.OutlineColor == nil then
                outlineKey = "textborder"
            elseif outlineColor == theme.textborder then
                outlineKey = "textborder"
            end
        elseif outlineKey == false then
            outlineKey = nil
        end

        if colorKey then
            bindThemeProperty(
                object,
                "Color",
                colorKey
            )
        end

        if outlineKey then
            bindThemeProperty(
                object,
                "OutlineColor",
                outlineKey
            )
        end

        if properties.Size == nil then
            table.insert(
                library.textSizeBindings,
                {
                    object = object,
                    property = "Size",
                }
            )
        end

        if properties.Font == nil then
            table.insert(
                library.fontBindings,
                {
                    object = object,
                    property = "Font",
                }
            )
        end
    end

    return object
end

local function createSquare(parentList, position, size, color, properties)
    properties = properties or {}

    local object =
        utility:Create("Frame", nil, {
            Position = position,
            Size = size,
            Color = color,
            Filled = properties.Filled == nil and true or properties.Filled,
            Thickness = properties.Thickness or 0,
            ZIndex = properties.ZIndex or 50,
            Transparency = properties.Transparency == nil and 1 or properties.Transparency,
            Visible = properties.Visible == nil and true or properties.Visible,
        }, parentList)

    if object then
        local themeKey =
            properties.ThemeKey

        if themeKey == nil then
            themeKey =
                resolveSquareThemeKey(color)
        elseif themeKey == false then
            themeKey = nil
        end

        if themeKey then
            bindThemeProperty(
                object,
                "Color",
                themeKey
            )
        end
    end

    return object
end

local function createOutlineBox(
    parentList,
    position,
    size,
    insideColor,
    visible,
    insideThemeKey
)
    local outline = createSquare(
        parentList,
        position,
        size,
        theme.outline,
        {Visible = visible, ZIndex = 56}
    )

    local inline = createSquare(
        parentList,
        position + Vector2.new(1, 1),
        size - Vector2.new(2, 2),
        theme.inline,
        {Visible = visible, ZIndex = 57}
    )

    local frameProperties = {
        Visible = visible,
        ZIndex = 58,
    }

    if insideThemeKey ~= nil then
        frameProperties.ThemeKey =
            insideThemeKey
    end

    local frame = createSquare(
        parentList,
        position + Vector2.new(2, 2),
        size - Vector2.new(4, 4),
        insideColor or theme.light_contrast,
        frameProperties
    )

    return outline, inline, frame
end

local function createCheckerboard(parentList, position, size, columns, rows, visible, zIndex)
    columns = columns or 8
    rows = rows or 2

    local pieces = {}

    for row = 1, rows do
        for column = 1, columns do
            local x1 = math.floor((column - 1) * size.X / columns)
            local x2 = math.floor(column * size.X / columns)
            local y1 = math.floor((row - 1) * size.Y / rows)
            local y2 = math.floor(row * size.Y / rows)

            local light = (row + column) % 2 == 0

            local square = createSquare(
                parentList,
                position + Vector2.new(x1, y1),
                Vector2.new(math.max(1, x2 - x1), math.max(1, y2 - y1)),
                light and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(80, 80, 80),
                {
                    Visible = visible,
                    ZIndex = zIndex or 55,
                }
            )

            table.insert(pieces, square)
        end
    end

    return pieces
end

local function createHueStrip(parentList, position, size, visible)
    local strips = {}
    local count = 30

    for index = 1, count do
        local y1 = math.floor((index - 1) * size.Y / count)
        local y2 = math.floor(index * size.Y / count)
        local hue = (index - 1) / (count - 1)

        local strip = createSquare(
            parentList,
            position + Vector2.new(0, y1),
            Vector2.new(size.X, math.max(1, y2 - y1)),
            Color3.fromHSV(hue, 1, 1),
            {
                Visible = visible,
                ZIndex = 80,
            }
        )

        table.insert(strips, strip)
    end

    return strips
end

local function createSVOverlay(parentList, position, size, hue, visible)
    local pieces = {}

    local background = createSquare(
        parentList,
        position,
        size,
        Color3.fromHSV(hue, 1, 1),
        {
            Visible = visible,
            ZIndex = 80,
            ThemeKey = false,
        }
    )

    table.insert(pieces, background)

    local count = 20

    -- Saturation component: white -> transparent from left to right.
    for index = 1, count do
        local x1 = math.floor((index - 1) * size.X / count)
        local x2 = math.floor(index * size.X / count)
        local midpoint = (index - 0.5) / count

        local strip = createSquare(
            parentList,
            position + Vector2.new(x1, 0),
            Vector2.new(math.max(1, x2 - x1), size.Y),
            Color3.fromRGB(255, 255, 255),
            {
                Visible = visible,
                ZIndex = 81,
                Transparency = 1 - midpoint,
                ThemeKey = false,
            }
        )

        table.insert(pieces, strip)
    end

    -- Value component: transparent -> black from top to bottom.
    for index = 1, count do
        local y1 = math.floor((index - 1) * size.Y / count)
        local y2 = math.floor(index * size.Y / count)
        local midpoint = (index - 0.5) / count

        local strip = createSquare(
            parentList,
            position + Vector2.new(0, y1),
            Vector2.new(size.X, math.max(1, y2 - y1)),
            Color3.fromRGB(0, 0, 0),
            {
                Visible = visible,
                ZIndex = 82,
                Transparency = midpoint,
                ThemeKey = false,
            }
        )

        table.insert(pieces, strip)
    end

    return background, pieces
end

--==============================================================
-- WINDOW
--==============================================================

function library:New(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "Empyrean"
    local size = info.Size or info.size or Vector2.new(504, 604)
    local accent = info.Accent or info.accent or info.Color or info.color or theme.accent

    theme.accent = accent

    local window = {
        pages = {},
        isVisible = false,
        uibind = Enum.KeyCode.Z,
        currentPage = nil,
        fading = false,
        dragging = false,
        drag = Vector2.new(0, 0),
        currentContent = {
            frame = nil,
            control = nil,
        },
    }

    local viewport = utility:GetScreenSize()
    local origin = Vector2.new(
        math.floor((viewport.X - size.X) / 2),
        math.floor((viewport.Y - size.Y) / 2)
    )

    local mainFrame = createSquare(
        nil,
        origin,
        size,
        theme.outline,
        {ZIndex = 40}
    )

    window.main_frame = mainFrame

    local accentFrame = createSquare(
        nil,
        origin + Vector2.new(1, 1),
        size - Vector2.new(2, 2),
        theme.accent,
        {ZIndex = 41}
    )

    local innerFrame = createSquare(
        nil,
        origin + Vector2.new(2, 2),
        size - Vector2.new(4, 4),
        theme.light_contrast,
        {ZIndex = 42}
    )

    local title = createText(
        nil,
        name,
        origin + Vector2.new(6, 4),
        {ZIndex = 43}
    )

    local backOutline = createSquare(
        nil,
        origin + Vector2.new(5, 22),
        Vector2.new(size.X - 10, size.Y - 27),
        theme.inline,
        {ZIndex = 43}
    )

    local backFrame = createSquare(
        nil,
        origin + Vector2.new(6, 23),
        Vector2.new(size.X - 12, size.Y - 29),
        theme.dark_contrast,
        {ZIndex = 44}
    )

    window.back_frame = backFrame

    local tabOutline = createSquare(
        nil,
        origin + Vector2.new(10, 53),
        Vector2.new(size.X - 20, size.Y - 64),
        theme.inline,
        {ZIndex = 44}
    )

    local tabFrame = createSquare(
        nil,
        origin + Vector2.new(11, 54),
        Vector2.new(size.X - 22, size.Y - 66),
        theme.light_contrast,
        {ZIndex = 45}
    )

    window.tab_frame = tabFrame

    window._baseDrawings = {
        mainFrame,
        accentFrame,
        innerFrame,
        title,
        backOutline,
        backFrame,
        tabOutline,
        tabFrame,
    }

    window._size = size

    setmetatable(window, library)
    library.currentWindow = window

    --==========================================================
    -- WINDOW CONTENT HELPERS
    --==========================================================

    function window:CloseContent()
        local control = self.currentContent.control

        if control and control.Close then
            control:Close()
        end

        self.currentContent.frame = nil
        self.currentContent.control = nil
    end

    function window:IsOverContent()
        local frame = self.currentContent.frame

        if not frame then
            return false
        end

        local mouse = utility:MouseLocation()

        return pointInside(frame.Position, frame.Size, mouse)
    end

    function window:Move(vector)
        local delta = vector - self.main_frame.Position

        if delta.Magnitude <= 0 then
            return
        end

        for _, entry in ipairs(library.drawings) do
            shiftDrawing(entry[1], delta, entry.kind)
        end

        for _, entry in ipairs(library.hidden) do
            shiftDrawing(entry[1], delta, entry.kind)
        end
    end

    function window:GetConfig()
        local config = {}

        for pointer, control in pairs(library.pointers) do
            if control.Get then
                local value = control:Get()

                if type(value) == "table" and value.Color and value.Transparency ~= nil then
                    local hue, saturation, brightness = value.Color:ToHSV()

                    config[pointer] = {
                        Color = {hue, saturation, brightness},
                        Transparency = value.Transparency,
                    }
                elseif typeof(value) == "Color3" then
                    local hue, saturation, brightness = value:ToHSV()
                    config[pointer] = {__Color3 = {hue, saturation, brightness}}
                else
                    config[pointer] = value
                end
            end
        end

        return HttpService:JSONEncode(config)
    end

    function window:LoadConfig(config)
        if type(config) == "string" then
            config = HttpService:JSONDecode(config)
        end

        if type(config) ~= "table" then
            return
        end

        for pointer, value in pairs(config) do
            local control = library.pointers[pointer]

            if control and control.Set then
                if type(value) == "table" and value.__Color3 then
                    control:Set(Color3.fromHSV(
                        value.__Color3[1],
                        value.__Color3[2],
                        value.__Color3[3]
                    ))
                else
                    control:Set(value)
                end
            end
        end
    end

    function window:Fade()
        self.isVisible = not self.isVisible
        self.fading = true

        for _, entry in ipairs(library.drawings) do
            setDrawingTransparency(
                entry[1],
                self.isVisible
                and (
                    (entry[3] or 1)
                    * (library.shared.opacity or 1)
                )
                or 0
            )
        end

        UserInputService.MouseIconEnabled = true
        self.fading = false
    end

    function window:Cursor()
        UserInputService.MouseIconEnabled = true

        self.cursor = self.cursor or {
            cursor = {Transparency = 0},
            cursor_inline = {Transparency = 0},
        }

        return self.cursor
    end

    function window:Watermark()
        self.watermark = self.watermark or {
            visible = false,
            Update = function(selfObject, updateType, updateValue)
                if updateType == "Visible" then
                    selfObject.visible = updateValue == true
                end
            end,
        }

        return self.watermark
    end

    function window:KeybindsList()
        self.keybindslist = self.keybindslist or {
            visible = false,
            keybinds = {},
            Add = function(selfObject, keybindName, keybindValue)
                selfObject.keybinds[keybindName] = keybindValue
            end,
            Remove = function(selfObject, keybindName)
                selfObject.keybinds[keybindName] = nil
            end,
            Update = function(selfObject, updateType, updateValue)
                if updateType == "Visible" then
                    selfObject.visible = updateValue == true
                end
            end,
        }

        return self.keybindslist
    end

    function window:Initialize()
        if #self.pages == 0 then
            return
        end

        if not self.currentPage then
            self.pages[1]:Show()
        end

        for _, page in ipairs(self.pages) do
            page:Update()
        end

        library.shared.initialized = true
        self.isVisible = true

        for _, entry in ipairs(library.drawings) do
            setDrawingTransparency(
                entry[1],
                (entry[3] or 1)
                * (library.shared.opacity or 1)
            )
        end

        self:Cursor()
        self:Watermark()
        self:KeybindsList()
    end

    function window:Unload()
        self:CloseContent()

        for _, connection in ipairs(library.connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        table.clear(library.connections)

        for index = #library.hidden, 1, -1 do
            local entry = library.hidden[index]
            safeRemoveDrawing(entry[1])
            table.remove(library.hidden, index)
        end

        for index = #library.drawings, 1, -1 do
            local entry = library.drawings[index]
            safeRemoveDrawing(entry[1])
            table.remove(library.drawings, index)
        end

        table.clear(library.began)
        table.clear(library.ended)
        table.clear(library.changed)
        table.clear(library.pointers)

        UserInputService.MouseIconEnabled = true
    end

    --==========================================================
    -- WINDOW DRAGGING
    --==========================================================

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and utility:MouseOverDrawing({
                window.main_frame.Position.X,
                window.main_frame.Position.Y,
                window.main_frame.Position.X + window.main_frame.Size.X,
                window.main_frame.Position.Y + 20,
            })
        then
            local mouse = utility:MouseLocation()
            window.dragging = true
            window.drag = mouse - window.main_frame.Position
        end
    end)

    table.insert(library.ended, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            window.dragging = false
        end
    end)

    -- Dragging is intentionally handled once per rendered frame rather than
    -- once per InputChanged event. This is substantially cheaper on executors
    -- whose mouse-movement signal fires more than once per rendered frame.
    utility:Connection(RunService.RenderStepped, function()
        if not window.dragging or not window.isVisible then
            return
        end

        local mouse = utility:MouseLocation()
        local screen = utility:GetScreenSize()
        local desired = mouse - window.drag

        local maximumX = math.max(5, screen.X - window.main_frame.Size.X - 5)
        local maximumY = math.max(5, screen.Y - window.main_frame.Size.Y - 5)

        desired = Vector2.new(
            math.clamp(desired.X, 5, maximumX),
            math.clamp(desired.Y, 5, maximumY)
        )

        window:Move(desired)
    end)

    table.insert(library.began, function(input)
        if input.KeyCode == window.uibind then
            window:Fade()
        end
    end)

    utility:Connection(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
        local screen = utility:GetScreenSize()
        local desired = Vector2.new(
            math.floor((screen.X - window.main_frame.Size.X) / 2),
            math.floor((screen.Y - window.main_frame.Size.Y) / 2)
        )

        window:Move(desired)
    end)

    return window
end

--==============================================================
-- INPUT DISPATCH
--==============================================================

local inputConnectionsInitialized = false

local function initializeInputConnections()
    if inputConnectionsInitialized then
        return
    end

    inputConnectionsInitialized = true

    utility:Connection(UserInputService.InputBegan, function(input)
        for _, callback in ipairs(library.began) do
            local ok = pcall(callback, input)

            if not ok then
                -- UI input callbacks are isolated so one malformed control
                -- cannot disable every other control.
            end
        end
    end)

    utility:Connection(UserInputService.InputEnded, function(input)
        for _, callback in ipairs(library.ended) do
            pcall(callback, input)
        end
    end)

    utility:Connection(UserInputService.InputChanged, function(input)
        for _, callback in ipairs(library.changed) do
            pcall(callback, input)
        end
    end)

    utility:Connection(RunService.RenderStepped, function(delta)
        if delta > 0 then
            library.shared.fps = math.floor(1 / delta + 0.5)
        end
    end)
end

initializeInputConnections()

--==============================================================
-- PAGE
--==============================================================

function library:Page(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Page"
    local window = self

    local page = {
        open = false,
        sections = {},
        sectionOffset = {
            left = 0,
            right = 0,
        },
        window = window,
    }

    setmetatable(page, pages)

    local buttonX = window.back_frame.Position.X + 4

    for _, existingPage in ipairs(window.pages) do
        buttonX = buttonX + existingPage.page_button.Size.X + 2
    end

    local textBounds = utility:GetTextBounds(name, theme.textsize, theme.font)
    local buttonSize = Vector2.new(textBounds.X + 20, 22)

    local buttonOutline = createSquare(
        nil,
        Vector2.new(buttonX, window.back_frame.Position.Y + 4),
        buttonSize,
        theme.outline,
        {ZIndex = 48}
    )

    page.page_button = buttonOutline

    local buttonInline = createSquare(
        nil,
        buttonOutline.Position + Vector2.new(1, 1),
        buttonOutline.Size - Vector2.new(2, 1),
        theme.inline,
        {ZIndex = 49}
    )

    page.page_button_inline = buttonInline

    local buttonColor = createSquare(
        nil,
        buttonInline.Position + Vector2.new(1, 1),
        buttonInline.Size - Vector2.new(2, 1),
        theme.dark_contrast,
        {ZIndex = 50}
    )

    page.page_button_color = buttonColor

    createText(
        nil,
        name,
        Vector2.new(
            buttonColor.Position.X + buttonColor.Size.X / 2,
            buttonColor.Position.Y + 3
        ),
        {
            Center = true,
            ZIndex = 51,
        }
    )

    table.insert(window.pages, page)

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and page.page_button.Visible
            and pointInside(page.page_button.Position, page.page_button.Size, utility:MouseLocation())
            and window.currentPage ~= page
        then
            page:Show()
        end
    end)

    return page
end

function pages:_moveSection(section, desiredPosition)
    local delta = desiredPosition - section.section_inline.Position

    if delta.Magnitude <= 0 then
        return
    end

    for _, drawing in ipairs(section.visibleContent) do
        shiftDrawing(drawing, delta)
    end
end

function pages:Update()
    local offsets = {
        left = 5,
        right = 5,
    }

    for _, section in ipairs(self.sections) do
        local side = section.side
        local x

        if side == "right" then
            x = self.window.tab_frame.Position.X + self.window.tab_frame.Size.X / 2 + 2
        else
            x = self.window.tab_frame.Position.X + 5
        end

        local desired = Vector2.new(
            x,
            self.window.tab_frame.Position.Y + offsets[side]
        )

        self:_moveSection(section, desired)
        offsets[side] = offsets[side] + section.section_inline.Size.Y + 5
    end

    self.sectionOffset.left = offsets.left - 5
    self.sectionOffset.right = offsets.right - 5
end

function pages:Show()
    local window = self.window

    if window.currentPage and window.currentPage ~= self then
        local oldPage = window.currentPage
        oldPage.open = false
        utility:SetThemeProperty(
            oldPage.page_button_color,
            "Color",
            "dark_contrast"
        )

        for _, section in ipairs(oldPage.sections) do
            for _, drawing in ipairs(section.visibleContent) do
                drawing.Visible = false
            end
        end

        window:CloseContent()
    end

    window.currentPage = self
    self.open = true
    utility:SetThemeProperty(
        self.page_button_color,
        "Color",
        "light_contrast"
    )

    for _, section in ipairs(self.sections) do
        for _, drawing in ipairs(section.visibleContent) do
            drawing.Visible = true
        end
    end
end

--==============================================================
-- SECTION
--==============================================================

function pages:Section(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Section"
    local side = string.lower(info.Side or info.side or "left")

    if side ~= "right" then
        side = "left"
    end

    local page = self
    local window = self.window

    local section = {
        window = window,
        page = page,
        visibleContent = {},
        currentAxis = 20,
        side = side,
    }

    setmetatable(section, sections)

    local width = window.tab_frame.Size.X / 2 - 7
    local x = side == "right"
        and window.tab_frame.Position.X + window.tab_frame.Size.X / 2 + 2
        or window.tab_frame.Position.X + 5

    local y = window.tab_frame.Position.Y + 5 + (page.sectionOffset[side] or 0)

    local sectionInline = createSquare(
        section.visibleContent,
        Vector2.new(x, y),
        Vector2.new(width, 24),
        theme.inline,
        {
            Visible = page.open,
            ZIndex = 50,
        }
    )

    section.section_inline = sectionInline

    local sectionOutline = createSquare(
        section.visibleContent,
        sectionInline.Position + Vector2.new(1, 1),
        sectionInline.Size - Vector2.new(2, 2),
        theme.outline,
        {
            Visible = page.open,
            ZIndex = 51,
        }
    )

    section.section_outline = sectionOutline

    local sectionFrame = createSquare(
        section.visibleContent,
        sectionOutline.Position + Vector2.new(1, 1),
        sectionOutline.Size - Vector2.new(2, 2),
        theme.dark_contrast,
        {
            Visible = page.open,
            ZIndex = 52,
        }
    )

    section.section_frame = sectionFrame

    local sectionAccent = createSquare(
        section.visibleContent,
        sectionFrame.Position,
        Vector2.new(sectionFrame.Size.X, 2),
        theme.accent,
        {
            Visible = page.open,
            ZIndex = 53,
        }
    )

    section.section_accent = sectionAccent

    section.section_title = createText(
        section.visibleContent,
        name,
        sectionFrame.Position + Vector2.new(4, 4),
        {
            Visible = page.open,
            ZIndex = 54,
        }
    )

    page.sectionOffset[side] = (page.sectionOffset[side] or 0) + sectionInline.Size.Y + 5
    table.insert(page.sections, section)

    return section
end

function sections:Update()
    local desiredHeight = self.currentAxis + 4

    self.section_inline.Size = Vector2.new(
        self.section_inline.Size.X,
        desiredHeight
    )

    self.section_outline.Size = self.section_inline.Size - Vector2.new(2, 2)
    self.section_frame.Size = self.section_outline.Size - Vector2.new(2, 2)
    self.section_accent.Size = Vector2.new(self.section_frame.Size.X, 2)

    self.page:Update()
end

function pages:MultiSection(info)
    info = info or {}

    local names = info.Sections or info.sections or {"Main"}
    local side = info.Side or info.side or "left"

    local created = {}

    for _, name in ipairs(names) do
        local section = self:Section({
            Name = name,
            Side = side,
        })

        table.insert(created, section)
    end

    return table.unpack(created)
end

--==============================================================
-- POINTER REGISTRATION
--==============================================================

local function registerPointer(pointer, control)
    if pointer == nil then
        return
    end

    local key = tostring(pointer)

    if key == "" or key == " " then
        return
    end

    if library.pointers[key] == nil then
        library.pointers[key] = control
    end
end

--==============================================================
-- LABEL
--==============================================================

function sections:Label(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Label"
    local middle = info.Middle or info.middle or false
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag

    local label = {
        axis = self.currentAxis,
    }

    local bounds = utility:GetTextBounds(name, theme.textsize, theme.font)

    label.title = createText(
        self.visibleContent,
        name,
        Vector2.new(
            middle and self.section_frame.Position.X + self.section_frame.Size.X / 2 or self.section_frame.Position.X + 4,
            self.section_frame.Position.Y + label.axis
        ),
        {
            Center = middle,
            Visible = self.page.open,
            ZIndex = 56,
        }
    )

    registerPointer(pointer, label)

    self.currentAxis = self.currentAxis + bounds.Y + 4
    self:Update()

    return label
end

--==============================================================
-- TOGGLE
--==============================================================

function sections:Toggle(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Toggle"
    local default = info.Default

    if default == nil then
        default = info.default
    end

    if default == nil then
        default = info.Def
    end

    if default == nil then
        default = info.def
    end

    default = default == true

    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local section = self
    local window = self.window
    local page = self.page

    local toggle = {
        axis = section.currentAxis,
        current = default,
        addedAxis = 0,
        colorpickers = 0,
        keybind = nil,
    }

    local outline = createSquare(
        section.visibleContent,
        section.section_frame.Position + Vector2.new(4, toggle.axis),
        Vector2.new(15, 15),
        theme.outline,
        {
            Visible = page.open,
            ZIndex = 56,
        }
    )

    local inline = createSquare(
        section.visibleContent,
        outline.Position + Vector2.new(1, 1),
        outline.Size - Vector2.new(2, 2),
        theme.inline,
        {
            Visible = page.open,
            ZIndex = 57,
        }
    )

    local frame = createSquare(
        section.visibleContent,
        inline.Position + Vector2.new(1, 1),
        inline.Size - Vector2.new(2, 2),
        toggle.current and theme.accent or theme.light_contrast,
        {
            Visible = page.open,
            ZIndex = 58,
        }
    )

    toggle.frame = frame

    createText(
        section.visibleContent,
        name,
        section.section_frame.Position + Vector2.new(23, toggle.axis + 1),
        {
            Visible = page.open,
            ZIndex = 58,
        }
    )

    function toggle:Get()
        return self.current
    end

    function toggle:Set(value)
        self.current = value == true
        utility:SetThemeProperty(
            self.frame,
            "Color",
            self.current and "accent" or "light_contrast"
        )
        callback(self.current)
    end

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and page.open
            and outline.Visible
            and not window:IsOverContent()
        then
            local mouse = utility:MouseLocation()
            local clickableWidth = math.max(15, section.section_frame.Size.X - toggle.addedAxis)
            local clickablePosition = Vector2.new(section.section_frame.Position.X, outline.Position.Y)
            local clickableSize = Vector2.new(clickableWidth, 15)

            if pointInside(clickablePosition, clickableSize, mouse) then
                toggle:Set(not toggle.current)
            end
        end
    end)

    registerPointer(pointer, toggle)

    section.currentAxis = section.currentAxis + 19
    section:Update()

    -- Nested helpers are assigned after the main implementations exist.
    return toggle
end

--==============================================================
-- SLIDER
--==============================================================

function sections:Slider(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Slider"
    local minimum = info.Minimum or info.minimum or info.Min or info.min or 0
    local maximum = info.Maximum or info.maximum or info.Max or info.max or 100
    local default = info.Default or info.default or info.Def or info.def or minimum
    local measurement = info.Measurement or info.measurement or info.Suffix or info.suffix or ""
    local decimalStep = info.Decimals or info.decimals or 1
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local section = self
    local window = self.window
    local page = self.page

    local slider = {
        min = minimum,
        max = maximum,
        sub = measurement,
        step = decimalStep,
        axis = section.currentAxis,
        current = math.clamp(default, minimum, maximum),
        holding = false,
    }

    local title = createText(
        section.visibleContent,
        name,
        section.section_frame.Position + Vector2.new(4, slider.axis),
        {
            Visible = page.open,
            ZIndex = 56,
        }
    )

    local outline = createSquare(
        section.visibleContent,
        section.section_frame.Position + Vector2.new(4, slider.axis + 15),
        Vector2.new(section.section_frame.Size.X - 8, 12),
        theme.outline,
        {
            Visible = page.open,
            ZIndex = 56,
        }
    )

    local inline = createSquare(
        section.visibleContent,
        outline.Position + Vector2.new(1, 1),
        outline.Size - Vector2.new(2, 2),
        theme.inline,
        {
            Visible = page.open,
            ZIndex = 57,
        }
    )

    local frame = createSquare(
        section.visibleContent,
        inline.Position + Vector2.new(1, 1),
        inline.Size - Vector2.new(2, 2),
        theme.light_contrast,
        {
            Visible = page.open,
            ZIndex = 58,
        }
    )

    local slide = createSquare(
        section.visibleContent,
        frame.Position,
        Vector2.new(1, frame.Size.Y),
        theme.accent,
        {
            Visible = page.open,
            ZIndex = 59,
        }
    )

    local valueText = createText(
        section.visibleContent,
        "",
        Vector2.new(outline.Position.X + outline.Size.X / 2, outline.Position.Y - 1),
        {
            Center = true,
            Visible = page.open,
            ZIndex = 60,
        }
    )

    slider.outline = outline
    slider.frame = frame
    slider.slide = slide
    slider.valueText = valueText

    local function getStepPrecision(step)
        step = math.abs(tonumber(step) or 1)

        if step == 0 then
            return 6
        end

        -- Find how many decimal places are actually required by the slider
        -- increment. This prevents binary floating-point noise in the UI while
        -- still preserving values such as 0.025.
        for precision = 0, 8 do
            local scale = 10 ^ precision
            local scaled = step * scale

            if math.abs(scaled - math.round(scaled)) < 1e-7 then
                return precision
            end
        end

        return 8
    end

    local stepPrecision = getStepPrecision(slider.step)

    local function cleanNumber(value)
        local formatted = string.format(
            "%." .. tostring(stepPrecision) .. "f",
            tonumber(value) or 0
        )

        if string.find(formatted, ".", 1, true) then
            formatted = formatted:gsub("0+$", "")
            formatted = formatted:gsub("%.$", "")
        end

        if formatted == "-0" then
            formatted = "0"
        end

        return formatted
    end

    local function roundToStep(value)
        local step = tonumber(slider.step) or 1

        if step <= 0 then
            return value
        end

        local rounded = math.round(value / step) * step

        -- Normalize the numeric value too, so callbacks/configs do not receive
        -- avoidable floating-point noise.
        return tonumber(cleanNumber(rounded)) or rounded
    end

    function slider:Set(value)
        value = tonumber(value) or self.min
        value = math.clamp(roundToStep(value), self.min, self.max)
        self.current = value

        local range = self.max - self.min
        local percent = range == 0 and 0 or (self.current - self.min) / range

        self.slide.Size = Vector2.new(
            math.max(0, self.frame.Size.X * percent),
            self.frame.Size.Y
        )

        self.valueText.Text =
            cleanNumber(self.current)
            .. self.sub
            .. "/"
            .. cleanNumber(self.max)
            .. self.sub

        callback(self.current)
    end

    function slider:Get()
        return self.current
    end

    function slider:Refresh()
        local mouse = utility:MouseLocation()
        local percent = math.clamp((mouse.X - self.frame.Position.X) / self.frame.Size.X, 0, 1)
        self:Set(self.min + (self.max - self.min) * percent)
    end

    slider:Set(slider.current)

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and page.open
            and outline.Visible
            and not window:IsOverContent()
            and pointInside(
                Vector2.new(section.section_frame.Position.X, section.section_frame.Position.Y + slider.axis),
                Vector2.new(section.section_frame.Size.X, 27),
                utility:MouseLocation()
            )
        then
            slider.holding = true
            slider:Refresh()
        end
    end)

    table.insert(library.ended, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            slider.holding = false
        end
    end)

    table.insert(library.changed, function()
        if slider.holding and window.isVisible and page.open then
            slider:Refresh()
        end
    end)

    registerPointer(pointer, slider)

    section.currentAxis = section.currentAxis + 31
    section:Update()

    return slider
end

--==============================================================
-- BUTTON
--==============================================================

function sections:Button(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Button"
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local section = self
    local window = self.window
    local page = self.page

    local button = {
        axis = section.currentAxis,
    }

    local outline, inline, frame = createOutlineBox(
        section.visibleContent,
        section.section_frame.Position + Vector2.new(4, button.axis),
        Vector2.new(section.section_frame.Size.X - 8, 20),
        theme.light_contrast,
        page.open
    )

    createText(
        section.visibleContent,
        name,
        Vector2.new(frame.Position.X + frame.Size.X / 2, frame.Position.Y + 1),
        {
            Center = true,
            Visible = page.open,
            ZIndex = 60,
        }
    )

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and page.open
            and outline.Visible
            and not window:IsOverContent()
            and pointInside(outline.Position, outline.Size, utility:MouseLocation())
        then
            callback()
        end
    end)

    registerPointer(pointer, button)

    section.currentAxis = section.currentAxis + 24
    section:Update()

    return button
end

function sections:ButtonHolder(info)
    info = info or {}

    local buttons = info.Buttons or info.buttons or {}
    local section = self
    local axis = section.currentAxis

    for index = 1, math.min(2, #buttons) do
        local buttonInfo = buttons[index]
        local name = buttonInfo[1] or buttonInfo.Name or "Button"
        local callback = buttonInfo[2] or buttonInfo.Callback or function() end
        local halfWidth = section.section_frame.Size.X / 2 - 6
        local x = index == 1
            and section.section_frame.Position.X + 4
            or section.section_frame.Position.X + section.section_frame.Size.X / 2 + 2

        local outline, _, frame = createOutlineBox(
            section.visibleContent,
            Vector2.new(x, section.section_frame.Position.Y + axis),
            Vector2.new(halfWidth, 20),
            theme.light_contrast,
            section.page.open
        )

        createText(
            section.visibleContent,
            name,
            Vector2.new(frame.Position.X + frame.Size.X / 2, frame.Position.Y + 1),
            {
                Center = true,
                Visible = section.page.open,
                ZIndex = 60,
            }
        )

        table.insert(library.began, function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                and section.window.isVisible
                and section.page.open
                and outline.Visible
                and not section.window:IsOverContent()
                and pointInside(outline.Position, outline.Size, utility:MouseLocation())
            then
                callback()
            end
        end)
    end

    section.currentAxis = section.currentAxis + 24
    section:Update()
end

--==============================================================
-- DROPDOWN
--==============================================================

function sections:Dropdown(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Dropdown"
    local options = info.Options or info.options or {"1", "2", "3"}
    local default = info.Default or info.default or info.Def or info.def or options[1]
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local section = self
    local window = self.window
    local page = self.page

    local dropdown = {
        open = false,
        current = tostring(default),
        options = options,
        axis = section.currentAxis,
        holder = {
            drawings = {},
            buttons = {},
            frame = nil,
        },
    }

    createText(
        section.visibleContent,
        name,
        section.section_frame.Position + Vector2.new(4, dropdown.axis),
        {
            Visible = page.open,
            ZIndex = 56,
        }
    )

    local outline, _, frame = createOutlineBox(
        section.visibleContent,
        section.section_frame.Position + Vector2.new(4, dropdown.axis + 15),
        Vector2.new(section.section_frame.Size.X - 8, 20),
        theme.light_contrast,
        page.open
    )

    local valueText = createText(
        section.visibleContent,
        dropdown.current,
        frame.Position + Vector2.new(4, 2),
        {
            Visible = page.open,
            ZIndex = 60,
        }
    )

    local arrow = createText(
        section.visibleContent,
        "v",
        Vector2.new(frame.Position.X + frame.Size.X - 10, frame.Position.Y + 1),
        {
            Visible = page.open,
            ZIndex = 60,
        }
    )

    dropdown.outline = outline
    dropdown.valueText = valueText
    dropdown.arrow = arrow

    function dropdown:Get()
        return self.current
    end

    function dropdown:Set(value)
        if table.find(self.options, value) then
            self.current = tostring(value)
            self.valueText.Text = self.current
            callback(self.current)
        end
    end

    function dropdown:Close()
        if not self.open then
            return
        end

        self.open = false
        self.arrow.Text = "v"

        for index = #self.holder.drawings, 1, -1 do
            utility:Remove(self.holder.drawings[index])
        end

        table.clear(self.holder.drawings)
        table.clear(self.holder.buttons)
        self.holder.frame = nil

        if window.currentContent.control == self then
            window.currentContent.frame = nil
            window.currentContent.control = nil
        end
    end

    function dropdown:Open()
        if self.open then
            return
        end

        window:CloseContent()
        self.open = true
        self.arrow.Text = "^"

        local popupHeight = #self.options * 19 + 2
        local popupPosition = self.outline.Position + Vector2.new(0, self.outline.Size.Y)

        local popupOutline, popupInline, popupFrame = createOutlineBox(
            self.holder.drawings,
            popupPosition,
            Vector2.new(self.outline.Size.X, popupHeight),
            theme.dark_contrast,
            true
        )

        popupOutline.ZIndex = 70
        popupInline.ZIndex = 71
        popupFrame.ZIndex = 72

        self.holder.frame = popupOutline

        for index, option in ipairs(self.options) do
            local rowPosition = popupFrame.Position + Vector2.new(2, (index - 1) * 19 + 1)
            local rowSize = Vector2.new(popupFrame.Size.X - 4, 18)

            local row = createSquare(
                self.holder.drawings,
                rowPosition,
                rowSize,
                theme.light_contrast,
                {ZIndex = 73}
            )

            local text = createText(
                self.holder.drawings,
                tostring(option),
                rowPosition + Vector2.new(option == self.current and 8 or 6, 2),
                {
                    Color = tostring(option) == self.current and theme.accent or theme.textcolor,
                    ZIndex = 74,
                }
            )

            table.insert(self.holder.buttons, {
                value = tostring(option),
                row = row,
                text = text,
            })
        end

        window.currentContent.frame = popupOutline
        window.currentContent.control = self
    end

    table.insert(library.began, function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            or not window.isVisible
            or not page.open
            or not outline.Visible
        then
            return
        end

        local mouse = utility:MouseLocation()

        if dropdown.open and dropdown.holder.frame and pointInside(
            dropdown.holder.frame.Position,
            dropdown.holder.frame.Size,
            mouse
        ) then
            for _, button in ipairs(dropdown.holder.buttons) do
                if pointInside(button.row.Position, button.row.Size, mouse) then
                    if dropdown.ToggleValue then
                        dropdown:ToggleValue(button.value)
                    else
                        dropdown:Set(button.value)
                        dropdown:Close()
                    end
                    return
                end
            end

            return
        end

        if pointInside(outline.Position, outline.Size, mouse) and not window:IsOverContent() then
            if dropdown.open then
                dropdown:Close()
            else
                dropdown:Open()
            end

            return
        end

        if dropdown.open then
            dropdown:Close()
        end
    end)

    registerPointer(pointer, dropdown)

    section.currentAxis = section.currentAxis + 39
    section:Update()

    return dropdown
end

--==============================================================
-- MULTIBOX
--==============================================================

function sections:Multibox(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Multibox"
    local options = info.Options or info.options or {"1", "2", "3"}
    local default = info.Default or info.default or info.Def or info.def or {options[1]}
    local minimum = info.Minimum or info.minimum or info.Min or info.min or 0
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local dropdown = self:Dropdown({
        Name = name,
        Options = options,
        Default = options[1],
    })

    dropdown.current = table.clone(default)
    dropdown.minimum = minimum

    local function serialize(values)
        local result = {}

        for _, option in ipairs(options) do
            if table.find(values, option) then
                table.insert(result, option)
            end
        end

        return table.concat(result, ", ")
    end

    dropdown.valueText.Text = serialize(dropdown.current)

    function dropdown:Get()
        return table.clone(self.current)
    end

    function dropdown:Set(values)
        if type(values) ~= "table" then
            return
        end

        self.current = table.clone(values)
        self.valueText.Text = serialize(self.current)
        callback(table.clone(self.current))
    end

    local oldOpen = dropdown.Open

    function dropdown:Open()
        oldOpen(self)

        if not self.open then
            return
        end

        for _, button in ipairs(self.holder.buttons) do
            local selected = table.find(self.current, button.value) ~= nil
            utility:SetThemeProperty(
                button.text,
                "Color",
                selected and "accent" or "textcolor"
            )
            button.text.Position = button.row.Position + Vector2.new(selected and 8 or 6, 2)
        end
    end

    function dropdown:ToggleValue(value)
        local found = table.find(self.current, value)

        if found then
            if #self.current > self.minimum then
                table.remove(self.current, found)
            end
        else
            table.insert(self.current, value)
        end

        self.valueText.Text = serialize(self.current)

        for _, button in ipairs(self.holder.buttons) do
            local selected = table.find(self.current, button.value) ~= nil
            utility:SetThemeProperty(
                button.text,
                "Color",
                selected and "accent" or "textcolor"
            )
            button.text.Position = button.row.Position + Vector2.new(selected and 8 or 6, 2)
        end

        callback(table.clone(self.current))
    end

    registerPointer(pointer, dropdown)
    return dropdown
end

--==============================================================
-- KEYBIND
--==============================================================

function sections:Keybind(info)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "New Keybind"
    local default = info.Default or info.default or info.Def or info.def
    local mode = info.Mode or info.mode or "Always"
    local keybindName = info.KeybindName or info.keybindName or info.Keybindname or info.keybindname or name
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local section = self
    local window = self.window
    local page = self.page

    local keybind = {
        keybindname = keybindName,
        axis = section.currentAxis,
        current = {},
        selecting = false,
        mode = mode,
        active = mode == "Always",
        open = false,
        holding = false,
    }

    createText(
        section.visibleContent,
        name,
        section.section_frame.Position + Vector2.new(4, keybind.axis + 2),
        {
            Visible = page.open,
            ZIndex = 56,
        }
    )

    local outline, _, frame = createOutlineBox(
        section.visibleContent,
        Vector2.new(
            section.section_frame.Position.X + section.section_frame.Size.X - 44,
            section.section_frame.Position.Y + keybind.axis
        ),
        Vector2.new(40, 17),
        theme.light_contrast,
        page.open
    )

    local valueText = createText(
        section.visibleContent,
        "...",
        Vector2.new(frame.Position.X + frame.Size.X / 2, frame.Position.Y + 1),
        {
            Center = true,
            Visible = page.open,
            ZIndex = 60,
        }
    )

    keybind.outline = outline
    keybind.frame = frame
    keybind.valueText = valueText

    function keybind:Change(input)
        if typeof(input) == "EnumItem" then
            if input.EnumType == Enum.KeyCode then
                self.current = {"KeyCode", input.Name}
            elseif input.EnumType == Enum.UserInputType then
                self.current = {"UserInputType", input.Name}
            else
                return false
            end
        elseif type(input) == "table" and input[1] and input[2] then
            self.current = {input[1], input[2]}
        else
            return false
        end

        self.valueText.Text = shortenKeyName(self.current[2])
        return true
    end

    function keybind:Set(value)
        if typeof(value) == "EnumItem" then
            self:Change(value)
        elseif type(value) == "table" then
            self:Change(value)
        end
    end

    function keybind:Get()
        return table.clone(self.current)
    end

    function keybind:Active()
        return self.active
    end

    function keybind:Reset()
        self.active = self.mode == "Always"
        local enumValue = resolveEnumTable(self.current)

        if enumValue then
            callback(enumValue, self.active)
        end
    end

    if default then
        keybind:Change(default)
    end

    table.insert(library.began, function(input)
        if keybind.selecting and window.isVisible then
            local candidate

            if input.KeyCode and input.KeyCode ~= Enum.KeyCode.Unknown then
                candidate = input.KeyCode
            elseif
                input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3
            then
                candidate = input.UserInputType
            end

            if candidate and keybind:Change(candidate) then
                keybind.selecting = false
                utility:SetThemeProperty(
                    keybind.frame,
                    "Color",
                    "light_contrast"
                )
                keybind.active = keybind.mode == "Always"
                callback(candidate, keybind.active)
            end

            return
        end

        local bound = resolveEnumTable(keybind.current)

        if bound then
            local matched = input.KeyCode == bound or input.UserInputType == bound

            if matched then
                if keybind.mode == "Toggle" then
                    keybind.active = not keybind.active
                    callback(bound, keybind.active)
                elseif keybind.mode == "Hold" then
                    keybind.active = true
                    callback(bound, true)
                elseif keybind.mode == "Always" then
                    callback(bound, true)
                end
            end
        end

        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and window.isVisible
            and page.open
            and outline.Visible
            and not window:IsOverContent()
            and pointInside(outline.Position, outline.Size, utility:MouseLocation())
        then
            keybind.selecting = true
            utility:SetThemeProperty(
                keybind.frame,
                "Color",
                "dark_contrast"
            )
            keybind.valueText.Text = "..."
        end
    end)

    table.insert(library.ended, function(input)
        if keybind.mode ~= "Hold" or not keybind.active then
            return
        end

        local bound = resolveEnumTable(keybind.current)

        if bound and (input.KeyCode == bound or input.UserInputType == bound) then
            keybind.active = false
            callback(bound, false)
        end
    end)

    registerPointer(pointer, keybind)

    section.currentAxis = section.currentAxis + 21
    section:Update()

    return keybind
end

--==============================================================
-- COLOR PICKER
--==============================================================

local function buildColorpicker(section, info, axis, compactRightOffset)
    info = info or {}

    local name = info.Name or info.name or info.Title or info.title or "Color"
    local pickerTitle = info.Info or info.info or name
    local default = info.Default or info.default or info.Def or info.def or Color3.fromRGB(255, 0, 0)
    local transparency = info.Transparency or info.transparency or info.Transp or info.transp or info.Alpha or info.alpha
    local pointer = info.Pointer or info.pointer or info.Flag or info.flag
    local callback = info.Callback or info.callback or info.CallBack or info.callBack or function() end

    local window = section.window
    local page = section.page
    local hue, saturation, brightness = default:ToHSV()

    local colorpicker = {
        axis = axis,
        current = {hue, saturation, brightness, transparency or 0},
        open = false,
        holding = {
            picker = false,
            huepicker = false,
            transparency = false,
        },
        holder = {
            drawings = {},
            frame = nil,
            picker = nil,
            background = nil,
            picker_cursor = nil,
            huepicker = nil,
            huepicker_cursor = nil,
            transparency = nil,
            transparency_cursor = nil,
            transparencybg = nil,
        },
    }

    local swatchX = section.section_frame.Position.X + section.section_frame.Size.X - compactRightOffset

    local outline, inline, frame = createOutlineBox(
        section.visibleContent,
        Vector2.new(swatchX, section.section_frame.Position.Y + axis),
        Vector2.new(30, 15),
        default,
        page.open,
        false
    )

    if transparency ~= nil then
        createCheckerboard(
            section.visibleContent,
            frame.Position,
            frame.Size,
            6,
            2,
            page.open,
            57
        )
        frame.ZIndex = 58
    end

    frame.Color = default
    frame.Transparency = transparency == nil and 1 or 1 - transparency

    colorpicker.outline = outline
    colorpicker.frame = frame

    if compactRightOffset == 34 then
        createText(
            section.visibleContent,
            name,
            section.section_frame.Position + Vector2.new(4, axis + 1),
            {
                Visible = page.open,
                ZIndex = 56,
            }
        )
    end

    local function currentColor()
        return Color3.fromHSV(
            colorpicker.current[1],
            colorpicker.current[2],
            colorpicker.current[3]
        )
    end

    local function updateCursorPositions()
        local holder = colorpicker.holder

        if holder.picker and holder.picker_cursor then
            holder.picker_cursor.Position = Vector2.new(
                holder.picker.Position.X + holder.picker.Size.X * colorpicker.current[2] - 3,
                holder.picker.Position.Y + holder.picker.Size.Y * (1 - colorpicker.current[3]) - 3
            )

            if holder.picker_cursor_inner then
                holder.picker_cursor_inner.Position = holder.picker_cursor.Position + Vector2.new(1, 1)
            end
        end

        if holder.huepicker and holder.huepicker_cursor then
            holder.huepicker_cursor.Position = Vector2.new(
                holder.huepicker.Position.X - 3,
                holder.huepicker.Position.Y + holder.huepicker.Size.Y * colorpicker.current[1] - 2
            )
        end

        if holder.transparency and holder.transparency_cursor then
            holder.transparency_cursor.Position = Vector2.new(
                holder.transparency.Position.X + holder.transparency.Size.X * (1 - colorpicker.current[4]) - 2,
                holder.transparency.Position.Y - 2
            )
        end
    end

    function colorpicker:Get()
        if transparency ~= nil then
            return {
                Color = currentColor(),
                Transparency = self.current[4],
            }
        end

        return currentColor()
    end

    function colorpicker:Set(color, transparencyValue)
        if type(color) == "table" and color.Color and color.Transparency ~= nil then
            local h, s, v = color.Color:ToHSV()
            self.current = {h, s, v, color.Transparency}

        elseif type(color) == "table" and color[1] and color[2] and color[3] then
            self.current = {
                color[1],
                color[2],
                color[3],
                color[4] or self.current[4],
            }

        elseif typeof(color) == "Color3" then
            local h, s, v = color:ToHSV()
            self.current[1] = h
            self.current[2] = s
            self.current[3] = v

            if transparencyValue ~= nil then
                self.current[4] = transparencyValue
            end
        else
            return
        end

        self.frame.Color = currentColor()

        if transparency ~= nil then
            self.frame.Transparency = 1 - self.current[4]
            utility:UpdateTransparency(self.frame, self.frame.Transparency)
        end

        if self.holder.background then
            self.holder.background.Color = Color3.fromHSV(self.current[1], 1, 1)
        end

        if self.holder.transparencybg then
            self.holder.transparencybg.Color = currentColor()
        end

        updateCursorPositions()
        callback(currentColor(), self.current[4])
    end

    function colorpicker:Refresh()
        local mouse = utility:MouseLocation()
        local holder = self.holder

        if self.holding.picker and holder.picker then
            self.current[2] = math.clamp(
                (mouse.X - holder.picker.Position.X) / holder.picker.Size.X,
                0,
                1
            )

            self.current[3] = 1 - math.clamp(
                (mouse.Y - holder.picker.Position.Y) / holder.picker.Size.Y,
                0,
                1
            )

        elseif self.holding.huepicker and holder.huepicker then
            self.current[1] = math.clamp(
                (mouse.Y - holder.huepicker.Position.Y) / holder.huepicker.Size.Y,
                0,
                1
            )

            if holder.background then
                holder.background.Color = Color3.fromHSV(self.current[1], 1, 1)
            end

        elseif self.holding.transparency and holder.transparency then
            self.current[4] = 1 - math.clamp(
                (mouse.X - holder.transparency.Position.X) / holder.transparency.Size.X,
                0,
                1
            )
        end

        self:Set(self.current)
    end

    function colorpicker:Close()
        if not self.open then
            return
        end

        self.open = false
        self.holding.picker = false
        self.holding.huepicker = false
        self.holding.transparency = false

        for index = #self.holder.drawings, 1, -1 do
            utility:Remove(self.holder.drawings[index])
        end

        table.clear(self.holder.drawings)
        self.holder.frame = nil
        self.holder.picker = nil
        self.holder.background = nil
        self.holder.picker_cursor = nil
        self.holder.picker_cursor_inner = nil
        self.holder.huepicker = nil
        self.holder.huepicker_cursor = nil
        self.holder.transparency = nil
        self.holder.transparency_cursor = nil
        self.holder.transparencybg = nil

        if window.currentContent.control == self then
            window.currentContent.frame = nil
            window.currentContent.control = nil
        end
    end

    function colorpicker:Open()
        if self.open then
            return
        end

        window:CloseContent()
        self.open = true

        local popupWidth = section.section_frame.Size.X - 8
        local popupHeight = transparency ~= nil and 219 or 200
        local popupPosition = Vector2.new(
            section.section_frame.Position.X + 4,
            section.section_frame.Position.Y + self.axis + 19
        )

        local popupOutline, popupInline, popupFrame = createOutlineBox(
            self.holder.drawings,
            popupPosition,
            Vector2.new(popupWidth, popupHeight),
            theme.dark_contrast,
            true
        )

        popupOutline.ZIndex = 70
        popupInline.ZIndex = 71
        popupFrame.ZIndex = 72

        self.holder.frame = popupOutline

        createSquare(
            self.holder.drawings,
            popupFrame.Position,
            Vector2.new(popupFrame.Size.X, 2),
            theme.accent,
            {ZIndex = 73}
        )

        createText(
            self.holder.drawings,
            pickerTitle,
            popupFrame.Position + Vector2.new(4, 3),
            {ZIndex = 74}
        )

        local pickerPosition = popupFrame.Position + Vector2.new(5, 18)
        local pickerSize = Vector2.new(
            popupFrame.Size.X - 29,
            popupFrame.Size.Y - (transparency ~= nil and 41 or 22)
        )

        local pickerOutline, pickerInline = createOutlineBox(
            self.holder.drawings,
            pickerPosition - Vector2.new(2, 2),
            pickerSize + Vector2.new(4, 4),
            theme.inline,
            true
        )

        pickerOutline.ZIndex = 74
        pickerInline.ZIndex = 75

        local background = createSVOverlay(
            self.holder.drawings,
            pickerPosition,
            pickerSize,
            self.current[1],
            true
        )

        -- createSVOverlay returns background as its first value.
        self.holder.background = background
        self.holder.picker = background

        local pickerCursor = createSquare(
            self.holder.drawings,
            Vector2.new(0, 0),
            Vector2.new(6, 6),
            Color3.fromRGB(255, 255, 255),
            {
                Filled = false,
                Thickness = 1,
                ZIndex = 84,
                ThemeKey = false,
            }
        )

        self.holder.picker_cursor = pickerCursor

        local pickerCursorInner = createSquare(
            self.holder.drawings,
            Vector2.new(0, 0),
            Vector2.new(4, 4),
            Color3.fromRGB(0, 0, 0),
            {
                Filled = false,
                Thickness = 1,
                ZIndex = 85,
                ThemeKey = false,
            }
        )

        -- Keep the inner cursor attached manually during refresh/move.
        self.holder.picker_cursor_inner = pickerCursorInner

        local huePosition = Vector2.new(
            popupFrame.Position.X + popupFrame.Size.X - 18,
            pickerPosition.Y
        )

        local hueSize = Vector2.new(12, pickerSize.Y)

        local hueOutline, hueInline = createOutlineBox(
            self.holder.drawings,
            huePosition - Vector2.new(2, 2),
            hueSize + Vector2.new(4, 4),
            theme.inline,
            true
        )

        hueOutline.ZIndex = 74
        hueInline.ZIndex = 75

        local hueHitbox = createSquare(
            self.holder.drawings,
            huePosition,
            hueSize,
            Color3.fromRGB(255, 255, 255),
            {
                Transparency = 0,
                ZIndex = 60,
                ThemeKey = false,
            }
        )

        self.holder.huepicker = hueHitbox
        createHueStrip(self.holder.drawings, huePosition, hueSize, true)

        local hueCursor = createSquare(
            self.holder.drawings,
            Vector2.new(0, 0),
            Vector2.new(hueSize.X + 6, 4),
            Color3.fromRGB(255, 255, 255),
            {
                Filled = false,
                Thickness = 1,
                ZIndex = 84,
                ThemeKey = false,
            }
        )

        self.holder.huepicker_cursor = hueCursor

        if transparency ~= nil then
            local transparencyPosition = Vector2.new(
                pickerPosition.X,
                popupFrame.Position.Y + popupFrame.Size.Y - 17
            )

            local transparencySize = Vector2.new(pickerSize.X, 10)

            local transparencyOutline, transparencyInline = createOutlineBox(
                self.holder.drawings,
                transparencyPosition - Vector2.new(2, 2),
                transparencySize + Vector2.new(4, 4),
                theme.inline,
                true
            )

            transparencyOutline.ZIndex = 74
            transparencyInline.ZIndex = 75

            createCheckerboard(
                self.holder.drawings,
                transparencyPosition,
                transparencySize,
                12,
                2,
                true,
                76
            )

            local transparencyBackground = createSquare(
                self.holder.drawings,
                transparencyPosition,
                transparencySize,
                currentColor(),
                {
                    Transparency = 0.5,
                    ZIndex = 77,
                }
            )

            self.holder.transparencybg = transparencyBackground
            self.holder.transparency = transparencyBackground

            local transparencyCursor = createSquare(
                self.holder.drawings,
                Vector2.new(0, 0),
                Vector2.new(4, transparencySize.Y + 4),
                Color3.fromRGB(255, 255, 255),
                {
                    Filled = false,
                    Thickness = 1,
                    ZIndex = 78,
                }
            )

            self.holder.transparency_cursor = transparencyCursor
        end

        updateCursorPositions()

        if self.holder.picker_cursor_inner then
            self.holder.picker_cursor_inner.Position = self.holder.picker_cursor.Position + Vector2.new(1, 1)
        end

        window.currentContent.frame = popupOutline
        window.currentContent.control = self
    end

    table.insert(library.began, function(input)
        if
            input.UserInputType ~= Enum.UserInputType.MouseButton1
            or not window.isVisible
            or not page.open
            or not outline.Visible
        then
            return
        end

        local mouse = utility:MouseLocation()

        if colorpicker.open and colorpicker.holder.frame and pointInside(
            colorpicker.holder.frame.Position,
            colorpicker.holder.frame.Size,
            mouse
        ) then
            if colorpicker.holder.picker and pointInside(
                colorpicker.holder.picker.Position,
                colorpicker.holder.picker.Size,
                mouse
            ) then
                colorpicker.holding.picker = true
                colorpicker:Refresh()
                return
            end

            if colorpicker.holder.huepicker and pointInside(
                colorpicker.holder.huepicker.Position,
                colorpicker.holder.huepicker.Size,
                mouse
            ) then
                colorpicker.holding.huepicker = true
                colorpicker:Refresh()
                return
            end

            if colorpicker.holder.transparency and pointInside(
                colorpicker.holder.transparency.Position,
                colorpicker.holder.transparency.Size,
                mouse
            ) then
                colorpicker.holding.transparency = true
                colorpicker:Refresh()
                return
            end

            return
        end

        if pointInside(outline.Position, outline.Size, mouse) and not window:IsOverContent() then
            if colorpicker.open then
                colorpicker:Close()
            else
                colorpicker:Open()
            end

            return
        end

        if colorpicker.open then
            colorpicker:Close()
        end
    end)

    table.insert(library.ended, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            colorpicker.holding.picker = false
            colorpicker.holding.huepicker = false
            colorpicker.holding.transparency = false
        end
    end)

    table.insert(library.changed, function()
        if
            colorpicker.open
            and window.isVisible
            and (
                colorpicker.holding.picker
                or colorpicker.holding.huepicker
                or colorpicker.holding.transparency
            )
        then
            colorpicker:Refresh()

            if colorpicker.holder.picker_cursor_inner and colorpicker.holder.picker_cursor then
                colorpicker.holder.picker_cursor_inner.Position = colorpicker.holder.picker_cursor.Position + Vector2.new(1, 1)
            end
        end
    end)

    registerPointer(pointer, colorpicker)
    colorpicker:Set(default, transparency or 0)

    return colorpicker
end

function sections:Colorpicker(info)
    local colorpicker = buildColorpicker(self, info, self.currentAxis, 34)

    self.currentAxis = self.currentAxis + 19
    self:Update()

    function colorpicker:Colorpicker(secondInfo)
        local second = buildColorpicker(
            self._section or colorpicker._section,
            secondInfo,
            colorpicker.axis,
            68
        )

        return second
    end

    colorpicker._section = self
    return colorpicker
end

--==============================================================
-- CONFIG BOX
--==============================================================

function sections:ConfigBox(info)
    info = info or {}

    local section = self
    local configBox = {
        axis = section.currentAxis,
        current = 1,
        buttons = {},
    }

    local outline, _, frame = createOutlineBox(
        section.visibleContent,
        section.section_frame.Position + Vector2.new(4, configBox.axis),
        Vector2.new(section.section_frame.Size.X - 8, 148),
        theme.light_contrast,
        section.page.open
    )

    for index = 1, 8 do
        local title = createText(
            section.visibleContent,
            "Config-Slot: " .. tostring(index),
            Vector2.new(frame.Position.X + frame.Size.X / 2, frame.Position.Y + 2 + (index - 1) * 18),
            {
                Center = true,
                Color = index == 1 and theme.accent or theme.textcolor,
                Visible = section.page.open,
                ZIndex = 60,
            }
        )

        configBox.buttons[index] = title
    end

    function configBox:Refresh()
        for index, button in ipairs(self.buttons) do
            utility:SetThemeProperty(
                button,
                "Color",
                index == self.current and "accent" or "textcolor"
            )
        end
    end

    function configBox:Get()
        return self.current
    end

    function configBox:Set(value)
        value = math.clamp(math.floor(tonumber(value) or 1), 1, 8)
        self.current = value
        self:Refresh()
    end

    table.insert(library.began, function(input)
        if
            input.UserInputType == Enum.UserInputType.MouseButton1
            and section.window.isVisible
            and section.page.open
            and outline.Visible
            and not section.window:IsOverContent()
            and pointInside(outline.Position, outline.Size, utility:MouseLocation())
        then
            local mouse = utility:MouseLocation()
            local relativeY = mouse.Y - frame.Position.Y
            local index = math.clamp(math.floor(relativeY / 18) + 1, 1, 8)
            configBox:Set(index)
        end
    end)

    library.pointers.configbox = configBox

    section.currentAxis = section.currentAxis + 152
    section:Update()

    return configBox
end

--==============================================================
-- NESTED CONTROL HELPERS
--==============================================================

local originalToggle = sections.Toggle

-- Attach nested methods to each toggle after creation without changing the
-- existing Toggle constructor's public behavior.
function sections:Toggle(info)
    local toggle = originalToggle(self, info)
    local section = self

    function toggle:Colorpicker(colorInfo)
        local rightOffset = toggle.colorpickers == 0 and 34 or 68
        local picker = buildColorpicker(section, colorInfo, toggle.axis, rightOffset)

        toggle.colorpickers = toggle.colorpickers + 1
        toggle.addedAxis = toggle.addedAxis + 36

        return picker, toggle
    end

    function toggle:Keybind(keyInfo)
        keyInfo = keyInfo or {}

        local name = keyInfo.Name or keyInfo.name or info.Name or info.name or "Keybind"
        local default = keyInfo.Default or keyInfo.default or keyInfo.Def or keyInfo.def
        local mode = keyInfo.Mode or keyInfo.mode or "Always"
        local pointer = keyInfo.Pointer or keyInfo.pointer or keyInfo.Flag or keyInfo.flag
        local callback = keyInfo.Callback or keyInfo.callback or keyInfo.CallBack or keyInfo.callBack or function() end

        local keybind = {
            keybindname = keyInfo.KeybindName or keyInfo.keybindName or name,
            axis = toggle.axis,
            current = {},
            selecting = false,
            mode = mode,
            active = mode == "Always",
        }

        local outline, _, frame = createOutlineBox(
            section.visibleContent,
            Vector2.new(
                section.section_frame.Position.X + section.section_frame.Size.X - 44,
                section.section_frame.Position.Y + toggle.axis
            ),
            Vector2.new(40, 17),
            theme.light_contrast,
            section.page.open
        )

        local valueText = createText(
            section.visibleContent,
            "...",
            Vector2.new(frame.Position.X + frame.Size.X / 2, frame.Position.Y + 1),
            {
                Center = true,
                Visible = section.page.open,
                ZIndex = 60,
            }
        )

        keybind.outline = outline
        keybind.frame = frame
        keybind.valueText = valueText

        function keybind:Change(input)
            if typeof(input) == "EnumItem" and input.EnumType == Enum.KeyCode then
                self.current = {"KeyCode", input.Name}
            elseif typeof(input) == "EnumItem" and input.EnumType == Enum.UserInputType then
                self.current = {"UserInputType", input.Name}
            elseif type(input) == "table" and input[1] and input[2] then
                self.current = {input[1], input[2]}
            else
                return false
            end

            self.valueText.Text = shortenKeyName(self.current[2])
            return true
        end

        function keybind:Get()
            return table.clone(self.current)
        end

        function keybind:Set(value)
            self:Change(value)
        end

        function keybind:Active()
            return self.active
        end

        if default then
            keybind:Change(default)
        end

        table.insert(library.began, function(input)
            if keybind.selecting and section.window.isVisible then
                local candidate = input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode or nil

                if candidate and keybind:Change(candidate) then
                    keybind.selecting = false
                    utility:SetThemeProperty(
                        keybind.frame,
                        "Color",
                        "light_contrast"
                    )
                    callback(candidate, keybind.active)
                end

                return
            end

            local bound = resolveEnumTable(keybind.current)

            if bound and (input.KeyCode == bound or input.UserInputType == bound) then
                if keybind.mode == "Toggle" then
                    keybind.active = not keybind.active and toggle:Get() or false
                    callback(bound, keybind.active)
                elseif keybind.mode == "Hold" then
                    keybind.active = toggle:Get()
                    callback(bound, keybind.active)
                elseif keybind.mode == "Always" then
                    callback(bound, toggle:Get())
                end
            end

            if
                input.UserInputType == Enum.UserInputType.MouseButton1
                and section.window.isVisible
                and section.page.open
                and outline.Visible
                and not section.window:IsOverContent()
                and pointInside(outline.Position, outline.Size, utility:MouseLocation())
            then
                keybind.selecting = true
                utility:SetThemeProperty(
                    keybind.frame,
                    "Color",
                    "dark_contrast"
                )
                keybind.valueText.Text = "..."
            end
        end)

        table.insert(library.ended, function(input)
            if keybind.mode ~= "Hold" or not keybind.active then
                return
            end

            local bound = resolveEnumTable(keybind.current)

            if bound and (input.KeyCode == bound or input.UserInputType == bound) then
                keybind.active = false
                callback(bound, false)
            end
        end)

        registerPointer(pointer, keybind)
        toggle.keybind = keybind
        toggle.addedAxis = math.max(toggle.addedAxis, 46)

        return keybind, toggle
    end

    return toggle
end

--==============================================================
-- OPTIONAL CONFIG FILE HELPERS
--==============================================================

function library:SaveConfig(name)
    if not writefile then
        return false
    end

    local encoded = self:GetConfig()
    local path = library.folders.configs .. "/" .. tostring(name) .. ".json"

    return pcall(writefile, path, encoded)
end

function library:LoadConfigFile(name)
    if not readfile or not isfile then
        return false
    end

    local path = library.folders.configs .. "/" .. tostring(name) .. ".json"
    local ok, exists = pcall(isfile, path)

    if not ok or not exists then
        return false
    end

    local readOk, data = pcall(readfile, path)

    if not readOk then
        return false
    end

    self:LoadConfig(data)
    return true
end

--==============================================================
-- FINAL COMPATIBILITY ALIASES
--==============================================================

library.NewWindow = library.New
library.CreateWindow = library.New
library.SetColor = library.SetThemeColor
library.SetUIOpacity = library.SetOpacity

-- The old source returned four values. Keep the exact return shape so current
-- Empyrean integrations can switch source URLs without changing their loader.
return library, utility, library.pointers, theme
