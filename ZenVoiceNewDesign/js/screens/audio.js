/* ZenVoice v2 — Audio: microphones + on-device Audio Doctor */
"use strict";
window.Screens = window.Screens || {};

Screens.audio = {
  doctor: "idle", // idle | running | passed | quiet

  html() {
    const devices = [
      { name: "MacBook Pro Microphone", detail: "Built-in · 48 kHz", active: true },
      { name: "AirPods Pro", detail: "Bluetooth · 24 kHz", active: false },
      { name: "Yeti Stereo Microphone", detail: "USB · 48 kHz", active: false },
    ];

    return `
      <div class="screen-head">
        <h1>Audio</h1>
        <p>Pick which microphone ZenVoice listens to, and test it without leaving
           this screen.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Input device</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Follow the system default</div>
              <div class="row-sub">ZenVoice switches automatically when macOS does.
                If a pinned mic disconnects mid-dictation, recording stops safely and
                anything captured goes to the Recovery Inbox.</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="followDefault"
              aria-label="Follow system default input"></button>
          </div>
          ${devices.map(d => `
            <div class="row is-clickable device-row" data-device="${esc(d.name)}">
              <div class="row-icon">${icon(d.name.includes("AirPods") ? "headphones" : "mic")}</div>
              <div class="row-main">
                <div class="row-title">${esc(d.name)}</div>
                <div class="row-sub">${esc(d.detail)}</div>
              </div>
              ${d.active
                ? `<span class="badge badge-accent">${icon("check")}In use</span>`
                : `<span class="t-caption">Pin</span>`}
            </div>`).join("")}
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Live level</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main" style="display:grid;gap:8px">
              <div class="row-title">MacBook Pro Microphone</div>
              <div class="level-track"><i id="live-level" style="width:32%"></i></div>
              <div class="row-sub">Speak normally — the bar should reach the middle.</div>
            </div>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Audio Doctor</h2>
          <span class="t-caption">3-second on-device check</span></div>
        <div class="panel">
          <div class="row" id="doctor-row">
            <div class="row-icon">${icon("stethoscope")}</div>
            <div class="row-main" id="doctor-main">
              <div class="row-title">Check signal and format</div>
              <div class="row-sub">Records three seconds locally, measures loudness,
                confirms the sample format, then deletes the clip.</div>
            </div>
            <button class="btn btn-secondary" id="doctor-run">Run check</button>
          </div>
          <div class="row" id="doctor-result" style="display:none"></div>
        </div>
      </div>`;
  },

  bind(root) {
    /* fake live level */
    const level = root.querySelector("#live-level");
    let t = 0;
    const tick = () => {
      if (!document.body.contains(level)) return;
      t += 0.4;
      const v = 22 + Math.abs(Math.sin(t)) * 34 + Math.random() * 8;
      level.style.width = (REDUCED_MOTION ? 40 : v) + "%";
      if (!REDUCED_MOTION) this._raf = setTimeout(tick, 120);
    };
    tick();

    /* pin devices */
    root.querySelectorAll(".device-row").forEach(row =>
      row.addEventListener("click", () =>
        toast(`Pinned ${row.dataset.device}`)));

    /* audio doctor */
    const runBtn = root.querySelector("#doctor-run");
    const result = root.querySelector("#doctor-result");
    runBtn.addEventListener("click", () => {
      runBtn.classList.add("is-loading");
      result.style.display = "";
      result.innerHTML = `
        <div class="row-main" style="display:grid;gap:8px">
          <div class="row-title">Listening…</div>
          <div class="doctor-meter" id="doctor-meter">
            ${Array.from({ length: 28 }, () => "<i></i>").join("")}
          </div>
        </div>`;
      const bars = result.querySelectorAll("#doctor-meter i");
      const anim = setInterval(() => {
        bars.forEach(b => b.style.height = (3 + Math.random() * 30) + "px");
      }, REDUCED_MOTION ? 999999 : 90);

      setTimeout(() => {
        clearInterval(anim);
        runBtn.classList.remove("is-loading");
        result.innerHTML = `
          <div class="row-main" style="display:grid;gap:6px">
            <div class="hstack"><span class="badge badge-success">${icon("check")}Signal healthy</span>
              <span class="badge badge-success">${icon("check")}Format 48 kHz · Float32</span></div>
            <div class="row-sub">Peak −14 dBFS · noise floor −62 dBFS. Test clip deleted.</div>
          </div>
          <button class="btn btn-ghost btn-sm" id="doctor-again">Run again</button>`;
        result.querySelector("#doctor-again").addEventListener("click", () => runBtn.click());
      }, 3000);
    });
  },
};
