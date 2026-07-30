export type Unit = "mph" | "kmh";
export type Cam = "front" | "rear";
export type AntennaMode = "both" | "closing" | "away";
export type Direction = "closing" | "away";

export interface Target {
  speed: number;
  dir: Direction;
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
}

export interface Position {
  x: number;
  y: number;
}

export interface SettingsPayload {
  settings: Settings;
  positions: { radar: Position; plate: Position };
  unit: Unit;
  keyLock: boolean;
  watch: string[];
  limits: Limits;
  keys: Record<string, string>;
}
