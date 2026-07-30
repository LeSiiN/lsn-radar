<script lang="ts">
  import Plate from "@components/Plate.svelte";
  import { draggable } from "@actions/draggable";
  import { PLATES, CONFIG, REMOTE_OPEN } from "@store/stores";
  import type { Cam } from "@typings/type";

  $: pos = $CONFIG.positions.plate;
  $: scale = $CONFIG.settings.scale;
  $: powered = $PLATES.power;
  $: anyFlagged = $PLATES.front.flagged || $PLATES.rear.flagged;

  const CAMS: { id: Cam; label: string }[] = [
    { id: "front", label: "Fwd" },
    { id: "rear", label: "Aft" },
  ];

  // Rows are a fixed height and hits collapse to a single line. An MDT answer
  // can carry several flags at once, and letting them stack would make the
  // panel grow and shrink as traffic goes past — the plate and the worst flag
  // are what gets read at speed anyway, so the rest is a count.
  function summary(hits?: { label: string; severity?: string }[] | null): string {
    if (!hits || hits.length === 0) return "";
    if (hits.length === 1) return hits[0].label;
    return hits[0].label + " +" + (hits.length - 1);
  }
</script>

<div
  class="rd-anchor"
  style="left:{pos.x * 100}vw; top:{pos.y * 100}vh; transform:scale({scale})"
  class:rd-drag-armed={$REMOTE_OPEN}
  class:rd-draggable={$REMOTE_OPEN}
  use:draggable={{ panel: "plate", enabled: $REMOTE_OPEN }}
>
  <div class="rd-panel" class:rd-panel--off={!powered}>
    <div class="rd-head">
      <div class="rd-icon" class:rd-icon--off={!powered} class:rd-icon--alert={anyFlagged}>
        <i class="fas fa-camera"></i>
      </div>
      <span class="rd-title">Plate reader</span>

      <!-- Reserved whether or not a plate is armed, so arming one does not
           change the height of the panel. -->
      <span class="rd-badge rd-badge--red rd-bolo" style:visibility={$PLATES.bolo ? "visible" : "hidden"}>
        WATCH {$PLATES.bolo || ""}
      </span>
    </div>

    <div class="rd-body">
      {#each CAMS as c}
        {@const cam = $PLATES[c.id]}
        <div
          class="rd-cam"
          class:rd-cam--locked={cam.locked && !cam.flagged}
          class:rd-cam--flagged={cam.flagged}
        >
          <span class="rd-cam-name">{c.label}</span>

          <div class="rd-cam-body">
            {#if powered && cam.plate}
              <Plate plate={cam.plate} index={cam.index} />

              {#if cam.flagged}
                <span class="rd-badge rd-badge--red rd-hit">{summary(cam.hits) || cam.reason || "Flagged"}</span>
              {:else if cam.locked}
                <span class="rd-badge rd-badge--amber">Locked</span>
              {:else if cam.checked}
                <!-- An answered plate that came back clean says so. Without it
                     "no badge" means both "clean" and "still waiting". -->
                <span class="rd-badge rd-badge--green">Clear</span>
              {/if}
            {:else}
              <span class="rd-cam-empty">--------</span>
            {/if}
          </div>
        </div>
      {/each}
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
  .rd-bolo {
    margin-left: auto;
    max-width: 130px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .rd-hit {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
