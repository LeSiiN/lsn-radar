<script lang="ts">
  import { ReceiveNUI } from "@utils/ReceiveNUI";
  import { debugData } from "@utils/debugData";
  import {
    RADAR,
    PLATES,
    CONFIG,
    SHOW_RADAR,
    REMOTE_OPEN,
    COPIED,
  } from "@store/stores";
  import type { RadarData, PlateData, SettingsPayload } from "@typings/type";

  ReceiveNUI<RadarData>("radar", (data) => {
    RADAR.set(data);
  });

  ReceiveNUI<PlateData>("plates", (data) => {
    PLATES.set(data);
  });

  ReceiveNUI<SettingsPayload>("settings", (data) => {
    CONFIG.set(data);
  });

  ReceiveNUI<{ radar: boolean }>("visible", (data) => {
    SHOW_RADAR.set(!!data.radar);
  });

  ReceiveNUI<boolean>("remote", (open) => {
    REMOTE_OPEN.set(!!open);
  });

  /**
   * Copy a plate to the system clipboard.
   *
   * A hidden textarea and execCommand, rather than navigator.clipboard: CEF
   * refuses the async clipboard API inside a FiveM NUI, and this display has no
   * focus to satisfy its permission check anyway. Same route ps-dispatch uses
   * for its own copy buttons, so it is known to work in this stack.
   */
  ReceiveNUI<{ cam: string; plate: string }>("copyPlate", (data) => {
    if (!data?.plate) return;

    try {
      const field = document.createElement("textarea");
      field.value = data.plate;
      field.style.cssText = "position:fixed;opacity:0;pointer-events:none;";
      document.body.appendChild(field);
      field.select();
      document.execCommand("copy");
      field.remove();
    } catch {
      // A failed copy is not worth interrupting a patrol over. The tick below
      // is the only feedback either way, and it is deliberately brief.
      return;
    }

    COPIED.set(data.cam);
    setTimeout(() => COPIED.update((c) => (c === data.cam ? null : c)), 1400);
  });

  // Browser development fixtures. Only fire outside the game — isEnvBrowser
  // checks for the invokeNative shim CEF injects.
  debugData([
    { action: "visible", data: { radar: true } },
    {
      action: "settings",
      data: {
        settings: { range: 250, sound: true, marker: true, fastLock: true, fastLimit: 130, scale: 1, showPlate: true },
        positions: { radar: { x: 0.02, y: 0.22 }, plate: { x: 0.02, y: 0.62 } },
        unit: "kmh",
        keyLock: false,
        bolo: "46EEK872",
        limits: {
          minRange: 50, maxRange: 350, minScale: 0.7, maxScale: 1.4,
          fastLock: true, plateBolo: true, plates: true, mdtMode: "alert", preview: true, marker: true,
        },
        keys: {
          Remote: "NUMPAD7", KeyLock: "L", FrontAnt: "NUMPAD8",
          RearAnt: "NUMPAD5", FrontCam: "NUMPAD9", RearCam: "NUMPAD6",
        },
      },
    },
    {
      action: "radar",
      data: {
        power: true,
        keyLock: false,
        unit: "kmh",
        patrolSpeed: 64,
        front: {
          xmit: true, mode: "both",
          strong: { speed: 88, dir: "closing" },
          fast: { speed: 141, dir: "closing" },
          lock: { speed: 141, peak: 178, dir: "closing", src: "fast", auto: true, at: 0, plate: "68HBW691", lost: false },
        },
        rear: { xmit: false, mode: "away", strong: { speed: 52, dir: "away" }, fast: null, lock: null },
      },
    },
    {
      action: "plates",
      data: {
        power: true,
        enabled: true,
        bolo: "46EEK872",
        front: { plate: "46EEK872", index: 1, locked: true, pinned: true, flagged: true, reason: "BOLO",
          hits: [{ label: "Stolen", severity: "critical" }, { label: "Owner wanted", severity: "critical" }], checked: true },
        rear: { plate: "68HBW691", index: 3, locked: false, flagged: false, checked: true },
      },
    },
  ]);
</script>
