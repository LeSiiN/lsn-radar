-- ═══════════════════════════════════════════════════════════════════════════
--  Detection sweep
-- ═══════════════════════════════════════════════════════════════════════════
-- One pass over the vehicle pool, feeding both the antennas and the plate
-- cameras.
--
-- It used to be two: the radar walked the pool at 10Hz and the plate reader
-- walked it again at 4Hz, each doing its own coordinate read and class check on
-- every vehicle in the world before rejecting most of them. On a busy street
-- that is around 6,000 native calls a second spent almost entirely on deciding
-- that a car three blocks away is not interesting.
--
-- Three things fixed that:
--
--   1. One walk instead of two. The cameras look at a wider, shorter cone than
--      the antennas, but they look at the same vehicles, so the geometry is
--      computed once and both consumers read it.
--
--   2. Cheapest rejection first. Distance is now the first test, before the
--      class check — most vehicles fail it, and failing it now costs one native
--      instead of two.
--
--   3. Nothing expensive happens for a vehicle that is not going to win.
--      Plate text, driver lookups and line-of-sight raycasts used to run for
--      every candidate in the cone; they now run only for the one or two
--      vehicles that actually reach a display.

-- ── Caches ────────────────────────────────────────────────────────────────

--- GetGamePool allocates a fresh table on every call. Cars do not enter and
--- leave the world at 10Hz, so the list is reused for half a second; stale
--- handles are caught by the existence check when they are used.
local pool = {}
local poolAt = 0
local POOL_TTL = 500

--- Whether an entity is a class the radar reads. Keyed by handle and dropped
--- with the pool, so a recycled handle cannot inherit an answer.
local readable = {}

local function refreshPool()
    local now = GetGameTimer()
    if (now - poolAt) < POOL_TTL then return end

    poolAt = now
    pool = GetGamePool('CVehicle')

    for k in pairs(readable) do readable[k] = nil end
end

--- The cached vehicle list, for consumers outside the sweep. The handheld unit
--- uses it while aiming; sharing the cache means the two devices cannot end up
--- refreshing the pool twice in the same frame.
---@return table
function GetVehiclePool()
    refreshPool()
    return pool
end

---@param veh number
---@return boolean
local function isReadable(veh)
    local cached = readable[veh]
    if cached ~= nil then return cached end

    local ok = IsReadableVehicle(veh)
    readable[veh] = ok
    return ok
end

-- ── Results ───────────────────────────────────────────────────────────────
-- Reused between ticks. Allocating two candidate lists ten times a second for
-- the lifetime of a shift is free garbage nobody asked for.

Sweep = {
    front = {},        -- radar cone candidates, geometry and speed only
    rear  = {},
    plateFront = nil,  -- nearest vehicle in the camera cone
    plateRear  = nil,
}

--- Candidate tables are pooled as well: the fields are overwritten in place, so
--- a busy road does not produce a fresh table per vehicle per tick.
local scratch = { front = {}, rear = {} }

---@param list table
---@param n number
---@return table
local function slot(list, n)
    local t = list[n]
    if not t then
        t = {}
        list[n] = t
    end
    return t
end

-- ── Sweep ─────────────────────────────────────────────────────────────────

local cosRadar, cosPlate
local lastRadarAngle, lastPlateAngle

--- One pass. Fills Sweep for both consumers.
---@param patrolVeh number
---@param wantPlates boolean cameras are off or the panel is hidden
function RunSweep(patrolVeh, wantPlates)
    refreshPool()

    local pc = GetEntityCoords(patrolVeh)
    local px, py, pz = pc.x, pc.y, pc.z
    local fwd = GetEntityForwardVector(patrolVeh)
    local fx, fy, fz = fwd.x, fwd.y, fwd.z

    -- Hoisted: the patrol car's own velocity does not change while the loop
    -- runs, and reading it per candidate was one wasted native per vehicle in
    -- the cone on every tick.
    local pvel = GetEntityVelocity(patrolVeh)
    local pvx, pvy, pvz = pvel.x, pvel.y, pvel.z

    local radarRange = RadarState.settings.range
    local radarSq = radarRange * radarRange
    local plateRange = Config.PlateReader.Range
    local plateSq = plateRange * plateRange

    -- One distance gate for both consumers, set to whichever reaches further.
    local maxSq = radarSq > plateSq and radarSq or plateSq

    if lastRadarAngle ~= Config.Radar.ConeAngle then
        lastRadarAngle = Config.Radar.ConeAngle
        cosRadar = math.cos(math.rad(lastRadarAngle))
    end
    if lastPlateAngle ~= Config.PlateReader.ConeAngle then
        lastPlateAngle = Config.PlateReader.ConeAngle
        cosPlate = math.cos(math.rad(lastPlateAngle))
    end

    local unit = RadarState.unit
    local minSpeed = Config.Radar.MinSpeed[unit] or 0

    -- Each antenna's Approaching / Departing / Both filter. Applied here, at
    -- the point of collection, so a target the operator has filtered out never
    -- becomes a candidate and never costs a size lookup.
    local frontMode = RadarState.antennas.front.mode
    local rearMode  = RadarState.antennas.rear.mode

    local nFront, nRear = 0, 0
    local bestFront, bestFrontDist
    local bestRear, bestRearDist

    for i = 1, #pool do
        local veh = pool[i]

        if veh ~= patrolVeh and DoesEntityExist(veh) then
            local c = GetEntityCoords(veh)
            local dx, dy, dz = c.x - px, c.y - py, c.z - pz
            local distSq = dx * dx + dy * dy + dz * dz

            -- Distance first. Most of the world fails here, and failing here is
            -- the cheapest failure available.
            if distSq <= maxSq and distSq > 1.0 and isReadable(veh) then
                local len = math.sqrt(distSq)
                local nx, ny, nz = dx / len, dy / len, dz / len
                local alignment = fx * nx + fy * ny + fz * nz

                local isFront = alignment >= 0
                local absAlign = isFront and alignment or -alignment

                -- Camera cone: wider and shorter. Only the nearest matters, so
                -- there is nothing to collect — just a running minimum.
                if wantPlates and absAlign >= cosPlate and distSq <= plateSq then
                    if isFront then
                        if not bestFrontDist or distSq < bestFrontDist then
                            bestFront, bestFrontDist = veh, distSq
                        end
                    else
                        if not bestRearDist or distSq < bestRearDist then
                            bestRear, bestRearDist = veh, distSq
                        end
                    end
                end

                -- Antenna cone: narrow and long.
                if absAlign >= cosRadar and distSq <= radarSq then
                    local speed = ConvertSpeed(GetEntitySpeed(veh), unit)

                    if speed >= minSpeed then
                        local tvel = GetEntityVelocity(veh)
                        -- n points patrol → target, so a closing target has a
                        -- negative component along it.
                        local closing = -((tvel.x - pvx) * nx
                                        + (tvel.y - pvy) * ny
                                        + (tvel.z - pvz) * nz)

                        -- Cross traffic has no speed a Doppler antenna could
                        -- honestly report.
                        if closing >= 1.0 or closing <= -1.0 then
                            local mode = isFront and frontMode or rearMode
                            local wanted = mode == 'both'
                                or (mode == 'closing' and closing > 0)
                                or (mode == 'away' and closing < 0)

                            if wanted then
                            local list, n
                            if isFront then
                                nFront = nFront + 1
                                list, n = scratch.front, nFront
                            else
                                nRear = nRear + 1
                                list, n = scratch.rear, nRear
                            end

                            local t = slot(list, n)
                            t.entity = veh
                            t.speed = speed
                            t.size = GetVehicleSize(veh)
                            t.dir = closing > 0 and 'closing' or 'away'
                            -- Plate and driver are deliberately absent. They are
                            -- filled in later, and only for a candidate that
                            -- actually wins a window.
                            t.plate = nil
                            t.isPlayer = nil
                            t.resolved = false
                            end
                        end
                    end
                end
            end
        end
    end

    Sweep.front, Sweep.rear = scratch.front, scratch.rear
    Sweep.frontCount, Sweep.rearCount = nFront, nRear
    Sweep.plateFront, Sweep.plateRear = bestFront, bestRear
end

--- Fill in the fields that were skipped during the sweep.
---
--- Called for a candidate only once it has won a window, which is what keeps
--- the plate read and the driver lookup off the hot path — in traffic those two
--- natives per vehicle per tick were most of the cost of knowing things nobody
--- ever looked at.
---@param c table
function ResolveCandidate(c)
    if c.resolved then return c end
    c.resolved = true
    c.plate = GetCleanPlate(c.entity)
    -- Carried so a lock can pin the plate *with* its design. Without it the
    -- pinned row falls back to a plain badge and the artwork disappears the
    -- moment the plate matters most.
    c.plateIndex = GetVehicleNumberPlateTextIndex(c.entity)

    local driver = GetPedInVehicleSeat(c.entity, -1)
    c.isPlayer = driver ~= 0 and IsPedAPlayer(driver)
    return c
end

--- Line of sight, checked only for a candidate about to be displayed.
---@param patrolVeh number
---@param c table
---@return boolean
function HasSight(patrolVeh, c)
    return HasEntityClearLosToEntity(patrolVeh, c.entity, 17)
end
