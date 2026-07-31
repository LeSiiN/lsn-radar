<script lang="ts">
  import AlwaysListener from "@providers/AlwaysListener.svelte";
  import Radar from "@components/Radar.svelte";
  import Handheld from "@components/Handheld.svelte";
  import Remote from "@components/Remote.svelte";
  import { SHOW_RADAR, REMOTE_OPEN, BROWSER_MODE, RESOURCE_NAME, HANDHELD } from "@store/stores";
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

<!-- The device in hand decides. Holding the gun takes precedence over the
     mounted radar, so a passenger who draws one does not end up with two speed
     displays disagreeing about which vehicle is being measured. -->
{#if $HANDHELD.active}
  <Handheld />
{:else if $SHOW_RADAR}
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
