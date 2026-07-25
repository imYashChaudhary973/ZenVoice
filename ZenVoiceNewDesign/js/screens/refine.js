/* ZenVoice v2 — Instant Refine: modes, guarantees, models, live dictation, commands */
"use strict";
window.Screens = window.Screens || {};

Screens.refine = {
  mode: "clean",

  modeCopy: {
    off: {
      title: "Exactly what you said",
      sample: "so um I think we should uh move the the meeting to thursday",
    },
    clean: {
      title: "Fillers and restarts removed — meaning untouched",
      sample: "I think we should move the meeting to Thursday.",
    },
    agent: {
      title: "Structured as a prompt for AI tools",
      sample: "Task: Reschedule the meeting.\nDetails: Move it to Thursday.",
    },
    model: {
      title: "Local model polish, guarded against invention",
      sample: "Let's move the meeting to Thursday.",
    },
  },

  html() {
    const m = this.modeCopy[this.mode];
    const refModel = r => `
      <div class="row model-row">
        <div class="row-icon">${icon("sparkles")}</div>
        <div class="row-main">
          <div class="row-title">${esc(r.name)}</div>
          <div class="row-sub">${esc(r.note)}</div>
          <div class="model-meta">
            <span>${esc(r.params)} parameters</span><span>${esc(r.size)}</span>
            <span class="t-mono">rev ${esc(r.revision)}</span>
            <span class="t-mono">sha256 ${esc(r.sha)}</span>
            <a href="#" class="t-caption" style="color:var(--accent)"
               data-toast="Apache-2.0 licence opens in the browser">${esc(r.license)} ↗</a>
          </div>
        </div>
        ${r.installed
          ? `<span class="badge badge-success">${icon("check")}Installed</span>`
          : `<button class="btn btn-secondary" data-toast="Download starts — verified before use">
              ${icon("download")}Download</button>`}
      </div>`;

    return `
      <div class="screen-head">
        <h1>Instant Refine</h1>
        <p>Cleanup happens after transcription, entirely on-device. Your meaning is
           never changed — and never invented.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Refinement mode</h2></div>
        <div class="reco" style="grid-template-columns:repeat(4,1fr)" role="group" aria-label="Refinement mode">
          <button data-mode="off" ${this.mode === "off" ? 'class="is-active"' : ""}>
            <b>Off</b><span>Raw transcript</span></button>
          <button data-mode="clean" ${this.mode === "clean" ? 'class="is-active"' : ""}>
            <b>Clean</b><span>Fillers &amp; restarts out</span></button>
          <button data-mode="agent" ${this.mode === "agent" ? 'class="is-active"' : ""}>
            <b>Agent Prompt</b><span>Speech → structured prompt</span></button>
          <button data-mode="model" ${this.mode === "model" ? 'class="is-active"' : ""}>
            <b>Local Model</b><span>Verified on-device polish</span></button>
        </div>

        <div class="panel" style="margin-top:12px">
          <div class="row">
            <div class="row-main">
              <div class="row-title">${esc(m.title)}</div>
              <div class="row-sub" style="white-space:pre-line;font-family:var(--font-mono);
                font-size:0.71875rem;margin-top:6px">${esc(m.sample)}</div>
            </div>
          </div>
        </div>
      </div>

      ${this.mode === "model" ? `
      <div class="section">
        <div class="section-head"><h2>Local Model guarantees</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-icon">${icon("clock")}</div>
            <div class="row-main"><div class="row-title">Five-second deadline</div>
              <div class="row-sub">If refinement takes longer, the Clean result is inserted instead — deterministically.</div></div>
          </div>
          <div class="row">
            <div class="row-icon">${icon("shieldCheck")}</div>
            <div class="row-main"><div class="row-title">No-invention guard</div>
              <div class="row-sub">Output is grammar-constrained JSON, checked so nothing is added that you didn't say.</div></div>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Refinement models</h2>
          <span class="t-caption">Qwen · llama.cpp runtime, bundled</span></div>
        <div class="panel">${DATA.refineModels.map(refModel).join("")}</div>
      </div>` : ""}

      <div class="section">
        <div class="section-head"><h2>Live dictation</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Stable phrase preview in ZenBar</div>
              <div class="row-sub">See your words as you speak — the preview never rewrites itself mid-phrase</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="livePreview"
              aria-label="Stable phrase preview"></button>
          </div>
          <div class="row">
            <div class="row-main">
              <div class="row-title">Commit on pause
                <span class="badge badge-warn">Experimental</span></div>
              <div class="row-sub">Insert each phrase when you pause, instead of all at the end.
                Guarded: only commits into the app where dictation started.</div>
            </div>
            <button class="switch" role="switch" aria-checked="false" data-pref="commitOnPause"
              aria-label="Commit on pause"></button>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>One-shot context</h2>
          <span class="t-caption">Memory only — clears when the next recording starts</span></div>
        <div class="panel"><div class="row">
          <div class="row-main stack-2">
            <div class="row-sub" style="max-width:100%">Names and topic hints help
              transcription get spellings right. Nothing here is ever written to disk.</div>
            <textarea class="field" rows="2" aria-label="Context hints"
              placeholder="e.g. Priya Sharma, notarization, TestFlight, Q3 roadmap"></textarea>
          </div>
        </div></div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Voice commands</h2>
          <span class="t-caption">Layout &amp; punctuation, spoken mid-dictation</span></div>
        <div class="panel">
          ${DATA.commands.map(c => `
            <div class="row" style="min-height:44px">
              <div class="row-main"><div class="row-title" style="font-weight:400">
                “<b>${esc(c.say)}</b>”</div></div>
              <span class="t-caption">${esc(c.does)}</span>
            </div>`).join("")}
          <div class="row">
            <div class="row-main">
              <div class="row-title">Command languages</div>
              <div class="row-sub">Aliases work in ${DATA.commandLanguages.join(", ")}</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="voiceCommands"
              aria-label="Enable voice commands"></button>
          </div>
        </div>
      </div>`;
  },

  bind(root) {
    root.querySelectorAll("[data-mode]").forEach(btn =>
      btn.addEventListener("click", () => {
        this.mode = btn.dataset.mode;
        go("refine");
      }));
  },
};
