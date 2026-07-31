<script lang="ts">
  import Segment from "@components/Segment.svelte";
  import Plate from "@components/Plate.svelte";
  import { draggable } from "@actions/draggable";
  import { HANDHELD, CONFIG, REMOTE_OPEN } from "@store/stores";
  import { fly } from "svelte/transition";
  import { cubicOut } from "svelte/easing";

  // One reading, not two windows. A gun is pointed at a single vehicle, so the
  // strong/fast split that makes a mounted antenna readable has nothing to
  // separate here — and patrol speed is meaningless on foot.

  $: pos = $CONFIG.positions.gun;
  $: scale = $CONFIG.settings.gunScale ?? 1;
  $: h = $HANDHELD;
  $: locked = !!h.lock;
  $: reading = locked ? h.lock : h;
  $: hitCount = h.hits?.length ?? 0;
  $: watchHit = h.flagged && hitCount === 0 && h.reason === "WATCH";
  $: critical = h.severity === "critical";

  const arrow = (dir?: string | null) => (dir === "closing" ? "\u25B2" : "\u25BC");
</script>

<div
  class="rd-anchor"
  style="left:{pos.x * 100}vw; top:{pos.y * 100}vh"
  class:rd-draggable={$REMOTE_OPEN}
  use:draggable={{ panel: "gun", enabled: $REMOTE_OPEN }}
  in:fly={{ y: 14, duration: 260, easing: cubicOut }}
  out:fly={{ y: 10, duration: 180, easing: cubicOut }}
>
  <div class="rd-scaler" class:rd-drag-armed={$REMOTE_OPEN} style="transform:scale({scale})">
    <div class="rd-panel" class:rd-panel--off={!h.aiming && !locked}>
      <div class="rd-head">
        <div class="rd-icon" class:rd-icon--off={!h.aiming && !locked} class:rd-icon--alert={h.flagged}>
          <i class="fas fa-gauge-high"></i>
        </div>
        <span class="rd-title">Radar gun</span>

        <span class="rd-badge rd-badge--red" style:visibility={locked ? "visible" : "hidden"}>LOCK</span>

        <!-- Distance rather than patrol speed. It is the number that tells the
             operator whether the reading is one they can stand behind. -->
        <div class="rd-sub rd-gun-dist">
          {#if reading?.dist != null}{reading.dist} m{:else}&mdash;{/if}
        </div>
      </div>

      <div class="rd-body">
        <div class="rd-ant" class:rd-ant--locked={locked} class:rd-ant--flagged={h.flagged}>
          <div class="rd-ant-head">
            <span class="rd-dot" class:rd-dot--xmit={h.aiming && !locked} class:rd-dot--hold={locked}></span>
            <span class="rd-ant-name">{locked ? "Held" : h.aiming ? "Measuring" : "Standby"}</span>
            <span class="rd-dir" style:visibility={reading?.speed != null ? "visible" : "hidden"}>
              {arrow(reading?.dir)}
            </span>
          </div>

          <div class="rd-windows">
            <div class="rd-win rd-win--strong">
              <span class="rd-win-label">Speed</span>
              <Segment
                value={reading?.speed ?? null}
                size="lg"
                state={locked ? "lock" : reading?.speed != null ? "live" : "idle"}
              />
            </div>
            <div class="rd-win rd-gun-unit">
              <span class="rd-win-label">Unit</span>
              <span class="rd-gun-unit-value">{h.unit}</span>
            </div>
          </div>

          <div class="rd-plate-row" class:rd-plate-row--pinned={locked}>
            {#if reading?.plate}
              <Plate plate={reading.plate} index={reading.index} />

              <div class="rd-plate-meta">
                {#if watchHit}
                  <span class="rd-badge rd-badge--red rd-hit"><i class="fas fa-eye"></i></span>
                {:else if hitCount > 0}
                  <span class="rd-badge rd-hit" class:rd-badge--red={critical} class:rd-badge--amber={!critical}>
                    <i class="fas fa-triangle-exclamation"></i>
                    {#if hitCount > 1}{hitCount}{/if}
                  </span>
                {:else if h.checked}
                  <span class="rd-badge rd-badge--green">Clear</span>
                {:else}
                  <span class="rd-badge">Checking</span>
                {/if}
              </div>
            {:else}
              <span class="rd-cam-empty">
                {#if h.aiming}--------{:else}Aim at a vehicle{/if}
              </span>
            {/if}
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .rd-anchor {
    position: absolute;
    width: 268px;
    transform-origin: top left;
    pointer-events: none;
  }
  .rd-anchor.rd-draggable {
    pointer-events: auto;
  }
  .rd-scaler {
    transform-origin: top left;
  }
  .rd-gun-dist {
    margin-left: auto;
    font-family: "Courier New", monospace;
    font-weight: 700;
  }
  .rd-gun-unit {
    align-items: flex-start;
  }
  .rd-gun-unit-value {
    font-size: 13px;
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: rgba(255, 255, 255, 0.4);
    line-height: 30px;
  }
</style>