# ZenVoice Private Beta

Thank you for testing ZenVoice. This page explains what it does, what it asks
your Mac for and why, and how to get rid of it cleanly if you decide not to keep
it.

ZenVoice is a dictation app. You press a shortcut, speak, and the text is
inserted into whatever app you were already typing in.

## What you need

- An Apple Silicon Mac (M1 or later)
- **macOS 27.** ZenVoice is built to run on macOS 14 and newer, but macOS 27 is
  the only version this beta has been tested on. If you are on something older
  and want to help test it, say so — that is useful information rather than a
  problem.
- About 1 GB of disk space for a speech model, which the app downloads on first
  use.

## Installing

1. Unzip `ZenVoice-distribution.zip`.
2. Drag **ZenVoice.app** into your Applications folder.
3. Open it.

You should *not* see a warning saying the app is from an unidentified developer
or cannot be checked for malware. ZenVoice is signed with an Apple Developer ID
and has been notarized by Apple, which means Apple has scanned this exact build.
**If you do see that warning, stop and tell me** — it means something is wrong
with the build, and I would rather hear about it than have you click through.

## The two permissions, and why

macOS will ask for two things. Both requests are real and both deserve
scepticism, so here is exactly what each one is for.

### Microphone

To hear you. Audio is transcribed on your Mac by a local speech model. It is not
uploaded anywhere.

### Accessibility

This is the one worth explaining, because macOS describes it alarmingly and it
genuinely is a powerful permission.

ZenVoice needs it to put text into the app you are currently using. That is the
entire product — without it, ZenVoice can transcribe but cannot type for you.
Specifically it is used to:

- send a paste keystroke to the app you have focused;
- write text directly into the focused field when macOS secure input is active
  and a keystroke would be swallowed;
- read the focused field's current text and cursor position when replacing text
  ZenVoice itself just inserted with a cleaned-up version.

That last one means ZenVoice can read the contents of the field you are typing
in. It is used in memory to find the text it wrote, and it is never saved,
never included in history, and never sent anywhere.

**You can decline it.** ZenVoice still works: it transcribes and copies the
result to your clipboard, and you paste it yourself.

ZenVoice deliberately refuses to type into password fields, and refuses fields
it cannot positively identify while macOS reports secure input is active. In
those cases it copies to the clipboard instead and tells you so.

## What leaves your Mac

Nothing you say or type.

There is no account, no login, no analytics, no telemetry, and no cloud
transcription. The app makes exactly one kind of network request: downloading a
speech model from Hugging Face when you ask it to, verified against a checksum
before installation.

Your transcripts, if you enable history, are encrypted on disk with a key held
in your Mac's Keychain.

If you want the detail, [Privacy](PRIVACY.md) documents every piece of data the
app touches, and the source is public — you are welcome to check rather than
take my word for it.

## First run

1. Open **Models** and download a speech model. **Whisper Turbo** is the
   recommended model on Apple Silicon. If you dictate in another language, or
   in Hinglish, pick the model the screen suggests for it.
2. Open **Shortcuts** to see or change the dictation shortcut.
3. Put your cursor somewhere you can type, press the shortcut, say a sentence,
   and press it again.

## What is worth reporting

Everything, but especially:

- text inserted into the wrong place, or not at all;
- transcription that is wrong in a way that seems consistent rather than random;
- anything that hangs, crashes, or leaves ZenBar stuck;
- anything that made you hesitate about privacy or permissions;
- the moment you gave up on a task and did it by hand instead.

That last one is the most valuable and the least reported.

**Please do not paste private transcript text into a bug report.** Describe what
happened. If the exact wording matters, change the names and details first.

## Removing it

- Quit ZenVoice from the menu bar.
- Use **Privacy → Delete All** first if you enabled history. This deletes saved
  transcripts and rotates the encryption key.
- Drag ZenVoice.app to the Trash.
- Downloaded speech models live in
  `~/Library/Application Support/ZenVoice/` — delete that folder to remove them.
- Revoke Microphone and Accessibility in **System Settings → Privacy &
  Security** if you want to be thorough.

## Cost

ZenVoice is free during this beta — an initial one to three month period. There
is no trial timer, no licence key, and no payment mechanism in the app; there is
nothing to cancel. What happens after that period has not been decided, and
nothing will start charging you silently.

## This is a beta

It has been through a full manual test pass and its security and privacy
behaviour has been reviewed and documented, but it has been used in earnest by
very few people. Assume rough edges. Do not rely on it for something you cannot
afford to lose, and keep History enabled if you would rather be able to recover
a dictation that goes wrong.
