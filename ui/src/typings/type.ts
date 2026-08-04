export type Unit = "mph" | "kmh";
export type Cam = "front" | "rear";
export type AntennaMode = "both" | "closing" | "away";
export type Direction = "closing" | "away";

export interface Target {
  speed: number;
  dir: Direction;
  model?: string | null;
  /** Which vehicle the reading came from, so HOLD can freeze its plate too. */
  entity?: number;
  plate?: string | null;
  index?: number | null;
}

export interface Lock extends Target {
  src: "strong" | "fast";
  auto: boolean;
  at: number;
  /** Plate of the tracked vehicle, for identifying which car was measured. */
  plate?: string | null;
  /** Readable vehicle name, e.g. "Karin Sultan". */
  model?: string | null;
  /** Highest speed seen since the lock was taken. */
  peak?: number;
  /** True when the tracked vehicle is out of range or gone. */
  lost?: boolean;
}

export interface Antenna {
  xmit: boolean;
  mode: AntennaMode;
  strong?: Target | null;
  fast?: Target | null;
  lock?: Lock | null;
}

export interface RadarData {
  power: boolean;
  /** Power-on lamp test: every segment lit, then blank, then live. */
  selfTest?: "lamps" | "sweep" | "antennas" | "ready" | null;
  keyLock: boolean;
  unit: Unit;
  patrolSpeed: number;
  front: Antenna;
  rear: Antenna;
}

export interface Hit {
  key?: string;
  label: string;
  detail?: string | null;
  severity?: "critical" | "warning" | null;
}

export interface Camera {
  plate: string;
  index?: number | null;
  model?: string | null;
  locked: boolean;
  /** Held because the antenna on this side locked the vehicle. */
  pinned?: boolean;
  flagged: boolean;
  reason?: string | null;
  /** Flags returned by the MDT lookup, worst first. */
  hits?: Hit[] | null;
  severity?: "critical" | "warning" | null;
  /** True once the MDT has answered — distinguishes "clean" from "pending". */
  checked?: boolean;
}

export interface PlateData {
  power: boolean;
  enabled: boolean;
  /** The operator's own watchlist, newest first. */
  watch: string[];
  front: Camera;
  rear: Camera;
}

export interface HandheldData {
  active: boolean;
  aiming: boolean;
  unit: Unit;
  speed?: number | null;
  plate?: string | null;
  index?: number | null;
  model?: string | null;
  dir?: Direction | null;
  dist?: number | null;
  lock?: {
    speed: number;
    plate?: string | null;
    index?: number | null;
    model?: string | null;
    dir?: Direction | null;
    dist?: number | null;
    at: number;
  } | null;
  hits?: Hit[] | null;
  severity?: "critical" | "warning" | null;
  checked?: boolean;
  flagged?: boolean;
  reason?: string | null;
}

export interface HistoryEntry {
  id: number;
  speed: number;
  peak: number;
  unit: Unit;
  plate?: string | null;
  index?: number | null;
  model?: string | null;
  dir?: Direction | null;
  /** Which device took it: an antenna, or the handheld unit. */
  source: "front" | "rear" | "gun";
  auto: boolean;
  /** In-game clock at the moment of the lock. */
  clock: string;
  /** Wall clock, for ageing entries out. */
  epoch: number;
}

export interface HistoryData {
  enabled: boolean;
  entries: HistoryEntry[];
}

export interface Settings {
  range: number;
  sound: boolean;
  fastLock: boolean;
  fastLimit: number;
  scale: number;
  showPlate: boolean;
  /** Whether the radar comes up powered in the next patrol vehicle. */
  autoPower?: boolean;
  /** Bracket the vehicle currently being read. */
  marker?: boolean;
  /** Handheld unit — kept separate from the mounted radar throughout. */
  gunScale?: number;
  gunRange?: number;
  gunCone?: number;
  gunAutoLock?: boolean;
  gunLimit?: number;
}

export interface Limits {
  minRange: number;
  maxRange: number;
  minScale: number;
  maxScale: number;
  fastLock: boolean;
  watchlist: boolean;
  maxWatch: number;
  plates: boolean;
  mdtMode: "alert" | "lookup" | "off";
  preview: boolean;
  marker: boolean;
  history: boolean;
  gun: boolean;
  gunMinRange: number;
  gunMaxRange: number;
  gunCones: number[];
  /** Slider ends for both auto-lock limits, in the selected unit. */
  limitMin: number;
  limitMax: number;
  gunLimitMin: number;
  gunLimitMax: number;
}

export interface Position {
  x: number;
  y: number;
}

export interface SettingsPayload {
  settings: Settings;
  positions: { radar: Position; gun: Position };
  unit: Unit;
  keyLock: boolean;
  watch: string[];
  limits: Limits;
  keys: Record<string, string>;
}