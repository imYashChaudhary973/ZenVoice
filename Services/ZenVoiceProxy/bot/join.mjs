#!/usr/bin/env node
// Joins a Meet / Zoom web / Teams URL as "ZenVoice Notetaker" and stays
// until SIGTERM. Visible Chromium window — that is the disclosure.

import { chromium } from "playwright";

const url = process.argv[2];
const name = process.argv[3] || "ZenVoice Notetaker";
if (!url) {
  console.error("usage: join.mjs <url> [name]");
  process.exit(1);
}

const browser = await chromium.launch({
  headless: false,
  args: [
    "--use-fake-ui-for-media-stream",
    "--autoplay-policy=no-user-gesture-required",
  ],
});
const context = await browser.newContext({
  permissions: ["microphone", "camera"],
});
const page = await context.newPage();
await page.goto(url, { waitUntil: "domcontentloaded", timeout: 45_000 });

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
      return;
    }
  }
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
      return;
    }
  }
}

await fillName().catch(() => {});
await clickJoin().catch(() => {});
console.log(JSON.stringify({ status: "joined", url, name }));

const shutdown = async () => {
  await browser.close().catch(() => {});
  process.exit(0);
};
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
await new Promise(() => {});
