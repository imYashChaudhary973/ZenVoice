/* ZenVoice v2 — Models: verified catalog + hardware-aware recommendation */
"use strict";
window.Screens = window.Screens || {};

Screens.models = {
  reco: "balanced",
  progress: {}, // id → percent

  html() {
    const tierIcon = { fast: "gauge", balanced: "sliders", accurate: "target" };

    const modelRow = m => {
      const p = this.progress[m.id];
      let trailing;
      if (m.installed) {
        trailing = `<span class="badge badge-success">${icon("check")}Installed</span>
          <button class="icon-btn is-danger" data-remove="${m.id}" title="Remove model"
            aria-label="Remove ${esc(m.name)}">${icon("trash")}</button>`;
      } else if (p !== undefined) {
        trailing = `<div class="model-progress" data-progress="${m.id}">
            <div class="progress"><i style="width:${p}%"></i></div>
            <span class="t-caption"><span data-pct>${p}</span>% of ${esc(m.size)} ·
              <a href="#" data-cancel="${m.id}" style="color:var(--text-3)">Cancel</a></span>
          </div>`;
      } else {
        trailing = `<button class="btn btn-secondary" data-download="${m.id}">
          ${icon("download")}Download</button>`;
      }
      return `
        <div class="row model-row">
          <div class="row-icon">${icon(tierIcon[m.tier])}</div>
          <div class="row-main">
            <div class="row-title">${esc(m.name)}
              ${m.recommended ? `<span class="badge badge-accent">Recommended for this Mac</span>` : ""}</div>
            <div class="row-sub">${esc(m.note)}</div>
            <div class="model-meta">
              <span>${esc(m.lang)}</span><span>${esc(m.size)}</span>
              <span class="t-mono">rev ${esc(m.revision)}</span>
              <span class="t-mono">sha256 ${esc(m.sha)}</span>
            </div>
          </div>
          ${trailing}
        </div>`;
    };

    return `
      <div class="screen-head">
        <h1>Models</h1>
        <p>Every download is pinned to an exact revision and verified with SHA-256
           before it can run. Weights live only on this Mac.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>What matters most?</h2>
          <span class="t-caption">Measured on this Mac from private local timing samples</span>
        </div>
        <div class="reco" role="group" aria-label="Performance priority">
          <button data-reco="fast" ${this.reco === "fast" ? 'class="is-active"' : ""}>
            <b>${icon("gauge")}Fast</b>
            <span>~0.4 s per sentence · good accuracy</span>
          </button>
          <button data-reco="balanced" ${this.reco === "balanced" ? 'class="is-active"' : ""}>
            <b>${icon("sliders")}Balanced</b>
            <span>~0.9 s per sentence · best accuracy per second</span>
          </button>
          <button data-reco="accurate" ${this.reco === "accurate" ? 'class="is-active"' : ""}>
            <b>${icon("target")}High Accuracy</b>
            <span>~2.1 s per sentence · multilingual</span>
          </button>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Speech models</h2>
          <span class="t-caption">whisper.cpp runtime, bundled</span></div>
        <div class="panel">${DATA.speechModels.map(modelRow).join("")}</div>
      </div>

      <div class="banner">
        ${icon("hardDrive")}
        <p>Model provenance, licences, and checksums are documented in the Verified
           Model Catalogue. Deleting a model frees its disk space immediately.</p>
      </div>`;
  },

  bind(root) {
    root.querySelectorAll("[data-reco]").forEach(btn =>
      btn.addEventListener("click", () => {
        this.reco = btn.dataset.reco;
        DATA.speechModels.forEach(m => m.recommended = false);
        const target = { fast: "base-en", balanced: "small-en", accurate: "medium-multi" }[this.reco];
        const m = DATA.speechModels.find(x => x.id === target);
        if (m) m.recommended = true;
        go("models");
      }));

    root.querySelectorAll("[data-download]").forEach(btn =>
      btn.addEventListener("click", () => this.download(btn.dataset.download)));

    root.querySelectorAll("[data-cancel]").forEach(a =>
      a.addEventListener("click", e => {
        e.preventDefault();
        clearInterval(this._timers?.[a.dataset.cancel]);
        delete this.progress[a.dataset.cancel];
        go("models");
        toast("Download cancelled — partial file removed", "x");
      }));

    root.querySelectorAll("[data-remove]").forEach(btn =>
      btn.addEventListener("click", () => {
        const m = DATA.speechModels.find(x => x.id === btn.dataset.remove);
        if (m) m.installed = false;
        go("models");
        toast(`${m.name} removed — ${m.size} freed`);
      }));
  },

  download(id) {
    this._timers = this._timers || {};
    this.progress[id] = 0;
    go("models");
    this._timers[id] = setInterval(() => {
      this.progress[id] = Math.min(100, (this.progress[id] + 1 + Math.random() * 5) | 0);
      if (this.progress[id] >= 100) {
        clearInterval(this._timers[id]);
        delete this.progress[id];
        const m = DATA.speechModels.find(x => x.id === id);
        m.installed = true;
        toast("Checksum verified — model ready");
        if (currentScreen === "models") go("models");
        return;
      }
      /* update in place — don't re-render (would reset scroll) */
      const wrap = document.querySelector(`[data-progress="${id}"]`);
      if (wrap) {
        wrap.querySelector(".progress i").style.width = this.progress[id] + "%";
        wrap.querySelector("[data-pct]").textContent = this.progress[id];
      }
    }, 300);
  },
};
