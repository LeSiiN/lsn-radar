import { writable } from "svelte/store";
import type { RadarData, PlateData, SettingsPayload } from "@typings/type";
import { isEnvBrowser } from "@utils/misc";

export const BROWSER_MODE = writable<boolean>(isEnvBrowser());
export const RESOURCE_NAME = writable<string>("lsn-radar");

/** Whether the panel is on screen at all — driven by the vehicle watch. */
export const SHOW_RADAR = writable<boolean>(false);

/** The control panel. Also the only state in which panels can be dragged. */
export const REMOTE_OPEN = writable<boolean>(false);

/** Which side just had its plate copied, and what — drives the confirmation
 *  banner on that row. */
export const COPIED = writable<{ cam: string; plate: string } | null>(null);

export const RADAR = writable<RadarData>({
  power: false,
  keyLock: false,
  unit: "kmh",
  patrolSpeed: 0,
  front: { xmit: true, mode: "both" },
  rear: { xmit: true, mode: "both" },
});

export const PLATES = writable<PlateData>({
  power: false,
  enabled: true,
  watch: [],
  front: { plate: "", locked: false, flagged: false },
  rear: { plate: "", locked: false, flagged: false },
});

export const CONFIG = writable<SettingsPayload>({
  settings: { range: 250, sound: true, marker: true, fastLock: false, fastLimit: 130, scale: 1, showPlate: true },
  positions: { radar: { x: 0.015, y: 0.3 }, plate: { x: 0.015, y: 0.62 } },
  unit: "kmh",
  keyLock: false,
  watch: [],
  limits: { minRange: 50, maxRange: 350, minScale: 0.7, maxScale: 1.4, fastLock: true, watchlist: true, maxWatch: 20, plates: true, mdtMode: "alert", preview: true, marker: true },
  keys: {},
});
