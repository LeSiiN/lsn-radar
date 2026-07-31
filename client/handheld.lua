-- ═══════════════════════════════════════════════════════════════════════════
--  Handheld unit
-- ═══════════════════════════════════════════════════════════════════════════
-- A radar gun. Hold the configured weapon, aim at a vehicle, read its speed and
-- plate.
--
-- Almost none of the vehicle radar's machinery applies here, and that is the
-- point rather than a gap. A mounted antenna sweeps a cone because it cannot be
-- pointed; a gun is pointed, so one raycast down the aim vector replaces the
-- whole pool walk. The handheld path never touches scan.lua and is by some
-- margin the cheaper of the two.
--
-- What *is* shared is everything behind the reading: the MDT lookup and its
-- throttling, the watchlist, unit conversion, sound, and the target bracket.
-- Two lookup paths would have meant two sets of rules quietly disagreeing about
-- how often a plate may be asked about.

local function cfg() return Config.Handheld end

HandheldState = {
    active  = false,   -- the weapon is in hand
    aiming  = false,
    entity  = nil,
    speed   = nil,
    plate   = nil,
    index   = nil,
    dir     = nil,
    dist    = nil,
    lock    = nil,     -- frozen reading
    hits    = nil,
    severity = nil,
    checked = false,
    flagged = false,
    reason  = nil,
}

local weaponHash
local lastPushed = ''
local lastMeasure = 0

--- Push only when something visible changed. Aiming runs at frame rate, and a
--- vehicle held steadily in the crosshair produces an identical frame sixty
--- times a second.
local function push(force)
    local h = HandheldState
    local sig = table.concat({
        h.active and '1' or '0',
        h.aiming and '1' or '0',
        h.speed or '-', h.plate or '-', h.dir or '-',
        h.lock and h.lock.speed or '-',
        h.lock and h.lock.plate or '-',
        h.flagged and '1' or '0',
        h.checked and '1' or '0',
        h.hits and #h.hits or 0,
    }, '|')

    if not force and sig == lastPushed then return end
    lastPushed = sig

    SendNUIMessage({
        action = 'handheld',
        data = {
            active  = h.active,
            aiming  = h.aiming,
            unit    = RadarState.unit,
            speed   = h.speed,
            plate   = h.plate,
            index   = h.index,
            dir     = h.dir,
            dist    = h.dist,
            lock    = h.lock,
            hits    = h.hits,
            severity = h.severity,
            checked = h.checked,
            flagged = h.flagged,
            reason  = h.reason,
        },
    })
end

PushHandheldToNui = push

--- The MDT's answer for a plate this unit read. Dropped if the operator has
--- since pointed the gun somewhere else, rather than flagging whatever is in
--- the crosshair now.
---@param plate string
---@param hits table
---@param severity string|nil
function ApplyHandheldPlateResult(plate, hits, severity)
    local h = HandheldState
    local held = h.lock and h.lock.plate or h.plate
    if held ~= plate then return end

    h.checked = true

    if type(hits) == 'table' and #hits > 0 then
        h.hits, h.severity = hits, severity
        h.flagged = true
        h.reason = hits[1] and hits[1].label or 'Flagged'
        PlayRadarSound('Bolo', 1500)
    end

    push(true)
end

local function clearReading()
    local h = HandheldState
    h.entity, h.speed, h.plate, h.index, h.dir, h.dist = nil, nil, nil, nil, nil, nil
    h.hits, h.severity, h.checked = nil, nil, false
    h.flagged, h.reason = false, nil
end

--- Freeze the current reading, or release it.
local function toggleLock()
    local h = HandheldState

    if h.lock then
        h.lock = nil
        clearReading()
        PlayRadarSound('Blip', 150)
        push(true)
        return
    end

    if not h.speed then return end

    h.lock = {
        speed = h.speed, plate = h.plate, index = h.index,
        dir = h.dir, dist = h.dist, at = GetGameTimer(),
    }
    PlayRadarSound('Lock', 250)
    push(true)

    TriggerServerEvent('lsn-radar:server:speedLocked', h.speed, RadarState.unit, h.plate or '')
end

--- The vehicle the operator is pointing at.
---
--- A cone from the camera, not a ray. The first version cast a shape test ray
--- and it worked only at close range for a reason that is obvious in hindsight:
--- a ray is infinitely thin, so at 300m — where a car covers a couple of
--- pixels — you would have to be pixel perfect to register it at all. Distant
--- vehicles also frequently have no collision loaded, and a ray simply passes
--- through them.
---
--- A real radar gun has a beam with a width, and that is the right model here
--- too. Every vehicle inside a narrow cone is a candidate; the one nearest the
--- centre of the crosshair wins, which is what aiming means.
---@param ped number
---@return number|nil vehicle
---@return number|nil distance
local function aimedVehicle(ped)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)

    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local cosRx = math.abs(math.cos(rx))
    local fx, fy, fz = -math.sin(rz) * cosRx, math.cos(rz) * cosRx, math.sin(rx)

    local range = RadarState.settings.gunRange
    local rangeSq = range * range
    local cosCone = math.cos(math.rad(RadarState.settings.gunCone))

    local best, bestAlign, bestDist

    local pool = GetVehiclePool()
    for i = 1, #pool do
        local veh = pool[i]
        if DoesEntityExist(veh) and veh ~= GetVehiclePedIsIn(ped, false) then
            local c = GetEntityCoords(veh)
            local dx, dy, dz = c.x - cam.x, c.y - cam.y, c.z - cam.z
            local distSq = dx * dx + dy * dy + dz * dz

            if distSq <= rangeSq and distSq > 0.5 and IsReadableVehicle(veh) then
                local len = math.sqrt(distSq)
                local align = (dx * fx + dy * fy + dz * fz) / len

                -- Closest to the crosshair rather than closest to the operator.
                -- Aiming past a nearby car at one further down the road is a
                -- thing people do on purpose.
                if align >= cosCone and (not bestAlign or align > bestAlign) then
                    if HasEntityClearLosToEntity(ped, veh, 17) then
                        best, bestAlign, bestDist = veh, align, len
                    end
                end
            end
        end
    end

    return best, bestDist
end

--- Measure whatever the operator is aiming at.
local function measure()
    local h = HandheldState
    local ped = PlayerPedId()

    local entity, dist = aimedVehicle(ped)
    if not entity then
        -- Losing the crosshair does not blank the reading immediately, for the
        -- same reason the antennas hold theirs: a hand shakes, a car passes
        -- behind a post, and a display that empties on every wobble is unusable.
        if h.speed and (GetGameTimer() - (h.readAt or 0)) >= (Config.Radar.ReadingHold or 0) then
            clearReading()
        end
        return
    end

    if not IsReadableVehicle(entity) then return end

    local speed = ConvertSpeed(GetEntitySpeed(entity), RadarState.unit)
    if speed < (Config.Radar.MinSpeed[RadarState.unit] or 0) then
        -- Stationary traffic is not a reading. The plate still is, though: a
        -- parked car is exactly the thing you would point this at to run.
        speed = 0
    end

    local plate = GetCleanPlate(entity)
    local newPlate = plate ~= h.plate

    local pc = GetEntityCoords(ped)
    local vc = GetEntityCoords(entity)
    local nx, ny, nz = (vc.x - pc.x) / dist, (vc.y - pc.y) / dist, (vc.z - pc.z) / dist
    local v = GetEntityVelocity(entity)
    local closing = -(v.x * nx + v.y * ny + v.z * nz)

    h.entity = entity
    h.speed  = speed
    h.plate  = plate
    h.index  = GetVehicleNumberPlateTextIndex(entity)
    h.dir    = closing > 0 and 'closing' or 'away'
    h.dist   = math.floor(dist + 0.5)
    h.readAt = GetGameTimer()

    if newPlate then
        h.hits, h.severity, h.checked = nil, nil, false
        h.flagged, h.reason = false, nil

        if IsWatched(plate) then
            h.flagged, h.reason, h.checked = true, 'WATCH', true
            PlayRadarSound('Bolo', 1500)
        end

        RunPlateCheck('gun', plate, h.index)
    end

    -- Automatic lock. No player-driven filter here, unlike the antennas: a
    -- sweeping antenna catches whatever passes, but a gun was pointed at this
    -- vehicle on purpose.
    if RadarState.settings.gunAutoLock and not h.lock and speed >= RadarState.settings.gunLimit then
        h.lock = {
            speed = speed, plate = plate, index = h.index,
            dir = h.dir, dist = h.dist, at = GetGameTimer(), auto = true,
        }
        PlayRadarSound('Lock', 250)
        TriggerServerEvent('lsn-radar:server:speedLocked', speed, RadarState.unit, plate)
        push(true)
    end
end

--- What the target bracket should frame. Read by target.lua so both devices
--- feed one renderer instead of each drawing their own.
---@return number|nil entity
---@return boolean locked
function GetHandheldTarget()
    local h = HandheldState
    if not h.active then return nil, false end
    if h.lock then return h.entity, true end
    if h.aiming and h.entity then return h.entity, false end
    return nil, false
end

-- ── Device thread ─────────────────────────────────────────────────────────
-- Three cadences. Without the gun in hand this costs one native every half
-- second; that is the state a player is in for essentially their whole session,
-- so it is the one worth being cheap.

CreateThread(function()
    while true do
        local wait = 500

        if cfg().Enabled and HasRadarAccess() then
            weaponHash = weaponHash or GetHashKey(cfg().Weapon)
            local ped = PlayerPedId()
            local holding = GetSelectedPedWeapon(ped) == weaponHash

            if holding ~= HandheldState.active then
                HandheldState.active = holding
                if not holding then
                    HandheldState.lock, HandheldState.aiming = nil, false
                    clearReading()
                end
                push(true)
            end

            if holding then
                -- Firing is disabled outright. Whatever weapon this is bound to
                -- is a measuring instrument here, and an officer who pulls the
                -- trigger to take a reading must not put a round into the car
                -- they were measuring.
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)   -- attack
                DisableControlAction(0, 257, true)  -- attack2
                DisableControlAction(0, 140, true)  -- melee

                -- Either signal counts. IsPlayerFreeAiming reports the game's
                -- own aiming state, which does not always fire depending on the
                -- weapon and whether aim assist is in play; the raw aim control
                -- is what the operator actually pressed. Requiring only the
                -- former was why aiming at a car did nothing.
                local aiming = IsPlayerFreeAiming(PlayerId()) or IsControlPressed(0, 25)
                if aiming ~= HandheldState.aiming then
                    HandheldState.aiming = aiming
                    push(true)
                end

                if aiming then
                    -- The frame loop has to keep running to hold the firing
                    -- controls down and to catch the trigger, but measuring now
                    -- walks the vehicle pool, and doing that sixty times a
                    -- second would cost more than the mounted radar does. Same
                    -- cadence as the antennas: ten readings a second is already
                    -- faster than a number can be read.
                    wait = 0

                    local now = GetGameTimer()
                    if not HandheldState.lock and (now - lastMeasure) >= Config.Radar.Tick then
                        lastMeasure = now
                        measure()
                    end

                    -- The trigger locks instead of firing, which is where a
                    -- radar gun's lock button is anyway.
                    if IsDisabledControlJustPressed(0, 24) then toggleLock() end
                    push()
                else
                    wait = 0  -- controls must be disabled every frame
                end
            end
        elseif HandheldState.active then
            HandheldState.active, HandheldState.aiming, HandheldState.lock = false, false, nil
            clearReading()
            push(true)
        end

        Wait(wait)
    end
end)