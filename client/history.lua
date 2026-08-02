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

--- In-game clock, which is the time that belongs on a report — a server's clock
--- runs at its own rate and an officer writing up an incident dates it by what
--- the world said, not by their operating system.
---@return string
local function gameClock()
    return ('%02d:%02d'):format(GetClockHours(), GetClockMinutes())
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
            plate = e.plate, index = e.index, dir = e.dir,
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
        dir    = lock.dir,
        source = source,
        auto   = lock.auto and true or false,
        clock  = gameClock(),
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
            dir = e.dir, source = e.source, auto = e.auto, clock = e.clock,
            epoch = e.epoch,
        }
    end
    return copy
end)