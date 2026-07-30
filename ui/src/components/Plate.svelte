<script lang="ts">
  export let plate: string;
  export let index: number | null | undefined = null;

  // GTA's plate designs, by the index the native reports. The order is not the
  // intuitive one — Blue on White 2 is index 0, Blue on White 1 is 3:
  //   0 Blue on White 2 · 1 Yellow on Black · 2 Yellow on Blue
  //   3 Blue on White 1 · 4 Blue on White 3 · 5 North Yankton
  //
  // Four images cover six designs, so the white variants share. Same table as
  // ps-dispatch uses; if a design comes out wrong in game, swapping the two
  // white names here fixes it in both places the same way.
  const ART: Record<number, string> = {
    0: "platewhite2",
    1: "plateblack",
    2: "plateblue",
    3: "platewhite",
    4: "platewhite",
    5: "platewhite2",
  };

  $: art = index === null || index === undefined ? null : ART[index];
</script>

{#if art}
  <!-- Set inline rather than in CSS: the NUI is served out of html/, so the
       path has to stay relative to index.html, and a url() in the stylesheet
       gets rewritten at build time. -->
  <span class="rd-plateart rd-plateart--{art}" style="background-image:url('./plates/{art}.png')">{plate}</span>
{:else}
  <span class="rd-plate">{plate}</span>
{/if}
