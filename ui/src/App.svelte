<script lang="ts">
  import AlwaysListener from "@providers/AlwaysListener.svelte";
  import Radar from "@components/Radar.svelte";
  import Remote from "@components/Remote.svelte";
  import { SHOW_RADAR, REMOTE_OPEN, BROWSER_MODE, RESOURCE_NAME } from "@store/stores";
  import { SendNUI } from "@utils/SendNUI";
  import { onMount } from "svelte";

  $RESOURCE_NAME = "lsn-radar";

  onMount(() => {
    const onKey = (e: KeyboardEvent) => {
      // Escape closes the control panel and hands focus back to the game. The
      // displays themselves have no focus to give up.
      if (e.code === "Escape" && $REMOTE_OPEN) SendNUI("closeRemote", {});
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });
</script>

<AlwaysListener />

{#if $SHOW_RADAR}
  <Radar />
{/if}

{#if $REMOTE_OPEN}
  <Remote />
{/if}

{#if $BROWSER_MODE}
  <div class="browser-bg"></div>
{/if}

<style>
  .browser-bg {
    position: fixed;
    inset: 0;
    z-index: -1;
    background: #2b2f36;
  }
</style>
