/* ZenVoice v2 — App Profiles: per-application language / refine / commands */
"use strict";
window.Screens = window.Screens || {};

Screens["app-profiles"] = {
  html() {
    return `
      <div class="screen-head">
        <h1>App Profiles</h1>
        <p>Give each app its own dictation behavior. Anything not set here uses
           your global settings.</p>
      </div>

      <div class="section">
        <div class="panel">
          ${DATA.appProfiles.map((p, idx) => `
            <div class="row">
              <div class="row-icon">${icon(p.icon)}</div>
              <div class="row-main">
                <div class="row-title">${esc(p.app)}</div>
                <div class="row-sub">Voice commands ${p.commands ? "on" : "off"}</div>
              </div>
              <select class="field" style="width:130px" aria-label="${esc(p.app)} language"
                data-idx="${idx}" data-kind="lang">
                ${["English", "Hinglish", "Auto-detect"].map(l =>
                  `<option ${p.lang === l ? "selected" : ""}>${l}</option>`).join("")}
              </select>
              <select class="field" style="width:130px" aria-label="${esc(p.app)} refinement"
                data-idx="${idx}" data-kind="refine">
                ${["Off", "Clean", "Agent Prompt", "Local Model"].map(r =>
                  `<option ${p.refine === r ? "selected" : ""}>${r}</option>`).join("")}
              </select>
              <button class="icon-btn is-danger" data-del="${idx}" title="Remove profile"
                aria-label="Remove ${esc(p.app)} profile">${icon("trash")}</button>
            </div>`).join("")}
          <div class="row is-clickable" id="ap-add">
            <div class="row-icon" style="background:var(--accent-soft);color:var(--accent)">${icon("plus")}</div>
            <div class="row-main">
              <div class="row-title">Add an app…</div>
              <div class="row-sub">Pick any installed application</div>
            </div>
          </div>
        </div>
      </div>

      <div class="banner">
        ${icon("info")}
        <p>Profiles switch automatically the moment you start dictating — ZenVoice
           checks which app is frontmost, locally.</p>
      </div>`;
  },

  bind(root) {
    root.querySelectorAll("select[data-idx]").forEach(sel =>
      sel.addEventListener("change", () => {
        const p = DATA.appProfiles[Number(sel.dataset.idx)];
        p[sel.dataset.kind === "lang" ? "lang" : "refine"] = sel.value;
        toast(`${p.app} profile updated`);
      }));

    root.querySelectorAll("[data-del]").forEach(btn =>
      btn.addEventListener("click", () => {
        const p = DATA.appProfiles.splice(Number(btn.dataset.del), 1)[0];
        go("app-profiles");
        toast(`${p.app} now uses global settings`);
      }));

    root.querySelector("#ap-add").addEventListener("click", () => {
      const pool = [
        { app: "Messages", icon: "message" }, { app: "Pages", icon: "fileText" },
        { app: "Terminal", icon: "monitor" }, { app: "Obsidian", icon: "book" },
      ];
      const next = pool.find(c => !DATA.appProfiles.some(p => p.app === c.app));
      if (!next) { toast("All demo apps added", "info"); return; }
      DATA.appProfiles.push({ ...next, lang: "English", refine: "Clean", commands: true });
      go("app-profiles");
      toast(`${next.app} profile added`);
    });
  },
};
