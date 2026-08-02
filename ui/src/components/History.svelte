<script lang="ts">
  import Plate from "@components/Plate.svelte";
  import Segment from "@components/Segment.svelte";
  import { SendNUI } from "@utils/SendNUI";
  import { HISTORY } from "@store/stores";
  import type { HistoryEntry } from "@typings/type";

  $: entries = $HISTORY.entries ?? [];

  // Which row was just copied, for the confirmation. Same reasoning as the
  // plate copy: the clipboard is invisible, so a copy with no acknowledgement
  // leaves the officer pressing it twice and none the wiser either time.
  let copied: number | null = null;
  let copyTimer: ReturnType<typeof setTimeout>;

  const SOURCE_LABEL: Record<string, string> = {
    front: "Front",
    rear: "Rear",
    gun: "Gun",
  };

  const SOURCE_ICON: Record<string, string> = {
    front: "fa-arrow-up",
    rear: "fa-arrow-down",
    gun: "fa-gauge-high",
  };

  /**
   * One line, ready to paste into a report.
   *
   * This is the whole point of the panel. The gap it closes is not "I cannot
   * see my old readings" — it is that turning a reading into a citation meant
   * retyping a speed and eight plate characters off a screenshot, which is
   * where transcription errors come from.
   *
   * The peak is only included when it differs from the locked reading, because
   * on a stationary measurement the two are the same number and printing it
   * twice reads as a mistake.
   */
  function reportLine(e: HistoryEntry): string {
    const parts = [`${e.speed} ${e.unit}`];
    if (e.peak > e.speed) parts.push(`peak ${e.peak} ${e.unit}`);
    if (e.plate) parts.push(`plate ${e.plate}`);
    parts.push(`${SOURCE_LABEL[e.source] ?? e.source} antenna`);
    parts.push(`at ${e.clock}`);
    return parts.join(", ");
  }

  function copy(e: HistoryEntry) {
    try {
      // Hidden textarea and execCommand: CEF refuses navigator.clipboard
      // inside a NUI, and this display has no focus to satisfy its permission
      // check anyway.
      const field = document.createElement("textarea");
      field.value = reportLine(e);
      field.style.cssText = "position:fixed;opacity:0;pointer-events:none;";
      document.body.appendChild(field);
      field.select();
      document.execCommand("copy");
      field.remove();
    } catch {
      return;
    }

    copied = e.id;
    clearTimeout(copyTimer);
    copyTimer = setTimeout(() => (copied = null), 1600);
  }

  /** How long ago, in words. A clock time alone does not say whether a reading
   *  is from this stop or from before lunch. */
  function age(epoch: number): string {
    const mins = Math.floor((Date.now() / 1000 - epoch) / 60);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    return `${hrs}h ago`;
  }
</script>

{#if entries.length === 0}
  <div class="rd-hist-empty">
    <i class="fas fa-clock-rotate-left"></i>
    <span>No readings yet.</span>
    <span class="rd-hist-empty-hint">
      Every lock is recorded here, from both the antennas and the gun.
    </span>
  </div>
{:else}
  <div class="rd-hist">
    {#each entries as e (e.id)}
      <div class="rd-hist-row" class:rd-hist-row--copied={copied === e.id}>
        <div class="rd-hist-main">
          <Segment value={e.speed} size="md" state="lock" />
          <span class="rd-hist-unit">{e.unit}</span>

          <div class="rd-hist-meta">
            <!-- The peak earns its place only when the target was faster at
                 some point than it was when locked. -->
            {#if e.peak > e.speed}
              <span class="rd-badge rd-badge--amber">Peak {e.peak}</span>
            {/if}
            {#if e.auto}
              <span class="rd-badge rd-badge--blue" title="Locked automatically">A</span>
            {/if}
          </div>

          <button
            class="rd-ctl rd-hist-copy"
            class:rd-hist-copy--done={copied === e.id}
            on:click={() => copy(e)}
            aria-label="Copy for report"
          >
            <i class="fas {copied === e.id ? 'fa-check' : 'fa-clipboard'}"></i>
          </button>

          <button
            class="rd-ctl rd-ctl--alert"
            on:click={() => SendNUI("removeHistory", { id: e.id })}
            aria-label="Remove entry"
          ><i class="fas fa-xmark"></i></button>
        </div>

        <div class="rd-hist-sub">
          {#if e.plate}
            <Plate plate={e.plate} index={e.index} />
          {:else}
            <span class="rd-hist-noplate">No plate read</span>
          {/if}

          <span class="rd-hist-source">
            <i class="fas {SOURCE_ICON[e.source] ?? 'fa-gauge-high'}"></i>
            {SOURCE_LABEL[e.source] ?? e.source}
          </span>

          <span class="rd-hist-time" title={age(e.epoch)}>{e.clock}</span>
        </div>
      </div>
    {/each}
  </div>

  <button class="rd-btn rd-btn--red" on:click={() => SendNUI("clearHistory", {})}>
    <i class="fas fa-trash"></i> Clear history
  </button>
{/if}
