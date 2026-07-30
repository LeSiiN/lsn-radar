-- ═══════════════════════════════════════════════════════════════════════════
--  lsn-radar — client
-- ═══════════════════════════════════════════════════════════════════════════
-- State, the NUI bridge, keybinds and the exports other resources hook into.
--
-- Two panels render without NUI focus, exactly like ps-dispatch's alerts: the
-- radar and the plate reader are read while driving, and a HUD that steals the
-- mouse is a HUD that gets switched off. Only the control panel takes focus,
-- and only while it is open.

local resourceName = GetCurrentResourceName()

-- ── State ─────────────────────────────────────────────────────────────────

local prefs = LoadPrefs()

--- Pick a stored boolean, falling back to the configured default.
---
--- Not the usual `a ~= nil and a or b` idiom: that one collapses a stored
--- `false` back to the default, so an operator who switched something off finds
--- it on again next session.
---@param stored boolean|nil
---@param fallback boolean
---@return boolean
local function boolOr(stored, fallback)
    if stored == nil then return fallback end
    return stored and true or false
end

RadarState = {
    power    = false,
    visible  = false,
    keyLock  = false,
    unit     = prefs.unit or Config.DefaultUnit,
    patrolSpeed = 0,

    antennas = {
        front = { cam = 'front', xmit = true, mode = prefs.frontMode or 'both', strong = nil, fast = nil, lock = nil },
        rear  = { cam = 'rear',  xmit = true, mode = prefs.rearMode  or 'both', strong = nil, fast = nil, lock = nil },
    },

    settings = {
        range     = prefs.range     or Config.Radar.DefaultRange,
        sound     = boolOr(prefs.sound, Config.Audio.DefaultOn),
        fastLock  = boolOr(prefs.fastLock, Config.Radar.DefaultFastLock),
        fastLimit = prefs.fastLimit or Config.Radar.DefaultFastLimit[prefs.unit or Config.DefaultUnit],
        scale     = prefs.scale     or Config.UI.DefaultScale,
        showPlate = boolOr(prefs.showPlate, true),
        -- Whether the radar was left switched on. Restored on the next patrol
        -- vehicle, because switching it on again every single shift is not a
        -- decision anybody is making — it is a chore.
        autoPower = boolOr(prefs.autoPower, false),
        marker    = boolOr(prefs.marker, true),
    },

    positions = {
        radar = prefs.radarPos or Config.UI.RadarPos,
        plate = prefs.platePos or Config.UI.PlatePos,
    },
}

PlateState = {
    power = false,
    -- The operator's own watchlist. Copied out of prefs rather than referenced,
    -- so the table the rest of the code mutates is never the one handed back by
    -- the JSON decode.
    watch = (function()
        local list = {}
        if type(prefs.watch) == 'table' then
            for i = 1, #prefs.watch do list[i] = prefs.watch[i] end
        elseif type(prefs.bolo) == 'string' and prefs.bolo ~= '' then
            -- Carried over from when the watchlist was a single plate. Someone
            -- who armed one before this update should not have it quietly
            -- vanish on the first login after it.
            list[1] = prefs.bolo
        end
        return list
    end)(),
    cameras = {
        front = { plate = '', index = nil, locked = false, pinned = false, flagged = false, reason = nil, hits = nil, severity = nil, checked = false },
        rear  = { plate = '', index = nil, locked = false, pinned = false, flagged = false, reason = nil, hits = nil, severity = nil, checked = false },
    },
}

local remoteOpen = false

--- Write the operator's preferences back to KVP. Called on every settings
--- change rather than on resource stop: a client that crashes should not lose
--- the panel layout someone spent a minute arranging.
local function persist()
    SavePrefs({
        unit      = RadarState.unit,
        range     = RadarState.settings.range,
        sound     = RadarState.settings.sound,
        fastLock  = RadarState.settings.fastLock,
        fastLimit = RadarState.settings.fastLimit,
        scale     = RadarState.settings.scale,
        showPlate = RadarState.settings.showPlate,
        autoPower = RadarState.settings.autoPower,
        marker    = RadarState.settings.marker,
        frontMode = RadarState.antennas.front.mode,
        rearMode  = RadarState.antennas.rear.mode,
        radarPos  = RadarState.positions.radar,
        platePos  = RadarState.positions.plate,
        watch     = PlateState.watch,
    })
end

-- ── NUI push ──────────────────────────────────────────────────────────────
-- The antenna thread runs at 10Hz, but most ticks change nothing — traffic
-- holding a steady speed produces an identical frame. Comparing a cheap
-- signature first keeps CEF from re-rendering sixty identical displays a
-- second, which is where an in-world HUD's frame cost actually goes.

local lastSignature = ''

local function antennaSignature(a)
    local lock = a.lock
    return table.concat({
        a.xmit and '1' or '0',
        a.mode,
        a.strong and a.strong.speed or '-',
        a.strong and a.strong.dir or '-',
        a.strong and a.strong.plate or '-',
        a.fast and a.fast.speed or '-',
        -- Every field the lock window renders has to appear here. A tracked
        -- target in a pursuit changes speed and direction constantly, and a
        -- signature that only watched for the lock's existence would hold the
        -- display on the speed it was locked at.
        lock and lock.speed or '-',
        lock and lock.peak or '-',
        lock and lock.dir or '-',
        lock and lock.plate or '-',
        lock and (lock.lost and 'X' or 'T') or '-',
    }, '|')
end

--- Strip the entity handle before the antenna crosses into the interface. It is
--- a local handle with no meaning there, and it changes on every re-stream,
--- which would churn the payload for no visible reason.
---@param a table
---@return table
local function antennaForNui(a)
    local lock = a.lock
    local function target(t)
        if not t then return nil end
        -- Entity handle stays behind: it means nothing in the interface and
        -- changes on every re-stream, which would churn the payload for no
        -- visible reason. The plate is what the display actually shows.
        return { speed = t.speed, dir = t.dir, plate = t.plate, index = t.index }
    end

    return {
        xmit = a.xmit,
        mode = a.mode,
        strong = target(a.strong),
        fast = target(a.fast),
        lock = lock and {
            speed = lock.speed,
            peak  = lock.peak,
            dir   = lock.dir,
            src   = lock.src,
            auto  = lock.auto,
            lost  = lock.lost,
            plate = lock.plate,
            at    = lock.at,
        } or nil,
    }
end

function PushRadarToNui(force)
    local sig = table.concat({
        RadarState.power and '1' or '0',
        RadarState.patrolSpeed,
        RadarState.unit,
        antennaSignature(RadarState.antennas.front),
        antennaSignature(RadarState.antennas.rear),
    }, '#')

    if not force and sig == lastSignature then return end
    lastSignature = sig

    SendNUIMessage({
        action = 'radar',
        data = {
            power       = RadarState.power,
            keyLock     = RadarState.keyLock,
            unit        = RadarState.unit,
            patrolSpeed = RadarState.patrolSpeed,
            front       = antennaForNui(RadarState.antennas.front),
            rear        = antennaForNui(RadarState.antennas.rear),
        },
    })
end

function PushPlatesToNui()
    SendNUIMessage({
        action = 'plates',
        data = {
            power   = PlateState.power,
            enabled = Config.PlateReader.Enabled,
            watch   = PlateState.watch,
            front   = PlateState.cameras.front,
            rear    = PlateState.cameras.rear,
        },
    })
end

--- Everything the interface needs that isn't per-tick: settings, layout, and
--- the config ceilings the control panel has to respect.
function PushSettingsToNui()
    SendNUIMessage({
        action = 'settings',
        data = {
            settings  = RadarState.settings,
            positions = RadarState.positions,
            unit      = RadarState.unit,
            keyLock   = RadarState.keyLock,
            watch     = PlateState.watch,
            limits = {
                minRange  = Config.Radar.MinRange,
                maxRange  = Config.Radar.MaxRange,
                minScale  = Config.UI.MinScale,
                maxScale  = Config.UI.MaxScale,
                fastLock  = Config.Radar.AllowFastLock,
                watchlist = Config.PlateReader.AllowWatchlist,
                maxWatch  = Config.PlateReader.MaxWatchPlates or 20,
                plates    = Config.PlateReader.Enabled,
                mdtMode   = Config.PlateReader.Mdt and Config.PlateReader.Mdt.Mode or 'off',
                preview   = Config.Radar.Preview and Config.Radar.Preview.Enabled or false,
                marker    = Config.Radar.TargetMarker and Config.Radar.TargetMarker.Enabled or false,
            },
            keys = Config.Keys,
        },
    })
end

local function pushVisibility()
    -- One panel now. The plate rows live inside it and are toggled by the
    -- showPlate setting, which the interface already receives.
    SendNUIMessage({
        action = 'visible',
        data = { radar = RadarState.visible },
    })
end

-- ── Show / hide ───────────────────────────────────────────────────────────

---@param visible boolean
function SetRadarVisible(visible)
    if RadarState.visible == visible then return end
    RadarState.visible = visible

    if not visible then
        CloseRemote()
    end

    pushVisibility()
    PushRadarToNui(true)
    PushPlatesToNui()
end

--- Power is not visibility: an unpowered radar still shows its housing, dark,
--- the way it does in a real car. Switching it off entirely is what leaving
--- the vehicle does.
function ToggleRadarPower()
    RadarState.power = not RadarState.power
    PlateState.power = RadarState.power and Config.PlateReader.Enabled

    if not RadarState.power then
        for _, a in pairs(RadarState.antennas) do
            a.strong, a.fast, a.lock, a.frozen = nil, nil, nil, nil
        end
        for _, c in pairs(PlateState.cameras) do
            c.plate, c.index, c.locked, c.flagged, c.reason = '', nil, false, false, nil
            c.hits, c.severity, c.checked = nil, nil, false
        end
    end

    -- Remember the choice for the next vehicle.
    RadarState.settings.autoPower = RadarState.power
    persist()

    PlayRadarSound('Alert', 200)
    PushRadarToNui(true)
    PushPlatesToNui()
end

function OpenRemote()
    if remoteOpen or not RadarState.visible then return end
    remoteOpen = true
    SetNuiFocus(true, true)
    PushSettingsToNui()
    SendNUIMessage({ action = 'remote', data = true })
end

function CloseRemote()
    if not remoteOpen then return end
    remoteOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'remote', data = false })
end

-- ── Vehicle watch ─────────────────────────────────────────────────────────
-- Owns show/hide. Polls at 1Hz because getting in and out of a car is not a
-- thing that needs frame-accurate detection, and this thread runs for every
-- officer on the server for their entire session.

CreateThread(function()
    while true do
        local shouldShow = false

        if HasRadarAccess() then
            local veh = GetPatrolVehicle()
            shouldShow = veh ~= nil
        end

        if shouldShow and not RadarState.visible and Config.UI.AutoShow then
            SetRadarVisible(true)

            -- Come up in the state it was left in rather than dark every time.
            if RadarState.settings.autoPower and not RadarState.power then
                RadarState.power = true
                PlateState.power = Config.PlateReader.Enabled
                PushRadarToNui(true)
                PushPlatesToNui()
            end
        elseif not shouldShow and RadarState.visible then
            SetRadarVisible(false)
            RadarState.power = false
            PlateState.power = false
        end

        Wait(1000)
    end
end)

-- ── Keybinds ──────────────────────────────────────────────────────────────
-- Registered through RegisterKeyMapping so every client can rebind them in
-- GTA's own settings. The commands are hidden from the chat suggestion list —
-- they are key handlers, not commands anyone should type.

---@param name string
---@param description string
---@param defaultKey string
---@param handler function
local function bind(name, description, defaultKey, handler)
    RegisterCommand(name, function()
        if not RadarState.visible then return end
        -- Key lock exists so the radar's keys stop fighting with everything
        -- else bound to the numpad. It deliberately does not block its own
        -- release key.
        if RadarState.keyLock and name ~= 'radar_keylock' then return end
        handler()
    end, false)

    RegisterKeyMapping(name, description, 'keyboard', defaultKey)
    TriggerEvent('chat:removeSuggestion', '/' .. name)
end

CreateThread(function()
    bind('radar_remote', 'Radar — open control panel', Config.Keys.Remote, function()
        if remoteOpen then CloseRemote() else OpenRemote() end
    end)

    bind('radar_keylock', 'Radar — key lock', Config.Keys.KeyLock, function()
        RadarState.keyLock = not RadarState.keyLock
        PlayRadarSound('Alert', 200)
        PushRadarToNui(true)
    end)

    --- One key per antenna, doing whichever thing the antenna currently needs.
    --- A locked antenna is waiting to be released and nothing else, so the key
    --- releases it; otherwise it toggles XMIT/HOLD. Two separate binds would
    --- mean an officer in a pursuit hunting for the right one.
    ---@param cam string
    local function antennaKey(cam)
        return function()
            if not RadarState.power then return end
            local a = RadarState.antennas[cam]

            if a.lock then
                ReleaseLock(cam)
                return
            end

            -- `hold` is the state to move *into*. Transmitting means the next
            -- press holds, so the current xmit flag is the argument — negating
            -- it here made the key a no-op that still played its beep.
            SetAntennaHold(cam, a.xmit)
        end
    end

    bind('radar_front_ant', 'Radar — front antenna hold / release lock', Config.Keys.FrontAnt, antennaKey('front'))
    bind('radar_rear_ant',  'Radar — rear antenna hold / release lock',  Config.Keys.RearAnt,  antennaKey('rear'))

    --- Copying happens in the interface, not here: there is no clipboard native,
    --- and CEF refuses navigator.clipboard inside a NUI. A hidden textarea plus
    --- execCommand is the route that works, and it is the same one ps-dispatch
    --- already uses for its own copy buttons.
    ---@param cam string
    local function copyKey(cam)
        return function()
            if not PlateState.power then return end

            local plate = PlateState.cameras[cam] and PlateState.cameras[cam].plate
            if not plate or plate == '' then return end

            SendNUIMessage({ action = 'copyPlate', data = { cam = cam, plate = plate } })
        end
    end

    bind('radar_copy_front', 'Radar — copy front plate', Config.Keys.CopyFront, copyKey('front'))
    bind('radar_copy_rear',  'Radar — copy rear plate',  Config.Keys.CopyRear,  copyKey('rear'))
end)

-- ── NUI callbacks ─────────────────────────────────────────────────────────

RegisterNUICallback('closeRemote', function(_, cb)
    CloseRemote()
    cb('ok')
end)

RegisterNUICallback('power', function(_, cb)
    ToggleRadarPower()
    cb('ok')
end)

RegisterNUICallback('antenna', function(data, cb)
    local a = RadarState.antennas[data.cam]
    if a then
        if data.mode then
            a.mode = data.mode
            persist()
            PushRadarToNui(true)
        else
            SetAntennaHold(data.cam, a.xmit)
        end
    end
    cb('ok')
end)

--- Put an antenna into HOLD, or take it back out.
---
--- HOLD freezes the plate as well as the speed. A held number that nobody can
--- attach to a vehicle is not much use, and the plate row underneath used to
--- carry on scanning whatever drove past next — so the display showed a speed
--- from one car above a plate from another.
---
--- The plate held is the strong target's: that is the vehicle the big number
--- refers to. If the fast window was the interesting one, lock it instead —
--- a lock knows exactly which vehicle it took.
---@param cam string 'front' | 'rear'
---@param hold boolean
function SetAntennaHold(cam, hold)
    local a = RadarState.antennas[cam]
    if not a then return end

    a.xmit = not hold

    if hold then
        -- A camera already pinned is holding a plate check hit, which is a more
        -- specific claim than "whatever the strong target was". Leave it.
        local c = PlateState.cameras[cam]
        local target = a.strong
        if not (c and c.pinned) and target and target.plate and target.plate ~= '' then
            PinCameraToPlate(cam, target.plate, target.index)
        end
    else
        UnpinCamera(cam)
    end

    PlayRadarSound('Blip', 150)
    PushRadarToNui(true)
end

--- Freeze an antenna because the camera beside it hit a flagged plate.
---
--- Separate from SetAntennaHold because the camera is already pinned to the
--- plate that caused the hit — going through the normal hold would repoint it
--- at the strong target instead, which is very likely a different car.
---
--- Releasing is the ordinary antenna key: resuming XMIT unpins the camera and
--- clears the alarm. That matters more than it sounds, because the camera lock
--- keys are gone, and for a while a hit could be raised with no way at all to
--- acknowledge it short of power cycling the radar.
---@param cam string 'front' | 'rear'
function HoldAntennaForHit(cam)
    local a = RadarState.antennas[cam]
    if not a or not a.xmit or a.lock then return end

    a.xmit = false
    PushRadarToNui(true)
end

--- Release an antenna and let it acquire again.
---@param cam string 'front' | 'rear'
function ReleaseLock(cam)
    local a = RadarState.antennas[cam]
    if not a or not a.lock then return end

    a.lock, a.frozen = nil, nil
    a.strong, a.fast = nil, nil
    UnpinCamera(cam)

    PlayRadarSound('Blip', 150)
    PushRadarToNui(true)
end

RegisterNUICallback('clearLock', function(data, cb)
    ReleaseLock(data.cam)
    cb('ok')
end)

RegisterNUICallback('plateLock', function(data, cb)
    TogglePlateLock(data.cam, data.state)
    cb('ok')
end)

RegisterNUICallback('addWatch', function(data, cb)
    AddWatchPlate(data.plate or '')
    persist()
    cb('ok')
end)

RegisterNUICallback('removeWatch', function(data, cb)
    RemoveWatchPlate(data.plate or '')
    persist()
    cb('ok')
end)

RegisterNUICallback('clearWatch', function(_, cb)
    ClearWatchPlates()
    persist()
    cb('ok')
end)

RegisterNUICallback('setting', function(data, cb)
    local s = RadarState.settings
    local key, value = data.key, data.value

    if key == 'unit' and (value == 'mph' or value == 'kmh') then
        RadarState.unit = value
        -- The fast limit is a speed, so it has to move with the unit or the
        -- operator silently ends up with a 130 mph trigger.
        s.fastLimit = Config.Radar.DefaultFastLimit[value]
    elseif key == 'range' then
        s.range = math.max(Config.Radar.MinRange, math.min(Config.Radar.MaxRange, tonumber(value) or s.range))
        -- Show the cone in the world for as long as the slider keeps moving.
        ShowRangePreview()
    elseif key == 'scale' then
        s.scale = math.max(Config.UI.MinScale, math.min(Config.UI.MaxScale, tonumber(value) or s.scale))
    elseif key == 'sound' then
        s.sound = value and true or false
    elseif key == 'fastLock' then
        s.fastLock = value and true or false
    elseif key == 'fastLimit' then
        s.fastLimit = math.max(1, tonumber(value) or s.fastLimit)
    elseif key == 'showPlate' then
        s.showPlate = value and true or false
    elseif key == 'marker' then
        s.marker = value and true or false
    end

    persist()
    PushSettingsToNui()
    PushRadarToNui(true)
    cb('ok')
end)

RegisterNUICallback('savePosition', function(data, cb)
    if data.panel == 'radar' or data.panel == 'plate' then
        RadarState.positions[data.panel] = { x = data.x, y = data.y }
        persist()
    end
    cb('ok')
end)

RegisterNUICallback('previewRange', function(_, cb)
    ShowRangePreview()
    cb('ok')
end)

RegisterNUICallback('resetLayout', function(_, cb)
    RadarState.positions.radar = Config.UI.RadarPos
    RadarState.positions.plate = Config.UI.PlatePos
    RadarState.settings.scale  = Config.UI.DefaultScale
    persist()
    PushSettingsToNui()
    cb('ok')
end)

-- ── Exports ───────────────────────────────────────────────────────────────
-- The surface other resources use. ps-mdt's BOLO list is the obvious consumer:
-- issue a BOLO there, push the plate here, and every unit's reader starts
-- watching for it.

--- Add a plate to this officer's watchlist from another resource.
---@param plate string
---@return boolean added true if it was added, false if already present, empty
---                      or the list is full
exports('AddWatchPlate', function(plate) return AddWatchPlate(plate) end)
exports('RemoveWatchPlate', function(plate) return RemoveWatchPlate(plate) end)
exports('ClearWatchPlates', function() ClearWatchPlates() end)

--- A copy of the watchlist. Copied rather than handed out directly, so a caller
--- cannot mutate the live list through the reference it was given.
---@return table
local function watchPlatesCopy()
    local copy = {}
    for i = 1, #PlateState.watch do copy[i] = PlateState.watch[i] end
    return copy
end

--- The plates this officer is currently watching for.
---@return table
exports('GetWatchPlates', watchPlatesCopy)

--- Lock a plate reader camera. Used by a CAD or the MDT to make a unit's reader
--- hold a plate it has been told to care about.
---@param cam string 'front' | 'rear'
---@param beep boolean|nil
exports('LockCamera', function(cam, beep)
    if cam ~= 'front' and cam ~= 'rear' then return false end
    TogglePlateLock(cam, true, not beep)
    return true
end)

--- Whatever the reader currently has in each window.
---@return table
exports('GetPlates', function()
    return {
        front = PlateState.cameras.front.plate,
        rear  = PlateState.cameras.rear.plate,
        watch = watchPlatesCopy(),
    }
end)

--- The last locked speed per antenna, for a citation form that would rather not
--- ask the officer to retype a number the radar already knows.
---@return table
exports('GetLockedSpeeds', function()
    local front = RadarState.antennas.front.lock
    local rear  = RadarState.antennas.rear.lock
    return {
        unit  = RadarState.unit,
        front = front and front.speed or nil,
        rear  = rear and rear.speed or nil,
    }
end)

RegisterNetEvent('lsn-radar:client:addWatch', function(plate)
    AddWatchPlate(plate)
    persist()
end)

RegisterNetEvent('lsn-radar:client:removeWatch', function(plate)
    RemoveWatchPlate(plate)
    persist()
end)

RegisterNetEvent('lsn-radar:client:lockCamera', function(cam, beep)
    if cam ~= 'front' and cam ~= 'rear' then return end
    TogglePlateLock(cam, true, not beep)
end)

RegisterNetEvent('lsn-radar:client:openRemote', function()
    OpenRemote()
end)

-- ── Boot ──────────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(500)
    PushSettingsToNui()
    PushRadarToNui(true)
    PushPlatesToNui()
end)
