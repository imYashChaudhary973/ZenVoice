/* ZenVoice v2 — Voice Profile: phrases, correction rules, pattern controls */
"use strict";
window.Screens = window.Screens || {};

Screens["voice-profile"] = {
  html() {
    return `
      <div class="screen-head">
        <h1>Voice Profile</h1>
        <p>ZenVoice learns how you speak — locally. Recurring phrases improve
           recognition; correction rules fix words it keeps getting wrong.</p>
      </div>

      <div class="section">
        <div class="section-head"><h2>Learning controls</h2></div>
        <div class="panel">
          <div class="row">
            <div class="row-icon">${icon("type")}</div>
            <div class="row-main">
              <div class="row-title">Local pattern analysis</div>
              <div class="row-sub">Notices phrases you use often. Runs on-device; pause it anytime.</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="patternAnalysis"
              aria-label="Local pattern analysis"></button>
          </div>
          <div class="row">
            <div class="row-icon">${icon("edit")}</div>
            <div class="row-main">
              <div class="row-title">Apply personal rules</div>
              <div class="row-sub">Pause without deleting — rules stay encrypted and inactive.</div>
            </div>
            <button class="switch" role="switch" aria-checked="true" data-pref="applyRules"
              aria-label="Apply personal rules"></button>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Recurring phrases</h2>
          <span class="t-caption">Learned locally · most used first</span></div>
        <div class="panel">
          ${DATA.phrases.map(p => `
            <div class="row" style="min-height:44px">
              <div class="row-main"><div class="row-title" style="font-weight:400">${esc(p.text)}</div></div>
              <span class="t-caption">${p.uses} uses</span>
              <button class="icon-btn is-danger" data-toast="Phrase forgotten"
                title="Forget phrase" aria-label="Forget ${esc(p.text)}">${icon("x")}</button>
            </div>`).join("")}
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Correction rules</h2>
          <span class="t-caption">Encrypted · independent of History</span></div>
        <div class="panel" id="rules-panel">
          ${DATA.rules.map((r, idx) => `
            <div class="row" data-rule="${idx}">
              <div class="row-main">
                <div class="row-title" style="font-weight:400">
                  “${esc(r.from)}” <span class="t-3" style="margin:0 4px">→</span> <b>${esc(r.to)}</b></div>
                <div class="row-sub">${esc(r.scope)}</div>
              </div>
              <button class="icon-btn is-danger" data-del-rule="${idx}"
                title="Delete rule" aria-label="Delete rule ${esc(r.from)}">${icon("trash")}</button>
            </div>`).join("")}
          <div class="row" style="align-items:flex-end;gap:8px">
            <div class="row-main grid-2" style="gap:8px">
              <div class="stack-2"><label class="t-caption" for="rule-from">When I say</label>
                <input class="field" id="rule-from" placeholder="zen voice"></div>
              <div class="stack-2"><label class="t-caption" for="rule-to">Write</label>
                <input class="field" id="rule-to" placeholder="ZenVoice"></div>
            </div>
            <button class="btn btn-secondary" id="rule-add">${icon("plus")}Add rule</button>
          </div>
        </div>
      </div>

      <div class="banner">
        ${icon("lock")}
        <p>Phrases and rules are stored encrypted on this Mac and are never part of
           any model. Deleting them here does not touch your dictation History.</p>
      </div>`;
  },

  bind(root) {
    root.querySelectorAll("[data-del-rule]").forEach(btn =>
      btn.addEventListener("click", () => {
        DATA.rules.splice(Number(btn.dataset.delRule), 1);
        go("voice-profile");
        toast("Correction rule deleted");
      }));

    root.querySelector("#rule-add").addEventListener("click", () => {
      const from = root.querySelector("#rule-from").value.trim();
      const to = root.querySelector("#rule-to").value.trim();
      if (!from || !to) { toast("Fill in both sides of the rule", "info"); return; }
      DATA.rules.push({ from, to, scope: "Everywhere" });
      go("voice-profile");
      toast("Rule added — applies from your next dictation");
    });
  },
};
