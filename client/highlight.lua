-- ═══════════════════════════════════════════════════════════════════════════
--  Target highlight
-- ═══════════════════════════════════════════════════════════════════════════
-- An outline on the vehicle the radar is currently reading.
--
-- The point is answering "which one of those is it?" without the operator
-- having to work it out from the direction arrow and a guess. It is off by
-- default and deliberately faint: this is an aid to reading the display, not a
-- wallhack, and an outline bright enough to see through a building would be a
-- different feature with different consequences for how the server plays.
--
-- SetEntityDrawOutlineColor is global rather than per-entity, which cuts both
-- ways: one call covers every outline this resource owns, and any other script
-- that touches it — target systems commonly do — silently repaints ours. So it
-- is re-applied on every update rather than once at startup. It is a single
-- native at the antenna tick rate, which is nothing next to being quietly
-- turned someone else's colour halfway through a shift.
--
-- What has to be managed per entity is the toggle: an outline switched on and
-- never switched off follows a vehicle for the rest of its life, including
-- after it has left the cone, the officer has left the car, or the resource
-- has stopped.

--- Entities currently outlined by this resource, so they can all be turned off
--- again — including the ones that stopped being targets between two ticks.
local outlined = {}

local shaderSet = false

local function applyColour()
    local c = Config.Radar.Highlight.Colour
    SetEntityDrawOutlineColor(c[1], c[2], c[3], c[4])

    if not shaderSet then
        shaderSet = true
        -- Shader 0 is the plain outline. Wrapped because the native is absent
        -- on older builds, and a missing shader selection is not worth an
        -- error — the outline still draws with the default.
        pcall(SetEntityDrawOutlineShader, 0)
    end
end

---@param entity number
---@param on boolean
local function setOutline(entity, on)
    if not entity or entity == 0 then return end
    if not DoesEntityExist(entity) then
        outlined[entity] = nil
        return
    end

    SetEntityDrawOutline(entity, on)
    outlined[entity] = on or nil
end

--- Turn everything off. Called on power down, on leaving the vehicle and on
--- resource stop — the three ways an outline would otherwise be left behind.
function ClearHighlights()
    for entity in pairs(outlined) do
        if DoesEntityExist(entity) then SetEntityDrawOutline(entity, false) end
        outlined[entity] = nil
    end
end

--- Bring the outlines in line with what the antennas are currently reading.
---
--- Diffed against the previous tick rather than cleared and reapplied: toggling
--- an outline off and immediately on again makes it flicker at the tick rate,
--- which on a vehicle held steadily in the cone is both wrong and distracting.
function UpdateHighlights()
    if not Config.Radar.Highlight.Enabled or not RadarState.settings.highlight then
        if next(outlined) then ClearHighlights() end
        return
    end

    if not RadarState.power then
        if next(outlined) then ClearHighlights() end
        return
    end

    applyColour()

    -- Build the wanted set. A locked antenna highlights what it is tracking;
    -- otherwise the strong target, which is the vehicle the big number belongs
    -- to. The fast target is deliberately left out — two outlines in one cone
    -- would put the operator back to guessing which is which.
    local wanted = {}
    for _, cam in ipairs({ 'front', 'rear' }) do
        local a = RadarState.antennas[cam]
        if a.lock then
            if a.lock.entity and not a.lock.lost then wanted[a.lock.entity] = true end
        elseif a.strong and a.strong.entity then
            wanted[a.strong.entity] = true
        end
    end

    for entity in pairs(outlined) do
        if not wanted[entity] then setOutline(entity, false) end
    end

    for entity in pairs(wanted) do
        if not outlined[entity] then setOutline(entity, true) end
    end
end

--- Diagnostic. Outlines the nearest vehicle at full white for five seconds,
--- which separates "this build does not support the native" from "our logic
--- never reached it" — the two look identical from the driver's seat.
RegisterCommand('radaroutlinetest', function()
    local ped = PlayerPedId()
    local veh = GetClosestVehicle(GetEntityCoords(ped), 30.0, 0, 71)

    if not veh or veh == 0 or not DoesEntityExist(veh) then
        print('^3[lsn-radar]^7 no vehicle within 30m to test on')
        return
    end

    SetEntityDrawOutlineColor(255, 255, 255, 255)
    pcall(SetEntityDrawOutlineShader, 0)
    SetEntityDrawOutline(veh, true)
    print(('^2[lsn-radar]^7 outline on entity %s for 5s — if nothing appears, the native is unsupported on this build'):format(veh))

    CreateThread(function()
        Wait(5000)
        if DoesEntityExist(veh) then SetEntityDrawOutline(veh, false) end
        applyColour()
    end)
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ClearHighlights()
end)
