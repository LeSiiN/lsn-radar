<script lang="ts">
  import { SendNUI } from "@utils/SendNUI";
  import { RADAR, PLATES, CONFIG } from "@store/stores";
  import type { Unit, AntennaMode, Cam } from "@typings/type";

  let boloDraft = "";
  let boloTouched = false;

  // Mirror the armed plate into the field until the operator starts typing —
  // after that the draft is theirs and must not be overwritten by a state push.
  $: if (!boloTouched) boloDraft = $PLATES.bolo || "";

  $: s = $CONFIG.settings;
  $: limits = $CONFIG.limits;
  $: keys = $CONFIG.keys;

  const UNITS: Unit[] = ["kmh", "mph"];
  const SCALES = [0.7, 0.85, 1.0, 1.15, 1.4];

  const ANTENNAS: { id: Cam; label: string }[] = [
    { id: "front", label: "Front antenna" },
    { id: "rear", label: "Rear antenna" },
  ];

  // Spelled out rather than abbreviated. CLO/AWY/BTH saved eight pixels on the
  // display and cost the operator the meaning; the display now shows a single
  // arrow and the words live here, where there is room for them.
  const MODES: { id: AntennaMode; label: string; hint: string }[] = [
    { id: "closing", label: "Approaching", hint: "Only vehicles getting closer" },
    { id: "away", label: "Departing", hint: "Only vehicles getting further away" },
    { id: "both", label: "Both", hint: "Everything the antenna can measure" },
  ];

  function set(key: string, value: unknown) {
    SendNUI("setting", { key, value });
  }

  function close() {
    SendNUI("closeRemote", {});
  }

  function commitBolo() {
    SendNUI("setBolo", { plate: boloDraft.trim().toUpperCase() });
    boloTouched = false;
  }

  function clearBolo() {
    boloDraft = "";
    boloTouched = false;
    SendNUI("setBolo", { plate: "" });
  }

  function onBoloKey(e: KeyboardEvent) {
    if (e.key === "Enter") commitBolo();
    if (e.key === "Escape") {
      boloTouched = false;
      boloDraft = $PLATES.bolo || "";
    }
  }

  const KEY_LABELS: [string, string][] = [
    ["Remote", "Control panel"],
    ["KeyLock", "Key lock"],
    ["FrontAnt", "Front antenna XMIT/HOLD"],
    ["RearAnt", "Rear antenna XMIT/HOLD"],
    ["CopyFront", "Copy front plate"],
    ["CopyRear", "Copy rear plate"],
  ];

  const MDT_LABEL: Record<string, string> = {
    alert: "Plates are checked against the MDT and hits raise a dispatch card.",
    lookup: "Plates are checked against the MDT. Hits show here only, no dispatch card.",
    off: "MDT plate checks are switched off for this server.",
  };
</script>

<div class="rd-remote">
  <div class="rd-modal-head">
    <div class="rd-icon"><i class="fas fa-sliders"></i></div>
    <span class="rd-modal-title">Radar control</span>
    <button class="rd-ctl" on:click={close} aria-label="Close"><i class="fas fa-xmark"></i></button>
  </div>

  <div class="rd-modal-body rd-scroll">
    <!-- Power -->
    <div class="rd-row rd-row--between">
      <div>
        <div class="rd-form-label">Power</div>
        <div class="rd-form-hint">
          {#if s.autoPower}Comes up on its own next shift{:else}Off means off — the display hides too{/if}
        </div>
      </div>
      <button
        class="rd-toggle"
        class:rd-toggle--on={$RADAR.power}
        on:click={() => SendNUI("power", {})}
        aria-label="Toggle power"
      ></button>
    </div>

    <div class="rd-divider"></div>

    <!-- Antennas. These used to be buttons on the display itself; they are here
         now so the display can stay a fixed size. -->
    {#each ANTENNAS as a}
      {@const ant = $RADAR[a.id]}
      <div class="rd-form-group">
        <div class="rd-row rd-row--between">
          <span class="rd-form-label">{a.label}</span>
          {#if ant.lock}
            <!-- A locked antenna has one thing worth doing to it. The hold
                 toggle is meaningless until it is released, so it is not
                 offered. -->
            <button
              class="rd-btn rd-btn--red"
              style="padding:3px 9px;font-size:10px"
              on:click={() => SendNUI("clearLock", { cam: a.id })}
            ><i class="fas fa-lock-open"></i> Release lock</button>
          {:else}
            <button
              class="rd-btn"
              class:rd-btn--amber={!ant.xmit}
              style="padding:3px 9px;font-size:10px"
              disabled={!$RADAR.power}
              on:click={() => SendNUI("antenna", { cam: a.id })}
            >{ant.xmit ? "Transmitting" : "Holding"}</button>
          {/if}
        </div>

        <div class="rd-steps">
          {#each MODES as m}
            <button
              class="rd-step"
              class:rd-step--active={ant.mode === m.id}
              on:click={() => SendNUI("antenna", { cam: a.id, mode: m.id })}
            >{m.label}</button>
          {/each}
        </div>
        {#if ant.lock}
          <span class="rd-form-hint">
            Holding {ant.lock.plate || "a vehicle"} at {ant.lock.speed} {$RADAR.unit}{ant.lock.peak &&
            ant.lock.peak > ant.lock.speed
              ? ", peaked at " + ant.lock.peak
              : ""}. This antenna will not read anything else until released.
            {#if ant.lock.lost}Target is out of range — the reading is the last one taken.{/if}
          </span>
        {:else if !ant.xmit}
          <span class="rd-form-hint">
            {#if ($PLATES[a.id]?.hits?.length ?? 0) > 0 || $PLATES[a.id]?.flagged}
              Held by a plate check hit on {$PLATES[a.id]?.plate}. Resume to
              acknowledge it — the finding stays on the row either way.
            {:else}
              Holding {ant.strong?.plate || "the last reading"}. The plate is
              frozen with the speed, so the two still belong together.
            {/if}
          </span>
        {:else}
          <span class="rd-form-hint">
            {MODES.find((m) => m.id === ant.mode)?.hint}
          </span>
        {/if}
      </div>
    {/each}

    <span class="rd-form-hint">
      A radar antenna only measures movement along its own axis, so a vehicle
      crossing your path has no speed it could honestly report. Those are never
      shown, whichever filter is set.
    </span>

    <div class="rd-divider"></div>

    <!-- Units -->
    <div class="rd-form-group">
      <span class="rd-form-label">Units</span>
      <div class="rd-steps">
        {#each UNITS as u}
          <button
            class="rd-step"
            class:rd-step--active={$RADAR.unit === u}
            on:click={() => set("unit", u)}
          >{u.toUpperCase()}</button>
        {/each}
      </div>
    </div>

    <!-- Range -->
    <div class="rd-form-group">
      <div class="rd-row rd-row--between">
        <span class="rd-form-label">Antenna range</span>
        <button
          class="rd-btn"
          style="padding:3px 9px;font-size:10px"
          on:click={() => SendNUI("previewRange", {})}
        ><i class="fas fa-eye"></i> Show</button>
      </div>
      <div class="rd-row">
        <input
          class="rd-range"
          type="range"
          min={limits.minRange}
          max={limits.maxRange}
          step="10"
          value={s.range}
          on:input={(e) => set("range", +e.currentTarget.value)}
        />
        <span class="rd-range-value">{Math.round(s.range)} m</span>
      </div>
      <span class="rd-form-hint">
        Moving the slider draws the cone on the road in front of and behind you,
        so the number can be judged against real traffic. Shorter also means
        fewer line-of-sight checks per tick.
      </span>
    </div>

    {#if limits.fastLock}
      <div class="rd-divider"></div>

      <div class="rd-row rd-row--between">
        <div>
          <div class="rd-form-label">Automatic lock</div>
          <div class="rd-form-hint">Lock anything over the limit</div>
        </div>
        <button
          class="rd-toggle"
          class:rd-toggle--on={s.fastLock}
          on:click={() => set("fastLock", !s.fastLock)}
          aria-label="Toggle automatic lock"
        ></button>
      </div>

      {#if s.fastLock}
        <div class="rd-form-group">
          <span class="rd-form-label">Lock above</span>
          <div class="rd-row">
            <input
              class="rd-range"
              type="range"
              min="20"
              max={$RADAR.unit === "mph" ? 140 : 220}
              step="5"
              value={s.fastLimit}
              on:input={(e) => set("fastLimit", +e.currentTarget.value)}
            />
            <span class="rd-range-value">{s.fastLimit} {$RADAR.unit}</span>
          </div>
        </div>
      {/if}
    {/if}

    {#if limits.plates}
      <div class="rd-divider"></div>

      <div class="rd-row rd-row--between">
        <div>
          <div class="rd-form-label">Plate rows</div>
          <div class="rd-form-hint">Show plates under each antenna</div>
        </div>
        <button
          class="rd-toggle"
          class:rd-toggle--on={s.showPlate}
          on:click={() => set("showPlate", !s.showPlate)}
          aria-label="Toggle plate reader panel"
        ></button>
      </div>

      <span class="rd-form-hint">{MDT_LABEL[limits.mdtMode] ?? MDT_LABEL.off}</span>

      {#if limits.plateBolo}
        <div class="rd-form-group">
          <span class="rd-form-label">Watch plate</span>
          <div class="rd-row">
            <input
              class="rd-input"
              maxlength="8"
              placeholder="Plate to watch for"
              bind:value={boloDraft}
              on:input={() => (boloTouched = true)}
              on:keydown={onBoloKey}
              on:blur={commitBolo}
            />
            {#if $PLATES.bolo}
              <button class="rd-btn rd-btn--red" style="padding:6px 9px" on:click={clearBolo} aria-label="Clear watch plate">
                <i class="fas fa-xmark"></i>
              </button>
            {/if}
          </div>
          <span class="rd-form-hint">
            Your own note, for a plate the MDT has nothing on yet — the car that
            just made off, for instance. Real BOLOs are already caught by the
            MDT check above and need no entry here. One plate at a time.
          </span>
        </div>
      {/if}
    {/if}

    {#if limits.marker}
      <div class="rd-divider"></div>

      <div class="rd-row rd-row--between">
        <div>
          <div class="rd-form-label">Target bracket</div>
          <div class="rd-form-hint">Frame the vehicle being read</div>
        </div>
        <button
          class="rd-toggle"
          class:rd-toggle--on={s.marker}
          on:click={() => set("marker", !s.marker)}
          aria-label="Toggle target bracket"
        ></button>
      </div>

      <span class="rd-form-hint">
        White for an ordinary reading, red while an antenna is tracking. Marks
        the strong target only — two brackets in one cone puts you back to
        working out which is which.
      </span>
    {/if}

    <div class="rd-divider"></div>

    <!-- Sound. A toggle, not a slider: PlaySoundFrontend takes no gain
         parameter, so a percentage would have been a mute switch in disguise. -->
    <div class="rd-row rd-row--between">
      <div>
        <div class="rd-form-label">Sound</div>
        <div class="rd-form-hint">Locks, hits and scans</div>
      </div>
      <button
        class="rd-toggle"
        class:rd-toggle--on={s.sound}
        on:click={() => set("sound", !s.sound)}
        aria-label="Toggle sound"
      ></button>
    </div>

    <div class="rd-divider"></div>

    <div class="rd-form-group">
      <span class="rd-form-label">Interface scale</span>
      <div class="rd-steps">
        {#each SCALES as sc}
          <button
            class="rd-step"
            class:rd-step--active={Math.abs(s.scale - sc) < 0.01}
            disabled={sc < limits.minScale || sc > limits.maxScale}
            on:click={() => set("scale", sc)}
          >{Math.round(sc * 100)}%</button>
        {/each}
      </div>
      <span class="rd-form-hint">
        While this panel is open the radar can be dragged anywhere on screen.
        It is also visible while this panel is open even when switched off, so
        there is something to aim at.
      </span>
    </div>

    <button class="rd-btn" on:click={() => SendNUI("resetLayout", {})}>
      <i class="fas fa-rotate-left"></i> Reset layout
    </button>

    <div class="rd-divider"></div>

    <div class="rd-form-group">
      <span class="rd-form-label">Keys</span>
      <div class="rd-keys">
        {#each KEY_LABELS as [id, label]}
          <div class="rd-key-row">
            <span>{label}</span>
            <span class="rd-kbd">{keys[id] || "\u2014"}</span>
          </div>
        {/each}
      </div>
      <span class="rd-form-hint">Rebind under Settings &rarr; Key Bindings &rarr; FiveM.</span>
    </div>
  </div>
</div>