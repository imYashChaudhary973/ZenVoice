/* ZenVoice v2 — Languages: explicit profiles, Hinglish modes, 64 languages */
"use strict";
window.Screens = window.Screens || {};

Screens.languages = {
  active: "English",

  html() {
    const profile = (label, sub, needsMulti) => `
      <button class="lang-chip${this.active === label ? " is-active" : ""}"
        data-profile="${esc(label)}" style="min-height:56px">
        <div>
          <div style="font:var(--text-label)">${esc(label)}
            ${needsMulti ? `<span class="badge" style="margin-left:6px">Multilingual model</span>` : ""}</div>
          <div class="t-caption">${esc(sub)}</div>
        </div>
        ${icon("check", "check")}
      </button>`;

    return `
      <div class="screen-head">
        <h1>Languages</h1>
        <p>Profiles are explicit — ZenVoice never silently switches what it writes.
           Set a different profile per app in App Profiles.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Active profile</h2></div>
        <div class="lang-grid" style="grid-template-columns:1fr 1fr">
          ${profile("English", "English-safe: never outputs another language")}
          ${profile("Hinglish", "Hindi–English the way you actually speak it", true)}
          ${profile("Auto-detect", "Detects the spoken language per dictation", true)}
        </div>
      </div>

      <div class="section" id="hinglish-modes" style="display:${this.active === "Hinglish" ? "" : "none"}">
        <div class="section-head"><h2>Hinglish output</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Script</div>
              <div class="row-sub">How mixed Hindi–English speech is written</div>
            </div>
            <div class="segmented" role="group" aria-label="Hinglish output mode">
              <button aria-pressed="true" data-value="latin">Latin script</button>
              <button aria-pressed="false" data-value="native">देवनागरी</button>
              <button aria-pressed="false" data-value="translate">English translation</button>
            </div>
          </div>
          <div class="row">
            <div class="row-main">
              <div class="row-sub" id="hinglish-sample" style="max-width:100%">
                “kal ka standup 10 baje shift kar do, please” — written exactly as spoken.
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>All languages</h2>
          <span class="t-caption">${DATA.languages.length} supported</span></div>
        <div class="stack-3">
          <div class="search-wrap">
            ${icon("search")}
            <input class="field" id="lang-search" type="search"
              placeholder="Search languages…" aria-label="Search languages">
          </div>
          <div class="lang-grid" id="lang-grid">
            ${DATA.languages.map(l => `
              <button class="lang-chip" data-lang="${esc(l)}">
                <span>${esc(l)}</span>${icon("check", "check")}
              </button>`).join("")}
          </div>
        </div>
      </div>

      <div class="banner banner-warn" id="lang-banner" style="display:${this.active === "English" ? "none" : "flex"}">
        ${icon("warn")}
        <p>Non-English profiles require the Multilingual model.
           <a href="#" data-go="models" style="color:inherit;font-weight:590">Download it in Models</a> —
           1.5 GB, checksum-verified.</p>
      </div>`;
  },

  bind(root) {
    root.querySelectorAll("[data-profile]").forEach(chip =>
      chip.addEventListener("click", () => {
        this.active = chip.dataset.profile;
        go("languages");
      }));

    root.querySelectorAll("[data-lang]").forEach(chip =>
      chip.addEventListener("click", () => {
        root.querySelectorAll("[data-lang]").forEach(c => c.classList.remove("is-active"));
        chip.classList.add("is-active");
        toast(`${chip.dataset.lang} selected — requires the Multilingual model`);
        root.querySelector("#lang-banner").style.display = "flex";
      }));

    const search = root.querySelector("#lang-search");
    search.addEventListener("input", () => {
      const q = search.value.trim().toLowerCase();
      root.querySelectorAll("#lang-grid .lang-chip").forEach(chip => {
        chip.style.display = chip.dataset.lang.toLowerCase().includes(q) ? "" : "none";
      });
    });

    const seg = root.querySelector(".segmented");
    if (seg) seg.addEventListener("zv-segment", e => {
      const sample = root.querySelector("#hinglish-sample");
      sample.textContent = {
        latin: "“kal ka standup 10 baje shift kar do, please” — written exactly as spoken.",
        native: "“कल का standup 10 बजे shift कर दो, please” — Hindi in Devanagari, English stays English.",
        translate: "“Please move tomorrow's standup to 10 o'clock” — translated locally, nothing sent anywhere.",
      }[e.detail.value];
    });
  },
};
