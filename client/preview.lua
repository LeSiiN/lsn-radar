-- ═══════════════════════════════════════════════════════════════════════════
--  Range preview
-- ═══════════════════════════════════════════════════════════════════════════
-- "250 metres" is not a distance anybody can picture. It becomes meaningful the
-- moment you see where it lands on the road you are parked on, which is why the
-- cone is drawn in the world while the operator drags the range slider.
--
-- The first version of this cost more frames than the radar itself. It called
-- GetGroundZFor_3dCoord for every marker on every frame — 56 ground raycasts a
-- frame, better than three thousand a second, to place points that mostly were
-- not moving. Ground lookups are the expensive part of drawing anything that
-- follows terrain, so they now happen when the shape actually changes and not
-- once per frame:
--
--   * The cone is rebuilt only when the range changes, or the car has moved
--     more than a couple of metres, or it has turned appreciably. Parked with
--     the panel open — which is when the slider is normally used — that is zero
--     lookups a second after the first build.
--   * Rebuilds are rate limited regardless, so driving cannot force more than
--     five a second.
--   * Drawing works off the cached points, so what is drawn is a presentation
--     question rather than a performance one. Bare lines were cheap but nearly
--     invisible — DrawLine is one pixel wide at any distance, so the far end of
--     a 250m cone is a hair. The cone is now a translucent filled surface with
--     bright doubled edges and the distance written at the tip.

local previewUntil = 0

--- Cached geometry, rebuilt only when the shape changes.
local cone = {
    front = {},   -- { left = {v3...}, right = {v3...} }
    rear  = {},
    builtAt = 0,
    range = nil,
    pos = nil,
    heading = nil,
}

local REBUILD_MS       = 200
local MOVE_THRESHOLD   = 2.0    -- metres
local TURN_THRESHOLD   = 0.05   -- radians, ~3°
local HEIGHT           = 0.12   -- above ground, to stay off the road surface
local EDGE_LIFT        = 0.10   -- second edge line, for a thicker looking rail

--- Keep the cone on screen. Called on every slider movement; the linger timer
--- is what makes it disappear on its own rather than needing a second action.
function ShowRangePreview()
    if not Config.Radar.Preview.Enabled then return end
    previewUntil = GetGameTimer() + Config.Radar.Preview.LingerMs
end

--- One edge of a cone, as a list of points that follow the ground.
---@param px number
---@param py number
---@param pz number
---@param heading number radians, already rotated onto the edge
---@param range number
---@param steps number
---@param out table
local function buildEdge(px, py, pz, heading, range, steps, out)
    for i = #out, 1, -1 do out[i] = nil end

    local dx, dy = -math.sin(heading), math.cos(heading)

    for i = 0, steps do
        local d = range * (i / steps)
        local x, y = px + dx * d, py + dy * d

        local found, z = GetGroundZFor_3dCoord(x, y, pz + 8.0, false)
        if not found then z = pz end

        out[#out + 1] = vector3(x, y, z + HEIGHT)
    end
end

---@param patrolVeh number
local function rebuild(patrolVeh)
    local c = GetEntityCoords(patrolVeh)
    local heading = math.rad(GetEntityHeading(patrolVeh))
    local range = RadarState.settings.range
    local half = math.rad(Config.Radar.ConeAngle)
    local steps = Config.Radar.Preview.Steps

    cone.front.left  = cone.front.left  or {}
    cone.front.right = cone.front.right or {}
    cone.rear.left   = cone.rear.left   or {}
    cone.rear.right  = cone.rear.right  or {}

    buildEdge(c.x, c.y, c.z, heading + half, range, steps, cone.front.left)
    buildEdge(c.x, c.y, c.z, heading - half, range, steps, cone.front.right)
    buildEdge(c.x, c.y, c.z, heading + math.pi + half, range, steps, cone.rear.left)
    buildEdge(c.x, c.y, c.z, heading + math.pi - half, range, steps, cone.rear.right)

    -- Far-end midpoint, bowed slightly outwards: the real edge of a cone is an
    -- arc, and a straight chord reads as a wall across the road.
    local function cap(edge, origin)
        local a, b2 = edge.left[#edge.left], edge.right[#edge.right]
        if not a or not b2 then edge.cap = nil return end

        local mx, my = (a.x + b2.x) * 0.5, (a.y + b2.y) * 0.5
        local ox, oy = mx - origin.x, my - origin.y
        local len = math.sqrt(ox * ox + oy * oy)
        if len > 0 then
            mx, my = mx + (ox / len) * (len * 0.04), my + (oy / len) * (len * 0.04)
        end

        local found, mz = GetGroundZFor_3dCoord(mx, my, a.z + 8.0, false)
        if not found then mz = a.z - HEIGHT end
        edge.cap = vector3(mx, my, mz + HEIGHT)
    end

    cap(cone.front, c)
    cap(cone.rear, c)

    -- Tip of each centreline, where the distance gets written.
    local function tip(edge)
        local a, b2 = edge.left[#edge.left], edge.right[#edge.right]
        if not a or not b2 then edge.tip = nil return end
        edge.tip = vector3((a.x + b2.x) * 0.5, (a.y + b2.y) * 0.5, (a.z + b2.z) * 0.5)
    end

    tip(cone.front)
    tip(cone.rear)

    cone.builtAt = GetGameTimer()
    cone.range = range
    cone.pos = c
    cone.heading = heading
end

--- Has the shape changed enough to be worth the ground lookups?
---@param patrolVeh number
---@return boolean
local function needsRebuild(patrolVeh)
    if not cone.pos then return true end
    if cone.range ~= RadarState.settings.range then return true end
    if (GetGameTimer() - cone.builtAt) < REBUILD_MS then return false end

    local c = GetEntityCoords(patrolVeh)
    local dx, dy = c.x - cone.pos.x, c.y - cone.pos.y
    if (dx * dx + dy * dy) > (MOVE_THRESHOLD * MOVE_THRESHOLD) then return true end

    local turn = math.abs(math.rad(GetEntityHeading(patrolVeh)) - cone.heading)
    if turn > math.pi then turn = (2 * math.pi) - turn end
    return turn > TURN_THRESHOLD
end

--- One edge, drawn as two stacked lines so it reads as a rail rather than a
--- hair. DrawLine is a single pixel wide however far away it is, which is why
--- the first attempt at this was almost invisible at the far end of a 250m
--- cone.
---@param points table
---@param r number
---@param g number
---@param b number
local function drawEdge(points, r, g, b)
    local n = #points
    for i = 1, n - 1 do
        local a, c = points[i], points[i + 1]
        local alpha = math.floor(235 * (1.0 - (i / n) * 0.45))

        DrawLine(a.x, a.y, a.z, c.x, c.y, c.z, r, g, b, alpha)
        DrawLine(a.x, a.y, a.z + EDGE_LIFT, c.x, c.y, c.z + EDGE_LIFT, r, g, b, alpha)
    end
end

--- The area between the two edges, as a translucent surface on the road.
---
--- This is what makes the cone actually visible: an outline has to be found,
--- a shaded area is simply there. Each quad is drawn with both windings
--- because DrawPoly is single sided and the operator may be looking at it from
--- either end.
---@param edge table
---@param r number
---@param g number
---@param b number
local function drawFill(edge, r, g, b)
    local left, right = edge.left, edge.right
    local n = #left
    if n < 2 or #right ~= n then return end

    for i = 1, n - 1 do
        local l1, l2 = left[i], left[i + 1]
        local r1, r2 = right[i], right[i + 1]

        -- Strongest at the car and fading out, so the shape says "reach" rather
        -- than sitting on the road like a painted box.
        local alpha = math.floor(70 * (1.0 - (i / n) * 0.8))
        if alpha > 2 then
            DrawPoly(l1.x, l1.y, l1.z, r1.x, r1.y, r1.z, l2.x, l2.y, l2.z, r, g, b, alpha)
            DrawPoly(r1.x, r1.y, r1.z, l1.x, l1.y, l1.z, l2.x, l2.y, l2.z, r, g, b, alpha)

            DrawPoly(r1.x, r1.y, r1.z, r2.x, r2.y, r2.z, l2.x, l2.y, l2.z, r, g, b, alpha)
            DrawPoly(r2.x, r2.y, r2.z, r1.x, r1.y, r1.z, l2.x, l2.y, l2.z, r, g, b, alpha)
        end
    end
end

--- The range, written where the range actually ends. A number on a slider is
--- an abstraction; the same number floating over the junction it reaches is
--- the answer to the question the operator was asking.
---@param edge table
---@param label string
local function drawTip(edge, label)
    local t = edge.tip
    if not t then return end

    SetDrawOrigin(t.x, t.y, t.z + 1.1, 0)
    SetTextScale(0.34, 0.34)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextColour(255, 255, 255, 210)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(label)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

--- Close the far end so the cone reads as an area with a limit rather than as
--- two rays heading off into the distance.
---
--- The midpoint is cached with the rest of the geometry. Computing it here
--- meant two more ground lookups every frame — small next to the fifty-odd the
--- edges used to cost, but the same mistake, and the last one left.
---@param edge table
---@param r number
---@param g number
---@param b number
local function drawCap(edge, r, g, b)
    local a, c, mid = edge.left[#edge.left], edge.right[#edge.right], edge.cap
    if not a or not c or not mid then return end

    DrawLine(a.x, a.y, a.z, mid.x, mid.y, mid.z, r, g, b, 150)
    DrawLine(mid.x, mid.y, mid.z, c.x, c.y, c.z, r, g, b, 150)
    DrawLine(a.x, a.y, a.z + EDGE_LIFT, mid.x, mid.y, mid.z + EDGE_LIFT, r, g, b, 150)
    DrawLine(mid.x, mid.y, mid.z + EDGE_LIFT, c.x, c.y, c.z + EDGE_LIFT, r, g, b, 150)
end

CreateThread(function()
    while true do
        local wait = 250

        if GetGameTimer() < previewUntil then
            local patrolVeh = GetPatrolVehicle()
            if patrolVeh then
                wait = 0

                if needsRebuild(patrolVeh) then rebuild(patrolVeh) end

                -- Front in the MDT accent blue, rear in amber — the colours the
                -- two antennas already carry in the interface.
                local label = ('%dm'):format(math.floor(RadarState.settings.range + 0.5))

                -- Fill first: the edges have to sit on top of it, not under.
                drawFill(cone.front, 96, 165, 250)
                drawEdge(cone.front.left, 96, 165, 250)
                drawEdge(cone.front.right, 96, 165, 250)
                drawCap(cone.front, 96, 165, 250)
                drawTip(cone.front, label)

                drawFill(cone.rear, 251, 191, 36)
                drawEdge(cone.rear.left, 251, 191, 36)
                drawEdge(cone.rear.right, 251, 191, 36)
                drawCap(cone.rear, 251, 191, 36)
                drawTip(cone.rear, label)
            end
        elseif cone.pos then
            -- Drop the cached geometry once the preview is done. It is a few
            -- hundred vectors, and holding them for a slider nobody is touching
            -- is pointless.
            cone.pos, cone.range, cone.heading = nil, nil, nil
        end

        Wait(wait)
    end
end)
