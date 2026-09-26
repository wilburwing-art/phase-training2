---
title: Phase Training — Privacy Policy
---

# Phase Training — Privacy Policy

_Effective 2026-09-21_ (previous version 2026-05-17)

Phase Training is a personal workout-logging iOS app. By default it runs entirely on your device. Optional features that send data to a third party are listed below and require your explicit consent before any transmission.

## Data collected

Phase Training does not collect personal data, usage analytics, crash reports, or device identifiers. No information is sent off your device unless you opt into the AI Coach (see below).

## Data stored locally

Workout sessions you record (exercises, sets, weights, reps, RPE, notes, feel ratings) are saved on your device using iOS's standard local storage. Uninstalling the app removes this data.

## Apple Health (optional, read-only)

Phase Training asks for Apple Health access once, as a step of the first-run setup, with a "Not now" choice that skips it. If you skip it you can connect later in Profile → Health & Imports, and the app works fully without it. If you grant access, Phase Training reads from Apple Health on your device: recent workouts (activity type, date, duration, and calories) and, with a separate permission, body weight, body-fat percentage, and lean-mass readings. This data is used to gauge your training readiness, to match generated workouts to your real activity, and to offer to log outdoor sessions the app finds (for example a ski day or a climb) so your training week can adjust. It is stored locally alongside the rest of your log and never leaves your device on its own.

Phase Training never writes to Apple Health, and Health data is never used for advertising or shared with data brokers. If you enable the AI Coach below, summaries of your logged activity, which can include sessions you confirmed from Health, may be part of the coach's context; nothing is sent unless the AI Coach is on. You can revoke Health access at any time in iOS Settings → Health → Data Access & Devices.

## Apple Music (optional, transport controls only)

The Log screen can show the track Apple Music is playing, with pause and skip, so you can change songs without leaving the app. Showing that card needs iOS's media-library permission. When music is playing and permission has not been given, the Log screen offers a "Show controls" button; the permission prompt appears only if you tap it, and if you decline, the card stays hidden. Phase Training only reads the currently playing item's title, artist and artwork while the Log screen is open. It never reads your library, playlists or listening history, never changes your library, never starts playback on its own, and stores nothing about what you played. Nothing from Apple Music is included in the AI Coach's context. You can revoke access at any time in iOS Settings → Privacy & Security → Media & Apple Music.

## Calendar (optional, read-only, only when you ask)

The weekly check-in has a "Find travel in my calendar" button. The calendar permission prompt appears only if you tap it, and the app works fully without it. When you tap it, Phase Training reads the events in your calendars for the week being planned, on your device, to spot trips: hotel or rental stays, flights, and multi-day events away. Each day it finds is added to that week's plan as a day titled "Travel", which you can remove before accepting the week.

Event titles, locations, attendees and notes are not stored, and nothing read from your calendar leaves your device. Only the resulting travel dates are kept, and those carry the generic title "Travel", so no calendar content reaches the AI Coach even when the coach is on. Phase Training never adds, edits or deletes calendar events. You can revoke access at any time in iOS Settings → Privacy & Security → Calendars.

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

Phase Training contains no analytics, advertising, or tracking SDKs. The only third-party network destination is the AI Coach's gateway, and only when you've toggled the AI Coach on. Exercise images and the exercise catalogue ship inside the app; nothing is fetched to display them.

## Subscriptions

Phase Training Pro is an auto-renewing subscription sold through Apple. Purchases are handled by the App Store; Phase Training never sees your payment details, and receives from Apple only whether a subscription is active. Manage or cancel it in your Apple ID subscription settings.

## Changes

This page is updated when the app asks for a new permission or sends data somewhere new. The effective date at the top changes with it.

## Contact

Questions or concerns: open an issue on the [GitHub repository](https://github.com/wilburwing-art/phase-training2) or email wilburwing@gmail.com.
