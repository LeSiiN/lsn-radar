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

--- How long the vehicle list is reused before being fetched again.
---
--- Briefly raised to 2000ms so the skip table below could bank more than five
--- ticks. That was wrong, and badly so: in dense traffic vehicles stream in
--- constantly, and a car that appeared right in front of the patrol vehicle
--- stayed invisible to the sweep for up to two seconds. Since that is precisely
--- the car whose plate an officer wants, the plate row went blank exactly when
--- there was most to read.
---
--- 500ms is the ceiling here. The skip table gets less out of it, and that is
--- the correct trade: skipping is an optimisation, seeing the vehicle in front
--- of you is the job.
local POOL_TTL = 500

--- Whether an entity is a class the radar reads. Keyed by handle and dropped
--- with the pool, so a recycled handle cannot inherit an answer.
local readable = {}

--- Vehicles too far away to matter yet, with the tick they become worth looking
--- at again.
---
--- This is the one remaining reduction available on the hot path. Every
--- candidate costs a GetEntityCoords before its distance can be judged, and on
--- a busy street most of the pool is hundreds of metres away — so the majority
--- of the work is reading positions in order to throw them away.
---
--- A vehicle 500m out cannot reach a 250m cone in a tenth of a second: that
--- would need a closing rate of 2,500 m/s. So the surplus distance buys a
--- number of ticks it can safely be ignored for, computed from a closing rate
--- no pair of vehicles in this game can exceed.
---
--- Cleared with the pool every 500ms, which caps a skip at five ticks. That
--- still removes about two thirds of the position reads on a busy street, and
--- keeping it longer is not worth what it costs — see POOL_TTL above.
local skipUntil = {}
local tickNo = 0

--- Line of sight per entity. A raycast is the most expensive thing on this
--- path — up to six a tick once traffic is in the cones, which is exactly when
--- the frame budget is under pressure.
---
--- 250ms is chosen against what the answer is worth: a target that ducks behind
--- a lorry is hidden for far longer than that, so nothing visibly lingers,
--- while one held steadily in the open stops paying for a ray it has already
--- passed four times.
local losCache = {}
local LOS_TTL = 250

--- Plate text and driver per entity. A vehicle's plate does not change, and
--- whether a real player is driving changes rarely enough that a second is
--- nothing. Without it the winning target paid three natives every tick to be
--- told what it was told a tenth of a second earlier.
local infoCache = {}
local INFO_TTL = 1000

--- Assumed worst-case closing rate in m/s, patrol and target combined.
--- Generously above anything drivable — the cost of overestimating is a few
--- wasted coordinate reads, while underestimating would mean missing a car.
local MAX_CLOSING = 220.0

local function refreshPool()
    local now = GetGameTimer()
    if (now - poolAt) < POOL_TTL then return end

    poolAt = now
    pool = GetGamePool('CVehicle')

    -- Both caches are keyed by entity handle, and handles get recycled. Cleared
    -- together with the pool so a new vehicle cannot inherit an old one's
    -- answer — a wrongly inherited skip would be a car the radar never sees,
    -- which is the worst failure this whole file can produce.
    -- All four are keyed by entity handle, and handles get recycled onto
    -- different vehicles. Cleared together with the pool so nothing can inherit
    -- an answer that belonged to a car that is gone.
    for k in pairs(readable) do readable[k] = nil end
    for k in pairs(skipUntil) do skipUntil[k] = nil end
    for k in pairs(losCache) do losCache[k] = nil end
    for k in pairs(infoCache) do infoCache[k] = nil end
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

    tickNo = tickNo + 1

    -- Metres a pair of vehicles can close between two sweeps. Anything further
    -- outside the range than this is provably irrelevant for at least one tick.
    local perTick = MAX_CLOSING * (Config.Radar.Tick / 1000.0)
    local maxRange = math.sqrt(maxSq)

    for i = 1, #pool do
        local veh = pool[i]
        local skip = skipUntil[veh]

        if skip and skip > tickNo then
            -- Known to be far away and not yet able to have arrived. Costs one
            -- table lookup instead of an existence check and a position read.
            goto continue
        end

        if veh ~= patrolVeh and DoesEntityExist(veh) then
            -- Verified on every read rather than trusted from the cache: a
            -- handle can be recycled onto a different vehicle inside the pool's
            -- lifetime, and an inherited skip would be a car the radar never
            -- sees. One cheap native to rule that out.
            local c = GetEntityCoords(veh)
            local dx, dy, dz = c.x - px, c.y - py, c.z - pz
            local distSq = dx * dx + dy * dy + dz * dz

            -- Bank the surplus distance as ticks that can be skipped. Only for
            -- vehicles comfortably outside: a car just past the edge is one the
            -- operator is about to be interested in.
            if distSq > maxSq then
                local surplus = math.sqrt(distSq) - maxRange
                if surplus > perTick then
                    skipUntil[veh] = tickNo + math.floor(surplus / perTick)
                end
            end

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

        ::continue::
    end

    Sweep.front, Sweep.rear = scratch.front, scratch.rear
    Sweep.frontCount, Sweep.rearCount = nFront, nRear
    Sweep.plateFront, Sweep.plateRear = bestFront, bestRear
end

--- Line of sight, checked only for a candidate about to be displayed.
---
--- Cached briefly, because this is a raycast and raycasts are the most
--- expensive thing on this path — up to six a tick once traffic is in the
--- cones, which is exactly when the frame budget is under pressure.
---
--- 250ms is chosen against what the answer is worth: a target that ducks behind
--- a lorry is hidden for far longer than that, so nothing visibly lingers,
--- while a target held steadily in the open stops paying for a ray it has
--- already passed four times.
---@param patrolVeh number
---@param c table
---@return boolean
function HasSight(patrolVeh, c)
    local entity = c.entity
    local now = GetGameTimer()

    local hit = losCache[entity]
    if hit and (now - hit.at) < LOS_TTL then return hit.ok end

    local ok = HasEntityClearLosToEntity(patrolVeh, entity, 17)
    if hit then
        hit.ok, hit.at = ok, now
    else
        losCache[entity] = { ok = ok, at = now }
    end
    return ok
end

--- Plate text and driver for a candidate that won a window.
---
--- Cached per entity: a vehicle's plate does not change, and whether a real
--- player is driving changes rarely enough that a second is nothing. Without
--- this the winning target paid three natives every tick to be told the same
--- thing it was told a tenth of a second earlier.
--- Fill in the fields skipped during the sweep.
---@param c table
function ResolveCandidate(c)
    if c.resolved then return c end
    c.resolved = true

    local entity = c.entity
    local now = GetGameTimer()
    local info = infoCache[entity]

    if not info or (now - info.at) >= INFO_TTL then
        local driver = GetPedInVehicleSeat(entity, -1)
        info = {
            plate    = GetCleanPlate(entity),
            index    = GetVehicleNumberPlateTextIndex(entity),
            isPlayer = driver ~= 0 and IsPedAPlayer(driver),
            at       = now,
        }
        infoCache[entity] = info
    end

    c.plate      = info.plate
    c.plateIndex = info.index
    c.isPlayer   = info.isPlayer
    return c
end