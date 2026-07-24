/* ZenVoice v2 — Shortcuts: every binding in one calm place */
"use strict";
window.Screens = window.Screens || {};

Screens.shortcuts = {
  combos: {
    dictate: ["⌃", "⌥", "␣"],
    paste: ["⌃", "⌥", "V"],
    private: ["⌃", "⌥", "P"],
  },

  recorderHtml(id) {
    const keys = this.combos[id].map(k => `<span class="kbd">${esc(k)}</span>`).join("");
    return `<button class="recorder" data-rec="${id}"
      aria-label="Record a new shortcut"><span class="kbd-group">${keys}</span></button>`;
  },

  html() {
    return `
      <div class="screen-head">
        <h1>Shortcuts</h1>
        <p>Global shortcuts work in every app. ZenVoice warns you about conflicts
           with system shortcuts before saving.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Dictation</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-icon">${icon("mic")}</div>
            <div class="row-main">
              <div class="row-title">Start / stop dictation</div>
              <div class="row-sub">Press once to start, again to transcribe and insert</div>
            </div>
            ${this.recorderHtml("dictate")}
          </div>
          <div class="row">
            <div class="row-icon">${icon("eyeOff")}</div>
            <div class="row-main">
              <div class="row-title">Private dictation</div>
              <div class="row-sub">Dictate without saving history, insights, or recovery audio</div>
            </div>
            ${this.recorderHtml("private")}
          </div>
          <div class="row">
            <div class="row-icon">${icon("copy")}</div>
            <div class="row-main">
              <div class="row-title">Paste latest dictation</div>
              <div class="row-sub">Re-insert the most recent transcript anywhere</div>
            </div>
            ${this.recorderHtml("paste")}
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Hold to dictate</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Hold a modifier key instead</div>
              <div class="row-sub">Hold, speak, release — the text is inserted when you let go</div>
            </div>
            <button class="switch" role="switch" aria-checked="false" data-pref="holdToDictate"
              aria-label="Hold to dictate"></button>
          </div>
          <div class="row" id="hold-row" style="display:none">
            <div class="row-main">
              <div class="row-title">Hold key</div>
              <div class="row-sub">Chosen key is reserved while ZenVoice is running</div>
            </div>
            <select class="field" style="width:180px" aria-label="Hold key">
              <option>Right Command ⌘</option>
              <option selected>Right Option ⌥</option>
              <option>Fn (Globe)</option>
              <option>Caps Lock</option>
            </select>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>While dictating</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Show “Dictating with ZenVoice” status</div>
              <div class="row-sub">A small caption under the ZenBar while you speak</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="statusMessage"
              aria-label="Show status message"></button>
          </div>
          <div class="row">
            <div class="row-main">
              <div class="row-title">ZenBar controls</div>
              <div class="row-sub">Cancel or finish a dictation from the bar itself — no shortcut needed</div>
            </div>
            <button class="btn btn-secondary" id="sc-preview">${icon("play")}Preview ZenBar</button>
          </div>
        </div>
      </div>

      <div class="banner">
        ${icon("info")}
        <p>Shortcuts are checked against macOS system shortcuts when you record them.
           If a combination is taken, ZenVoice tells you which feature owns it.</p>
      </div>`;
  },

  bind(root) {
    /* recorders */
    root.querySelectorAll("[data-rec]").forEach(rec => {
      let recording = false;
      const id = rec.dataset.rec;
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
          this.combos[id] = [...combo, k];
          recording = false;
          document.removeEventListener("keydown", onKey, true);
          rec.classList.remove("is-recording");
          rec.innerHTML = `<span class="kbd-group">${this.combos[id]
            .map(x => `<span class="kbd">${esc(x)}</span>`).join("")}</span>`;
          toast("Shortcut saved — no conflicts found");
        }
      };
      rec.addEventListener("click", () => {
        recording = !recording;
        rec.classList.toggle("is-recording", recording);
        if (recording) {
          rec.innerHTML = `<span>Press keys…</span>`;
          document.addEventListener("keydown", onKey, true);
        } else {
          document.removeEventListener("keydown", onKey, true);
          rec.innerHTML = `<span class="kbd-group">${this.combos[id]
            .map(x => `<span class="kbd">${esc(x)}</span>`).join("")}</span>`;
        }
      });
    });

    /* hold-to-dictate reveal */
    const holdRow = root.querySelector("#hold-row");
    const sw = root.querySelector('[data-pref="holdToDictate"]');
    const sync = () => holdRow.style.display =
      sw.getAttribute("aria-checked") === "true" ? "" : "none";
    sw.addEventListener("zv-toggle", sync);
    sync();

    root.querySelector("#sc-preview").addEventListener("click", () => HUD.demo({}));
  },
};
