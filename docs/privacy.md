---
title: Phase Training — Privacy Policy
---

# Phase Training — Privacy Policy

_Effective 2026-05-17_

Phase Training is a personal workout-logging iOS app. By default it runs entirely on your device. Optional features that send data to a third party are listed below and require your explicit consent before any transmission.

## Data collected

Phase Training does not collect personal data, usage analytics, crash reports, or device identifiers. No information is sent off your device unless you opt into the AI Coach (see below).

## Data stored locally

Workout sessions you record (exercises, sets, weights, reps, RPE, notes, feel ratings) are saved on your device using iOS's standard local storage. Uninstalling the app removes this data.

## Apple Health (optional, read-only)

If you grant access, Phase Training reads from Apple Health on your device: recent workouts (activity type, date, duration, and calories) and, with a separate permission, body weight, body-fat percentage, and lean-mass readings. This data is used to gauge your training readiness, to match generated workouts to your real activity, and to offer to log outdoor sessions the app finds (for example a ski day or a climb) so your training week can adjust. It is stored locally alongside the rest of your log and never leaves your device on its own.

Phase Training never writes to Apple Health, and Health data is never used for advertising or shared with data brokers. If you enable the AI Coach below, summaries of your logged activity, which can include sessions you confirmed from Health, may be part of the coach's context; nothing is sent unless the AI Coach is on. You can revoke Health access at any time in iOS Settings → Health → Data Access & Devices.

## AI Coach (optional, off by default)

If you enable the AI Coach in Profile → AI Coach, the app sends a snapshot of your training context to Anthropic (Claude) via our Cloudflare AI Gateway proxy each turn. That snapshot is assembled fresh per message and can include:

- the text of your messages to the coach;
- your current week's plan, past weeks, and any plan issues or missed workouts;
- your completed sessions and logged sets, including sport sessions you confirmed from Apple Health;
- body metrics you have entered: height, weight, age, gender;
- injuries you have declared, their severity, side and onset, your own notes on them, and which exercises they filtered out;
- soreness and post-workout feedback, including free-text notes;
- dislikes and constraints you have written;
- derived figures the app computes from the above: estimated strength numbers, muscle balance, movement-pattern frequency, exercise familiarity, recovery trend, and week adherence.

No name, email, or device identifier is sent. The data is used only to generate the coach's response and is not used to train any model.

Anthropic's processing is governed by their [Commercial Terms](https://www.anthropic.com/legal/commercial-terms) and [Privacy Policy](https://www.anthropic.com/legal/privacy). You can disable the AI Coach at any time from the same screen — once off, no further data leaves your device.

## Third parties

Phase Training contains no analytics, advertising, or tracking SDKs. The only third-party network destination is the AI Coach's gateway, and only when you've toggled the AI Coach on.

## Contact

Questions or concerns: open an issue on the [GitHub repository](https://github.com/wilburwing-art/phase-training2).
