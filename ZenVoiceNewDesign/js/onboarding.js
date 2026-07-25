/* ZenVoice v2 — first-run onboarding: full-window, 7 steps, resumable, replayable */
"use strict";

const Onboarding = {
  el: null,
  step: 0,
  state: {
    mic: false, ax: false,
    shortcut: ["⌃", "⌥", "␣"],
    language: "English",
    modelProgress: null, // null | 0-100 | "done"
    tested: false,
  },

  steps: ["welcome", "privacy", "permissions", "shortcut", "language", "model", "test"],

  start() {
    this.el = document.getElementById("onboarding");
    this.step = ZV.pref("onboardingStep", 0);
    this.el.hidden = false;
    this.render();
  },

  finish(skipped) {
    ZV.setPref("onboarded", true);
    ZV.setPref("onboardingStep", 0);
    this.el.hidden = true;
    toast(skipped ? "You can replay setup from Help & FAQ" : "You're all set — try ⌃⌥Space anywhere", "checkCircle");
  },

  move(delta) {
    this.step = Math.max(0, Math.min(this.steps.length - 1, this.step + delta));
    ZV.setPref("onboardingStep", this.step);
    this.render();
  },

  render() {
    const name = this.steps[this.step];
    const last = this.step === this.steps.length - 1;
    const dots = this.steps.map((_, i) =>
      `<i class="${i < this.step ? "is-done" : i === this.step ? "is-current" : ""}"></i>`).join("");

    this.el.innerHTML = `
      <div class="ob-top">
        <div class="hstack" style="gap:8px">
          <div class="side-brand" style="padding:0">
            <div class="logo" style="width:24px;height:24px;border-radius:7px">${icon("waveform")}</div>
          </div>
          <b style="font:var(--text-label)">ZenVoice</b>
        </div>
        <div class="ob-progress" aria-label="Step ${this.step + 1} of ${this.steps.length}">${dots}</div>
      </div>
      <div class="ob-body"><div class="ob-card">${this["step_" + name]()}</div></div>
      <div class="ob-foot">
        <button class="btn btn-ghost" id="ob-skip">Skip setup</button>
        <span class="spacer"></span>
        ${this.step > 0 ? `<button class="btn btn-secondary btn-lg" id="ob-back">Back</button>` : ""}
        <button class="btn btn-primary btn-lg" id="ob-next">
          ${last ? "Start using ZenVoice" : "Continue"}</button>
      </div>`;

    postRender(this.el);
    this.el.querySelector("#ob-skip").addEventListener("click", () => this.finish(true));
    const back = this.el.querySelector("#ob-back");
    if (back) back.addEventListener("click", () => this.move(-1));
    this.el.querySelector("#ob-next").addEventListener("click", () =>
      last ? this.finish(false) : this.move(1));
    this["bind_" + name] && this["bind_" + name]();
  },

  fact(iconName, title, sub) {
    return `<div class="ob-fact">${icon(iconName)}
      <div><b>${esc(title)}</b><span>${esc(sub)}</span></div></div>`;
  },

  /* ---- 1 · welcome ---- */
  step_welcome() {
    return `
      <div class="icon-hero">${icon("waveform")}</div>
      <h1>Speak. It types. Nothing leaves your Mac.</h1>
      <p>ZenVoice turns speech into text on this Mac and inserts it wherever your
         cursor is — in any app.</p>
      <div class="panel">
        ${this.fact("cloudOff", "No account, no cloud", "Transcription runs entirely on-device.")}
        ${this.fact("zap", "One shortcut, everywhere", "Dictate into Mail, Slack, Xcode — anything with a cursor.")}
        ${this.fact("lock", "Encrypted local history", "Recover any dictation, even partial ones.")}
      </div>`;
  },
  bind_welcome() {},

  /* ---- 2 · privacy ---- */
  step_privacy() {
    return `
      <div class="icon-hero">${icon("shieldCheck")}</div>
      <h1>Local-first by design.</h1>
      <p>Audio, transcripts, correction rules, insights, and model inference stay
         on this Mac. The only network use is model downloads you ask for.</p>
      <div class="panel">
        ${this.fact("key", "Transcripts are encrypted", "History is unreadable without this Mac's key.")}
        ${this.fact("eyeOff", "Private Dictation stores nothing", "One shortcut for zero-trace dictation.")}
        ${this.fact("trash", "You control deletion", "Privacy shows a live inventory — delete anything, anytime.")}
      </div>`;
  },
  bind_privacy() {},

  /* ---- 3 · permissions ---- */
  step_permissions() {
    const row = (granted, title, sub, id) => `
      <div class="row">
        <div class="row-icon">${icon(id === "mic" ? "mic" : "hand")}</div>
        <div class="row-main">
          <div class="row-title">${esc(title)}</div>
          <div class="row-sub">${esc(sub)}</div>
        </div>
        ${granted
          ? `<span class="badge badge-success">${icon("check")}Allowed</span>`
          : `<button class="btn btn-secondary" data-perm="${id}">Grant access</button>`}
      </div>`;
    return `
      <div class="icon-hero">${icon("checkCircle")}</div>
      <h1>Two permissions, clearly explained.</h1>
      <p>Both are optional — you can grant them later from Privacy.</p>
      <div class="panel">
        ${row(this.state.mic, "Microphone", "Records only after you start dictation.", "mic")}
        ${row(this.state.ax, "Accessibility", "Types the finished text into the active app. Without it, text is copied to the clipboard instead.", "ax")}
      </div>`;
  },
  bind_permissions() {
    this.el.querySelectorAll("[data-perm]").forEach(btn =>
      btn.addEventListener("click", () => {
        btn.classList.add("is-loading");
        setTimeout(() => {
          this.state[btn.dataset.perm === "mic" ? "mic" : "ax"] = true;
          this.render();
        }, 700);
      }));
  },

  /* ---- 4 · shortcut ---- */
  step_shortcut() {
    const keys = this.state.shortcut.map(k => `<span class="kbd">${esc(k)}</span>`).join("");
    return `
      <div class="icon-hero">${icon("command")}</div>
      <h1>Your dictation shortcut.</h1>
      <p>Press it once to start, again to finish. Keep the default or record your own —
         ZenVoice checks for conflicts with system shortcuts.</p>
      <div class="panel">
        <div class="row">
          <div class="row-main">
            <div class="row-title">Start / stop dictation</div>
            <div class="row-sub">Works in every app</div>
          </div>
          <button class="recorder" id="ob-recorder" aria-label="Record a new shortcut">
            <span class="kbd-group">${keys}</span>
          </button>
        </div>
        <div class="row">
          <div class="row-main">
            <div class="row-title">Hold to dictate</div>
            <div class="row-sub">Hold a key, speak, release to insert — set it up later in Shortcuts</div>
          </div>
          <span class="badge">Optional</span>
        </div>
      </div>`;
  },
  bind_shortcut() {
    const rec = this.el.querySelector("#ob-recorder");
    let recording = false;
    const onKey = e => {
      if (!recording) return;
      e.preventDefault();
      const combo = [];
      if (e.ctrlKey) combo.push("⌃");
      if (e.altKey) combo.push("⌥");
      if (e.shiftKey) combo.push("⇧");
      if (e.metaKey) combo.push("⌘");
      const k = e.key === " " ? "␣" : e.key.length === 1 ? e.key.toUpperCase() : null;
      if (k && combo.length) {
        this.state.shortcut = [...combo, k];
        recording = false;
        document.removeEventListener("keydown", onKey, true);
        this.render();
        toast("Shortcut saved — no conflicts found");
      }
    };
    rec.addEventListener("click", () => {
      recording = !recording;
      rec.classList.toggle("is-recording", recording);
      rec.innerHTML = recording
        ? `<span>Press keys…</span>`
        : `<span class="kbd-group">${this.state.shortcut.map(k => `<span class="kbd">${esc(k)}</span>`).join("")}</span>`;
      if (recording) document.addEventListener("keydown", onKey, true);
      else document.removeEventListener("keydown", onKey, true);
    });
  },

  /* ---- 5 · language ---- */
  step_language() {
    const chip = (label, sub) => `
      <button class="lang-chip${this.state.language === label ? " is-active" : ""}"
              data-lang="${esc(label)}" style="min-height:52px">
        <div><div style="font:var(--text-label)">${esc(label)}</div>
        <div class="t-caption">${esc(sub)}</div></div>
        ${icon("check", "check")}
      </button>`;
    return `
      <div class="icon-hero">${icon("globe")}</div>
      <h1>What will you speak?</h1>
      <p>You can change this anytime, or set a different language per app.</p>
      <div class="lang-grid" style="grid-template-columns:1fr 1fr">
        ${chip("English", "Fastest, works with every model")}
        ${chip("Hinglish", "Hindi–English, written in Latin script")}
        ${chip("Auto-detect", "Figures out the language as you speak")}
        ${chip("More languages…", "64 languages available")}
      </div>
      <p class="t-caption" style="margin-top:12px">Hinglish, auto-detect, and other
         languages use the Multilingual model — the next step recommends the right download.</p>`;
  },
  bind_language() {
    this.el.querySelectorAll("[data-lang]").forEach(chip =>
      chip.addEventListener("click", () => {
        this.state.language = chip.dataset.lang;
        this.render();
      }));
  },

  /* ---- 6 · model ---- */
  step_model() {
    const multi = this.state.language !== "English";
    const m = multi ? DATA.speechModels[2] : DATA.speechModels[1];
    const p = this.state.modelProgress;
    return `
      <div class="icon-hero">${icon("cpu")}</div>
      <h1>One verified download.</h1>
      <p>ZenVoice measured this Mac and picked the best fit. Every download is
         pinned to an exact revision and SHA-256 checked before use.</p>
      <div class="panel">
        <div class="row model-row">
          <div class="row-icon">${icon("cpu")}</div>
          <div class="row-main">
            <div class="row-title">${esc(m.name)}
              <span class="badge badge-accent">Recommended</span></div>
            <div class="model-meta">
              <span>${esc(m.lang)}</span><span>${esc(m.size)}</span>
              <span class="t-mono">rev ${esc(m.revision)}</span>
              <span class="t-mono">sha ${esc(m.sha)}</span>
            </div>
          </div>
          ${p === "done"
            ? `<span class="badge badge-success">${icon("check")}Verified &amp; ready</span>`
            : p === null
              ? `<button class="btn btn-primary" id="ob-dl">${icon("download")}Download</button>`
              : `<div class="model-progress">
                   <div class="progress"><i style="width:${p}%"></i></div>
                   <span class="t-caption">${p}% · <a href="#" id="ob-dl-cancel" style="color:var(--text-3)">Cancel</a></span>
                 </div>`}
        </div>
      </div>
      <p class="t-caption" style="margin-top:12px">You can skip this and download
         from Models later — dictation needs at least one speech model.</p>`;
  },
  bind_model() {
    const dl = this.el.querySelector("#ob-dl");
    if (dl) dl.addEventListener("click", () => this.simDownload());
    const cancel = this.el.querySelector("#ob-dl-cancel");
    if (cancel) cancel.addEventListener("click", e => {
      e.preventDefault();
      clearInterval(this._dlTimer);
      this.state.modelProgress = null;
      this.render();
      toast("Download cancelled", "x");
    });
  },
  simDownload() {
    this.state.modelProgress = 0;
    this.render();
    this._dlTimer = setInterval(() => {
      this.state.modelProgress = Math.min(100, this.state.modelProgress + 2 + Math.random() * 6 | 0);
      if (this.state.modelProgress >= 100) {
        clearInterval(this._dlTimer);
        this.state.modelProgress = "done";
        toast("Checksum verified — model ready");
      }
      if (this.steps[this.step] === "model") this.render();
    }, 220);
  },

  /* ---- 7 · test drive ---- */
  step_test() {
    return `
      <div class="icon-hero">${icon("mic")}</div>
      <h1>Take it for a spin.</h1>
      <p>This sandbox works exactly like any text field on your Mac.</p>
      <div class="ob-sandbox" id="ob-sandbox">
        ${this.state.tested
          ? `<span class="typed">Let's ship the new onboarding flow this week.</span>`
          : `<span class="hint">Your words will appear here…</span>`}
      </div>
      <div class="hstack" style="margin-top:16px">
        <button class="btn btn-primary btn-lg" id="ob-try">
          ${icon("mic")}${this.state.tested ? "Dictate again" : "Try dictating"}</button>
        ${this.state.tested
          ? `<span class="badge badge-success">${icon("check")}It works — you're ready</span>` : ""}
      </div>
      <p class="t-caption" style="margin-top:16px">Replay this setup anytime from
         Help &amp; FAQ. ZenVoice lives in your menu bar after you close the window.</p>`;
  },
  bind_test() {
    this.el.querySelector("#ob-try").addEventListener("click", () => {
      HUD.demo({
        app: "this sandbox",
        onDone: phrase => {
          this.state.tested = true;
          if (this.steps[this.step] === "test") this.render();
        },
      });
    });
  },
};
