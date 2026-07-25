/* ZenVoice v2 — History: encrypted records, search, Recovery Inbox, highlight cards */
"use strict";
window.Screens = window.Screens || {};

Screens.history = {
  tab: "all", // all | recovery
  query: "",
  sharing: null, // record being previewed as highlight card

  html() {
    const recs = DATA.history.filter(h =>
      !this.query || h.text.toLowerCase().includes(this.query) ||
      h.app.toLowerCase().includes(this.query));

    const historyRows = recs.length ? recs.map(h => `
      <div class="row hist-row">
        <div class="row-icon">${icon("message")}</div>
        <div class="row-main">
          <div class="row-title">${esc(h.app)}
            <span class="t-caption" style="font-weight:400">${esc(h.time)}</span>
            ${h.refined ? `<span class="badge">${icon("sparkles")}Refined</span>` : ""}</div>
          <div class="row-sub">${esc(h.text)}</div>
        </div>
        <span class="t-caption" style="flex:none">${h.words}w · ${h.wpm} wpm</span>
        <div class="hist-actions">
          <button class="icon-btn" data-copy="${h.id}" title="Copy" aria-label="Copy transcript">${icon("copy")}</button>
          <button class="icon-btn" data-share="${h.id}" title="Share as highlight card" aria-label="Share highlight card">${icon("share")}</button>
          <button class="icon-btn" data-retry="${h.id}" title="Retry transcription" aria-label="Retry transcription">${icon("retry")}</button>
          <button class="icon-btn is-danger" data-del="${h.id}" title="Delete" aria-label="Delete record">${icon("trash")}</button>
        </div>
      </div>`).join("")
      : `<div class="empty">${icon("search")}
          <h3>No matches</h3>
          <p>No dictation mentions “${esc(this.query)}”. Search covers the full
             decrypted text of every record.</p></div>`;

    const recoveryRows = DATA.recovery.length ? DATA.recovery.map(r => `
      <div class="row">
        <div class="row-icon" style="background:var(--warn-soft);color:var(--warn)">${icon("inbox")}</div>
        <div class="row-main">
          <div class="row-title">${esc(r.reason)}
            <span class="t-caption" style="font-weight:400">${esc(r.time)}</span></div>
          <div class="row-sub">${r.partial
            ? `Usable partial: “${esc(r.partial)}…”`
            : "No usable text recovered — audio was already deleted"}</div>
        </div>
        <div class="hist-actions" style="opacity:1">
          ${r.partial ? `<button class="icon-btn" data-rcopy="${r.id}" title="Copy partial" aria-label="Copy partial">${icon("copy")}</button>` : ""}
          <button class="icon-btn" data-rretry="${r.id}" title="Retry" aria-label="Retry">${icon("retry")}</button>
          <button class="icon-btn is-danger" data-rdel="${r.id}" title="Delete" aria-label="Delete">${icon("trash")}</button>
        </div>
      </div>`).join("")
      : `<div class="empty">${icon("checkCircle")}
          <h3>Recovery Inbox is empty</h3>
          <p>When a dictation fails, anything usable lands here with Copy, Retry,
             and Delete.</p></div>`;

    const shareCard = this.sharing ? `
      <div class="section" id="share-preview">
        <div class="section-head"><h2>Highlight card</h2>
          <span class="t-caption">Rendered locally · shared only when you say so</span></div>
        <div class="hl-card">
          <blockquote>“${esc(this.sharing.text)}”</blockquote>
          <div class="hl-meta">${icon("waveform")}<span>Dictated with ZenVoice ·
            ${this.sharing.words} words · ${this.sharing.wpm} wpm</span></div>
        </div>
        <div class="hstack" style="margin-top:12px">
          <button class="btn btn-primary" data-toast="Saved to Pictures/ZenVoice">${icon("download")}Save image</button>
          <button class="btn btn-secondary" data-toast="macOS share sheet opens">${icon("share")}Share…</button>
          <button class="btn btn-ghost" id="share-close">Close preview</button>
        </div>
      </div>` : "";

    return `
      <div class="screen-head">
        <h1>History</h1>
        <p>Stored encrypted on this Mac. Pause or clear it anytime from Privacy.</p>
      </div>

      <div class="tabs" role="tablist">
        <button role="tab" aria-selected="${this.tab === "all"}" data-tab="all">All dictations</button>
        <button role="tab" aria-selected="${this.tab === "recovery"}" data-tab="recovery">
          Recovery Inbox
          ${DATA.recovery.length ? `<span class="badge badge-warn">${DATA.recovery.length}</span>` : ""}
        </button>
      </div>

      ${this.tab === "all" ? `
        <div class="stack-3">
          <div class="search-wrap">
            ${icon("search")}
            <input class="field" id="hist-search" type="search" value="${esc(this.query)}"
              placeholder="Search transcripts…" aria-label="Search history">
          </div>
          <div class="panel">${historyRows}</div>
        </div>
        ${shareCard}`
      : `<div class="panel">${recoveryRows}</div>
         <div class="banner" style="margin-top:16px">
           ${icon("info")}
           <p>Temporary audio is deleted after every attempt — recovery keeps only
              encrypted text partials, never sound.</p>
         </div>`}`;
  },

  bind(root) {
    root.querySelectorAll("[data-tab]").forEach(t =>
      t.addEventListener("click", () => { this.tab = t.dataset.tab; go("history"); }));

    const search = root.querySelector("#hist-search");
    if (search) {
      search.addEventListener("input", () => {
        this.query = search.value.trim().toLowerCase();
        /* re-render rows only, keep focus in the field */
        const pos = search.selectionStart;
        go("history");
        const again = document.querySelector("#hist-search");
        again.focus();
        again.setSelectionRange(pos, pos);
      });
    }

    root.querySelectorAll("[data-copy]").forEach(b =>
      b.addEventListener("click", () => toast("Copied to clipboard")));
    root.querySelectorAll("[data-retry]").forEach(b =>
      b.addEventListener("click", () => toast("Re-transcribing with the current model…", "retry")));
    root.querySelectorAll("[data-del]").forEach(b =>
      b.addEventListener("click", () => {
        const i = DATA.history.findIndex(h => h.id === Number(b.dataset.del));
        DATA.history.splice(i, 1);
        go("history");
        toast("Record deleted");
      }));
    root.querySelectorAll("[data-share]").forEach(b =>
      b.addEventListener("click", () => {
        this.sharing = DATA.history.find(h => h.id === Number(b.dataset.share));
        go("history");
        document.querySelector("#share-preview")?.scrollIntoView({ behavior: "smooth" });
      }));
    const close = root.querySelector("#share-close");
    if (close) close.addEventListener("click", () => { this.sharing = null; go("history"); });

    root.querySelectorAll("[data-rcopy]").forEach(b =>
      b.addEventListener("click", () => toast("Partial copied to clipboard")));
    root.querySelectorAll("[data-rretry]").forEach(b =>
      b.addEventListener("click", () => toast("Retry queued — result will appear in History", "retry")));
    root.querySelectorAll("[data-rdel]").forEach(b =>
      b.addEventListener("click", () => {
        const i = DATA.recovery.findIndex(r => r.id === Number(b.dataset.rdel));
        DATA.recovery.splice(i, 1);
        go("history");
        toast("Recovery item deleted");
      }));
  },
};
