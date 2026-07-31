-- ═══════════════════════════════════════════════════════════════════════════
--  Plate reader
-- ═══════════════════════════════════════════════════════════════════════════
-- Two cameras, front and rear, each reading the nearest plate in its cone.
--
-- A camera is not an antenna: its cone is wide and its range is short, because
-- it is aimed at a lane rather than at a vehicle, and because it has to
-- actually resolve characters. A plate also has to sit in view for a moment
-- before it counts — without that the window strobes through every car in
-- oncoming traffic and is unreadable.

local lastConeAngle

--- What each camera is currently looking at, before the dwell timer has
--- decided it counts as a read.
local pending = {
    front = { plate = nil, since = 0 },
    rear  = { plate = nil, since = 0 },
}

--- Plates already sent to the MDT, with the time they were sent. The MDT caches
--- server side, but every scan still costs a network event, and in dense
--- traffic that is the actual bottleneck — not the database.
local sentToMdt = {}

local function cfg() return Config.PlateReader end

-- ── MDT plate check ───────────────────────────────────────────────────────

--- Hand a freshly read plate to ps-mdt.
---
--- Everything expensive happens on the other side: ps-mdt caches lookups,
--- coalesces concurrent queries for the same plate, holds a per-officer alert
--- cooldown and a per-minute budget, and audits hits rather than scans. The
--- radar's only job is not to shout the same plate at it twice.
--- Global rather than local because the handheld unit uses the same route. Two
--- lookup paths would mean two sets of throttling rules quietly disagreeing
--- about how often a plate may be asked about.
---@param cam string 'front' | 'rear' | 'gun'
---@param plate string
---@param index number|nil
function RunPlateCheck(cam, plate, index)
    local mdt = cfg().Mdt
    if not mdt or mdt.Mode == 'off' then return end
    if GetResourceState(mdt.Resource) ~= 'started' then return end

    local now = GetGameTimer()
    local window = (mdt.ResendSeconds or 120) * 1000

    local last = sentToMdt[plate]
    if last and (now - last) < window then return end

    -- Sweep on write so a long shift does not grow the table without bound.
    for known, at in pairs(sentToMdt) do
        if (now - at) >= window then sentToMdt[known] = nil end
    end
    sentToMdt[plate] = now

    -- No street resolved here. ps-dispatch already does it for its own plate
    -- log, and the alert card has no business showing a location at all — see
    -- docs/ps-dispatch-answer-cards.md.
    TriggerServerEvent('lsn-radar:server:checkPlate', cam, plate, index, GetEntityCoords(PlayerPedId()))
end

--- The MDT's answer. Arrives asynchronously, so the plate may already have
--- scrolled out of the window by the time it lands — in which case it is
--- dropped rather than flagging whatever is in there now.
RegisterNetEvent('lsn-radar:client:plateResult', function(cam, plate, hits, severity)
    -- The handheld unit has no camera, so its answers go to its own state. The
    -- lookup, the throttling and the flag rules are shared; only the place the
    -- answer lands differs.
    if cam == 'gun' then
        ApplyHandheldPlateResult(plate, hits, severity)
        return
    end

    local c = PlateState.cameras[cam]
    if not c or c.plate ~= plate then return end

    if type(hits) ~= 'table' or #hits == 0 then
        c.checked = true
        PushPlatesToNui()
        return
    end

    c.checked  = true
    c.hits     = hits
    c.severity = severity
    FlagCamera(cam, hits[1] and hits[1].label or 'Flagged')
end)

-- ── Camera state ──────────────────────────────────────────────────────────

--- Mark a camera's current plate as a hit and hold it there. A flagged plate
--- that scrolled past before anyone looked up is the failure this prevents.
---@param cam string
---@param reason string|nil
function FlagCamera(cam, reason)
    local c = PlateState.cameras[cam]
    c.flagged = true
    c.reason  = reason

    -- A hit holds the window by itself. A flagged plate that scrolled past
    -- before anyone looked up is the failure this prevents.
    --
    -- It holds the *antenna* too. Freezing only the plate left a red warning
    -- sitting above speeds that carried on changing — numbers belonging to
    -- whatever else happened to be in the cone, under a banner about a car that
    -- was no longer being measured.
    c.locked = true
    c.pinned = true
    HoldAntennaForHit(cam)

    PlayRadarSound('Bolo', 1500)
    PushPlatesToNui()
end

--- Lock or release a camera. Locking freezes the current plate in the window;
--- releasing lets it resume scanning.
---@param cam string 'front' | 'rear'
---@param state boolean|nil nil toggles
---@param silent boolean|nil suppress the beep
function TogglePlateLock(cam, state, silent)
    local c = PlateState.cameras[cam]
    if not c then return end

    -- A pinned camera is held by an antenna lock, not by the operator. Let the
    -- antenna release decide, so the two cannot disagree about what is held.
    if c.pinned then return end

    if state == nil then state = not c.locked end
    c.locked = state

    if not state then
        c.flagged  = false
        c.reason   = nil
        c.hits     = nil
        c.severity = nil
    elseif c.plate and c.plate ~= '' then
        TriggerServerEvent('lsn-radar:server:plateLocked', cam, c.plate, c.index)
    end

    if not silent then PlayRadarSound('Lock', 200) end
    PushPlatesToNui()
end

--- Hold a camera on a specific plate, because an antenna locked the vehicle it
--- belongs to.
---
--- Distinct from an operator lock: this one is released when the antenna is,
--- not by the camera key, so releasing the antenna releases both together and
--- there is no way to end up with a plate held for a lock that no longer
--- exists.
---@param cam string 'front' | 'rear'
---@param plate string
---@param index number|nil plate design index, so the artwork survives the pin
function PinCameraToPlate(cam, plate, index)
    local c = PlateState.cameras[cam]
    if not c then return end

    if c.plate ~= plate then
        c.plate    = plate
        c.index    = index
        c.hits     = nil
        c.severity = nil
        c.checked  = false
        RunPlateCheck(cam, plate, index)
    elseif index ~= nil and c.index == nil then
        -- Same plate the camera was already reading, but the pin knows the
        -- design and the camera might not have got that far.
        c.index = index
    end

    c.locked = true
    c.pinned = true
    PushPlatesToNui()
end

--- Release a pin. Called when the antenna that made it lets go.
---@param cam string
function UnpinCamera(cam)
    local c = PlateState.cameras[cam]
    if not c or not c.pinned then return end

    -- Clears the alarm, not the finding. `flagged` is "this is demanding
    -- attention right now"; `hits` and `reason` are what the MDT actually said,
    -- and those stay on the row after the officer has acknowledged it. Wiping
    -- them would make an acknowledged hit read as a clean plate.
    c.pinned = false
    c.locked = false
    c.flagged = false
    PushPlatesToNui()
end

-- ── Watchlist ─────────────────────────────────────────────────────────────

--- Normalise a plate the way both the game and the operator write it.
---@param plate string|nil
---@return string|nil
local function normalise(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():gsub('%s+', '')
    return plate ~= '' and plate or nil
end

--- Is this plate on the operator's own watchlist?
---@param plate string
---@return boolean
function IsWatched(plate)
    local list = PlateState.watch
    if not list then return false end
    for i = 1, #list do
        if list[i] == plate then return true end
    end
    return false
end

--- Add a plate to the watchlist. Idempotent, so an export firing twice does not
--- produce two identical entries the operator then has to remove twice.
---@param plate string
---@return boolean added
function AddWatchPlate(plate)
    plate = normalise(plate)
    if not plate then return false end
    if IsWatched(plate) then return false end

    local list = PlateState.watch
    if #list >= (Config.PlateReader.MaxWatchPlates or 20) then return false end

    -- Newest first: the plate just added is the one being looked for right now.
    table.insert(list, 1, plate)
    PushPlatesToNui()
    return true
end

--- Remove one plate from the watchlist.
---@param plate string
---@return boolean removed
function RemoveWatchPlate(plate)
    plate = normalise(plate)
    if not plate then return false end

    local list = PlateState.watch
    for i = #list, 1, -1 do
        if list[i] == plate then
            table.remove(list, i)
            PushPlatesToNui()
            return true
        end
    end
    return false
end

function ClearWatchPlates()
    local list = PlateState.watch
    for i = #list, 1, -1 do list[i] = nil end
    PushPlatesToNui()
end

-- ── Scanning ──────────────────────────────────────────────────────────────

--- Commit a plate to a camera once it has held still long enough.
---@param cam string
---@param veh number|nil
local function commit(cam, veh)
    local c = PlateState.cameras[cam]
    local p = pending[cam]

    -- A locked camera is holding a reading on purpose. Keep scanning in the
    -- background so it resumes instantly on release, but don't overwrite.
    if c.locked then return end

    local plate = veh and GetCleanPlate(veh) or nil
    local now = GetGameTimer()

    if plate ~= p.plate then
        p.plate = plate
        p.since = now
        return
    end

    if not plate then
        if c.plate ~= '' then
            c.plate, c.index, c.flagged, c.reason = '', nil, false, nil
            c.hits, c.severity, c.checked = nil, nil, false
            PushPlatesToNui()
        end
        return
    end

    if (now - p.since) < cfg().DwellTime then return end
    if c.plate == plate then return end

    c.plate    = plate
    c.index    = GetVehicleNumberPlateTextIndex(veh)
    c.flagged  = false
    c.reason   = nil
    c.hits     = nil
    c.severity = nil
    c.checked  = false

    PlayRadarSound('Blip', 200)
    TriggerServerEvent('lsn-radar:server:plateScanned', cam, plate, c.index)

    -- The operator's own watchlist takes precedence over the MDT lookup: it is
    -- what this officer personally decided to watch for, and it alarms without
    -- waiting for a server round trip.
    if IsWatched(plate) then
        FlagCamera(cam, 'WATCH')
    end

    -- Sent regardless of a local BOLO match: the MDT may know things about this
    -- plate that the operator's own watchlist does not.
    RunPlateCheck(cam, plate, c.index)

    PushPlatesToNui()
end

--- Read whatever the shared sweep found in each camera cone.
---
--- The cameras used to walk the vehicle pool themselves on a second timer,
--- duplicating the coordinate read and class check the antennas had already
--- done for the same cars. They now read the result of the single sweep, and
--- the dwell timer below is what keeps the cadence honest — a plate still has
--- to hold still for DwellTime before it counts, regardless of how often the
--- sweep happens to run.
---@param patrolVeh number
function CommitPlates(patrolVeh)
    local front, rear = Sweep.plateFront, Sweep.plateRear

    -- Line of sight is checked here, for at most two vehicles, rather than for
    -- every car that fell inside the cone.
    if front and not HasEntityClearLosToEntity(patrolVeh, front, 17) then front = nil end
    if rear and not HasEntityClearLosToEntity(patrolVeh, rear, 17) then rear = nil end

    commit('front', front)
    commit('rear', rear)
end
