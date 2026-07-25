/* ZenVoice v2 — application runtime: state, router, sidebar, HUD, menu bar */
"use strict";

/* ---------------- state ---------------- */
const ZV = {
  prefs: JSON.parse(localStorage.getItem("zv2-prefs") || "{}"),
  save() { localStorage.setItem("zv2-prefs", JSON.stringify(this.prefs)); },
  pref(key, def) { return key in this.prefs ? this.prefs[key] : def; },
  setPref(key, val) { this.prefs[key] = val; this.save(); },
};

const REDUCED_MOTION =
  window.matchMedia("(prefers-reduced-motion: reduce)").matches;

function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

function toast(msg, iconName = "checkCircle") {
  const region = document.getElementById("toast-region");
  const el = document.createElement("div");
  el.className = "toast";
  el.innerHTML = `${icon(iconName)}<span>${esc(msg)}</span>`;
  region.appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 200ms ease";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 220);
  }, 2400);
}

/* ---------------- navigation model ---------------- */
const NAV = [
  { group: null, items: [
    { id: "home", label: "Home", icon: "home" },
  ]},
  { group: "Dictation", items: [
    { id: "shortcuts", label: "Shortcuts", icon: "command" },
    { id: "audio", label: "Audio", icon: "mic" },
    { id: "languages", label: "Languages", icon: "globe" },
    { id: "refine", label: "Instant Refine", icon: "sparkles" },
  ]},
  { group: "Personal", items: [
    { id: "voice-profile", label: "Voice Profile", icon: "user" },
    { id: "app-profiles", label: "App Profiles", icon: "grid" },
  ]},
  { group: "Your data", items: [
    { id: "history", label: "History", icon: "clock", badge: () => DATA.recovery.length },
    { id: "insights", label: "Insights", icon: "chart" },
  ]},
  { group: "System", items: [
    { id: "models", label: "Models", icon: "cpu" },
    { id: "privacy", label: "Privacy", icon: "shield" },
    { id: "help", label: "Help & FAQ", icon: "help" },
  ]},
];

let currentScreen = null;

function renderSidebar() {
  const el = document.getElementById("sidebar");
  const groups = NAV.map(g => `
    <div class="nav-group">
      ${g.group ? `<div class="nav-group-label">${esc(g.group)}</div>` : ""}
      ${g.items.map(item => `
        <button class="nav-item${item.id === currentScreen ? " is-active" : ""}"
                data-go="${item.id}" aria-current="${item.id === currentScreen ? "page" : "false"}">
          ${icon(item.icon)}<span>${esc(item.label)}</span>
          ${item.badge && item.badge() ? `<span class="badge badge-warn">${item.badge()}</span>` : ""}
        </button>`).join("")}
    </div>`).join("");

  const dark = document.documentElement.dataset.theme === "dark";
  el.innerHTML = `
    <div class="side-brand">
      <div class="logo">${icon("waveform")}</div>
      <div><b>ZenVoice</b><span>Local voice, refined</span></div>
    </div>
    ${groups}
    <div class="side-foot">
      <button class="appearance-toggle" id="side-theme">
        ${icon(dark ? "sun" : "moon")}<span>${dark ? "Light mode" : "Dark mode"}</span>
      </button>
      <div class="local-beacon">
        <span class="dot" aria-hidden="true"></span><span>Processing stays local</span>
      </div>
    </div>`;

  el.querySelector("#side-theme").addEventListener("click", toggleTheme);
  el.querySelectorAll(".nav-item[data-go]").forEach(btn =>
    btn.addEventListener("click", () => go(btn.dataset.go)));
}

function go(id) {
  const screen = Screens[id];
  if (!screen) return;
  currentScreen = id;
  ZV.setPref("lastScreen", id);
  const content = document.getElementById("content");
  content.innerHTML = `<div class="screen">${screen.html()}</div>`;
  content.scrollTop = 0;
  postRender(content);
  screen.bind && screen.bind(content);
  renderSidebar();
}

/* generic behaviors shared by every screen */
function postRender(root) {
  root.querySelectorAll(".switch").forEach(sw => {
    if (sw.dataset.bound) return;
    sw.dataset.bound = "1";
    if (sw.dataset.pref) {
      const on = ZV.pref(sw.dataset.pref, sw.getAttribute("aria-checked") === "true");
      sw.setAttribute("aria-checked", String(on));
    }
    sw.addEventListener("click", () => {
      const on = sw.getAttribute("aria-checked") !== "true";
      sw.setAttribute("aria-checked", String(on));
      if (sw.dataset.pref) ZV.setPref(sw.dataset.pref, on);
      sw.dispatchEvent(new CustomEvent("zv-toggle", { bubbles: true, detail: { on } }));
    });
  });

  root.querySelectorAll(".segmented").forEach(seg => {
    if (seg.dataset.bound) return;
    seg.dataset.bound = "1";
    seg.addEventListener("click", e => {
      const btn = e.target.closest("button");
      if (!btn) return;
      seg.querySelectorAll("button").forEach(b =>
        b.setAttribute("aria-pressed", String(b === btn)));
      seg.dispatchEvent(new CustomEvent("zv-segment",
        { bubbles: true, detail: { value: btn.dataset.value } }));
    });
  });

  root.querySelectorAll("[data-go]").forEach(b => {
    if (b.dataset.boundGo) return;
    b.dataset.boundGo = "1";
    b.addEventListener("click", () => go(b.dataset.go));
  });

  root.querySelectorAll("[data-toast]").forEach(b => {
    if (b.dataset.boundToast) return;
    b.dataset.boundToast = "1";
    b.addEventListener("click", () => toast(b.dataset.toast));
  });
}

/* ---------------- theme ---------------- */
function setTheme(theme) {
  document.documentElement.dataset.theme = theme;
  ZV.setPref("theme", theme);
  const pb = document.getElementById("pb-theme");
  pb.innerHTML = `${icon(theme === "dark" ? "sun" : "moon")}<span>${theme === "dark" ? "Light" : "Dark"}</span>`;
  renderSidebar();
}
function toggleTheme() {
  setTheme(document.documentElement.dataset.theme === "dark" ? "light" : "dark");
}

/* ---------------- ZenBar HUD ---------------- */
const HUD = {
  el: null,
  timer: null,
  raf: null,
  levels: new Array(24).fill(2),

  stop() {
    clearTimeout(this.timer);
    cancelAnimationFrame(this.raf);
    this.el.hidden = true;
    this.el.className = "";
  },

  render(state, opts = {}) {
    cancelAnimationFrame(this.raf); // stop any waveform loop on a detached canvas
    this.el.hidden = false;
    this.el.className = `is-${state}`;
    const statusLine = ZV.pref("statusMessage", true)
      ? `<div class="hud-sub">Dictating with ZenVoice</div>` : "";
    const priv = opts.private
      ? `<span class="private-badge">${icon("eyeOff")}Private</span>` : "";

    if (state === "ready") {
      this.el.innerHTML = `
        <div class="state-icon">${icon("mic")}</div>
        <div class="hud-main"><div class="hud-label">Ready</div>
          <div class="hud-sub">Press ⌃⌥Space and speak</div></div>${priv}`;
    }

    if (state === "listening") {
      this.el.innerHTML = `
        <div class="state-icon">${icon("mic")}</div>
        <div class="hud-main">
          <div class="hud-label">Listening…</div>
          <div class="hud-sub" id="hud-preview">${opts.preview ? esc(opts.preview) : ""}</div>
        </div>
        ${priv}
        <canvas id="hud-wave" width="144" height="52"></canvas>
        <button class="hud-btn" id="hud-cancel" title="Cancel dictation" aria-label="Cancel dictation">${icon("x")}</button>
        <button class="hud-btn hud-done" id="hud-done" title="Finish and insert" aria-label="Finish and insert">${icon("check")}</button>`;
      this.el.querySelector("#hud-cancel").addEventListener("click", () => {
        this.stop(); toast("Dictation cancelled", "x");
      });
      this.el.querySelector("#hud-done").addEventListener("click", () => this.finish(opts));
      this.wave();
    }

    if (state === "processing") {
      this.el.innerHTML = `
        <div class="state-icon">${icon("waveform")}</div>
        <div class="hud-main"><div class="hud-label">Transcribing…</div>${statusLine}</div>${priv}`;
    }

    if (state === "success") {
      this.el.innerHTML = `
        <div class="state-icon">${icon("check")}</div>
        <div class="hud-main"><div class="hud-label">Inserted into ${esc(opts.app || "Notes")}</div>
          <div class="hud-sub">${opts.words || 9} words · ${opts.private ? "not saved (private)" : "saved to history"}</div></div>${priv}`;
    }

    if (state === "error") {
      this.el.innerHTML = `
        <div class="state-icon">${icon("warn")}</div>
        <div class="hud-main"><div class="hud-label">Couldn't finish transcription</div>
          <div class="hud-sub">Partial saved to Recovery Inbox</div></div>
        <button class="hud-btn" id="hud-retry" title="Retry" aria-label="Retry">${icon("retry")}</button>
        <button class="hud-btn" id="hud-close" title="Dismiss" aria-label="Dismiss">${icon("x")}</button>`;
      this.el.querySelector("#hud-retry").addEventListener("click", () => this.demo({}));
      this.el.querySelector("#hud-close").addEventListener("click", () => this.stop());
    }
  },

  wave() {
    const canvas = this.el.querySelector("#hud-wave");
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const accent = getComputedStyle(document.documentElement)
      .getPropertyValue("--accent").trim() || "#debd85";
    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = accent;
      const n = this.levels.length, w = 3, gap = 3, mid = canvas.height / 2;
      this.levels = this.levels.map(v => {
        const target = 3 + Math.random() * 22;
        return REDUCED_MOTION ? 12 : v + (target - v) * 0.3;
      });
      this.levels.forEach((v, i) => {
        const x = i * (w + gap);
        ctx.beginPath();
        ctx.roundRect(x, mid - v, w, v * 2, 2);
        ctx.fill();
      });
      if (!REDUCED_MOTION) this.raf = requestAnimationFrame(draw);
    };
    draw();
  },

  finish(opts = {}) {
    cancelAnimationFrame(this.raf);
    clearTimeout(this.timer);
    this.render("processing", opts);
    this.timer = setTimeout(() => {
      if (opts.fail) {
        this.render("error", opts);
      } else {
        this.render("success", opts);
        this.timer = setTimeout(() => this.stop(), 2000);
      }
    }, 1300);
  },

  /* full simulated dictation */
  demo(opts = {}) {
    clearTimeout(this.timer);
    const phrase = "Let's ship the new onboarding flow this week.";
    const words = phrase.split(" ");
    this.render("listening", { ...opts, preview: "" });
    let i = 0;
    const type = () => {
      i++;
      const preview = this.el.querySelector("#hud-preview");
      if (preview) preview.textContent = words.slice(0, i).join(" ");
      if (i < words.length) {
        this.timer = setTimeout(type, 240);
      } else {
        this.timer = setTimeout(() =>
          this.finish({ ...opts, words: words.length, app: opts.app || "Notes" }), 700);
      }
    };
    this.timer = setTimeout(type, 500);
    if (opts.onDone) {
      const prevFinish = this.finish.bind(this);
      // let callers observe completion (onboarding test drive)
      this.finish = (o) => { prevFinish(o); opts.onDone(phrase); this.finish = prevFinish; };
    }
  },
};

/* ---------------- menu bar popover ---------------- */
function renderMenubar() {
  const el = document.getElementById("menubar-pop");
  el.innerHTML = `
    <button class="mb-item" id="mb-dictate">${icon("mic")}<span>Start dictation</span>
      <span class="kbd-group"><span class="kbd">⌃</span><span class="kbd">⌥</span><span class="kbd">␣</span></span></button>
    <button class="mb-item" data-toast="Last dictation pasted">${icon("copy")}<span>Paste last dictation</span>
      <span class="kbd-group"><span class="kbd">⌃</span><span class="kbd">⌥</span><span class="kbd">V</span></span></button>
    <button class="mb-item" id="mb-private">${icon("eyeOff")}<span>Private dictation</span>
      <span class="kbd-group"><span class="kbd">⌃</span><span class="kbd">⌥</span><span class="kbd">P</span></span></button>
    <hr class="divider">
    <button class="mb-item" id="mb-open">${icon("monitor")}<span>Open ZenVoice…</span></button>
    <button class="mb-item" id="mb-help">${icon("help")}<span>Help &amp; FAQ</span></button>
    <hr class="divider">
    <div class="mb-status"><span class="dot" aria-hidden="true"></span>Processing stays local</div>
    <button class="mb-item">${icon("x")}<span>Quit ZenVoice</span></button>`;
  postRender(el);
  el.querySelector("#mb-dictate").addEventListener("click", () => {
    el.hidden = true; HUD.demo({});
  });
  el.querySelector("#mb-private").addEventListener("click", () => {
    el.hidden = true; HUD.demo({ private: true });
  });
  el.querySelector("#mb-open").addEventListener("click", () => { el.hidden = true; go("home"); });
  el.querySelector("#mb-help").addEventListener("click", () => { el.hidden = true; go("help"); });
}

/* ---------------- boot ---------------- */
document.addEventListener("DOMContentLoaded", () => {
  HUD.el = document.getElementById("zenbar");

  /* URL-addressable states for design review:
     ?theme=light&screen=models&hud=listening&ob=2&onboarded=1&menubar=1 */
  const q = new URLSearchParams(location.search);

  setTheme(q.get("theme") || ZV.pref("theme", "dark"));
  renderMenubar();
  go(q.get("screen") || ZV.pref("lastScreen", "home"));

  if (q.has("onboarded")) ZV.setPref("onboarded", q.get("onboarded") === "1");
  if (q.has("ob")) {
    ZV.setPref("onboarded", false);
    ZV.setPref("onboardingStep", Number(q.get("ob")) || 0);
  }
  if (q.has("hud")) {
    const state = q.get("hud");
    ZV.setPref("onboarded", true);
    HUD.render(state, {
      preview: state === "listening" ? "Let's ship the new onboarding flow" : "",
      private: q.has("private"), app: "Mail", words: 9,
    });
  }
  if (q.has("menubar")) document.getElementById("menubar-pop").hidden = false;

  /* prototype bar */
  document.getElementById("pb-theme").addEventListener("click", toggleTheme);
  document.getElementById("pb-onboarding").addEventListener("click", () => {
    ZV.setPref("onboarded", false); Onboarding.start();
  });
  document.getElementById("pb-zenbar").addEventListener("click", () => HUD.demo({}));
  document.getElementById("pb-private").addEventListener("click", () => HUD.demo({ private: true }));
  document.getElementById("pb-error").addEventListener("click", () => HUD.demo({ fail: true }));
  document.getElementById("pb-menubar").addEventListener("click", () => {
    const pop = document.getElementById("menubar-pop");
    pop.hidden = !pop.hidden;
  });

  document.addEventListener("keydown", e => {
    if (e.key === "Escape") {
      document.getElementById("menubar-pop").hidden = true;
      if (!HUD.el.hidden) HUD.stop();
    }
  });

  /* first launch → onboarding */
  if (!ZV.pref("onboarded", false)) Onboarding.start();
});
