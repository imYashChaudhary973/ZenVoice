/* ZenVoice v2 — Help & FAQ: searchable answers, cheat-sheet, replay setup */
"use strict";
window.Screens = window.Screens || {};

Screens.help = {
  query: "",

  html() {
    const q = this.query.toLowerCase();
    const faqs = DATA.faqs.filter(f =>
      !q || f.q.toLowerCase().includes(q) || f.a.toLowerCase().includes(q) ||
      f.tags.includes(q));

    return `
      <div class="screen-head">
        <h1>Help &amp; FAQ</h1>
        <p>Answers first, setup second. Everything here works offline.</p>
      </div>

      <div class="section">
        <div class="panel">
          <div class="row is-clickable" id="help-replay">
            <div class="row-icon" style="background:var(--accent-soft);color:var(--accent)">${icon("replay")}</div>
            <div class="row-main">
              <div class="row-title">Replay the setup guide</div>
              <div class="row-sub">The same 7 steps you saw on first launch — permissions, shortcut, language, model</div>
            </div>
            ${icon("chevronRight")}
          </div>
          <div class="row is-clickable" id="help-demo">
            <div class="row-icon" style="background:var(--accent-soft);color:var(--accent)">${icon("play")}</div>
            <div class="row-main">
              <div class="row-title">Watch a dictation demo</div>
              <div class="row-sub">See ZenBar go from listening to inserted text</div>
            </div>
            ${icon("chevronRight")}
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Shortcut cheat-sheet</h2></div>
        <div class="panel">
          ${[
            ["Start / stop dictation", ["⌃", "⌥", "␣"]],
            ["Private dictation", ["⌃", "⌥", "P"]],
            ["Paste latest dictation", ["⌃", "⌥", "V"]],
          ].map(([label, keys]) => `
            <div class="row" style="min-height:44px">
              <div class="row-main"><div class="row-title" style="font-weight:400">${label}</div></div>
              <span class="kbd-group">${keys.map(k => `<span class="kbd">${k}</span>`).join("")}</span>
            </div>`).join("")}
          <div class="row" style="min-height:44px">
            <div class="row-main"><div class="row-title" style="font-weight:400">Change any of these</div></div>
            <button class="btn btn-ghost btn-sm" data-go="shortcuts">Shortcuts ${icon("chevronRight")}</button>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Frequently asked</h2>
          <span class="t-caption">${faqs.length} of ${DATA.faqs.length}</span></div>
        <div class="stack-3">
          <div class="search-wrap">
            ${icon("search")}
            <input class="field" id="faq-search" type="search" value="${esc(this.query)}"
              placeholder="Search answers — try “private”, “model”, “hinglish”…"
              aria-label="Search FAQs">
          </div>
          <div class="panel">
            ${faqs.length ? faqs.map((f, idx) => `
              <div class="faq-item" data-open="false">
                <button class="faq-q" aria-expanded="false">
                  ${esc(f.q)} ${icon("chevronDown")}
                </button>
                <div class="faq-a">${esc(f.a)}</div>
              </div>`).join("")
            : `<div class="empty">${icon("search")}
                <h3>No answer found</h3>
                <p>Try a different word — or read the full documentation.</p></div>`}
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>More</h2></div>
        <div class="panel">
          <div class="row is-clickable" data-toast="Opens docs/PRIVACY.md">
            <div class="row-icon">${icon("book")}</div>
            <div class="row-main"><div class="row-title">Documentation</div>
              <div class="row-sub">Architecture, privacy, model catalogue, languages</div></div>
            ${icon("externalLink")}
          </div>
          <div class="row">
            <div class="row-icon">${icon("waveform")}</div>
            <div class="row-main"><div class="row-title">ZenVoice</div>
              <div class="row-sub">Version 2.0 (redesign prototype) · macOS 14+ · Apple Silicon</div></div>
          </div>
        </div>
      </div>`;
  },

  bind(root) {
    root.querySelector("#help-replay").addEventListener("click", () => Onboarding.start());
    root.querySelector("#help-demo").addEventListener("click", () => HUD.demo({}));

    const search = root.querySelector("#faq-search");
    search.addEventListener("input", () => {
      this.query = search.value.trim();
      const pos = search.selectionStart;
      go("help");
      const again = document.querySelector("#faq-search");
      again.focus();
      again.setSelectionRange(pos, pos);
    });

    root.querySelectorAll(".faq-item").forEach(item => {
      const btn = item.querySelector(".faq-q");
      btn.addEventListener("click", () => {
        const open = item.dataset.open === "true";
        item.dataset.open = String(!open);
        btn.setAttribute("aria-expanded", String(!open));
      });
    });
  },
};
