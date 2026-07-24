/* ZenVoice v2 — Insights: private local stats, no cloud, no comparisons */
"use strict";
window.Screens = window.Screens || {};

Screens.insights = {
  html() {
    const i = DATA.insights;
    const max = Math.max(...i.week.map(d => d.v));
    const top = i.week.reduce((a, b) => (b.v > a.v ? b : a));

    return `
      <div class="screen-head">
        <h1>Insights</h1>
        <p>Computed on this Mac from your encrypted history. Pause collection
           anytime from Privacy — nothing is ever uploaded.</p>
      </div>

      <div class="section">
        <div class="stats">
          <div class="stat"><b>${i.words.toLocaleString()}</b><span>words this week</span>
            <small>↑ 18% vs last week</small></div>
          <div class="stat"><b>${i.wpm}</b><span>weighted WPM</span>
            <small>↑ 4 wpm</small></div>
          <div class="stat"><b>${i.streak} days</b><span>streak</span>
            <small>best: 14</small></div>
          <div class="stat"><b>${i.sessions}</b><span>dictations</span></div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Words per day</h2>
          <span class="t-caption">Busiest: ${top.d} · ${top.v.toLocaleString()} words</span></div>
        <div class="panel" style="padding:20px 16px 14px">
          <div class="bars" role="img" aria-label="Words dictated per day this week">
            ${i.week.map(d => `<i style="height:${Math.round(d.v / max * 100)}%"
              ${d.v === max ? 'class="is-top"' : ""} title="${d.d}: ${d.v.toLocaleString()} words"></i>`).join("")}
          </div>
          <div class="bars-labels">${i.week.map(d => `<span>${d.d}</span>`).join("")}</div>
        </div>
      </div>

      <div class="grid-2">
        <div class="section">
          <div class="section-head"><h2>Where you dictate</h2></div>
          <div class="panel" style="padding:8px 16px">
            ${i.apps.map(a => `
              <div class="meter-row">
                <span style="font:var(--text-label);font-weight:400">${esc(a.name)}</span>
                <span class="t-caption">${a.pct}%</span>
                <div class="meter"><i style="width:${a.pct}%"></i></div>
              </div>`).join("")}
          </div>
        </div>

        <div class="section">
          <div class="section-head"><h2>What kind of work</h2></div>
          <div class="panel" style="padding:8px 16px">
            ${i.categories.map(c => `
              <div class="meter-row">
                <span style="font:var(--text-label);font-weight:400">${esc(c.name)}</span>
                <span class="t-caption">${c.pct}%</span>
                <div class="meter"><i style="width:${c.pct}%"></i></div>
              </div>`).join("")}
          </div>
        </div>
      </div>

      <div class="banner">
        ${icon("lock")}
        <p>Categories are inferred locally from app names only — never from what
           you said. Insights have no account and no server.</p>
      </div>`;
  },
};
