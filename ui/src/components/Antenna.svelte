<script lang="ts">
  import Segment from "@components/Segment.svelte";
  import Plate from "@components/Plate.svelte";
  import type { Antenna, Camera, Cam } from "@typings/type";
  import { COPIED } from "@store/stores";

  export let cam: Cam;
  export let data: Antenna;
  export let camera: Camera | null = null;
  export let powered: boolean = false;
  export let selfTest: "lamps" | "sweep" | "antennas" | "ready" | null = null;
  /** Which antenna the `antennas` phase is currently on. */
  export let antennaStep: number = 0;
  export let showPlate: boolean = true;

  // One block per side, carrying everything that side knows: the antenna that
  // measures the speed and the camera that reads the plate. They were two
  // separate panels, which meant an officer comparing a speed to a plate was
  // reading two boxes and trusting that the front row of one lined up with the
  // front row of the other. Front is front.
  //
  // Everything optional is rendered and hidden with `visibility` rather than
  // removed from the flow, so nothing here can change the panel's height.

  $: held = powered && !data.xmit;
  $: locked = powered && !!data.lock;
  $: readingState = (held ? "hold" : "live") as "hold" | "live";

  // The self test overrides every window at once. Computed here rather than
  // per window so the three cannot disagree about which phase is running.
  //
  // `antennas` walks the two blocks in turn, so each one has to know whether
  // its own turn has come — front first, because that is the order they are
  // listed in and the order an operator reads them.
  $: testing = selfTest === "lamps";
  $: rolling = selfTest === "sweep";
  $: marching = selfTest === "antennas";
  $: myTurn = marching && (cam === "front" ? antennaStep === 0 : antennaStep === 1);
  $: zeroed = selfTest === "ready";
  $: booting = !!selfTest;

  // Computed here rather than with {@const} in the markup: that directive is
  // only allowed as the immediate child of a block construct, and these sit
  // inside plain divs.
  type Win = {
    value: number | null;
    state: "idle" | "live" | "hold" | "lock" | "test" | "roll";
  };

  function win(value: number | null | undefined, live: "live" | "hold" | "lock"): Win {
    if (testing) return { value: null, state: "test" };
    if (rolling) return { value: null, state: "roll" };
    if (marching) return myTurn ? { value: null, state: "test" } : { value: null, state: "idle" };
    if (zeroed) return { value: 0, state: "live" };
    if (value == null) return { value: null, state: "idle" };
    return { value, state: live };
  }

  $: strongWin = win(powered ? data.strong?.speed : null, readingState);
  $: fastWin = win(powered ? data.fast?.speed : null, readingState);
  $: lockWin = win(locked ? data.lock?.speed : null, "lock");
  $: showPeak = locked && !!data.lock?.peak && (data.lock?.peak ?? 0) > (data.lock?.speed ?? 0);

  // A pinned camera is being held because this antenna locked the vehicle, so
  // the plate on screen is the plate the speed belongs to.
  $: pinned = !!camera?.pinned;

  const MODE_MARK: Record<string, string> = {
    closing: "\u25B2",
    away: "\u25BC",
    both: "\u21C5",
  };

  const arrow = (dir?: string) => (dir === "closing" ? "\u25B2" : "\u25BC");

  // The reason deliberately does not appear here. ps-mdt already raises a
  // dispatch card carrying the full text, and repeating it in a 90px slot means
  // showing "OWNER HAS NO DRIVER L..." — which is worse than showing nothing,
  // because it looks like information while being unreadable.
  //
  // What the row owes the operator is that there *is* a hit and roughly how bad
  // it is. The card says what.
  $: hitCount = camera?.hits?.length ?? 0;
  $: critical = camera?.severity === "critical";
  // A match on the operator's own watch plate is a different fact from an MDT
  // record, and it is the one thing here the dispatch card will not mention —
  // nobody else knows this plate was being watched. It gets its own marker.
  // Two different facts, and they used to share one flag. `flagged` is "this is
  // demanding attention right now" and drives the red block; the badge is what
  // the MDT found, which stays true after the officer has acknowledged it.
  // Keyed together, acknowledging a hit turned the row green and said "Clear".
  $: watchHit = hitCount === 0 && camera?.reason === "WATCH";

  // A tick in the corner was too quiet for something triggered by a key press
  // the operator cannot see the result of anywhere else. The confirmation now
  // takes the whole row and names the plate it put on the clipboard.
  $: copied = $COPIED && $COPIED.cam === cam ? $COPIED : null;
</script>

<div
  class="rd-ant"
  class:rd-ant--locked={locked}
  class:rd-ant--hold={held && !locked}
  class:rd-ant--flagged={camera?.flagged}
>
  <div class="rd-ant-head">
    <span
      class="rd-dot"
      class:rd-dot--xmit={(powered && data.xmit) || (booting && !marching)}
      class:rd-dot--hold={held}
      class:rd-dot--test={myTurn}
    ></span>
    <span class="rd-ant-name">{cam}</span>

    {#if booting}
      <span class="rd-badge" class:rd-badge--green={myTurn} class:rd-badge--blue={!myTurn}>
        {myTurn ? "OK" : "TEST"}
      </span>
      <span class="rd-ant-mode">&nbsp;</span>
    {:else if locked}
      <span class="rd-badge rd-badge--red">LOCK</span>
      <span class="rd-ant-mode rd-track" class:rd-stale={data.lock?.lost}>
        {data.lock?.lost ? "\u26A0" : "\u25CF"}
      </span>
    {:else}
      <span
        class="rd-badge"
        class:rd-badge--amber={held}
        class:rd-badge--blue={powered && data.xmit}
        style:visibility={powered ? "visible" : "hidden"}
      >{data.xmit ? "XMIT" : "HOLD"}</span>

      <span class="rd-ant-mode" style:visibility={powered ? "visible" : "hidden"}>
        {MODE_MARK[data.mode] ?? MODE_MARK.both}
      </span>
    {/if}
  </div>

  <div class="rd-windows">
    <div class="rd-win rd-win--strong">
      <span class="rd-win-label">
        Strong
        <span class="rd-dir" style:visibility={powered && data.strong ? "visible" : "hidden"}>
          {arrow(data.strong?.dir)}
        </span>
      </span>
      <Segment value={strongWin.value} size="lg" state={strongWin.state} rollDelay={0} />
    </div>

    <div class="rd-win">
      <span class="rd-win-label">
        Fast
        <span class="rd-dir" style:visibility={powered && data.fast ? "visible" : "hidden"}>
          {arrow(data.fast?.dir)}
        </span>
      </span>
      <Segment value={fastWin.value} size="md" state={fastWin.state} rollDelay={1} />
    </div>

    <div class="rd-win">
      <span class="rd-win-label rd-win-label--lock">
        {#if showPeak}Peak {data.lock?.peak}{:else}Lock{/if}
        <span class="rd-dir" style:visibility={locked && data.lock?.auto ? "visible" : "hidden"}>A</span>
      </span>
      <Segment value={lockWin.value} size="md" state={lockWin.state} rollDelay={2} />
    </div>
  </div>

  {#if showPlate}
    <div class="rd-plate-row" class:rd-plate-row--pinned={pinned} class:rd-plate-row--copied={!!copied}>
      {#if booting}
        <span class="rd-boot-line" class:rd-boot-line--done={zeroed}>
          {#if testing}LAMP TEST
          {:else if rolling}CALIBRATING
          {:else if marching}{myTurn ? "ANTENNA OK" : "STANDBY"}
          {:else}READY{/if}
        </span>
      {:else if copied}
        <span class="rd-copied">
          <i class="fas fa-clipboard-check"></i>
          <span class="rd-copied-label">Copied</span>
          <span class="rd-copied-plate">{copied.plate}</span>
        </span>
      {:else if powered && camera?.plate}
        <Plate plate={camera.plate} index={camera.index} />

        <div class="rd-plate-meta">
          {#if watchHit}
            <span class="rd-badge rd-badge--red rd-hit" aria-label="Your watch plate">
              <i class="fas fa-eye"></i>
            </span>
          {:else if hitCount > 0}
            <span class="rd-badge rd-hit" class:rd-badge--red={critical} class:rd-badge--amber={!critical}>
              <i class="fas fa-triangle-exclamation"></i>
              {#if hitCount > 1}{hitCount}{/if}
            </span>
          {:else if camera.checked}
            <span class="rd-badge rd-badge--green">Clear</span>
          {:else}
            <span class="rd-badge">Checking</span>
          {/if}
        </div>

        <!-- Pinned means this plate is held because the antenna beside it
             locked the vehicle. Without the marker a held plate and a plate
             that merely happens to still be in view look identical. -->
        <span class="rd-pin" style:visibility={pinned ? "visible" : "hidden"} aria-label="Held with the lock">
          <i class="fas fa-thumbtack"></i>
        </span>
      {:else}
        <span class="rd-cam-empty">--------</span>
      {/if}
    </div>
  {/if}
</div>

<style>
  /* Red only while tracking. This used to colour the direction glyph as well,
     because a scoped rule outranks the global one on specificity — so an idle
     antenna showed its filter marker in the colour this interface reserves for
     a lock. */
  .rd-track {
    color: rgba(248, 113, 113, 0.85);
  }
  .rd-track.rd-stale {
    color: rgba(251, 191, 36, 0.9);
  }
  .rd-hit {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
  }
</style>