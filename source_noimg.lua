--[[
    Empyrean UI
    Image-free Drawing API conversion of the legacy UI library.

    This loader is pinned to the current source revision so it can safely be
    uploaded as source.lua later without recursively loading itself.

    Fixes:
      * No Drawing.new("Image") dependency
      * Procedural HSV saturation/value picker
      * Procedural hue strip
      * Procedural colorpicker cursor
      * Procedural dropdown arrows
      * Procedural transparency checkerboards
      * Decorative image gradients flattened instead of externally loaded
      * No image downloads / PNG cache dependency
      * Legacy branding/folders converted to Empyrean:
            empyrean/
            empyrean/assets/
            empyrean/configs/
--]]

local SOURCE_URL =
    "https://raw.githubusercontent.com/koiify/empyrean/f51a88e0c0a5bb6b75257e9427885c2acf8fbd57/source.lua"

local function replacePlain(text, oldText, newText)
    local first, last =
        string.find(
            text,
            oldText,
            1,
            true
        )

    assert(
        first,
        "Empyrean conversion failed: source marker was not found"
    )

    return
        string.sub(text, 1, first - 1)
        .. newText
        .. string.sub(text, last + 1)
end

local function replaceBetween(
    text,
    startMarker,
    endMarker,
    replacement
)
    local first =
        string.find(
            text,
            startMarker,
            1,
            true
        )

    assert(
        first,
        "Empyrean conversion failed: start marker was not found"
    )

    local ending =
        string.find(
            text,
            endMarker,
            first + #startMarker,
            true
        )

    assert(
        ending,
        "Empyrean conversion failed: end marker was not found"
    )

    return
        string.sub(text, 1, first - 1)
        .. replacement
        .. string.sub(text, ending)
end

local source =
    game:HttpGet(SOURCE_URL)

assert(
    type(source) == "string"
    and #source > 100000,
    "Empyrean could not retrieve the pinned UI source"
)

-- Avoid retaining the legacy library name anywhere in the converted source.
local legacyLower =
    string.char(115, 112, 108, 105, 120)

local legacyTitle =
    string.char(83, 112, 108, 105, 120)

local legacyUpper =
    string.char(83, 80, 76, 73, 88)

source =
    source:gsub(
        legacyUpper,
        "EMPYREAN"
    )

source =
    source:gsub(
        legacyTitle,
        "Empyrean"
    )

source =
    source:gsub(
        legacyLower,
        "empyrean"
    )

local IMAGE_PROXY_CODE = [==[
--==============================================================
-- EMPYREAN IMAGE-FREE DRAWING PROXY
--==============================================================
--
-- Some executors expose Drawing.new("Image") but do not actually render image
-- bytes. Empyrean replaces every legacy image object with a lightweight proxy
-- backed only by Drawing Square/Triangle primitives.
--
-- The proxy intentionally exposes Position, Size, Visible, Transparency,
-- ZIndex, Color, Remove(), and __OBJECT_EXISTS so existing library layout,
-- fading, dragging, and cleanup code can continue to treat it like a normal
-- Drawing object.
--==============================================================

local EmpyreanImage = {}
local EmpyreanImageMT = {}

local function removeDrawingOnce(object)
    if not object then
        return
    end

    pcall(function()
        object.Visible = false
    end)

    local removed =
        pcall(function()
            object:Remove()
        end)

    if not removed then
        pcall(function()
            object:Destroy()
        end)
    end
end

local function clamp01(value)
    return
        math.clamp(
            tonumber(value) or 0,
            0,
            1
        )
end

function EmpyreanImage.new()
    local self =
        setmetatable(
            {},
            EmpyreanImageMT
        )

    rawset(
        self,
        "_state",
        {
            Position = Vector2.new(0, 0),
            Size = Vector2.new(12, 19),
            Visible = true,
            Transparency =
                library.shared.initialized
                and 1
                or 0,
            ZIndex = 50,
            Color = Color3.fromRGB(255, 255, 255),
            Kind = nil,
            __OBJECT_EXISTS = true,
        }
    )

    rawset(
        self,
        "_parts",
        {}
    )

    return self
end

function EmpyreanImage:_clearParts()
    for _, part in ipairs(self._parts) do
        removeDrawingOnce(
            part.Object
        )
    end

    table.clear(
        self._parts
    )
end

function EmpyreanImage:_addSquare(info)
    local object =
        Drawing.new("Square")

    object.Filled =
        info.Filled ~= false

    object.Thickness =
        info.Thickness or 1

    object.Color =
        info.Color
        or Color3.fromRGB(
            255,
            255,
            255
        )

    object.Visible = false

    table.insert(
        self._parts,
        {
            Object = object,
            Shape = "Square",

            X = info.X or 0,
            Y = info.Y or 0,
            W = info.W or 1,
            H = info.H or 1,

            OffsetX = info.OffsetX or 0,
            OffsetY = info.OffsetY or 0,
            OffsetW = info.OffsetW or 0,
            OffsetH = info.OffsetH or 0,

            Alpha =
                info.Alpha == nil
                and 1
                or info.Alpha,

            ZOffset =
                info.ZOffset or 0,

            Color =
                info.Color
                or Color3.fromRGB(
                    255,
                    255,
                    255
                ),
        }
    )
end

function EmpyreanImage:_addTriangle(info)
    local object =
        Drawing.new("Triangle")

    object.Filled = true
    object.Thickness = 0

    object.Color =
        info.Color
        or Color3.fromRGB(
            215,
            215,
            225
        )

    object.Visible = false

    table.insert(
        self._parts,
        {
            Object = object,
            Shape = info.Shape,
            Alpha =
                info.Alpha == nil
                and 1
                or info.Alpha,
            ZOffset =
                info.ZOffset or 0,
            Color =
                info.Color
                or Color3.fromRGB(
                    215,
                    215,
                    225
                ),
        }
    )
end

function EmpyreanImage:_buildHue()
    local strips = 30

    for index = 1, strips do
        local hue =
            (index - 1)
            / (strips - 1)

        self:_addSquare({
            X = 0,
            Y = (index - 1) / strips,
            W = 1,
            H = 1 / strips,
            Color =
                Color3.fromHSV(
                    hue,
                    1,
                    1
                ),
        })
    end
end

function EmpyreanImage:_buildValSat()
    -- Existing picker background supplies the current pure hue.
    --
    -- White vertical strips provide saturation:
    --     left = white
    --     right = pure hue
    --
    -- Black horizontal strips then provide value:
    --     top = full value
    --     bottom = black
    local steps = 20

    for index = 1, steps do
        local midpoint =
            (index - 0.5)
            / steps

        self:_addSquare({
            X = (index - 1) / steps,
            Y = 0,
            W = 1 / steps,
            H = 1,
            Color =
                Color3.fromRGB(
                    255,
                    255,
                    255
                ),
            Alpha =
                1 - midpoint,
        })
    end

    for index = 1, steps do
        local midpoint =
            (index - 0.5)
            / steps

        self:_addSquare({
            X = 0,
            Y = (index - 1) / steps,
            W = 1,
            H = 1 / steps,
            Color =
                Color3.fromRGB(
                    0,
                    0,
                    0
                ),
            Alpha =
                midpoint,
        })
    end
end

function EmpyreanImage:_buildCursor()
    self:_addSquare({
        X = 0,
        Y = 0,
        W = 1,
        H = 1,
        Color =
            Color3.fromRGB(
                0,
                0,
                0
            ),
        Filled = false,
        Thickness = 1,
    })

    self:_addSquare({
        X = 0,
        Y = 0,
        W = 1,
        H = 1,
        OffsetX = 1,
        OffsetY = 1,
        OffsetW = -2,
        OffsetH = -2,
        Color =
            Color3.fromRGB(
                255,
                255,
                255
            ),
        Filled = false,
        Thickness = 1,
    })
end

function EmpyreanImage:_buildChecker(
    columns,
    rows,
    alpha,
    zOffset
)
    for row = 1, rows do
        for column = 1, columns do
            local light =
                (row + column)
                % 2
                == 0

            self:_addSquare({
                X = (column - 1) / columns,
                Y = (row - 1) / rows,
                W = 1 / columns,
                H = 1 / rows,
                Color =
                    light
                    and Color3.fromRGB(
                        210,
                        210,
                        210
                    )
                    or Color3.fromRGB(
                        85,
                        85,
                        85
                    ),
                Alpha = alpha,
                ZOffset = zOffset or 0,
            })
        end
    end
end

function EmpyreanImage:_rebuild()
    self:_clearParts()

    local kind =
        string.lower(
            tostring(
                self._state.Kind
                or ""
            )
        )

    if
        string.find(
            kind,
            "valsat_cursor",
            1,
            true
        )
    then
        self:_buildCursor()

    elseif
        string.find(
            kind,
            "valsat",
            1,
            true
        )
    then
        self:_buildValSat()

    elseif
        string.find(
            kind,
            "hue",
            1,
            true
        )
    then
        self:_buildHue()

    elseif
        string.find(
            kind,
            "arrow_down",
            1,
            true
        )
    then
        self:_addTriangle({
            Shape = "TriangleDown",
        })

    elseif
        string.find(
            kind,
            "arrow_up",
            1,
            true
        )
    then
        self:_addTriangle({
            Shape = "TriangleUp",
        })

    elseif
        string.find(
            kind,
            "cptransp",
            1,
            true
        )
    then
        -- Closed color preview: checkerboard lives behind the actual color.
        self:_buildChecker(
            6,
            2,
            1,
            -1
        )

    elseif
        string.find(
            kind,
            "transp",
            1,
            true
        )
    then
        -- Open transparency slider: keep the selected-color background
        -- visible through a light checkerboard.
        self:_buildChecker(
            12,
            2,
            0.35,
            0
        )

    elseif
        string.find(
            kind,
            "gradient",
            1,
            true
        )
    then
        -- Decorative gradients are intentionally flattened. The underlying
        -- control frame remains visible, avoiding dozens of unnecessary
        -- Drawing objects and keeping window dragging lightweight.
    end

    self:_layout()
end

function EmpyreanImage:_layout()
    local state =
        self._state

    if
        not state
        or not state.__OBJECT_EXISTS
    then
        return
    end

    local position =
        state.Position
        or Vector2.new(0, 0)

    local size =
        state.Size
        or Vector2.new(0, 0)

    local visible =
        state.Visible == true

    local transparency =
        clamp01(
            state.Transparency
        )

    local baseZ =
        tonumber(
            state.ZIndex
        )
        or 50

    for _, part in ipairs(self._parts) do
        local object =
            part.Object

        if part.Shape == "Square" then
            local width =
                math.max(
                    0,
                    size.X * part.W
                    + part.OffsetW
                )

            local height =
                math.max(
                    0,
                    size.Y * part.H
                    + part.OffsetH
                )

            object.Position =
                Vector2.new(
                    position.X
                    + size.X * part.X
                    + part.OffsetX,

                    position.Y
                    + size.Y * part.Y
                    + part.OffsetY
                )

            object.Size =
                Vector2.new(
                    width,
                    height
                )

        elseif part.Shape == "TriangleDown" then
            object.PointA =
                Vector2.new(
                    position.X,
                    position.Y
                )

            object.PointB =
                Vector2.new(
                    position.X + size.X,
                    position.Y
                )

            object.PointC =
                Vector2.new(
                    position.X + size.X * 0.5,
                    position.Y + size.Y
                )

        elseif part.Shape == "TriangleUp" then
            object.PointA =
                Vector2.new(
                    position.X,
                    position.Y + size.Y
                )

            object.PointB =
                Vector2.new(
                    position.X + size.X,
                    position.Y + size.Y
                )

            object.PointC =
                Vector2.new(
                    position.X + size.X * 0.5,
                    position.Y
                )
        end

        object.Color =
            part.Color

        object.ZIndex =
            baseZ
            + part.ZOffset

        object.Transparency =
            clamp01(
                transparency
                * part.Alpha
            )

        object.Visible =
            visible
            and size.X > 0
            and size.Y > 0
    end
end

function EmpyreanImage:SetKind(kind)
    local normalized =
        string.lower(
            tostring(
                kind
                or ""
            )
        )

    if
        self._state.Kind
        == normalized
    then
        self:_layout()
        return
    end

    self._state.Kind =
        normalized

    self:_rebuild()
end

function EmpyreanImage:Remove()
    if
        not self._state
        or not self._state.__OBJECT_EXISTS
    then
        return
    end

    self._state.__OBJECT_EXISTS =
        false

    self:_clearParts()
end

function EmpyreanImage:Destroy()
    self:Remove()
end

EmpyreanImageMT.__index =
    function(self, key)
        local method =
            EmpyreanImage[key]

        if method ~= nil then
            return method
        end

        local state =
            rawget(
                self,
                "_state"
            )

        if state then
            return state[key]
        end

        return nil
    end

EmpyreanImageMT.__newindex =
    function(self, key, value)
        if
            key == "_state"
            or key == "_parts"
        then
            rawset(
                self,
                key,
                value
            )

            return
        end

        local state =
            rawget(
                self,
                "_state"
            )

        if not state then
            rawset(
                self,
                key,
                value
            )

            return
        end

        state[key] =
            value

        self:_layout()
    end

]==]

source =
    replacePlain(
        source,
        "-- // Utility Functions\ndo\n",
        IMAGE_PROXY_CODE
        .. "\n-- // Utility Functions\ndo\n"
    )

source =
    replaceBetween(
        source,

        [==[        elseif instanceType == "Image" or instanceType == "image" then]==],

        [==[        elseif instanceType == "Circle" or instanceType == "circle" then]==],

        [==[        elseif instanceType == "Image" or instanceType == "image" then
            instance = EmpyreanImage.new()
]==]
    )

source =
    replaceBetween(
        source,

        [==[    function utility:LoadImage(instance, imageName, imageLink)]==],

        [==[    --
    function utility:Lerp(instance, instanceTo, instanceTime)]==],

        [==[    function utility:LoadImage(instance, imageName, imageLink)
        -- Image URLs and filesystem PNGs are intentionally ignored.
        -- The proxy converts each legacy asset name into Drawing primitives.
        if
            instance
            and instance.SetKind
        then
            instance:SetKind(
                imageName
            )
        end
    end
]==]
    )

assert(
    not string.find(
        source,
        'Drawing.new("Image")',
        1,
        true
    ),
    "Empyrean conversion failed: a Drawing Image dependency remains"
)

assert(
    not string.find(
        string.lower(source),
        legacyLower,
        1,
        true
    ),
    "Empyrean conversion failed: legacy branding remains"
)

local loader, compileError =
    loadstring(source)

assert(
    loader,
    "Empyrean converted source failed to compile: "
    .. tostring(compileError)
)

return loader()
