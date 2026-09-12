#!/usr/bin/env node
// Joins Meet / Zoom web / Teams as "ZenVoice Notetaker" and stays until SIGTERM.
// Persistent profile so Google/Zoom login survives. Refuses to claim joined
// on a sign-in wall or invalid meeting.

import { homedir } from "os";
import { mkdirSync } from "fs";
import { join } from "path";
import { chromium } from "playwright";

const url = process.argv[2];
const name = process.argv[3] || "ZenVoice Notetaker";
if (!url) {
  console.error("usage: join.mjs <url> [name]");
  process.exit(1);
}

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
await page.waitForTimeout(3_000);

async function fillName() {
  const selectors = [
    'input[aria-label="Your name"]',
    'input[placeholder="Your name"]',
    'input[placeholder*="name" i]',
    "#inputname",
    "#input-for-name",
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

async function clickJoin() {
  const labels = [
    "Join now",
    "Ask to join",
    "Join from your browser",
    "Join from browser",
    "Launch meeting",
    "Join as guest",
    "Continue on this browser",
    "Continue",
    "Join",
  ];
  for (const label of labels) {
    const button = page.getByRole("button", { name: label });
    if ((await button.count()) > 0) {
      await button.first().click({ timeout: 5_000 }).catch(() => {});
      return true;
    }
  }
  return false;
}

await fillName().catch(() => false);
await clickJoin().catch(() => false);
await page.waitForTimeout(4_000);

const finalURL = page.url();
const title = await page.title();
const body = (await page.locator("body").innerText().catch(() => "")).slice(
  0,
  800,
);

function outcome() {
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
  if (b.includes("meeting link is invalid") || t === "error - zoom") {
    return "invalid_meeting";
  }
  if (/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}/.test(u)) {
    return "joined";
  }
  if (u.includes("zoom.us/wc/") && !t.includes("error")) {
    return "joined";
  }
  if (u.includes("teams.microsoft.com") && !u.includes("login")) {
    return "joined";
  }
  return "not_joined";
}

const status = outcome();
console.log(JSON.stringify({ status, url: finalURL, title, name }));
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
