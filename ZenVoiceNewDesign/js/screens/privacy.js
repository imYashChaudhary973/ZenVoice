/* ZenVoice v2 — Privacy: live inventory, controls, permissions */
"use strict";
window.Screens = window.Screens || {};

Screens.privacy = {
  html() {
    const inv = (iconName, title, detail, size, action) => `
      <div class="row inv-row">
        <div class="row-icon">${icon(iconName)}</div>
        <div class="row-main">
          <div class="row-title">${esc(title)}</div>
          <div class="row-sub">${detail}</div>
        </div>
        <span class="t-caption" style="flex:none">${esc(size)}</span>
        <button class="btn btn-ghost btn-sm" data-toast="${esc(action)}">Delete</button>
      </div>`;

    return `
      <div class="screen-head">
        <h1>Privacy</h1>
        <p>Everything ZenVoice stores, in one place — and the switch to turn each
           piece off. No accounts, no analytics, no cloud transcription.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Dictation privacy</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-icon">${icon("clock")}</div>
            <div class="row-main">
              <div class="row-title">Save history</div>
              <div class="row-sub">Encrypted locally. Pausing keeps existing records but stops new ones.</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="saveHistory"
              aria-label="Save history"></button>
          </div>
          <div class="row">
            <div class="row-icon">${icon("eyeOff")}</div>
            <div class="row-main">
              <div class="row-title">Private Dictation</div>
              <div class="row-sub">⌃⌥P dictates with nothing saved — no history, no insights, no recovery</div>
            </div>
            <button class="btn btn-secondary" id="priv-demo">${icon("play")}Preview</button>
          </div>
          <div class="row">
            <div class="row-icon">${icon("chart")}</div>
            <div class="row-main">
              <div class="row-title">Local insights</div>
              <div class="row-sub">Word counts, WPM, and app usage computed on-device</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="insights"
              aria-label="Local insights"></button>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>What's on this Mac right now</h2>
          <span class="t-caption">Live inventory · updates as you use ZenVoice</span></div>
        <div class="panel">
          ${inv("lock", "Encrypted transcripts",
            `${DATA.history.length} records · AES-GCM, key in the macOS Keychain`,
            "184 KB", "All transcripts deleted")}
          ${inv("inbox", "Recovery partials",
            `${DATA.recovery.length} items · text only, audio is never kept`,
            "2 KB", "Recovery Inbox emptied")}
          ${inv("edit", "Correction rules",
            `${DATA.rules.length} rules · encrypted with the same key`,
            "1 KB", "All correction rules deleted")}
          ${inv("cpu", "Speech models",
            `${DATA.speechModels.filter(m => m.installed).length} installed · verified weights`,
            "148 MB", "Model files removed")}
          ${inv("sparkles", "Refinement models",
            `${DATA.refineModels.filter(m => m.installed).length} installed · Apache-2.0`,
            "394 MB", "Refinement model removed")}
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>macOS permissions</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-icon">${icon("mic")}</div>
            <div class="row-main">
              <div class="row-title">Microphone</div>
              <div class="row-sub">Records only after you start dictation</div>
            </div>
            <span class="badge badge-success">${icon("check")}Allowed</span>
          </div>
          <div class="row">
            <div class="row-icon">${icon("hand")}</div>
            <div class="row-main">
              <div class="row-title">Accessibility</div>
              <div class="row-sub">Inserts finished text into the active app. Without it,
                transcripts are copied to the clipboard instead.</div>
            </div>
            <span class="badge badge-success">${icon("check")}Allowed</span>
          </div>
        </div>
      </div>

      <div class="banner banner-success">
        ${icon("cloudOff")}
        <p>Network access is used for one thing: model downloads you explicitly start.
           Each is pinned to a revision and SHA-256 verified. Everything else — audio,
           text, rules, insights — never leaves this Mac.</p>
      </div>`;
  },

  bind(root) {
    root.querySelector("#priv-demo").addEventListener("click", () => HUD.demo({ private: true }));
  },
};
