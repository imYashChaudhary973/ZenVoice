/* ZenVoice v2 — Home: status at a glance, then get out of the way */
"use strict";
window.Screens = window.Screens || {};

Screens.home = {
  html() {
    const recent = DATA.history.slice(0, 3).map(h => `
      <div class="row hist-row is-clickable" data-go="history">
        <div class="row-icon">${icon("message")}</div>
        <div class="row-main">
          <div class="row-title">${esc(h.app)}
            <span class="t-caption" style="font-weight:400">${esc(h.time)}</span></div>
          <div class="row-sub">${esc(h.text)}</div>
        </div>
        <span class="t-caption">${h.words} words</span>
      </div>`).join("");

    const i = DATA.insights;

    return `
      <div class="screen-head">
        <h1>Home</h1>
        <p>Everything is running locally and ready to dictate.</p>
      </div>

      <div class="section">
        <div class="panel">
          <div class="row is-clickable" data-go="models">
            <div class="row-icon">${icon("cpu")}</div>
            <div class="row-main">
              <div class="row-title">Speech model</div>
              <div class="row-sub">English · Fast — verified and loaded</div>
            </div>
            <span class="badge badge-success"><span class="dot"></span>Ready</span>
          </div>
          <div class="row is-clickable" data-go="audio">
            <div class="row-icon">${icon("mic")}</div>
            <div class="row-main">
              <div class="row-title">Microphone</div>
              <div class="row-sub">MacBook Pro Microphone — following system default</div>
            </div>
            <span class="badge badge-success"><span class="dot"></span>Connected</span>
          </div>
          <div class="row is-clickable" data-go="privacy">
            <div class="row-icon">${icon("shieldCheck")}</div>
            <div class="row-main">
              <div class="row-title">Permissions</div>
              <div class="row-sub">Microphone and Accessibility granted</div>
            </div>
            <span class="badge badge-success">2 of 2</span>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="panel">
          <div class="row">
            <div class="row-main">
              <div class="row-title">Dictate anywhere</div>
              <div class="row-sub">Place the cursor in any text field, press the
                shortcut, speak, press again to insert.</div>
            </div>
            <span class="kbd-group">
              <span class="kbd">⌃</span><span class="kbd">⌥</span><span class="kbd">␣</span>
            </span>
            <button class="btn btn-secondary" id="home-demo">${icon("play")}See it work</button>
          </div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>This week</h2>
          <button class="btn btn-ghost btn-sm" data-go="insights">All insights ${icon("chevronRight")}</button>
        </div>
        <div class="stats">
          <div class="stat"><b>${i.words.toLocaleString()}</b><span>words dictated</span></div>
          <div class="stat"><b>${i.wpm}</b><span>weighted WPM</span></div>
          <div class="stat"><b>${i.streak} days</b><span>current streak</span></div>
          <div class="stat"><b>${i.sessions}</b><span>dictations</span></div>
        </div>
      </div>

      <div class="section">
        <div class="section-head"><h2>Recent dictations</h2>
          <button class="btn btn-ghost btn-sm" data-go="history">History ${icon("chevronRight")}</button>
        </div>
        <div class="panel">${recent}</div>
      </div>`;
  },

  bind(root) {
    root.querySelector("#home-demo").addEventListener("click", () => HUD.demo({ app: "Mail" }));
  },
};
