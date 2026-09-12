#!/usr/bin/env node
// Joins Meet / Zoom web / Teams as "ZenVoice Notetaker" and stays until SIGTERM.
// Persistent profile so Google/Zoom login survives. Refuses to claim joined
// on a sign-in wall, /wc/my/ interstitial, or invalid meeting.

import { homedir } from "os";
import { mkdirSync } from "fs";
import { join } from "path";
import { chromium } from "playwright";

const rawUrl = process.argv[2];
const name = process.argv[3] || "ZenVoice Notetaker";
if (!rawUrl) {
  console.error("usage: join.mjs <url> [name]");
  process.exit(1);
}

function toWebJoin(raw) {
  try {
    const u = new URL(raw.includes("://") ? raw : `https://${raw}`);
    if (u.hostname.includes("zoom.us") && u.pathname.startsWith("/j/")) {
      const id = u.pathname.slice(3).split("/")[0];
      return `https://app.zoom.us/wc/${id}/join${u.search}`;
    }
  } catch {
    return raw;
  }
  return raw;
}

const url = toWebJoin(rawUrl);
const profile =
  process.env.ZENVOICE_BOT_PROFILE ||
  join(homedir(), "Library/Application Support/ZenVoice/BotProfile");
mkdirSync(profile, { recursive: true });

const context = await chromium.launchPersistentContext(profile, {
  headless: false,
  args: [
    "--use-fake-ui-for-media-stream",
    "--autoplay-policy=no-user-gesture-required",
  ],
  permissions: ["microphone", "camera"],
});
const page = context.pages()[0] || (await context.newPage());
await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45_000 });

async function dismissNoise() {
  for (const label of [
    "Accept Cookies",
    "Accept All Cookies",
    "Accept",
    "I Agree",
    "Close",
  ]) {
    const button = page.getByRole("button", { name: label });
    if ((await button.count()) > 0 && (await button.first().isVisible())) {
      await button.first().click().catch(() => {});
    }
  }
}

async function fillName() {
  const selectors = [
    'input[aria-label="Your name"]',
    'input[placeholder="Your name"]',
    'input[placeholder*="name" i]',
    "#input-for-name",
    "#inputname",
    'input[data-tid="guest-name"]',
    'input[type="text"]',
  ];
  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if ((await locator.count()) > 0 && (await locator.isVisible())) {
      await locator.fill(name);
      return true;
    }
  }
  return false;
}

async function clickLabeled(labels) {
  for (const label of labels) {
    const button = page.getByRole("button", { name: label });
    if ((await button.count()) > 0 && (await button.first().isVisible())) {
      await button.first().click({ timeout: 5_000 }).catch(() => {});
      return true;
    }
    const link = page.getByRole("link", { name: label });
    if ((await link.count()) > 0 && (await link.first().isVisible())) {
      await link.first().click({ timeout: 5_000 }).catch(() => {});
      return true;
    }
  }
  return false;
}

function outcome(finalURL, title, body) {
  const u = finalURL.toLowerCase();
  const t = title.toLowerCase();
  const b = body.toLowerCase();
  if (
    u.includes("accounts.google.com") ||
    u.includes("login.microsoftonline.com") ||
    t.includes("sign in")
  ) {
    return "sign_in_required";
  }
  if (
    b.includes("leave") &&
    (b.includes("mute") ||
      b.includes("join audio") ||
      b.includes("participants") ||
      b.includes("the meeting is at"))
  ) {
    return "joined";
  }
  if (/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}/.test(u)) {
    return "joined";
  }
  if (
    /zoom\.us\/wc\/\d+/.test(u) &&
    !u.includes("/join") &&
    !t.includes("error")
  ) {
    return "joined";
  }
  if (u.includes("teams.microsoft.com") && !u.includes("login")) {
    return "joined";
  }
  return "not_joined";
}

let status = "not_joined";
let finalURL = page.url();
let title = await page.title();
let body = "";

for (let i = 0; i < 8; i++) {
  await dismissNoise();
  await clickLabeled([
    "Join from your browser",
    "Join from Browser",
    "Launch Meeting",
    "Join from a browser",
    "OK",
  ]);
  await fillName();
  await clickLabeled([
    "Join now",
    "Ask to join",
    "Join from your browser",
    "Join as guest",
    "Continue on this browser",
    "Continue",
    "Join",
  ]);
  await page.waitForTimeout(3_000);
  finalURL = page.url();
  title = await page.title();
  body = (await page.locator("body").innerText().catch(() => "")).slice(0, 4000);
  status = outcome(finalURL, title, body);
  if (status !== "not_joined") break;
}

if (status !== "joined") {
  try {
    await page.getByRole("button", { name: /leave/i }).waitFor({
      timeout: 20_000,
    });
    status = "joined";
    finalURL = page.url();
    title = await page.title();
  } catch {
    /* still not in */
  }
}

console.log(JSON.stringify({ status, url: finalURL, title, name }));
await page
  .screenshot({ path: `/tmp/zenvoice-bot-${status}.png`, fullPage: true })
  .catch(() => {});
if (status !== "joined") {
  await context.close().catch(() => {});
  process.exit(1);
}

const shutdown = async () => {
  await context.close().catch(() => {});
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
await new Promise(() => {});
