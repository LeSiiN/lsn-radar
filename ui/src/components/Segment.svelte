<script lang="ts">
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
  export let state: "idle" | "live" | "hold" | "lock" | "patrol" = "idle";

  const ghost = "8".repeat(digits);

  // No reading is not a zero. A dark window means the antenna has nothing,
  // which is a different fact from a vehicle measured at 0.
  $: shown = value === null || value === undefined ? "" : String(value);
  $: display = shown === "" ? "".padStart(digits, " ") : shown.padStart(digits, " ");
</script>

<span class="rd-seg rd-seg--{size} rd-seg--{state}" style="width:{digits}ch">
  <span class="rd-seg-ghost">{ghost}</span>
  <span class="rd-seg-value">{display}</span>
</span>
