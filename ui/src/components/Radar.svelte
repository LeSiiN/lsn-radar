<script lang="ts">
  import Antenna from "@components/Antenna.svelte";
  import Segment from "@components/Segment.svelte";
  import { draggable } from "@actions/draggable";
  import { RADAR, PLATES, CONFIG, REMOTE_OPEN } from "@store/stores";
  import { fly } from "svelte/transition";
  import { cubicOut } from "svelte/easing";

  $: pos = $CONFIG.positions.radar;
  $: scale = $CONFIG.settings.scale;
  $: powered = $RADAR.power;
  $: showPlate = $CONFIG.settings.showPlate && $PLATES.enabled;
  $: watchCount = $PLATES.watch?.length ?? 0;

  // A switched-off radar is not on screen at all. It stays visible while the
  // control panel is open, though — that is where it gets switched back on, and
  // hiding the thing being configured would leave the power toggle pointing at
  // nothing.
  $: onScreen = powered || $REMOTE_OPEN;

  // The transition lives on the outer element and the scale on the inner one.
  // Both write to `transform`, and Svelte's would win — the panel would snap to
  // 100% for the length of every fade.
</script>

{#if onScreen}
<div
  class="rd-anchor"
  style="left:{pos.x * 100}vw; top:{pos.y * 100}vh"
  class:rd-draggable={$REMOTE_OPEN}
  use:draggable={{ panel: "radar", enabled: $REMOTE_OPEN }}
  in:fly={{ y: 14, duration: 260, easing: cubicOut }}
  out:fly={{ y: 10, duration: 180, easing: cubicOut }}
>
  <!-- The drag outline belongs on the scaled element, not on the anchor. The
       anchor keeps its unscaled layout box, so an outline drawn there traced a
       rectangle the size the panel used to be. -->
  <div class="rd-scaler" class:rd-drag-armed={$REMOTE_OPEN} style="transform:scale({scale})">
    <div class="rd-panel" class:rd-panel--off={!powered}>
      <div class="rd-head">
        <div class="rd-icon" class:rd-icon--off={!powered}>
          <i class="fas fa-satellite-dish"></i>
        </div>
        <span class="rd-title">Radar</span>

        <!-- How many plates are being watched for, not which. A single plate
             fitted in the header; a list does not, and the count is the part
             that has to survive a glance — the register itself is in the
             control panel. -->
        <span class="rd-badge rd-badge--red rd-watch" style:visibility={watchCount > 0 ? "visible" : "hidden"}>
          <i class="fas fa-eye"></i> {watchCount}
        </span>

        <span class="rd-badge rd-badge--amber" style:visibility={$RADAR.keyLock ? "visible" : "hidden"}>
          <i class="fas fa-lock"></i>
        </span>

        <!-- Patrol speed is context for every reading below it, not a fourth
             target, so it sits in the header rather than in a window. -->
        <div class="rd-sub rd-patrol">
          <Segment value={powered ? $RADAR.patrolSpeed : null} size="sm" state={powered ? "patrol" : "idle"} />
          <span>{$RADAR.unit}</span>
        </div>
      </div>

      <div class="rd-body">
        <Antenna cam="front" data={$RADAR.front} camera={$PLATES.front} {powered} {showPlate} />
        <Antenna cam="rear" data={$RADAR.rear} camera={$PLATES.rear} {powered} {showPlate} />
      </div>
    </div>
  </div>
</div>
{/if}

<style>
  .rd-anchor {
    position: absolute;
    width: 268px;
    transform-origin: top left;
    /* Renders without NUI focus, so it must never swallow a click meant for the
       game. Dragging re-enables pointer events. */
    pointer-events: none;
  }
  .rd-anchor.rd-draggable {
    pointer-events: auto;
  }
  .rd-scaler {
    transform-origin: top left;
  }
  .rd-patrol {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-left: auto;
  }
  .rd-watch {
    max-width: 84px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
