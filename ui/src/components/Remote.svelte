<script lang="ts">
  import { SendNUI } from "@utils/SendNUI";
  import { RADAR, PLATES, CONFIG, HANDHELD } from "@store/stores";
  import type { Unit, AntennaMode, Cam } from "@typings/type";

  // Three tabs, not two. Units, sound, key reference and the interface scale
  // belong to neither device on its own, and filing them under one of them
  // would mean an officer looking for the volume control has to remember which
  // half it landed in.
  //
  // The tab opens on whichever device is actually in hand, because that is
  // overwhelmingly the one being adjusted.
  type Tab = "vehicle" | "gun" | "general";
  let tab: Tab = "vehicle";
  let touched = false;

  $: if (!touched && $HANDHELD.active) tab = "gun";

  let body: HTMLElement;

  function pick(next: Tab) {
    if (next === tab) return;
    tab = next;
    // From here the operator's choice wins — auto-switching under someone who
    // is mid-adjustment is worse than opening on the wrong tab.
    touched = true;

    // A new tab starts at the top. Carrying the old scroll position across
    // drops the operator into the middle of a list they have not seen, and on
    // a shorter tab it looks like content is missing above.
    if (body) body.scrollTop = 0;
  }

  let watchDraft = "";
  let listOpen = false;

  $: s = $CONFIG.settings;
  $: limits = $CONFIG.limits;
  $: keys = $CONFIG.keys;
  $: watchList = $PLATES.watch ?? [];
  $: watchFull = watchList.length >= (limits.maxWatch ?? 20);

  const UNITS: Unit[] = ["kmh", "mph"];
  const SCALES = [0.7, 0.85, 1.0, 1.15, 1.4];

  const ANTENNAS: { id: Cam; label: string }[] = [
    { id: "front", label: "Front antenna" },
    { id: "rear", label: "Rear antenna" },
  ];

  const MODES: { id: AntennaMode; label: string; hint: string }[] = [
    { id: "closing", label: "Approaching", hint: "Only vehicles getting closer" },
    { id: "away", label: "Departing", hint: "Only vehicles getting further away" },
    { id: "both", label: "Both", hint: "Everything the antenna can measure" },
  ];

  const CONE_LABELS = ["Narrow", "Normal", "Wide"];
  $: coneOptions = (limits.gunCones ?? []).map((a, i) => ({
    angle: a,
    label: CONE_LABELS[i] ?? String(a),
  }));

  const KEY_LABELS: [string, string][] = [
    ["Remote", "Control panel"],
    ["KeyLock", "Key lock"],
    ["FrontAnt", "Front antenna hold / release"],
    ["RearAnt", "Rear antenna hold / release"],
    ["CopyFront", "Copy front plate"],
    ["CopyRear", "Copy rear plate"],
  ];

  const MDT_LABEL: Record<string, string> = {
    alert: "Plates are checked against the MDT and hits raise a dispatch card.",
    lookup: "Plates are checked against the MDT. Hits show here only, no dispatch card.",
    off: "MDT plate checks are switched off for this server.",
  };

  function set(key: string, value: unknown) {
    SendNUI("setting", { key, value });
  }

  function addWatch() {
    const plate = watchDraft.trim().toUpperCase();
    if (!plate) return;
    SendNUI("addWatch", { plate });
    watchDraft = "";
  }

  function onWatchKey(e: KeyboardEvent) {
    if (e.key === "Enter") addWatch();
    if (e.key === "Escape") watchDraft = "";
  }
</script>

<div class="rd-remote">
  <div class="rd-modal-head">
    <div class="rd-icon"><i class="fas fa-sliders"></i></div>
    <span class="rd-modal-title">Radar control</span>
    <button class="rd-ctl" on:click={() => SendNUI("closeRemote", {})} aria-label="Close">
      <i class="fas fa-xmark"></i>
    </button>
  </div>

  <div class="rd-tabs">
    <button class="rd-tab" class:rd-tab--active={tab === "vehicle"} on:click={() => pick("vehicle")}>
      <i class="fas fa-car"></i> Vehicle
      {#if $RADAR.power && !$HANDHELD.active}<span class="rd-tab-dot"></span>{/if}
    </button>

    {#if limits.gun}
      <button class="rd-tab" class:rd-tab--active={tab === "gun"} on:click={() => pick("gun")}>
        <i class="fas fa-gauge-high"></i> Gun
        {#if $HANDHELD.active}<span class="rd-tab-dot"></span>{/if}
      </button>
    {/if}

    <button class="rd-tab" class:rd-tab--active={tab === "general"} on:click={() => pick("general")}>
      <i class="fas fa-gear"></i> General
    </button>
  </div>

  <div class="rd-modal-body rd-scroll" bind:this={body}>
    {#if tab === "vehicle"}
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

      {#each ANTENNAS as a}
        {@const ant = $RADAR[a.id]}
        <div class="rd-form-group">
          <div class="rd-row rd-row--between">
            <span class="rd-form-label">{a.label}</span>
            {#if ant.lock}
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
              ant.lock.peak > ant.lock.speed ? ", peaked at " + ant.lock.peak : ""}. This antenna
              will not read anything else until released.
              {#if ant.lock.lost}Target is out of range — the reading is the last one taken.{/if}
            </span>
          {:else if !ant.xmit}
            <span class="rd-form-hint">
              {#if ($PLATES[a.id]?.hits?.length ?? 0) > 0 || $PLATES[a.id]?.flagged}
                Held by a plate check hit on {$PLATES[a.id]?.plate}. Resume to acknowledge it —
                the finding stays on the row either way.
              {:else}
                Holding {ant.strong?.plate || "the last reading"}. The plate is frozen with the
                speed, so the two still belong together.
              {/if}
            </span>
          {:else}
            <span class="rd-form-hint">{MODES.find((m) => m.id === ant.mode)?.hint}</span>
          {/if}
        </div>
      {/each}

      <span class="rd-form-hint">
        A radar antenna only measures movement along its own axis, so a vehicle crossing your
        path has no speed it could honestly report. Those are never shown, whichever filter is set.
      </span>

      <div class="rd-divider"></div>

      <div class="rd-form-group">
        <div class="rd-row rd-row--between">
          <span class="rd-form-label">Antenna range</span>
          <button class="rd-btn" style="padding:3px 9px;font-size:10px" on:click={() => SendNUI("previewRange", {})}>
            <i class="fas fa-eye"></i> Show
          </button>
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
          Moving the slider draws the cone on the road in front of and behind you.
        </span>
      </div>

      {#if limits.fastLock}
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
                min={limits.limitMin}
                max={limits.limitMax}
                step="5"
                value={s.fastLimit}
                on:input={(e) => set("fastLimit", +e.currentTarget.value)}
              />
              <span class="rd-range-value">{s.fastLimit} {$RADAR.unit}</span>
            </div>
            <span class="rd-form-hint">Between {limits.limitMin} and {limits.limitMax} {$RADAR.unit}.</span>
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
            aria-label="Toggle plate rows"
          ></button>
        </div>
      {/if}

      <div class="rd-form-group">
        <span class="rd-form-label">Display scale</span>
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
        </span>
      </div>

    {:else if tab === "gun"}
      <div class="rd-row rd-row--between">
        <span class="rd-form-label">Status</span>
        <span class="rd-badge" class:rd-badge--blue={$HANDHELD.active}>
          {$HANDHELD.active ? "In hand" : "Stowed"}
        </span>
      </div>

      <div class="rd-form-group">
        <span class="rd-form-label">Beam width</span>
        <div class="rd-steps">
          {#each coneOptions as c}
            <button
              class="rd-step"
              class:rd-step--active={Math.abs((s.gunCone ?? 0) - c.angle) < 0.01}
              on:click={() => set("gunCone", c.angle)}
            >{c.label}</button>
          {/each}
        </div>
        <span class="rd-form-hint">
          Narrow separates cars in dense traffic; wide is easier to hold on a target at distance.
        </span>
      </div>

      <div class="rd-form-group">
        <span class="rd-form-label">Range</span>
        <div class="rd-row">
          <input
            class="rd-range"
            type="range"
            min={limits.gunMinRange}
            max={limits.gunMaxRange}
            step="10"
            value={s.gunRange}
            on:input={(e) => set("gunRange", +e.currentTarget.value)}
          />
          <span class="rd-range-value">{Math.round(s.gunRange ?? 0)} m</span>
        </div>
        <span class="rd-form-hint">
          Past roughly 300m there is nothing to find — the game only keeps vehicles loaded that far.
        </span>
      </div>

      <div class="rd-divider"></div>

      <div class="rd-row rd-row--between">
        <div>
          <div class="rd-form-label">Automatic lock</div>
          <div class="rd-form-hint">Locks the moment a reading passes the limit</div>
        </div>
        <button
          class="rd-toggle"
          class:rd-toggle--on={s.gunAutoLock}
          on:click={() => set("gunAutoLock", !s.gunAutoLock)}
          aria-label="Toggle gun auto-lock"
        ></button>
      </div>

      {#if s.gunAutoLock}
        <div class="rd-form-group">
          <span class="rd-form-label">Lock above</span>
          <div class="rd-row">
            <input
              class="rd-range"
              type="range"
              min={limits.gunLimitMin}
              max={limits.gunLimitMax}
              step="5"
              value={s.gunLimit}
              on:input={(e) => set("gunLimit", +e.currentTarget.value)}
            />
            <span class="rd-range-value">{s.gunLimit} {$RADAR.unit}</span>
          </div>
          <span class="rd-form-hint">
            Its own limit, {limits.gunLimitMin}–{limits.gunLimitMax} {$RADAR.unit}. Unlike the
            antennas this does not skip NPC traffic: you aimed at it.
          </span>
        </div>
      {/if}

      <div class="rd-divider"></div>

      <div class="rd-form-group">
        <span class="rd-form-label">Display scale</span>
        <div class="rd-steps">
          {#each SCALES as sc}
            <button
              class="rd-step"
              class:rd-step--active={Math.abs((s.gunScale ?? 1) - sc) < 0.01}
              disabled={sc < limits.minScale || sc > limits.maxScale}
              on:click={() => set("gunScale", sc)}
            >{Math.round(sc * 100)}%</button>
          {/each}
        </div>
        <span class="rd-form-hint">Its position is stored separately from the mounted radar.</span>
      </div>

    {:else}
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
        <span class="rd-form-hint">
          Switching moves both lock limits to this unit's default, so nobody ends up with a
          130 mph trigger by accident.
        </span>
      </div>

      <div class="rd-divider"></div>

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

      {#if limits.marker}
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
      {/if}

      {#if limits.plates}
        <div class="rd-divider"></div>
        <span class="rd-form-hint">{MDT_LABEL[limits.mdtMode] ?? MDT_LABEL.off}</span>

        {#if limits.watchlist}
          <div class="rd-form-group">
            <span class="rd-form-label">Watch plates</span>
            <div class="rd-row">
              <input
                class="rd-input"
                maxlength="8"
                placeholder={watchFull ? "List is full" : "Add a plate"}
                disabled={watchFull}
                bind:value={watchDraft}
                on:keydown={onWatchKey}
              />
              <button
                class="rd-btn"
                style="padding:6px 9px"
                disabled={watchFull || !watchDraft.trim()}
                on:click={addWatch}
                aria-label="Add plate"
              ><i class="fas fa-plus"></i></button>
              <button
                class="rd-btn"
                class:rd-btn--amber={listOpen}
                style="padding:6px 9px"
                on:click={() => (listOpen = !listOpen)}
                aria-label="Show watch list"
              >
                <i class="fas fa-list"></i>
                {#if watchList.length > 0}<span class="rd-count">{watchList.length}</span>{/if}
              </button>
            </div>

            {#if listOpen}
              <div class="rd-watchlist rd-scroll">
                {#each watchList as plate (plate)}
                  <div class="rd-watch-row">
                    <span class="rd-watch-plate">{plate}</span>
                    <button
                      class="rd-ctl rd-ctl--alert"
                      on:click={() => SendNUI("removeWatch", { plate })}
                      aria-label={"Remove " + plate}
                    ><i class="fas fa-xmark"></i></button>
                  </div>
                {:else}
                  <div class="rd-watch-empty">Nothing on the list.</div>
                {/each}
              </div>

              {#if watchList.length > 0}
                <button class="rd-btn rd-btn--red" on:click={() => SendNUI("clearWatch", {})}>
                  <i class="fas fa-trash"></i> Clear all
                </button>
              {/if}
            {/if}

            <span class="rd-form-hint">
              Your own list, for plates the MDT has nothing on yet. Real BOLOs need no entry —
              the MDT check catches those on its own. Up to {limits.maxWatch ?? 20}.
            </span>
          </div>
        {/if}
      {/if}

      <div class="rd-divider"></div>

      <button class="rd-btn" on:click={() => SendNUI("resetLayout", {})}>
        <i class="fas fa-rotate-left"></i> Reset layout
      </button>

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
    {/if}
  </div>
</div>