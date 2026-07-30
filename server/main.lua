-- ═══════════════════════════════════════════════════════════════════════════
--  ps-radar — server
-- ═══════════════════════════════════════════════════════════════════════════
-- The radar itself is entirely client side: it reads entities the client can
-- already see, and nothing it computes needs to be trusted. What the server is
-- for is the seam with everything else — the events other resources listen to,
-- and the exports they call to reach into a specific unit's reader.

local QBCore = exports['qb-core']:GetCoreObject()

-- ── Abuse guard ───────────────────────────────────────────────────────────
-- These events are client-triggered, so they are reachable by anyone with an
-- executor. Nothing here grants anything, but an unbounded relay is still a
-- way to spam every listening resource, so each source gets a floor between
-- events. The window is generous — a plate reader legitimately fires several
-- times a second in traffic.

local lastEventAt = {}

---@param src number
---@param key string
---@param gapMs number
---@return boolean
local function allow(src, key, gapMs)
    local id = src .. ':' .. key
    local now = GetGameTimer()
    if now - (lastEventAt[id] or 0) < gapMs then return false end
    lastEventAt[id] = now
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    for id in pairs(lastEventAt) do
        if id:sub(1, #tostring(src) + 1) == src .. ':' then
            lastEventAt[id] = nil
        end
    end
end)

--- Is this source actually an officer? A relayed plate scan carries weight in
--- whatever listens for it, so it should not be possible to fabricate one from
--- a civilian character.
---@param src number
---@return boolean
local function isOfficer(src)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return false end

    local job = player.PlayerData.job
    if not job then return false end
    if Config.RequireDuty and not job.onduty then return false end

    local allowed = Config.Jobs
    if type(allowed) ~= 'table' or #allowed == 0 then return true end
    for i = 1, #allowed do
        if allowed[i] == job.type or allowed[i] == job.name then return true end
    end
    return false
end

-- ── MDT plate check ───────────────────────────────────────────────────────
-- The radar does not query the database itself. ps-mdt already owns plate
-- lookups, and its implementation is explicitly written for scanners: cached,
-- coalesced, cooldown-limited per officer, budgeted per minute, and audited on
-- hits rather than on every scan. Duplicating any of that here would mean two
-- systems disagreeing about what an officer has already been told.

RegisterNetEvent('ps-radar:server:checkPlate', function(cam, plate, plateIndex, coords)
    local src = source
    if cam ~= 'front' and cam ~= 'rear' then return end
    if type(plate) ~= 'string' or #plate > 8 then return end

    -- Floor is generous: two cameras legitimately produce a burst when a car
    -- passes. ps-mdt applies the real limits behind this.
    if not allow(src, 'mdt', 250) then return end
    if not isOfficer(src) then return end

    local mdt = Config.PlateReader.Mdt
    if not mdt or mdt.Mode == 'off' then return end
    if GetResourceState(mdt.Resource) ~= 'started' then return end

    -- Threaded because both exports hit the database. Blocking the event
    -- handler would stall every other net event from this client.
    CreateThread(function()
        local ok, result = pcall(function()
            if mdt.Mode == 'lookup' then
                -- Silent: hits show in the reader, no dispatch card. src is
                -- still passed so ps-mdt applies its own job check rather than
                -- trusting the radar to have done it.
                return exports[mdt.Resource]:CheckPlate(plate, src)
            end
            return exports[mdt.Resource]:PlateCheckAlert(src, plate, coords, plateIndex)
        end)

        if not ok or type(result) ~= 'table' then return end
        -- A denied lookup is not a clean plate. Say nothing rather than
        -- telling the reader the car came back clear.
        if result.denied then return end

        TriggerClientEvent('ps-radar:client:plateResult', src, cam, plate, result.hits or {}, result.severity)
    end)
end)

-- ── Relayed events ────────────────────────────────────────────────────────
-- Named to match the shape server owners already know from the resource this
-- one is modelled on, so existing integration snippets need only a rename.

RegisterNetEvent('ps-radar:server:plateScanned', function(cam, plate, index)
    local src = source
    if type(plate) ~= 'string' or #plate > 8 then return end
    if not allow(src, 'scan', 200) then return end
    if not isOfficer(src) then return end

    TriggerEvent('ps-radar:onPlateScanned', src, cam, plate, index)
end)

RegisterNetEvent('ps-radar:server:plateLocked', function(cam, plate, index)
    local src = source
    if type(plate) ~= 'string' or #plate > 8 then return end
    if not allow(src, 'lock', 200) then return end
    if not isOfficer(src) then return end

    TriggerEvent('ps-radar:onPlateLocked', src, cam, plate, index)
end)

RegisterNetEvent('ps-radar:server:speedLocked', function(speed, unit, plate)
    local src = source
    speed = tonumber(speed)
    if not speed then return end
    if not allow(src, 'speed', 1000) then return end
    if not isOfficer(src) then return end

    -- Relay only. The dispatch alert itself fires from the officer's client,
    -- because ps-dispatch's CustomAlert is a client export — routing it through
    -- here would mean rebuilding the coords, street and gender lookup that
    -- CustomAlert already does on the client that has them.
    TriggerEvent('ps-radar:onSpeedLocked', src, speed, unit, plate)
end)

-- ── Exports ───────────────────────────────────────────────────────────────

--- Make a specific unit's plate reader lock a camera.
---@param clientId number
---@param cam string 'front' | 'rear'
---@param beep boolean|nil
exports('TogglePlateLock', function(clientId, cam, beep)
    if cam ~= 'front' and cam ~= 'rear' then return false end
    TriggerClientEvent('ps-radar:client:lockCamera', clientId, cam, beep)
    return true
end)

--- Push a BOLO plate to one unit, or to everyone with -1. The MDT issuing a
--- BOLO is the case this exists for.
---@param clientId number
---@param plate string
exports('SetBolo', function(clientId, plate)
    TriggerClientEvent('ps-radar:client:setBolo', clientId, plate)
end)

--- Open a unit's control panel from elsewhere.
---@param clientId number
exports('OpenRemote', function(clientId)
    TriggerClientEvent('ps-radar:client:openRemote', clientId)
end)