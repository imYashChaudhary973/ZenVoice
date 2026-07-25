/* ZenVoice v2 — mock data mirroring the real app's catalogs and records */
"use strict";

const DATA = {
  speechModels: [
    {
      id: "base-en", name: "English · Fast", family: "whisper.cpp",
      lang: "English only", size: "148 MB", revision: "b1a2f04",
      sha: "9e4c…7f21", tier: "fast",
      note: "Lowest latency. Great for notes and chat.",
      installed: true,
    },
    {
      id: "small-en", name: "English · Balanced", family: "whisper.cpp",
      lang: "English only", size: "488 MB", revision: "c77d19e",
      sha: "4b0a…d3c8", tier: "balanced",
      note: "Recommended for this Mac — best accuracy per second.",
      installed: false, recommended: true,
    },
    {
      id: "medium-multi", name: "Multilingual · High Accuracy", family: "whisper.cpp",
      lang: "64 languages", size: "1.5 GB", revision: "a913bb2",
      sha: "77fe…0b6d", tier: "accurate",
      note: "Required for Hinglish and non-English profiles.",
      installed: false,
    },
  ],

  refineModels: [
    {
      id: "qwen-fast", name: "Refine · Fast", params: "0.6 B",
      size: "394 MB", revision: "f21c88a", sha: "1d9a…44e0",
      license: "Apache-2.0", installed: true,
      note: "Sub-second cleanup on Apple Silicon.",
    },
    {
      id: "qwen-balanced", name: "Refine · Balanced", params: "1.7 B",
      size: "1.1 GB", revision: "0be4d7c", sha: "b52f…9a17",
      license: "Apache-2.0", installed: false,
      note: "Stronger rewrites, still under the 5-second deadline.",
    },
  ],

  languages: [
    "Afrikaans","Albanian","Amharic","Armenian","Azerbaijani","Basque",
    "Belarusian","Bosnian","Burmese","Galician","Georgian",
    "Arabic","Bengali","Bulgarian","Cantonese","Catalan","Croatian","Czech",
    "Danish","Dutch","Estonian","Filipino","Finnish","French","German","Greek",
    "Gujarati","Hebrew","Hindi","Hungarian","Indonesian","Italian","Japanese",
    "Kannada","Kazakh","Korean","Latvian","Lithuanian","Malay","Malayalam",
    "Mandarin","Marathi","Nepali","Norwegian","Persian","Polish","Portuguese",
    "Punjabi","Romanian","Russian","Serbian","Slovak","Slovenian","Spanish",
    "Swahili","Swedish","Tamil","Telugu","Thai","Turkish","Ukrainian","Urdu",
    "Vietnamese","Welsh",
  ],

  history: [
    {
      id: 1, app: "Mail", time: "Today · 2:41 PM", words: 74, wpm: 132,
      text: "Hi Priya, following up on the release checklist — the notarization step is done and I pushed the build to TestFlight this morning.",
      refined: true,
    },
    {
      id: 2, app: "Slack", time: "Today · 1:18 PM", words: 32, wpm: 149,
      text: "Can we move the design review to four thirty? I want to include the new onboarding flow screens.",
      refined: true,
    },
    {
      id: 3, app: "Notes", time: "Today · 11:02 AM", words: 118, wpm: 121,
      text: "Ideas for the launch post: lead with privacy, show the ZenBar states, mention that every model download is checksum verified…",
      refined: false,
    },
    {
      id: 4, app: "Xcode", time: "Yesterday · 6:55 PM", words: 21, wpm: 138,
      text: "Add a guard so the recorder stops cleanly when the microphone disconnects mid dictation.",
      refined: true,
    },
    {
      id: 5, app: "Safari", time: "Yesterday · 3:12 PM", words: 47, wpm: 127,
      text: "Search for whisper CPP quantized model benchmarks on M series chips and open the first result.",
      refined: false,
    },
  ],

  recovery: [
    {
      id: 101, time: "Today · 9:14 AM", reason: "Microphone disconnected",
      partial: "…and the second point I wanted to raise about the migration is",
      usable: true,
    },
    {
      id: 102, time: "Mon · 8:03 PM", reason: "Transcription timed out",
      partial: null, usable: false,
    },
  ],

  phrases: [
    { text: "ZenVoice", uses: 41 },
    { text: "whisper.cpp", uses: 18 },
    { text: "TestFlight", uses: 12 },
    { text: "Priya Sharma", uses: 9 },
    { text: "notarization", uses: 7 },
  ],

  rules: [
    { from: "zen voice", to: "ZenVoice", scope: "Everywhere" },
    { from: "test flight", to: "TestFlight", scope: "Everywhere" },
    { from: "cue one", to: "Q1", scope: "Slack, Mail" },
  ],

  appProfiles: [
    { app: "Mail", icon: "message", lang: "English", refine: "Local Model", commands: true },
    { app: "Slack", icon: "message", lang: "English", refine: "Clean", commands: true },
    { app: "Xcode", icon: "monitor", lang: "English", refine: "Off", commands: false },
    { app: "Notes", icon: "fileText", lang: "Hinglish", refine: "Clean", commands: true },
  ],

  insights: {
    words: 12480, wpm: 131, streak: 9, sessions: 86,
    week: [
      { d: "Mon", v: 1240 }, { d: "Tue", v: 2210 }, { d: "Wed", v: 1730 },
      { d: "Thu", v: 2640 }, { d: "Fri", v: 1980 }, { d: "Sat", v: 620 },
      { d: "Sun", v: 2060 },
    ],
    apps: [
      { name: "Mail", pct: 34 }, { name: "Slack", pct: 27 },
      { name: "Notes", pct: 19 }, { name: "Xcode", pct: 12 },
      { name: "Safari", pct: 8 },
    ],
    categories: [
      { name: "Writing & email", pct: 44 }, { name: "Team chat", pct: 29 },
      { name: "Coding", pct: 15 }, { name: "Research", pct: 12 },
    ],
  },

  commands: [
    { say: "new line", does: "Inserts a line break" },
    { say: "new paragraph", does: "Inserts a blank line" },
    { say: "period / comma / question mark", does: "Inserts punctuation" },
    { say: "bullet list", does: "Starts a bulleted list" },
    { say: "all caps on / off", does: "Toggles capital letters" },
    { say: "undo that", does: "Removes the last phrase" },
  ],
  commandLanguages: ["English", "Hindi", "Spanish", "French", "Mandarin", "Arabic"],

  faqs: [
    {
      q: "Does my voice ever leave this Mac?",
      a: "No. Recording, transcription, refinement, history, and insights all run locally. ZenVoice has no accounts, no analytics, and no cloud transcription service. The only network use is downloading models you explicitly request — each one checksum-verified.",
      tags: "privacy cloud offline network",
    },
    {
      q: "How do I start dictating?",
      a: "Place the cursor in any text field and press ⌃⌥Space (or your custom shortcut). Speak while ZenBar shows the waveform, then press the shortcut again — the text is inserted where your cursor is. You can also enable hold-to-dictate in Shortcuts.",
      tags: "start dictate shortcut begin how",
    },
    {
      q: "What is Private Dictation?",
      a: "Press ⌃⌥P to dictate without saving anything: no history entry, no insights, no recovery audio. ZenBar shows a slashed-eye badge while it's active.",
      tags: "private incognito secret history",
    },
    {
      q: "Why does ZenVoice need Accessibility permission?",
      a: "macOS requires it to type the finished text into the active app. Without it, ZenVoice still works — the transcript is copied to your clipboard instead, and you paste manually.",
      tags: "accessibility permission paste insert",
    },
    {
      q: "What happens if transcription fails mid-sentence?",
      a: "Anything usable lands in the Recovery Inbox (History → Recovery) with Copy, Retry, and Delete actions. Temporary audio is deleted after every attempt either way.",
      tags: "fail crash recovery partial lost",
    },
    {
      q: "How does Hinglish mode work?",
      a: "With a Multilingual model installed, the Hinglish profile writes Hindi-English speech in Latin script the way you'd type it. You can also choose native Devanagari output or local English translation.",
      tags: "hinglish hindi language multilingual devanagari",
    },
    {
      q: "What does Instant Refine actually change?",
      a: "Clean removes fillers, repeated words, and spoken restarts — never meaning. Agent Prompt formats your speech as a structured prompt. Local Model uses a verified on-device model with a 5-second deadline, a no-invention guard, and automatic fallback to Clean.",
      tags: "refine clean agent model rewrite grammar",
    },
    {
      q: "Which model should I download?",
      a: "Open Models — ZenVoice measures this Mac and marks a recommendation. Fast favors latency, Balanced is the best accuracy per second for most machines, High Accuracy is the multilingual pick.",
      tags: "model download recommend fast balanced accuracy",
    },
    {
      q: "Can I correct a word it keeps getting wrong?",
      a: "Yes. Voice Profile → Correction rules: add \"what I said → what I meant\", optionally scoped to specific apps. Rules are encrypted and deletable one by one, independent of History.",
      tags: "correction wrong word fix rules dictionary",
    },
    {
      q: "How do I delete everything?",
      a: "Privacy shows a live inventory of everything stored — encrypted transcripts, recovery audio, correction rules, downloaded models — each with its own Delete control. There is no hidden data.",
      tags: "delete erase remove data reset",
    },
  ],
};
