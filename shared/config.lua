-- ═══════════════════════════════════════════════════════════════════════════
--  lsn-radar — configuration
-- ═══════════════════════════════════════════════════════════════════════════
-- Everything an operator can change lives in the operator menu and is stored
-- per client (KVP). Everything a server owner decides lives here.
--
-- The split matters: values in this file are the ceiling, the operator menu
-- moves within it. An officer can dial the range down to 80m, but never above
-- Config.Radar.MaxRange.

Config = Config or {}

-- ── Access ────────────────────────────────────────────────────────────────
-- Who gets the radar at all. Unlike the resource this is modelled on, this one
-- is not standalone: it sits in the same QBCore server as ps-mdt and
-- ps-dispatch, and equipment that every civilian can switch on is not
-- equipment. Job *types* are used rather than job names so that custom
-- departments inherit access without being listed.
Config.Jobs = { 'leo' }

-- Vehicle classes that may carry a radar. 18 is VC_EMERGENCY. Add classes here
-- if unmarked units in this server use civilian-class vehicles.
Config.VehicleClasses = { 18 }

-- Require the player to be on duty. Off-duty officers in a patrol car are a
-- normal sight; a running radar on one is not.
Config.RequireDuty = true

-- ── Units ─────────────────────────────────────────────────────────────────
-- 'mph' or 'kmh'. The operator can switch this; this is what they start with.
Config.DefaultUnit = 'kmh'

-- ── Radar ─────────────────────────────────────────────────────────────────
Config.Radar = {
    -- Hard ceiling for the operator menu's range setting, in metres. The
    -- detection is a cone test plus a line-of-sight check rather than a sphere
    -- lookup, so long ranges stay believable — but they also cost a raycast
    -- per candidate vehicle, so this is a performance dial too.
    MaxRange     = 150.0,
    DefaultRange = 100.0,
    MinRange     = 50.0,

    -- Half-angle of each antenna's cone, in degrees. A real X-band antenna is
    -- narrow; 12° keeps the radar from reading the car in the next lane over
    -- while still being forgiving on curves.
    ConeAngle = 12.0,

    -- How often the antennas sample, in ms. Wraith settled on 10Hz after
    -- starting at 20Hz, and the display genuinely does not benefit from more:
    -- the number would flicker faster than it can be read.
    Tick = 100,

    -- Vehicle classes the radar refuses to read. Boats, helicopters, planes and
    -- trains would otherwise produce speeds that make no sense on a road.
    IgnoreClasses = { 14, 15, 16, 21 },

    -- Speed below which a target is treated as noise and not displayed at all.
    -- Stationary traffic would otherwise keep the windows full of zeroes.
    MinSpeed = { mph = 5, kmh = 8 },

    -- Fast-lock: automatically lock a target that exceeds the operator's set
    -- limit. Off by default because a radar that locks by itself is a radar
    -- nobody has to aim.
    AllowFastLock  = true,
    DefaultFastLock = false,
    DefaultFastLimit = { mph = 80, kmh = 130 },

    -- Only auto-lock when the speeding vehicle is driven by a real player. NPC
    -- traffic speeds are a simulation artefact and locking them is noise.
    FastLockPlayersOnly = false,

    -- Seconds a locked speed stays on the display before the window releases
    -- it. 0 keeps it until the operator clears it manually.
    LockHold = 0,

    -- How long a reading survives a tick in which nothing was resolved, in ms.
    --
    -- Acquisition legitimately drops out for a moment: a lorry passes between
    -- the antenna and the target, the car clips the edge of the cone on a bend,
    -- a raycast lands on a lamp post. Without a grace window every one of those
    -- blanks the display and the target bracket for a frame or two, which reads
    -- as the radar losing the car it is plainly still pointed at.
    --
    -- Long enough to bridge a blink, short enough that a car which has actually
    -- gone does not linger. 0 disables it and restores the old behaviour.
    ReadingHold = 600,

    -- ── Target bracket ───────────────────────────────────────────────────
    -- A viewfinder bracket around the vehicle being read, so "which one of
    -- those is it?" stops being a guess.
    --
    -- Drawn in screen space with DrawRect rather than with SetEntityDrawOutline:
    -- that native depends on a post-processing pass that is missing on a good
    -- number of FiveM builds, where it fails silently. This has no engine
    -- feature behind it and cannot stop working.
    --
    -- Sizes are fractions of the screen. Horizontal values are divided by the
    -- aspect ratio at draw time so the bracket stays square.
    TargetMarker = {
        Enabled    = true,
        Colour     = { 255, 255, 255, 165 },  -- ordinary reading
        LockColour = { 248, 113, 113, 210 },  -- while an antenna is tracking
        Thickness  = 0.0016,
        -- Clamps on the bracket's half-height. Without the lower bound a car at
        -- 300m becomes a dot; without the upper one, pulling alongside fills
        -- the screen with corner marks.
        MinSize    = 0.014,
        MaxSize    = 0.085,
    },

    -- ── Range preview ────────────────────────────────────────────────────
    -- A number in metres means nothing until you have seen it on a road. While
    -- the operator drags the range slider, the antenna cone is drawn in the
    -- world ahead of and behind the patrol car so the setting can be judged
    -- against actual traffic rather than guessed at.
    Preview = {
        Enabled = true,
        -- How long the drawing stays up after the last slider movement.
        LingerMs = 2500,
        -- Segments per cone edge. Cheap now that the geometry is cached and
        -- only the drawing happens per frame, so this buys smoothness rather
        -- than costing frames.
        -- Segments per cone edge. The cone is a long thin triangle in plan
        -- view, so this only has to be fine enough to follow the ground — 12
        -- is smooth, and each segment costs four DrawPoly calls.
        Steps = 12,
    },
}

-- ── Plate reader ──────────────────────────────────────────────────────────
Config.PlateReader = {
    Enabled = true,

    -- Range of the plate cameras, in metres. Deliberately much shorter than
    -- the radar: a camera has to actually resolve characters.
    Range = 50.0,

    -- Half-angle of the camera cone, in degrees. Wider than the radar antenna
    -- because a plate reader is aimed at a lane, not at a vehicle.
    ConeAngle = 22.0,

    Tick = 250,

    -- A plate has to stay in view this long before it is considered read. Stops
    -- the display from strobing through every car in oncoming traffic.
    DwellTime = 350,

    -- BOLO: the operator can arm one plate. When the reader sees it, the window
    -- locks by itself and alarms.
    AllowBolo = true,

    -- ── MDT integration ──────────────────────────────────────────────────
    -- ps-mdt's plate check was written for exactly this: its own comments call
    -- out "a continuous scanner passes hundreds of plates a minute". It caches,
    -- coalesces concurrent lookups of the same plate, enforces a per-officer
    -- alert cooldown and a per-minute budget, and audits the hits rather than
    -- every scan. So the radar hands the plate over and lets the MDT decide
    -- what is worth saying — none of that logic is duplicated here.
    --
    -- Mode:
    --   'alert'  PlateCheckAlert — looks the plate up AND sends the officer a
    --            targeted ps-dispatch card. Hits also come back to the reader.
    --   'lookup' CheckPlate — looks the plate up silently. Hits show in the
    --            reader only, no dispatch card. For servers that find the
    --            card redundant next to the reader itself.
    --   'off'    No MDT contact at all.
    Mdt = {
        Mode     = 'alert',
        Resource = 'ps-mdt',

        -- Client-side throttle. The MDT caches server side, but every scan
        -- still costs one network event, and that is the actual bottleneck in
        -- a car full of traffic. Keep this at or above ps-mdt's
        -- Config.PlateCheck.alertCooldown (120s by default) — sending more
        -- often just gets the answer suppressed at the other end.
        ResendSeconds = 120,
    },
}

-- ── Interface ─────────────────────────────────────────────────────────────
Config.UI = {
    -- Starting positions as a fraction of the screen, {x, y} of the top-left
    -- corner. Both panels can be dragged and the position is remembered per
    -- client, so this only ever affects a first-time operator.
    RadarPos = { x = 0.015, y = 0.30 },
    PlatePos = { x = 0.015, y = 0.62 },

    DefaultScale = 1.0,
    MinScale     = 0.7,
    MaxScale     = 1.4,

    -- Show the radar automatically when the officer gets into a patrol car.
    AutoShow = true,
}

-- ── Audio ─────────────────────────────────────────────────────────────────
Config.Audio = {
    -- Whether operators may have sound at all.
    Enabled = true,
    -- What a first-time operator starts with. There is no volume control:
    -- PlaySoundFrontend takes no gain parameter, so a slider would have been a
    -- mute switch wearing a percentage. It is a mute switch, and says so.
    DefaultOn = true,

    -- Native GTA sounds, same approach ps-dispatch uses for its alert tones —
    -- no custom audio files to ship, and they already sit in the player's
    -- master volume.
    Lock  = { name = 'Beep_Red',  set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
    Bolo  = { name = 'Beep_Green', set = 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
    Alert = { name = 'Menu_Accept', set = 'Phone_SoundSet_Default' },
    Blip  = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

-- ── Integration ───────────────────────────────────────────────────────────
Config.Integration = {
    -- Fire a ps-dispatch alert when an automatic lock lands above this multiple
    -- of the operator's fast limit. Off by default, and deliberately so: a
    -- radar lock is evidence, not a call for backup, and a dispatch board full
    -- of speeding tickets is a board nobody reads.
    --
    -- CustomAlert is a *client* export on ps-dispatch taking a single table, so
    -- this fires from the officer's own client rather than through the server.
    SpeedAlert = {
        Enabled   = false,
        Resource  = 'ps-dispatch',
        Export    = 'CustomAlert',
        -- Multiple of the operator's fast limit. 1.5 with a 130 km/h limit
        -- means only locks at 195+ reach dispatch.
        Threshold = 1.5,
        Code      = '10-11',
        Icon      = 'fas fa-gauge-high',
        Priority  = 2,
    },
}

-- ── Keybinds ──────────────────────────────────────────────────────────────
-- Defaults only. Every client can rebind these in GTA's own key bindings menu
-- under "FiveM", which is the only reliable way to avoid collisions with the
-- rest of a server's scripts.
--
-- Two deliberate choices here:
--
--   * The control panel is NUMPAD7 rather than the F5 the resource this is
--     modelled on uses. ps-mdt's config documents F5/F6/F7 as example binds for
--     mdtstatus, and a default that collides with a sibling resource's own
--     documentation is a support ticket waiting to happen.
--
--   * Everything else stays on the numpad so the whole radar is one hand on
--     one cluster. It also keeps these keys well away from the vehicle
--     movement keys — binding those through RegisterKeyMapping is a known way
--     to crash the game while driving.
Config.Keys = {
    Remote      = 'NUMPAD7',  -- open the control panel
    KeyLock     = 'L',        -- freeze all radar keys
    FrontAnt    = 'NUMPAD8',  -- front antenna XMIT/HOLD
    RearAnt     = 'NUMPAD5',  -- rear antenna XMIT/HOLD
    -- The camera locks are gone. HOLD already freezes the plate alongside the
    -- speed, and an antenna lock pins the plate on its own — a second way to
    -- hold the same thing was two keys for one job. The slots now do something
    -- the radar could not do at all: get a plate out of the game and into a
    -- report without retyping eight characters from a screenshot.
    CopyFront   = 'NUMPAD9',  -- copy the front plate to the clipboard
    CopyRear    = 'NUMPAD6',  -- copy the rear plate to the clipboard
}