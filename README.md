# LSN Radar

Police radar and plate reader for FiveM, built to sit alongside `ps-mdt` and
`ps-dispatch` and to look like it belongs to them. Same panel anatomy, same
palette, same 9–14px type scale — the radar reads as another MDT surface that
happens to display numbers rather than as a piece of borrowed hardware.

Heavily inspired by [Wraith ARS 2X](https://github.com/WolfKnight98/wk_wars2x)
in behaviour: strong/fast target splitting, XMIT/HOLD antennas, plate cameras
with BOLO locking. The implementation, interface and integration surface are
new.

# Preview

<img src="https://r2.fivemanage.com/image/aQTxYJ0wm59X.png" width="450">
<img src="https://r2.fivemanage.com/image/zcVFPK2V2Cam.png" width="450">
<img src="https://r2.fivemanage.com/image/sRQ2RMgJ4aA1.png" width="450">
<img src="https://r2.fivemanage.com/image/mnjvn9BdRihb.png" width="450">
<img src="https://r2.fivemanage.com/image/VshJLRo5Apit.png" width="450">
<img src="https://r2.fivemanage.com/image/fIToS6JSlg4N.png" width="450">
<img src="https://r2.fivemanage.com/image/zvN6IyvfW1P2.jpg" width="450">
<img src="https://r2.fivemanage.com/image/AAJxUmo9gyE6.png" width="450">
<img src="https://r2.fivemanage.com/image/S067FudHnAxy.png" width="450">

# Dependency

- [qb-core](https://github.com/qbcore-framework/qb-core)
  or
- [qbx_core](https://github.com/Qbox-project/qbx_core)

Optional, and worth having:

- [ps-mdt](https://github.com/Project-Sloth/ps-mdt) — plate checks against MDT
  records (BOLO, stolen, owner warrants, impound history)
- [ps-dispatch](https://github.com/Project-Sloth/ps-dispatch) — plate hits and
  speed locks raised as alert cards

`ox_lib` and `PolyZone` are **not** required.

# Installation

1. Download the release archive and drop the `lsn-radar` folder into your
   resources directory.
2. Add `ensure lsn-radar` to your server configuration, after `qb-core`.
3. Adjust `shared/config.lua` — at minimum check `Config.Jobs` and
   `Config.VehicleClasses` match your server.

The interface ships prebuilt in `html/`. You only need Node if you intend to
change the UI (see [Building the UI](#building-the-ui)).

# Performance

Detection is a **single sweep** shared by the antennas and the cameras. It was
originally two — the radar walked the vehicle pool at 10Hz and the plate reader
walked it again at 4Hz, each doing its own coordinate read and class check on
every vehicle in the world before rejecting most of them. On a busy street that
is roughly 6,000 native calls a second spent deciding that a car three blocks
away is not interesting.

What changed:

| | Before | After |
| --- | --- | --- |
| Pool walks per second | 14 | 10 |
| Natives per rejected vehicle | 3 | 2 |
| `GetGamePool` allocations per second | 14 | 2 |
| Line-of-sight rays per tick | one per vehicle in cone | one per antenna |
| Plate text + driver lookup | every candidate, every tick | winners only |

The specific changes:

- **One walk instead of two.** The cameras use a wider, shorter cone than the
  antennas but look at the same vehicles, so the geometry is computed once.
- **Distance is tested first**, before the class check. Most of the world fails
  there, and failing there is now the cheapest failure available.
- **The pool list is cached for 500ms.** `GetGamePool` allocates a fresh table
  per call, and cars do not enter the world at 10Hz. Stale handles are caught by
  the existence check.
- **Class results are cached per entity** and dropped with the pool, so a
  recycled handle cannot inherit an answer.
- **Nothing expensive runs for a vehicle that will not win.** Plate text, driver
  lookups and raycasts happen after the strong/fast resolution, for the one or
  two vehicles that actually reach a window.
- **Both antennas locked and cameras off means the pool is never walked at
  all** — two entity reads replace the sweep entirely.

The range preview had the same class of problem and got the same treatment. It
called `GetGroundZFor_3dCoord` for every marker on every frame — 56 ground
raycasts a frame, over three thousand a second, to place points that mostly were
not moving. Ground lookups are the expensive part of anything that follows
terrain, so the cone geometry is now cached and rebuilt only when the range
changes, the car moves more than two metres or it turns more than about three
degrees, rate limited to five rebuilds a second regardless. Parked with the
control panel open — which is when the slider is actually used — that is zero
ground lookups a second after the first build. Drawing works off the cached points, so
what is drawn is a presentation question rather than a performance one: the cone
is a translucent filled surface (`DrawPoly`) with doubled edge lines and the
range written at the tip. Bare lines were tried first and were nearly
invisible — `DrawLine` is one pixel wide at any distance, so the far end of a
250m cone is a hair.

Per frame while the preview is up: ~88 `DrawPoly`, ~96 `DrawLine`, 2 `DrawText`,
and **no ground lookups at all**. It is on screen for a couple of seconds at a
time.

If it is still heavier than you want, the dials in order of effect are
`Config.Radar.MaxRange` (each metre widens the distance gate), `Config.Radar.Tick`
(going from 100 to 150ms costs nothing in readability) and
`Config.Radar.ConeAngle`.

# How it works

## Antennas

Two antennas, front and rear. Each reports two numbers rather than one, which
is the part that makes the display readable:

| Window | What it shows |
| --- | --- |
| **STRONG** | The largest vehicle in the cone — the biggest reflector, and usually the one you are looking at |
| **FAST** | A smaller vehicle travelling faster than the strong target |
| **LOCK** | A tracked vehicle — see below |

The FAST window is the reason this split exists. The car that overtakes the
lorry you were watching is invisible on a single-number display, and it is
invariably the one you wanted.

Detection is a cone test plus a line-of-sight raycast, not a sphere lookup. A
sphere reads the car beside you as readily as the one 300m up the road, and a
radar that cannot be aimed is not a radar. Cross traffic is discarded outright:
a Doppler antenna only measures motion along its own axis, so a vehicle
crossing your path has no speed the radar could honestly report.

**XMIT / HOLD** freezes an antenna on its current reading so it can be read out
while traffic moves on — **and freezes the plate with it**. A held number nobody
can attach to a vehicle is not much use, and the plate row underneath used to
carry on scanning, so the display could show a speed from one car above a plate
from another.

The plate held is the strong target's, since that is the vehicle the big number
refers to. If the fast window was the interesting one, lock it instead: a lock
knows exactly which vehicle it took.

Each antenna also has a direction filter — **Approaching**, **Departing** or
**Both** — which decides which targets it will report. The display shows it as a
single glyph (`▲` `▼` `⇅`); the words and an explanation live in the control
panel, where there is room for them.

## Locking

A lock is a **tracked target**, not a frozen number.

When an antenna locks — automatically or by hand — it commits to that one
vehicle and stops acquiring anything else until the officer releases it. The
STRONG and FAST windows keep the snapshot from the moment of the lock, as the
context the lock happened in. The LOCK window stays live: if the driver
accelerates away during a pursuit, the number climbs with them.

The tracked vehicle's plate appears next to the antenna name, because with two
cars in one cone there is otherwise no way to say afterwards which one the
number belonged to.

Once the live and peak readings differ, the LOCK label switches to showing the
peak. In a pursuit the driver brakes for corners, and the highest speed they
actually reached is the fact worth keeping.

Tracking is by **entity, not by plate**: NPC traffic in GTA reuses plates
freely, so following a plate would eventually hop to a different car wearing the
same characters. It is also deliberately not cone-limited — a locked vehicle in
a pursuit swerves and takes corners, and re-applying a 12° acquisition cone
would drop the reading exactly when it matters. Range still applies; past it the
antenna marks the reading stale (`⚠` beside the antenna name) and holds the last
value rather than pretending it is current.

**Release** with the same antenna key that toggles XMIT/HOLD — a locked antenna
is waiting to be released and nothing else, so the key does that instead. There
is also a Release button in the control panel.

With both antennas locked the vehicle pool is never walked at all: two entity
reads replace a scan of every car in the area, which is worth having during a
pursuit when the map around you is busiest.

## Automatic lock

Off by default. When enabled, an antenna locks anything above the operator's
set limit by itself.

`Config.Radar.FastLockPlayersOnly` defaults to `true` and should stay there:
NPC traffic regularly produces speeds that are a simulation artefact, and
locking them fills the window with numbers nobody can be stopped for.

## Plate reader

The plate rows live **inside** the radar panel, one under each antenna. They
used to be a second box, which meant an officer comparing a speed to a plate had
to trust that the top row of one lined up with the top row of the other. Front
is front.

When an antenna locks a vehicle, the camera on that side is **pinned** to that
vehicle's plate and marked with a pin icon. A speed without the plate it belongs
to is not evidence, and the plate the camera happened to be reading a moment
later belongs to whatever came next. The pin is released when the antenna is, so
the two cannot disagree about what is held.

Two cameras, much shorter range and a wider cone than the antennas — a camera
is aimed at a lane, not at a vehicle, and it has to actually resolve
characters. A plate must hold still for `DwellTime` before it counts as read,
without which the window strobes through every car in oncoming traffic.

Plate art uses the same four images and the same index mapping as
`ps-dispatch`, so a plate looks identical in both resources.

**Watch plates:** the operator's own list, for cars the MDT has nothing on yet —
the one that just made off, for instance. Real BOLOs need no entry: the MDT
check catches them on its own, since `bolo` is one of
`Config.PlateCheck.checks`. A match alarms immediately, without waiting on a
server round trip.

The field for adding sits in the open; the register folds away behind a button
next to it, with a count badge. Plates are added often and consulted rarely, so
that is the way round it belongs. `Config.PlateReader.MaxWatchPlates` caps the
list at 20 — past a couple of dozen it is a database, and a database belongs in
the MDT. The cap also bounds what the export can push into a client.

The radar header shows the count, not the plates. One plate fitted there; a list
does not, and the count is the part that survives a glance.

```lua
exports['lsn-radar']:AddWatchPlate('46EEK872')
exports['lsn-radar']:RemoveWatchPlate('46EEK872')
exports['lsn-radar']:ClearWatchPlates()
local plates = exports['lsn-radar']:GetWatchPlates()
```

The same four exist server side, taking a client id first — `-1` reaches
everyone:

```lua
exports['lsn-radar']:AddWatchPlate(clientId, '46EEK872')
exports['lsn-radar']:RemoveWatchPlate(clientId, '46EEK872')
```

# Configuration

Everything a server owner decides lives in `shared/config.lua`. Everything an
operator can change lives in the control panel and is stored per client via
KVP. The split matters: config values are the ceiling, the operator menu moves
within it. An officer can dial range down to 80m but never above
`Config.Radar.MaxRange`.

Notable options:

| Option | Effect |
| --- | --- |
| `Config.Jobs` | Job *types* (not names) that get the radar. Both are accepted. |
| `Config.RequireDuty` | Off-duty officers in a patrol car are normal; a running radar on one is not. |
| `Config.Radar.ConeAngle` | Antenna half-angle. 12° is narrow enough to ignore the next lane. |
| `Config.Radar.MaxRange` | Also a performance dial — each candidate vehicle costs a raycast. |
| `Config.PlateReader.DwellTime` | How long a plate must stay in view to count. |
| `Config.UI.AutoShow` | Show the panel automatically on entering a patrol vehicle. |

The panel fades in on entering a patrol vehicle and out on leaving it. Whether
the radar was left switched **on** is remembered too, so it comes up powered in
the next vehicle rather than needing to be switched on every shift.

A switched-off radar is not on screen at all — off means off. The exception is
while the control panel is open, since that is where it gets switched back on
and hiding the thing being configured would leave the power toggle pointing at
nothing.

# Keybinds

| Default | Action |
| --- | --- |
| `NUMPAD7` | Open the control panel |
| `NUMPAD8` / `NUMPAD5` | Front / rear antenna XMIT–HOLD |
| `NUMPAD9` / `NUMPAD6` | Copy front / rear plate to the clipboard |
| `L` | Key lock — freezes every radar key except its own release |

The camera-lock keys are gone. HOLD already freezes the plate alongside the
speed, and an antenna lock pins the plate by itself, so a third way to hold the
same thing was two keys doing no work. The slots now do something the radar
could not do at all: get a plate into a report without retyping eight characters
off a screenshot. A green tick appears briefly on the row that was copied.

Copying runs in the interface through a hidden textarea and `execCommand`.
There is no clipboard native, and CEF refuses `navigator.clipboard` inside a
NUI — this is the same route `ps-dispatch` uses for its own copy buttons.

Every client can rebind these under **Settings → Key Bindings → FiveM**.

Two notes on the defaults. The control panel is `NUMPAD7` rather than the `F5`
Wraith uses, because `ps-mdt`'s config documents F5/F6/F7 as example binds for
`mdtstatus`. And everything sits on the numpad deliberately: it keeps the radar
to one hand on one cluster, and it keeps these binds away from vehicle movement
keys, which are a known way to crash the game when bound through
`RegisterKeyMapping`.

# Interface

The displays are **read-only**. Every control lives either on a key or in the
control panel, and the panels are a fixed size in every state — nothing appears,
disappears or resizes when a plate is read, a lock lands or the control panel is
opened. That is what makes them parkable against a screen edge, and it keeps
movement out of peripheral vision, which is where a HUD lives.

They render **without NUI focus**, the same way `ps-dispatch` alerts do. Only
the control panel takes focus, and only while open.

That has one consequence worth knowing: **panels can only be dragged while the
control panel is open**, because that is the only time a cursor exists. Both
panels outline themselves in dashed blue when they become grabbable. Positions
are stored as a fraction of the viewport rather than in pixels, so a panel
parked against an edge stays there when the operator changes resolution.

The control panel is a side panel rather than a centred dialog, because the
displays it configures have to stay visible while it is open.

# Exports and events

## Client exports

```lua
-- Add a plate to this officer's watchlist
exports['lsn-radar']:AddWatchPlate('46EEK872')

-- Lock a camera. cam is 'front' or 'rear'
exports['lsn-radar']:LockCamera('front', true)

-- What the reader currently holds
local plates = exports['lsn-radar']:GetPlates()
-- { front = '46EEK872', rear = '68HBW691', bolo = '46EEK872' }

-- Last locked speed per antenna — for a citation form that would rather not
-- ask the officer to retype a number the radar already knows.
local speeds = exports['lsn-radar']:GetLockedSpeeds()
-- { unit = 'kmh', front = 141, rear = nil }
```

## Server exports

```lua
exports['lsn-radar']:TogglePlateLock(clientId, 'front', true)
exports['lsn-radar']:AddWatchPlate(clientId, '46EEK872')   -- -1 for everyone
exports['lsn-radar']:OpenRemote(clientId)
```

## Server events

Register them before adding a handler, as with any net event.

```lua
AddEventHandler('lsn-radar:onPlateScanned', function(src, cam, plate, index)
    -- Fires every time a camera reads a new plate
end)

AddEventHandler('lsn-radar:onPlateLocked', function(src, cam, plate, index)
    -- Fires when an operator locks a plate
end)

AddEventHandler('lsn-radar:onSpeedLocked', function(src, speed, unit, plate)
    -- Fires on an automatic lock
end)
```

All three are relayed through the server, which rate limits them per source and
verifies the sender is actually an officer. Nothing the radar computes needs to
be trusted — it reads entities the client can already see — but an unbounded
relay is still a way to spam every listening resource.

## MDT plate checks

`Config.PlateReader.Mdt` hands every newly read plate to `ps-mdt`, which owns
plate lookups for the whole server. Nothing is duplicated here — the MDT's own
implementation is explicitly written for scanners:

- lookups are cached, and concurrent queries for one plate share a single
  database round trip
- an officer is not alerted about the same plate twice inside
  `Config.PlateCheck.alertCooldown`
- there is a hard ceiling of alerts per officer per minute
- only scans that actually alert are written to the audit log, so a continuous
  reader does not bury the interesting queries

Three modes:

| `Mode` | Behaviour |
| --- | --- |
| `alert` | `PlateCheckAlert` — looks the plate up **and** sends the officer a targeted `ps-dispatch` card. Hits also come back to the reader. |
| `lookup` | `CheckPlate` — silent lookup. Hits show in the reader only. |
| `off` | No MDT contact at all. |

The radar adds one thing of its own: a client-side resend window
(`ResendSeconds`, default 120s) so the same plate is not sent twice. The MDT
caches server side, but each scan still costs a network event, and in dense
traffic that is the real bottleneck rather than the database. Keep this at or
above the MDT's `alertCooldown` — sending more often only gets the answer
suppressed at the far end.

Hits render beside the plate as a severity marker — a red triangle for
`critical`, amber for `warning`, with a count when there is more than one. The
reason text is deliberately **not** shown: the MDT already raises a dispatch
card carrying it in full, and repeating it in a 90px slot produces
`OWNER HAS NO DRIVER L...`, which looks like information while being
unreadable. The row's job is to say that there is a hit and roughly how bad; the
card says what.

A match on the operator's own watch plate gets an eye marker instead, because
that is the one hit no dispatch card will mention — nobody else knows the plate
was being watched.

A plate that came back with nothing gets a **Clear** badge rather than no badge,
because "no badge" would otherwise mean both *clean* and *still waiting*.

If the lookup is denied — an officer whose job is not in the MDT's
`allowedJobTypes` — the reader says nothing rather than reporting the plate as
clear.

## Dispatch integration

`Config.Integration.SpeedAlert` fires a `ps-dispatch` alert when an automatic
lock lands above a multiple of the operator's limit. Off by default: a radar
lock is evidence, not a call for backup, and a dispatch board full of speeding
tickets is a board nobody reads.

It calls `ps-dispatch`'s `CustomAlert`, which is a **client** export taking a
single table, so the alert fires from the officer's own client. The call is
wrapped — a renamed or stopped sibling resource must not take the radar down
with it.

# Building the UI

```bash
cd ui
npm install
npm run build     # writes to ../html
npm run check     # svelte-check, expected to be clean
```

`npm run dev` plus swapping the `ui_page` line in `fxmanifest.lua` to
`http://localhost:5173/` gives live reload in game.

`html/` is committed. If you change anything under `ui/src`, rebuild and commit
`html/` in the same commit — otherwise the resource ships a UI that does not
match its source, and nobody notices until a feature silently does nothing.

# FAQ

**The panels do not appear.**
Check `Config.Jobs`, `Config.RequireDuty`, and that your patrol vehicle's class
is in `Config.VehicleClasses`. Addon vehicles frequently ship without
`VC_EMERGENCY` set in `vehicles.meta`.

**I cannot drag the panels.**
Dragging requires a cursor, which only exists while the control panel is open.
Open it first; both panels will outline themselves.

**Why is sound only on/off and not a volume slider?**
`PlaySoundFrontend` takes no gain parameter — GTA's frontend sounds ride on the
player's master volume. A percentage slider would have been a mute switch
wearing a disguise, so it is a mute switch and says so. Real volume control
would mean shipping audio files and playing them through the NUI.

**Speeds look wrong on cross traffic.**
They are not shown at all, on purpose. See [Antennas](#antennas).

**My keybinds stopped working.**
`RegisterKeyMapping` occasionally fails to register. Remove the
`rbind lsn-radar ...` lines from `%AppData%\CitizenFX\fivem.cfg` and rejoin so
the resource can create them again.

# Credits

- [WolfKnight98](https://github.com/WolfKnight98) — Wraith ARS 2X, the design
  this borrows its behaviour from
- Interface follows the `ps-mdt` / `ps-dispatch` design language
