<script lang="ts">
  import { onDestroy } from "svelte";
  /**
   * A single numeric window.
   *
   * The ghost layer underneath is the whole point: an instrument display shows
   * its unlit segments, and that one detail is what stops a number from
   * reading as ordinary text. It also fixes the layout for free — the field is
   * always as wide as its widest possible value, so a reading climbing from 9
   * to 100 does not shove the rest of the row sideways.
   */
  export let value: number | null = null;
  export let digits: number = 3;
  export let size: "lg" | "md" | "sm" = "md";
  export let state: "idle" | "live" | "hold" | "lock" | "patrol" | "test" | "roll" = "idle";
  /** Staggers the roll so the windows do not move in lockstep. */
  export let rollDelay: number = 0;

  const ghost = "8".repeat(digits);

  // No reading is not a zero. A dark window means the antenna has nothing,
  // which is a different fact from a vehicle measured at 0.
  // Digits tumbling upward. Driven from here rather than from CSS because the
  // characters themselves have to change, and a keyframe cannot count.
  let rolled = "";
  let rollTimer: ReturnType<typeof setInterval> | undefined;

  function startRoll() {
    stopRoll();
    let n = 0;
    const tick = () => {
      n += 1;
      // Each window climbs at its own rate, so the display looks like several
      // instruments waking up rather than one animation applied three times.
      const spread = 1 + (rollDelay % 3);
      rolled = String((n * spread * 37) % Math.pow(10, digits)).padStart(digits, "0");
    };
    tick();
    rollTimer = setInterval(tick, 55 + rollDelay * 11);
  }

  function stopRoll() {
    if (rollTimer) clearInterval(rollTimer);
    rollTimer = undefined;
  }

  $: if (state === "roll") startRoll();
    else stopRoll();

  onDestroy(stopRoll);

  // During a lamp test every segment is lit — that is the whole point of one,
  // and it is why the ghost layer exists in the first place.
  $: shown =
    state === "test"
      ? ghost
      : state === "roll"
        ? rolled
        : value === null || value === undefined
          ? ""
          : String(value);
  $: display = shown === "" ? "".padStart(digits, " ") : shown.padStart(digits, " ");
</script>

<span class="rd-seg rd-seg--{size} rd-seg--{state}" style="width:{digits}ch">
  <span class="rd-seg-ghost">{ghost}</span>
  <span class="rd-seg-value">{display}</span>
</span>