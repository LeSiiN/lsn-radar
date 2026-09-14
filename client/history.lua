-- ═══════════════════════════════════════════════════════════════════════════
--  Lock history
-- ═══════════════════════════════════════════════════════════════════════════
-- Every lock is recorded, so a reading taken twenty minutes ago is still there
-- when the officer sits down to write it up.
--
-- Before this, each lock overwrote the last: an officer who stopped three cars
-- in a row had the numbers for one of them, and the gap between "measured" and
-- "in the report" was closed by retyping from a screenshot.
--
-- Two details do most of the work here:
--
--   The entry is written when the lock is taken, not when it is released.
--   Waiting for the release would lose every lock an officer never got round
--   to clearing — which, in a pursuit that ends with an arrest, is most of
--   them.
--
--   The peak keeps updating after the entry is written. A tracking lock climbs
--   with the driver, so the number that matters is not the one at the moment
--   of the lock; the entry holds a reference to the live lock until it ends.

local function cfg()
    return (Config.Radar and Config.Radar.LockHistory) or {}
end

--- Newest first.
LockHistory = {}

--- Locks still running, keyed by the entry they are writing into. A tracking
--- lock's peak is not final until the lock ends, so the entry has to keep
--- listening rather than being stamped once and forgotten.
local liveEntries = {}

local nextId = 1

-- ── Time ──────────────────────────────────────────────────────────────────

--- Wall clock, as HH:MM.
---
--- Real time rather than the in-game clock. The world clock runs at its own
--- rate — often several times faster — so two readings taken a minute apart can
--- be stamped an hour apart, and a list ordered by newest first ends up with
--- times that jump backwards when the in-game day rolls over. Neither is
--- something an officer can reason about.
---
--- GetLocalTime is the client's own clock, which is also the one they are
--- looking at if they glance at their taskbar.
---@return string
local function wallClock()
    local _, _, _, hour, minute = GetLocalTime()
    return ('%02d:%02d'):format(hour, minute)
end

--- Unix time, for ageing entries out.
---
--- GetCloudTimeAsInt rather than os.time: the os library is not available on
--- the client in FiveM. This native is, it returns the same kind of number, and
--- it comes from the platform rather than the player's machine — so an entry
--- cannot be kept alive past its age limit by putting the system clock back.
---@return number
local function epochNow()
    return GetCloudTimeAsInt()
end

-- ── Persistence ───────────────────────────────────────────────────────────

--- Trim to size and drop anything too old to still be a note.
local function prune()
    local max = cfg().Size or 12
    for i = #LockHistory, max + 1, -1 do
        LockHistory[i] = nil
    end

    local maxAge = (cfg().MaxAgeHours or 12) * 3600
    if maxAge <= 0 then return end

    -- Wall clock rather than the in-game one for ageing: a reading is stale
    -- because hours of real time passed, not because the in-game sun moved.
    local now = epochNow()
    for i = #LockHistory, 1, -1 do
        local at = LockHistory[i].epoch
        if at and (now - at) > maxAge then
            table.remove(LockHistory, i)
        end
    end
end

local function persist()
    if not cfg().Persist then return end

    local plain = {}
    for i = 1, #LockHistory do
        local e = LockHistory[i]
        plain[i] = {
            id = e.id, speed = e.speed, peak = e.peak, unit = e.unit,
            plate = e.plate, index = e.index, model = e.model, dir = e.dir,
            source = e.source, auto = e.auto, clock = e.clock, epoch = e.epoch,
        }
    end

    SetResourceKvp('lsn-radar:history', json.encode(plain))
end

function LoadLockHistory()
    if not cfg().Persist then return end

    local raw = GetResourceKvpString('lsn-radar:history')
    if not raw then return end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return end

    for i = 1, #decoded do
        local e = decoded[i]
        if type(e) == 'table' and e.speed then
            LockHistory[#LockHistory + 1] = e
            -- Ids have to stay unique against what was just loaded, or the
            -- interface keys two different entries the same and Svelte reuses
            -- one row for both.
            if type(e.id) == 'number' and e.id >= nextId then nextId = e.id + 1 end
        end
    end

    prune()
end

-- ── Recording ─────────────────────────────────────────────────────────────

function PushHistoryToNui()
    SendNUIMessage({
        action = 'history',
        data = { enabled = cfg().Enabled ~= false, entries = LockHistory },
    })
end

--- Record a lock as it is taken.
---
--- Returns the entry so the caller can keep updating its peak. A lock that goes
--- on climbing for another forty seconds would otherwise be filed at whatever
--- it happened to read in the first tenth of a second.
---@param lock table the live lock table
---@param source string 'front' | 'rear' | 'gun'
---@return table|nil entry
function RecordLock(lock, source)
    if cfg().Enabled == false then return nil end

    local entry = {
        id     = nextId,
        speed  = lock.speed,
        peak   = lock.peak or lock.speed,
        unit   = RadarState.unit,
        plate  = lock.plate,
        index  = lock.index,
        model  = lock.model,
        dir    = lock.dir,
        source = source,
        auto   = lock.auto and true or false,
        clock  = wallClock(),
        epoch  = epochNow(),
    }
    nextId = nextId + 1

    table.insert(LockHistory, 1, entry)
    prune()

    liveEntries[entry] = lock
    persist()
    PushHistoryToNui()

    return entry
end

--- Bring live entries up to date with the locks still feeding them.
---
--- Called from the antenna tick rather than on every peak change: the peak
--- moves constantly during a pursuit and the history panel is not being read
--- while it does.
function RefreshLiveHistory()
    local changed = false

    for entry, lock in pairs(liveEntries) do
        if lock.peak and lock.peak ~= entry.peak then
            entry.peak = lock.peak
            entry.speed = lock.speed or entry.speed
            changed = true
        end
        -- A plate can arrive after the lock: the vehicle may not have been
        -- resolved at the instant the trigger was pulled.
        if lock.plate and lock.plate ~= '' and entry.plate ~= lock.plate then
            entry.plate, entry.index = lock.plate, lock.index
            changed = true
        end
    end

    if changed then
        persist()
        PushHistoryToNui()
    end
end

--- Stop tracking a lock that has ended. The entry stays; only the live link
--- goes, so the peak is frozen at whatever the vehicle actually reached.
---@param lock table
function CloseHistoryEntry(lock)
    for entry, l in pairs(liveEntries) do
        if l == lock then
            liveEntries[entry] = nil
            persist()
            PushHistoryToNui()
            return
        end
    end
end

---@param id number
function RemoveHistoryEntry(id)
    for i = #LockHistory, 1, -1 do
        if LockHistory[i].id == id then
            liveEntries[LockHistory[i]] = nil
            table.remove(LockHistory, i)
            persist()
            PushHistoryToNui()
            return
        end
    end
end

function ClearLockHistory()
    for i = #LockHistory, 1, -1 do LockHistory[i] = nil end
    for entry in pairs(liveEntries) do liveEntries[entry] = nil end
    persist()
    PushHistoryToNui()
end

-- ── Exports ───────────────────────────────────────────────────────────────

--- The readings this officer has taken, newest first. For a citation form that
--- would rather offer a list than ask someone to remember a number.
---@return table
exports('GetLockHistory', function()
    local copy = {}
    for i = 1, #LockHistory do
        local e = LockHistory[i]
        copy[i] = {
            speed = e.speed, peak = e.peak, unit = e.unit, plate = e.plate,
            model = e.model, dir = e.dir, source = e.source, auto = e.auto, clock = e.clock,
            epoch = e.epoch,
        }
    end
    return copy
end)

--- Shape a history entry into what a caller gets back.
---
--- `unit` comes from the entry, not from `RadarState.unit`. Switching the
--- display between mph and km/h does not convert readings already taken — the
--- entry keeps the unit it was measured in — so reporting the current setting
--- would relabel an old number without changing it, which is the one failure
--- mode a citation cannot survive.
---@param e table
---@param live boolean
---@return table
local function shapeEntry(e, live)
    return {
        speed  = e.speed,
        peak   = e.peak or e.speed,
        unit   = e.unit,
        plate  = e.plate,
        index  = e.index,
        model  = e.model,
        dir    = e.dir,
        source = e.source,
        auto   = e.auto and true or false,
        clock  = e.clock,
        epoch  = e.epoch,
        age    = e.epoch and (epochNow() - e.epoch) or nil,
        live   = live and true or false,
    }
end

--- The newest lock still held on a device, for when the history is switched off.
---
--- Only ever the current lock per device: without the history there is nothing
--- holding a reading once the officer releases it. That is the cost of turning
--- the history off, and it is why this is a fallback rather than the path.
---@param source string|nil
---@return table|nil
local function lastLiveLock(source)
    local best, bestSource

    local function consider(lock, name)
        if not lock or not lock.speed then return end
        if source and source ~= name then return end
        -- `at` is GetGameTimer, so this only orders locks from one session —
        -- which is all three of these can ever be.
        if not best or (lock.at or 0) > (best.at or 0) then
            best, bestSource = lock, name
        end
    end

    local antennas = RadarState and RadarState.antennas
    if antennas then
        consider(antennas.front and antennas.front.lock, 'front')
        consider(antennas.rear and antennas.rear.lock, 'rear')
    end
    consider(HandheldState and HandheldState.lock, 'gun')

    if not best then return nil end

    return {
        speed  = best.speed,
        peak   = best.peak or best.speed,
        unit   = RadarState.unit,
        plate  = best.plate,
        index  = best.index,
        model  = best.model,
        dir    = best.dir,
        source = bestSource,
        auto   = best.auto and true or false,
        -- No clock, epoch or age: those are stamped when an entry is written,
        -- and nothing was written.
        live   = true,
    }
end

--- The last speed this officer locked.
---
--- `GetLockHistory` already returns this as its first element, but reaching
--- into index 1 requires the caller to know the list is ordered newest first.
--- That is a rule which holds right up until someone sorts the copy they were
--- given, and then a citation quietly carries the wrong number.
---
--- Narrow it to one device when the form knows which one it is asking about: a
--- handheld citation should not offer the number the patrol antenna caught
--- while the car was parked two streets away.
---
--- `peak` is the number to put on the ticket, not `speed`. `speed` is what the
--- vehicle read at the instant of the lock; `peak` is the highest it reached
--- while the lock held. On a tracking lock those are different, and the second
--- is the one that was measured.
---
--- Returns nil when nothing has been locked, rather than a zero — a form has to
--- be able to tell "no reading" from "stationary".
---
---@param source string|nil 'front' | 'rear' | 'gun'; omit for whichever is newest
---@return table|nil reading
exports('GetLastSpeed', function(source)
    if source ~= nil and source ~= 'front' and source ~= 'rear' and source ~= 'gun' then
        return nil
    end

    for i = 1, #LockHistory do
        local e = LockHistory[i]
        if not source or e.source == source then
            -- `live` means the lock is still held, so `peak` may still climb.
            -- A form that stores this number and closes is storing an interim
            -- reading; one that stays open should ask again on submit.
            return shapeEntry(e, liveEntries[e] ~= nil)
        end
    end

    -- Nothing in the history. Either nothing has been locked this session, or
    -- Config.Radar.LockHistory.Enabled is false — and an export that returns
    -- nothing because of a config flag nobody remembers setting is a worse
    -- outcome than three table lookups.
    return lastLiveLock(source)
end)