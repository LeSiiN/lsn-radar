-- ═══════════════════════════════════════════════════════════════════════════
--  Target bracket
-- ═══════════════════════════════════════════════════════════════════════════
-- Marks the vehicle the radar is currently reading with a bracket drawn around
-- it, the way a viewfinder frames a subject.
--
-- This replaces an attempt at SetEntityDrawOutline, which does nothing on a
-- good number of FiveM builds — the outline depends on a post-processing pass
-- that is not reliably present, so it fails silently and identically to a bug
-- in your own code. Nothing here touches an engine feature: the vehicle
-- position is projected to screen coordinates and four corner marks are drawn
-- with DrawRect. Colour, weight and size are entirely ours, which is also why
-- it can be made to match the rest of the interface rather than looking like a
-- mission marker.
--
-- Runs per frame rather than at the antenna tick rate. A marker updated ten
-- times a second visibly lags the car it is supposed to be on, and the whole
-- point is that it sits on the right vehicle.

local function cfg() return Config.Radar.TargetMarker end

--- Which vehicle each antenna is currently reading.
---
--- A locked antenna marks what it is tracking; otherwise the strong target,
--- which is the vehicle the big number belongs to. The fast target stays
--- unmarked on purpose — two brackets in one cone puts the operator back to
--- working out which is which.
---@param out table reused between frames
local function collectTargets(out)
    for i = #out, 1, -1 do out[i] = nil end

    for _, cam in ipairs({ 'front', 'rear' }) do
        local a = RadarState.antennas[cam]
        if a then
            if a.lock then
                if a.lock.entity and not a.lock.lost then
                    out[#out + 1] = { entity = a.lock.entity, locked = true }
                end
            elseif a.strong and a.strong.entity then
                out[#out + 1] = { entity = a.strong.entity, locked = false }
            end
        end
    end
end

--- Draw one corner mark. DrawRect takes the centre of the rectangle, and its
--- coordinates are fractions of the screen, so a horizontal and a vertical arm
--- of the same visual weight need different thicknesses — hence the aspect
--- division on everything horizontal.
local function corner(cx, cy, hw, hh, armW, armH, t, tw, r, g, b, a, dirX, dirY)
    -- Horizontal arm, running inwards from the corner.
    DrawRect(cx + dirX * (hw - armW * 0.5), cy + dirY * hh, armW, t, r, g, b, a)
    -- Vertical arm.
    DrawRect(cx + dirX * hw, cy + dirY * (hh - armH * 0.5), tw, armH, r, g, b, a)
end

---@param entity number
---@param locked boolean
---@param aspect number
local function drawBracket(entity, locked, aspect)
    local c = GetEntityCoords(entity)

    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z)
    if not onScreen then return end

    -- Size is measured rather than guessed: projecting a point a fixed height
    -- above the vehicle gives the on-screen size of a known real-world
    -- distance, so the bracket shrinks with range by itself and stays correct
    -- at any field of view.
    local okTop, _, topY = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 2.2)
    if not okTop then return end

    local hh = math.abs(sy - topY)
    hh = math.max(cfg().MinSize, math.min(cfg().MaxSize, hh))
    local hw = hh / aspect

    local col = locked and cfg().LockColour or cfg().Colour
    local r, g, b, a = col[1], col[2], col[3], col[4]

    local t = cfg().Thickness          -- horizontal bars
    local tw = t / aspect              -- vertical bars, same visual weight
    local armH = hh * 0.45
    local armW = hw * 0.45

    corner(sx, sy, hw, hh, armW, armH, t, tw, r, g, b, a, -1, -1)
    corner(sx, sy, hw, hh, armW, armH, t, tw, r, g, b, a,  1, -1)
    corner(sx, sy, hw, hh, armW, armH, t, tw, r, g, b, a, -1,  1)
    corner(sx, sy, hw, hh, armW, armH, t, tw, r, g, b, a,  1,  1)
end

local targets = {}

CreateThread(function()
    while true do
        -- Short idle wait rather than a quarter second: this is how long the
        -- bracket can lag a target that has just been acquired.
        local wait = 100

        if cfg().Enabled and RadarState.settings.marker and RadarState.power then
            local patrolVeh = GetPatrolVehicle()
            if patrolVeh then
                collectTargets(targets)

                if #targets > 0 then
                    -- Per frame only while there is something to draw. With no
                    -- target in either cone this thread costs one table clear
                    -- every tenth of a second.
                    wait = 0

                    local aspect = GetAspectRatio(false)
                    if not aspect or aspect <= 0 then aspect = 16 / 9 end

                    for i = 1, #targets do
                        local t = targets[i]
                        if DoesEntityExist(t.entity) then
                            drawBracket(t.entity, t.locked, aspect)
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)
