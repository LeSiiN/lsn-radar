-- ═══════════════════════════════════════════════════════════════════════════
--  Shared client helpers
-- ═══════════════════════════════════════════════════════════════════════════

local QBCore = exports['qb-core']:GetCoreObject()

PlayerData = QBCore.Functions.GetPlayerData() or {}

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
    if PlayerData.job then PlayerData.job.onduty = duty end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

-- ── Conversion ────────────────────────────────────────────────────────────

local MS_TO_MPH = 2.236936
local MS_TO_KMH = 3.6

--- Entity speed (m/s) in the operator's chosen unit, rounded to a whole number
--- the way a real display reports it.
---@param speed number metres per second
---@param unit string 'mph' | 'kmh'
---@return number
function ConvertSpeed(speed, unit)
    return math.floor(speed * (unit == 'mph' and MS_TO_MPH or MS_TO_KMH) + 0.5)
end

-- ── Vector helpers ────────────────────────────────────────────────────────
-- Written out rather than using vector3 arithmetic because the dot products
-- below run once per candidate vehicle per tick, and the plain-number form
-- avoids allocating a vector per operation.

---@return number x, number y, number z, number length
function NormalizeXYZ(x, y, z)
    local len = math.sqrt(x * x + y * y + z * z)
    if len == 0 then return 0.0, 0.0, 0.0, 0.0 end
    return x / len, y / len, z / len, len
end

---@return number
function Dot(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

-- ── Access checks ─────────────────────────────────────────────────────────

--- Does this player's job get radar equipment at all?
---@return boolean
function HasRadarAccess()
    local job = PlayerData and PlayerData.job
    if not job then return false end

    if Config.RequireDuty and not job.onduty then return false end

    local allowed = Config.Jobs
    if type(allowed) ~= 'table' or #allowed == 0 then return true end
    for i = 1, #allowed do
        if allowed[i] == job.type or allowed[i] == job.name then return true end
    end
    return false
end

--- The vehicle the player is currently operating a radar from, or nil.
--- Front passengers count: in a two-officer unit the passenger is the one with
--- their hands free, and a radar only the driver can touch is a radar nobody
--- uses while actually driving.
---@return number|nil vehicle
---@return boolean isDriver
function GetPatrolVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil, false end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil, false end

    local class = GetVehicleClass(veh)
    local ok = false
    for i = 1, #Config.VehicleClasses do
        if Config.VehicleClasses[i] == class then ok = true break end
    end
    if not ok then return nil, false end

    local driver = GetPedInVehicleSeat(veh, -1) == ped
    local passenger = GetPedInVehicleSeat(veh, 0) == ped
    if not driver and not passenger then return nil, false end

    return veh, driver
end

--- Is this vehicle class something a road radar should read?
---@param veh number
---@return boolean
function IsReadableVehicle(veh)
    local class = GetVehicleClass(veh)
    for i = 1, #Config.Radar.IgnoreClasses do
        if Config.Radar.IgnoreClasses[i] == class then return false end
    end
    return true
end

--- Rough physical size of a model, used to decide which of two targets in the
--- same cone reflects the stronger signal. A box volume is crude, but it ranks
--- a lorry above a hatchback reliably, which is all the display needs.
---@param veh number
---@return number
local sizeCache = {}
function GetVehicleSize(veh)
    local model = GetEntityModel(veh)
    local cached = sizeCache[model]
    if cached then return cached end

    local min, max = GetModelDimensions(model)
    local volume = (max.x - min.x) * (max.y - min.y) * (max.z - min.z)
    sizeCache[model] = volume
    return volume
end

--- Plate text with GTA's own padding stripped. The natives hand back an
--- 8-character field; every consumer here wants the characters.
---@param veh number
---@return string
function GetCleanPlate(veh)
    local plate = GetVehicleNumberPlateText(veh) or ''
    return (plate:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- ── Audio ─────────────────────────────────────────────────────────────────

local lastSoundAt = {}

--- Play one of the configured frontend sounds, rate limited per kind so a
--- repeating condition (a BOLO plate sitting in front of the car) alarms once
--- rather than continuously.
---@param kind string key in Config.Audio
---@param minGap number|nil ms between repeats, default 400
function PlayRadarSound(kind, minGap)
    if not Config.Audio.Enabled then return end
    if RadarState and RadarState.settings and not RadarState.settings.sound then return end

    local sound = Config.Audio[kind]
    if not sound then return end

    local now = GetGameTimer()
    if now - (lastSoundAt[kind] or 0) < (minGap or 400) then return end
    lastSoundAt[kind] = now

    PlaySoundFrontend(-1, sound.name, sound.set, true)
end

-- ── Persistence ───────────────────────────────────────────────────────────
-- KVP rather than a server-side store: these are interface preferences, they
-- belong to the machine the officer is sitting at, and syncing them would mean
-- a database round trip every time someone nudges a panel two pixels.

local KVP_KEY = 'lsn-radar:prefs'

---@return table
function LoadPrefs()
    local raw = GetResourceKvpString(KVP_KEY)
    if not raw then return {} end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return decoded
end

---@param prefs table
function SavePrefs(prefs)
    SetResourceKvp(KVP_KEY, json.encode(prefs))
end

function ResetPrefs()
    DeleteResourceKvp(KVP_KEY)
end
