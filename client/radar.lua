-- ═══════════════════════════════════════════════════════════════════════════
--  Antennas
-- ═══════════════════════════════════════════════════════════════════════════
-- Two antennas, front and rear. Each reports two numbers, which is the part
-- that makes a radar display readable rather than a single flickering figure:
--
--   STRONG  the largest vehicle in the cone — the one reflecting the most
--           signal back, and usually the one you are actually looking at.
--   FAST    a smaller vehicle travelling faster than the strong target. This
--           is the car that overtakes the lorry you were watching, and on a
--           single-number display it is invisible.
--
-- Detection is a cone test plus a line-of-sight raycast, not a sphere lookup.
-- A sphere would read the car beside you as readily as the one 300m up the
-- road, and a radar that cannot be aimed is not a radar.

--- Reused between ticks so rejecting a blocked target does not allocate.
local rejected = {}

--- Pick the strong and fast target out of a cone's candidates.
---
--- Strong is simply the biggest. Fast is the quickest vehicle that is both
--- smaller and faster than strong — if nothing is quicker than the strong
--- target the fast window stays dark, which is correct and is how the operator
--- knows the big number is the whole story.
---
--- Line of sight is checked here rather than during the sweep. A raycast per
--- candidate per tick was being spent on vehicles that lost the window anyway;
--- now the biggest is tested, and only if it turns out to be behind a building
--- does the next one get a ray. In practice that is one raycast per antenna per
--- tick instead of one per car in the cone.
---@param list table
---@param count number
---@param patrolVeh number
---@return table|nil strong
---@return table|nil fast
local function resolveTargets(list, count, patrolVeh)
    if count == 0 then return nil, nil end

    for k in pairs(rejected) do rejected[k] = nil end

    -- Strong: biggest reflector the antenna can actually see.
    local strong
    for _ = 1, 3 do
        local best, bestIdx
        for i = 1, count do
            if not rejected[i] then
                local c = list[i]
                if not best or c.size > best.size then best, bestIdx = c, i end
            end
        end
        if not best then break end

        if HasSight(patrolVeh, best) then
            strong = best
            break
        end
        rejected[bestIdx] = true
    end

    if not strong then return nil, nil end

    -- Fast: something smaller moving quicker than strong.
    local fast
    for _ = 1, 3 do
        local best, bestIdx
        for i = 1, count do
            local c = list[i]
            if not rejected[i] and c ~= strong and c.speed > strong.speed and c.size < strong.size then
                if not best or c.speed > best.speed then best, bestIdx = c, i end
            end
        end
        if not best then break end

        if HasSight(patrolVeh, best) then
            fast = best
            break
        end
        rejected[bestIdx] = true
    end

    return ResolveCandidate(strong), fast and ResolveCandidate(fast) or nil
end

--- Should this target trip the automatic lock?
---@param antenna table
---@param target table|nil
---@return boolean
local function shouldFastLock(antenna, target)
    if not target then return false end
    if not Config.Radar.AllowFastLock then return false end

    local s = RadarState.settings
    if not s.fastLock then return false end
    if target.speed < s.fastLimit then return false end

    -- An NPC doing 140 on the freeway is a traffic simulation artefact. Locking
    -- it fills the window with a speed nobody can be stopped for.
    if Config.Radar.FastLockPlayersOnly and not target.isPlayer then return false end

    -- A locked antenna is committed to one vehicle until the officer releases
    -- it. Re-locking on whatever else drives into the cone is precisely what
    -- the lock exists to prevent.
    if antenna.lock then return false end

    return true
end

---@param antenna table
---@param target table
---@param source string 'strong' | 'fast'
---@param auto boolean
function LockAntenna(antenna, target, source, auto)
    antenna.lock = {
        -- Tracked by entity rather than by plate. NPC traffic in GTA reuses
        -- plates freely, so a plate is not an identity — following one would
        -- eventually hop to a different car wearing the same characters.
        entity = target.entity,
        plate  = target.plate,
        index  = target.plateIndex,
        speed  = target.speed,
        peak   = target.speed,
        dir    = target.dir,
        src    = source,
        auto   = auto,
        lost   = false,
        at     = GetGameTimer(),
    }

    -- The windows keep the picture as it was at the moment of the lock. They
    -- are the context the lock happened in; the live number moves to the lock
    -- window from here on.
    antenna.frozen = { strong = antenna.strong, fast = antenna.fast }

    -- Pin the camera on the same side to the same vehicle. A speed without the
    -- plate that produced it is not evidence, and the plate the camera happened
    -- to be reading a moment later belongs to whatever came next.
    if antenna.cam and target.plate and target.plate ~= '' then
        PinCameraToPlate(antenna.cam, target.plate, target.plateIndex)
    end

    PlayRadarSound('Lock', 250)

    if not auto then return end

    TriggerServerEvent('ps-radar:server:speedLocked', target.speed, RadarState.unit, target.plate or '')

    -- ps-dispatch's CustomAlert is a client export taking one table, so the
    -- alert originates here rather than on the server. Wrapped because a
    -- renamed or stopped sibling resource must not take the radar down with it.
    local alert = Config.Integration.SpeedAlert
    if not alert.Enabled then return end
    if GetResourceState(alert.Resource) ~= 'started' then return end
    if target.speed < (RadarState.settings.fastLimit * alert.Threshold) then return end

    pcall(function()
        exports[alert.Resource][alert.Export]({
            message      = ('Reckless driver — %d %s'):format(target.speed, RadarState.unit),
            dispatchCode = 'radarspeed',
            code         = alert.Code,
            icon         = alert.Icon,
            priority     = alert.Priority,
            coords       = GetEntityCoords(PlayerPedId()),
            plate        = target.plate,
        })
    end)
end

--- Follow an already locked vehicle.
---
--- Deliberately not a cone test: once a target is locked the antenna is
--- tracking a known vehicle rather than acquiring a new one, and in a pursuit
--- that vehicle swerves, changes lane and takes corners. Re-applying a narrow
--- acquisition cone would drop the reading every time the road bends, which is
--- exactly when the number matters most.
---
--- Range still applies. Beyond it the last reading is held and marked stale
--- rather than silently continuing to look live.
---@param antenna table
---@param patrolVeh number
local function trackLocked(antenna, patrolVeh)
    local lock = antenna.lock
    local veh = lock.entity

    if not veh or not DoesEntityExist(veh) then
        lock.lost = true
        return
    end

    local pc = GetEntityCoords(patrolVeh)
    local vc = GetEntityCoords(veh)
    local dx, dy, dz = vc.x - pc.x, vc.y - pc.y, vc.z - pc.z
    local distSq = dx * dx + dy * dy + dz * dz

    local range = RadarState.settings.range
    if distSq > (range * range) then
        lock.lost = true
        return
    end

    local speed = ConvertSpeed(GetEntitySpeed(veh), RadarState.unit)
    lock.lost = false
    lock.speed = speed

    -- The highest reading seen while locked is kept alongside the live one. In
    -- a pursuit the speed the driver actually reached is the fact worth
    -- keeping, and it is gone the moment they brake for a corner.
    if speed > (lock.peak or 0) then lock.peak = speed end

    local len = math.sqrt(distSq)
    local nx, ny, nz = dx / len, dy / len, dz / len
    local pvel, tvel = GetEntityVelocity(patrolVeh), GetEntityVelocity(veh)
    local closingRate = -((tvel.x - pvel.x) * nx
                        + (tvel.y - pvel.y) * ny
                        + (tvel.z - pvel.z) * nz)
    lock.dir = closingRate > 0 and 'closing' or 'away'
end

---@param antenna table
---@param list table
local function applyToAntenna(antenna, list, count, patrolVeh)
    if antenna.lock then
        -- Locked: no new acquisition on this antenna at all. The windows keep
        -- the snapshot from the moment of the lock and trackLocked keeps the
        -- lock window live.
        local frozen = antenna.frozen
        if frozen then
            antenna.strong, antenna.fast = frozen.strong, frozen.fast
            -- Refreshed so the grace window cannot expire underneath a lock and
            -- take the frozen snapshot with it.
            antenna.strongAt, antenna.fastAt = GetGameTimer(), GetGameTimer()
        end
        return
    end

    if not antenna.xmit then
        -- HOLD: the display freezes on whatever it last showed. That is the
        -- entire point of the button — you hold the reading so you can read it
        -- out while the traffic moves on.
        return
    end

    local strong, fast = resolveTargets(list, count, patrolVeh)
    local now = GetGameTimer()
    local grace = Config.Radar.ReadingHold or 0

    -- Identity travels with the reading. Without it, holding an antenna froze a
    -- number with no way to say which car it came from — and the plate row
    -- underneath carried on scanning whatever drove past next.
    if strong then
        antenna.strong = {
            speed = strong.speed, dir = strong.dir,
            entity = strong.entity, plate = strong.plate, index = strong.plateIndex,
        }
        antenna.strongAt = now
    elseif antenna.strong and (now - (antenna.strongAt or 0)) >= grace then
        -- Held through the grace window above, dropped once it expires. The
        -- bracket reads the same field, so it appears and disappears with the
        -- number rather than on its own schedule.
        antenna.strong = nil
    end

    if fast then
        antenna.fast = {
            speed = fast.speed, dir = fast.dir,
            entity = fast.entity, plate = fast.plate, index = fast.plateIndex,
        }
        antenna.fastAt = now
    elseif antenna.fast and (now - (antenna.fastAt or 0)) >= grace then
        antenna.fast = nil
    end

    if shouldFastLock(antenna, strong) then
        LockAntenna(antenna, strong, 'strong', true)
    elseif shouldFastLock(antenna, fast) then
        LockAntenna(antenna, fast, 'fast', true)
    end

    -- Timed release, when the server owner has configured one.
    local hold = Config.Radar.LockHold
    if hold > 0 and antenna.lock and (GetGameTimer() - antenna.lock.at) > hold * 1000 then
        antenna.lock, antenna.frozen = nil, nil
    end
end

--- The antenna thread. Runs only while the radar is powered and the officer is
--- in a patrol vehicle; otherwise it sleeps a second at a time so a parked
--- resource costs nothing.
CreateThread(function()
    while true do
        local wait = 500

        if RadarState.power then
            local patrolVeh = GetPatrolVehicle()
            if patrolVeh then
                wait = Config.Radar.Tick

                RadarState.patrolSpeed = ConvertSpeed(GetEntitySpeed(patrolVeh), RadarState.unit)

                local front, rear = RadarState.antennas.front, RadarState.antennas.rear

                -- With both antennas locked there is nothing to acquire, so the
                -- vehicle pool is never walked. Two entity reads replace a scan
                -- of every car in the area — which is worth having during a
                -- pursuit, when the map around you is busiest.
                local wantPlates = PlateState.power and Config.PlateReader.Enabled

                if not (front.lock and rear.lock) or wantPlates then
                    RunSweep(patrolVeh, wantPlates)
                else
                    -- Both antennas locked and no cameras running: there is
                    -- nothing to acquire, so the pool is never walked.
                    Sweep.frontCount, Sweep.rearCount = 0, 0
                    Sweep.plateFront, Sweep.plateRear = nil, nil
                end

                if front.lock then trackLocked(front, patrolVeh) end
                if rear.lock  then trackLocked(rear,  patrolVeh) end

                applyToAntenna(front, Sweep.front, Sweep.frontCount or 0, patrolVeh)
                applyToAntenna(rear,  Sweep.rear,  Sweep.rearCount  or 0, patrolVeh)

                -- The cameras read from the same sweep rather than walking the
                -- pool again on their own timer.
                if wantPlates then CommitPlates(patrolVeh) end

                PushRadarToNui()
            end
        end

        Wait(wait)
    end
end)