# LSN Radar

A police radar for QBCore, in two forms: a **mounted radar** for patrol vehicles
and a **handheld radar gun** for officers on foot. Both read speeds and plates,
both check plates against the MDT, and both are styled to match `ps-mdt` and
`ps-dispatch` so they read as part of the same system rather than as a bolted-on
tool.

Behaviour is modelled on [Wraith ARS 2X](https://github.com/WolfKnight98/wk_wars2x).
The implementation, interface and integrations are new.

---

## Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Installation](#installation)
- [Setting up the radar gun](#setting-up-the-radar-gun)
- [Using it](#using-it)
- [Keybinds](#keybinds)
- [Configuration](#configuration)
- [MDT and dispatch](#mdt-and-dispatch)
- [Exports and events](#exports-and-events)
- [Performance](#performance)
- [Building the UI](#building-the-ui)
- [FAQ](#faq)

---

## What it does

**Mounted radar** — two antennas, front and rear. Each reports a STRONG and a
FAST target: the largest vehicle in the cone, and any smaller one moving quicker
than it. That second window is the point. The car overtaking the lorry you were
watching is invisible on a single-number display, and it is invariably the one
you wanted.

**Radar gun** — draw the configured weapon and a readout appears. Aim at a
vehicle to measure it, pull the trigger to lock. Firing is disabled while it is
out; the trigger is the lock button, which is where a real radar gun's lock
button is anyway.

**Plate reading** — plates appear under each antenna with their GTA artwork, and
under the gun's reading. Every plate is run against `ps-mdt`: stolen, BOLO,
owner warrants, impound history. Hits raise a `ps-dispatch` card and mark the
row.

**Tracking locks** — a lock follows the vehicle rather than freezing a number.
In a pursuit the speed climbs with the driver and the peak is kept, because the
driver brakes for corners and the highest speed they actually reached is the
fact worth having.

**A watchlist** — plates the officer decides to watch for, separate from the
MDT's records. For the car that just made off, which the MDT has nothing on yet.

Plus: a target bracket around the vehicle being measured, a range preview drawn
on the road, plate copying to the clipboard, and a control panel that remembers
everything per client.

---

## Requirements

**Required**

- [qb-core](https://github.com/qbcore-framework/qb-core)

**Optional but strongly recommended**

- [ps-mdt](https://github.com/Project-Sloth/ps-mdt) — plate checks against MDT
  records. Without it the readers still read plates, they just have nothing to
  check them against.
- [ps-dispatch](https://github.com/Project-Sloth/ps-dispatch) — plate hits and
  speed locks as alert cards.

**For the radar gun only**

- [ox_inventory](https://github.com/overextended/ox_inventory) — to hand out the
  weapon as an item.
- A prop resource for the radar model. Set up for
  [`bzzz_pdradar`](https://bzzz.tebex.io/) out of the box.

`ox_lib` and `PolyZone` are **not** required.

---

## Installation

1. Drop the `lsn-radar` folder into your resources directory.
2. Add `ensure lsn-radar` to your server configuration, after `qb-core`.
3. Open `shared/config.lua` and check `Config.Jobs` and `Config.VehicleClasses`
   match your server.

The interface ships prebuilt in `html/`. Node is only needed if you intend to
change the UI.

That is the mounted radar working. The gun needs a few more steps.

---

## Setting up the radar gun
> IMPORTANT: IF U USE ROBBERY SCRIPT OR CAR ROBBERY SCRIPT THAT LETS U ROB NPCS WITH A GUN OUT, ADD `WEAPON_RAYPISTOL` AS A WHITELIST WEAPON.

Five steps, roughly ten minutes.

### 1. Start the prop resource

Go to [RADAR GUN PROP](https://bzzz.tebex.io/package/6631002)
The radar model has to be streamed by something. This is set up for
`bzzz_pdradar`:

```cfg
ensure bzzz_pdradar
ensure lsn-radar
```

> **Do not copy the `.ydr` or `.ytyp` files into `lsn-radar` as well.** Loading
> the same `DLC_ITYP_REQUEST` twice stops the props working entirely — the
> pack's own readme warns about this. `lsn-radar` only references the model by
> name.

If you are using a different prop, put its model name in
`Config.Handheld.Prop.Model`.

### 2. Choose the weapon

The gun rides on a weapon, because a weapon is what provides aiming, the
crosshair and a trigger. The weapon model itself is made invisible and the radar
prop is attached in its place.

```lua
Config.Handheld.Weapon = 'WEAPON_RAYPISTOL'
```

Firing is disabled whenever it is out, so this being a real weapon is not a
risk — an officer taking a reading cannot put a round into the car.

### 3. Register the weapon in ox_inventory

In `ox_inventory/data/weapons.lua`, under `Weapons`:

```lua
['WEAPON_RAYPISTOL'] = {
  label = 'Radargun',
  weight = 1540,
  durability = 0.5
},
```

Give it an icon at `ox_inventory/web/images/WEAPON_RAYPISTOL.png`. The prop pack
ships inventory images under `data/images_for_inventory/`; rename the one you
want to match.

### 4. Hand one out

```
/giveitem [id] WEAPON_RAYPISTOL 1
```

Or through your job's shop, locker, or however officers normally draw equipment.

Detection reads the ped's **selected weapon**, not the inventory. A misconfigured
inventory can stop officers obtaining a gun; it cannot stop the radar working for
someone who has one.

### 5. Check the prop sits right

Draw it and look at your hands. If the radar is floating, clipping or pointing
the wrong way, the offsets are in `Config.Handheld.Prop`:

```lua
Prop = {
    Enabled  = true,
    Model    = 'bzzz_police_prop_radar_a',
    Bone     = 57005,                      -- IK_R_Hand
    Offset   = { 0.14, 0.04, 0.0 },        -- x, y, z
    Rotation = { -100.0, -110.0, -15.0 },  -- pitch, roll, yaw
},
```

These are the values from the prop pack's own dpemotes example, tuned for a
pistol grip. Change the weapon in step 2 and you will probably need to nudge
them. Restart the resource after each change.

### Done

Draw the weapon and the readout appears. If nothing does, work down the
[FAQ](#faq) — the usual causes are the job check, the prop resource not running,
or `Config.Handheld.Enabled` being off.

---

## Using it

### The mounted radar

Get into a patrol vehicle as an on-duty officer and the panel fades in. Power it
on from the control panel; it remembers that choice and comes up powered next
time.

**XMIT / HOLD** freezes an antenna on its current reading, and freezes the plate
with it. A held number nobody can attach to a vehicle is not much use.

Each antenna has a direction filter — **Approaching**, **Departing** or
**Both** — shown on the display as a single glyph and explained in the control
panel. Vehicles crossing your path are never shown whichever filter is set: a
Doppler antenna only measures motion along its own axis, so it has no speed it
could honestly report for them.

### The radar gun

Draw the weapon, aim, read. Pull the trigger to lock, pull again to release.

Aiming resolves through a **cone** from the camera rather than a thin ray: at
300m a car covers a couple of pixels, and a ray would demand pixel-perfect aim.
`Config.Handheld.ConeAngles` offers three widths in the control panel — narrow
separates cars in dense traffic, wide is easier to hold on a distant target.
Among the vehicles in the cone, the one **nearest the centre of the crosshair**
wins, not the one nearest you: aiming past a close car at one further down the
road is a thing people do on purpose.

The gun keeps its own scale, position, range, beam width and auto-lock limit. It
is read standing still with the display in the middle of the screen; the mounted
radar is read at a glance while driving. One set of numbers for both would suit
neither.

### Locks

A lock is a **tracked target**, not a frozen number. The antenna commits to that
vehicle and stops acquiring anything else until released; the LOCK window stays
live, so a driver accelerating away in a pursuit takes the number with them. The
plate appears beside the antenna name, because with two cars in one cone there
is otherwise no saying afterwards which one the number belonged to.

Once the live and peak readings differ, the label switches to showing the peak.

Tracking is by entity, not by plate — NPC traffic reuses plates, so following a
plate would eventually hop to a different car wearing the same characters. It is
also not cone-limited: a locked vehicle in a pursuit swerves and takes corners,
and re-applying an acquisition cone would drop the reading exactly when it
matters. Range still applies; past it the reading is marked stale (`⚠`) and held
rather than pretending to be current.

Release with the same antenna key that toggles XMIT/HOLD, or the button in the
control panel.

### Plates and the watchlist

Plates read under each antenna are checked against the MDT automatically. Hits
show as a severity marker — red triangle for critical, amber for warning, with a
count if there is more than one. The reason text is deliberately not shown: the
dispatch card carries it in full, and repeating it in a 90px slot produces
`OWNER HAS NO DRIVER L...`, which looks like information while being unreadable.

A hit also puts that antenna into HOLD, so the warning is not sitting above
speeds belonging to whatever else drove into the cone. Resume transmitting to
acknowledge it; the finding stays on the row, only the alarm clears.

The **watchlist** is separate and yours: plates the MDT has nothing on yet. The
field for adding is in the open, the register folds away behind a button with a
count. A match alarms immediately, without waiting on the server, and gets an
eye marker rather than a triangle — it is the one hit no dispatch card will
mention, because nobody else knows you were watching for it.

---

## Keybinds

| Default | Action |
| --- | --- |
| `NUMPAD7` | Control panel |
| `NUMPAD8` / `NUMPAD5` | Front / rear antenna: hold, or release a lock |
| `NUMPAD9` / `NUMPAD6` | Copy front / rear plate to the clipboard |
| `L` | Key lock — freezes every radar key except its own release |

Rebind under **Settings → Key Bindings → FiveM**.

Everything sits on the numpad on purpose: one hand, one cluster, and well away
from the vehicle movement keys, which are a known way to crash the game when
bound through `RegisterKeyMapping`. The control panel is `NUMPAD7` rather than
`F5` because `ps-mdt`'s config documents F5–F7 as example binds for `mdtstatus`.

The panel opens on foot as well as in a vehicle, so the gun's settings are
reachable while holding it.

---

## Configuration

Everything a server owner decides is in `shared/config.lua`. Everything an
operator can change is in the control panel and stored per client. The split
matters: config values are the ceiling, the operator menu moves within them.

### Access

| Option | Effect |
| --- | --- |
| `Config.Jobs` | Job *types* that get the radar. Job names are accepted too. |
| `Config.RequireDuty` | Off-duty officers in a patrol car are normal; a running radar on one is not. |
| `Config.VehicleClasses` | 18 is `VC_EMERGENCY`. Add classes for unmarked units. |

`VC_EMERGENCY` covers police cars, ambulances and fire trucks alike. The job
check is what keeps a paramedic out of the radar, so keep `Config.Jobs` tight.

### Mounted radar

| Option | Effect |
| --- | --- |
| `Config.Radar.ConeAngle` | Antenna half-angle. 12° ignores the next lane. |
| `Config.Radar.MaxRange` | Also a performance dial — every candidate costs a raycast. |
| `Config.Radar.Tick` | 100ms. Going to 150 costs nothing in readability. |
| `Config.Radar.ReadingHold` | How long a reading survives a tick that found nothing. |
| `Config.Radar.FastLock` | Auto-lock: allowed, default, and slider ends per unit. |
| `Config.Radar.TargetMarker` | The bracket around the measured vehicle. |
| `Config.Radar.Preview` | The cone drawn on the road while adjusting range. |

### Radar gun

| Option | Effect |
| --- | --- |
| `Config.Handheld.Enabled` | Whether the gun exists at all. |
| `Config.Handheld.Weapon` | The weapon it rides on. |
| `Config.Handheld.Prop` | Model, bone and offsets. |
| `Config.Handheld.ConeAngles` | The three beam widths offered in the panel. |
| `Config.Handheld.AutoLock` | Its own limit and slider ends, separate from the antennas. |

Both auto-lock sliders take their ends from the config, per unit:

```lua
Config.Radar.FastLock = {
    Default = { mph = 80,  kmh = 130 },
    Min     = { mph = 20,  kmh = 30  },
    Max     = { mph = 250, kmh = 400 },
}
```

A highway server wants a different band from a city one, which is why these are
not written into the interface. Switching units moves both limits to that unit's
default rather than carrying the number across, so nobody ends up with a 130 mph
trigger by accident.

### Plate reader

| Option | Effect |
| --- | --- |
| `Config.PlateReader.DwellTime` | How long a plate must hold still to count. |
| `Config.PlateReader.MaxWatchPlates` | 20. Past a couple of dozen it is a database, and a database belongs in the MDT. |
| `Config.PlateReader.Mdt` | Which MDT export to use, and the client-side resend window. |

---

## MDT and dispatch

### Plate checks

`Config.PlateReader.Mdt` hands every newly read plate to `ps-mdt`, which owns
plate lookups for the whole server. Nothing is reimplemented here — the MDT's own
code is written for scanners: lookups are cached, concurrent queries for one
plate share a database round trip, officers are not alerted twice about the same
plate inside a cooldown, there is a per-minute ceiling, and only scans that
actually alert are audited.

| `Mode` | Behaviour |
| --- | --- |
| `alert` | `PlateCheckAlert` — looks up **and** sends the officer a dispatch card. |
| `lookup` | `CheckPlate` — silent. Hits show in the reader only. |
| `off` | No MDT contact. |

The one thing the radar adds is a client-side resend window (`ResendSeconds`,
120s), because each scan costs a network event and in traffic that is the real
bottleneck rather than the database. Keep it at or above the MDT's own
`alertCooldown`.

A denied lookup — an officer whose job is not in the MDT's `allowedJobTypes` —
produces silence rather than a "clear".

### Alert cards

A plate check card should show neither a map thumbnail nor a location strip.
`PlateCheckAlert` sends a **targeted** alert, so it reaches only the officer who
ran the plate, and that officer is standing at the location. A map centred on
where they already are, above the answer they asked for, is the wrong half of the
card.

This takes a small change **in ps-dispatch**, not here: two conditions, one in
`Main.svelte` and one in `CallRow.svelte`, suppressing the map and the location
strip when the alert carries a `footer`. That is the resource's own test for an
answer as opposed to a job — `client/plates.lua` already uses it to decide what
belongs in the plate log.

Without that change the cards still work, they just carry a map and read
*Unknown location*.

### Speed alerts

`Config.Integration.SpeedAlert` raises a dispatch card when an automatic lock
lands above a multiple of the limit. Off by default: a radar lock is evidence,
not a call for backup, and a dispatch board full of speeding tickets is a board
nobody reads.

---

## Exports and events

### Client

```lua
exports['lsn-radar']:AddWatchPlate('46EEK872')     -- true / false
exports['lsn-radar']:RemoveWatchPlate('46EEK872')
exports['lsn-radar']:ClearWatchPlates()
exports['lsn-radar']:GetWatchPlates()

exports['lsn-radar']:LockCamera('front', true)
exports['lsn-radar']:GetPlates()        -- { front, rear, watch }
exports['lsn-radar']:GetLockedSpeeds()  -- { unit, front, rear }
```

`GetLockedSpeeds` exists for citation forms that would rather not ask an officer
to retype a number the radar already knows.

### Server

Client id first; `-1` reaches everyone.

```lua
exports['lsn-radar']:AddWatchPlate(clientId, '46EEK872')
exports['lsn-radar']:RemoveWatchPlate(clientId, '46EEK872')
exports['lsn-radar']:TogglePlateLock(clientId, 'front', true)
exports['lsn-radar']:OpenRemote(clientId)
```

### Events

```lua
AddEventHandler('lsn-radar:onPlateScanned', function(src, cam, plate, index) end)
AddEventHandler('lsn-radar:onPlateLocked',  function(src, cam, plate, index) end)
AddEventHandler('lsn-radar:onSpeedLocked',  function(src, speed, unit, plate) end)
```

All three are relayed through the server, rate limited per source and checked
against the sender's job. Nothing the radar computes needs to be trusted — it
reads entities the client can already see — but an unbounded relay is still a way
to spam every listening resource.

---

## Performance

Detection is a **single sweep** shared by the antennas and the cameras. It was
originally two, each walking the vehicle pool and doing its own coordinate read
and class check on every vehicle in the world before rejecting most of them —
around 6,000 native calls a second on a busy street, spent deciding that a car
three blocks away is not interesting.

| | Before | After |
| --- | --- | --- |
| Pool walks per second | 14 | 10 |
| Natives per rejected vehicle | 3 | 2 |
| `GetGamePool` allocations per second | 14 | 2 |
| Line-of-sight rays per tick | one per vehicle in cone | one per antenna |
| Plate text + driver lookup | every candidate, every tick | winners only |

Distance is tested first, before the class check — most of the world fails there
and failing there is the cheapest failure available. The pool list is cached for
500ms and class results per entity. Plate text, driver lookups and raycasts run
only for the one or two vehicles that reach a window. With both antennas locked
and the cameras off, the pool is never walked at all.

**The radar gun is the cheaper device.** A mounted antenna sweeps a cone because
it cannot be pointed; a gun is pointed, so it never touches the sweep. Without
the weapon in hand it costs one native every half second.

**The range preview** had the same problem and got the same treatment: it called
`GetGroundZFor_3dCoord` for every marker on every frame, over three thousand
ground raycasts a second to place points that were not moving. The geometry is
cached and rebuilt only when the range changes, the car moves more than two
metres, or it turns more than about three degrees.

Dials, in order of effect: `Config.Radar.MaxRange`, `Config.Radar.Tick`,
`Config.Radar.ConeAngle`.

---

## Building the UI

```bash
cd ui
npm install
npm run build     # writes to ../html
npm run check     # svelte-check
```

`npm run check` is expected to report **1 hint** and nothing else — a deprecation
notice for `document.execCommand`, which the plate copy needs because CEF refuses
`navigator.clipboard` inside a NUI.

`html/` is committed. If you change anything under `ui/src`, rebuild and commit
`html/` in the same commit, or the resource ships a UI that does not match its
source and nobody notices until a feature silently does nothing.

---

## FAQ

**The mounted radar does not appear.**
Check `Config.Jobs`, `Config.RequireDuty`, and that your patrol vehicle's class is
in `Config.VehicleClasses`. Addon vehicles frequently ship without
`VC_EMERGENCY` set in `vehicles.meta`.

**The radar gun does not appear.**
In order: is `Config.Handheld.Enabled` true, does your job pass the same check as
above, and is the weapon in `Config.Handheld.Weapon` the one you are actually
holding?

**The gun works but I am holding a weapon, not a radar.**
The prop resource is not running or the model name is wrong. The console says so
once on the first attempt. Check `ensure bzzz_pdradar` is in your server config
and comes before `lsn-radar`.

**The prop is in my hand but floating or rotated wrong.**
`Config.Handheld.Prop.Offset` and `.Rotation`. The defaults are tuned for a
pistol grip; a weapon with a different hand pose needs them nudged.

**Aiming at a car does nothing.**
Check `Config.Handheld.DefaultRange` against how far away it is, and remember GTA
only keeps vehicles streamed to roughly 300m — beyond that there is nothing on
your client to find. If it is close and still nothing, widen the beam in the
control panel.

**I cannot drag the displays.**
Dragging needs a cursor, which only exists while the control panel is open. Open
it first; the panel outlines itself.

**Why is sound only on/off?**
`PlaySoundFrontend` takes no gain parameter — GTA's frontend sounds ride on the
player's master volume. A percentage slider would have been a mute switch in
disguise.

**Speeds look wrong on cross traffic.**
They are not shown at all, on purpose. A Doppler antenna only measures motion
along its own axis.

**My keybinds stopped working.**
`RegisterKeyMapping` occasionally fails to register. Remove the
`rbind lsn-radar ...` lines from `%AppData%\CitizenFX\fivem.cfg` and rejoin.

---

## Credits

- [WolfKnight98](https://github.com/WolfKnight98) — Wraith ARS 2X, the design
  this borrows its behaviour from
- [BzZz](https://bzzz.tebex.io/) — the radar props the handheld unit is set up
  for
- Interface follows the `ps-mdt` / `ps-dispatch` design language
