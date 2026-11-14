# App Store listing

Draft 2026-09-21. Field limits from App Store Connect are noted; lengths
were counted. Numbers come from the shipped `coach.db` (580 exercises,
118 routines, 217 sport categories) and the app's own copy.

## Product page

**Name** (30): Phase Training

**Subtitle** (30): Training that fits your season

**Category**: Health & Fitness. Secondary: Sports.

**Promotional text** (170, editable without a new build):

> Plan your lifting week around the sport you actually do. 580 illustrated exercises, season phases and Apple Health import.

**Description** (4000):

> Phase Training plans your strength week around the sport you do outside the gym. Tell it your primary sport, the second one you refuse to give up, and where you are in the season. Your week is ready in three questions, and it changes when your life does.
>
> BUILT AROUND YOUR SPORT
> Pick from over 200 sports and activities, from climbing and skiing to trail running, BJJ, mountain biking and golf. Lifts are chosen for what your sport asks of your body, and they flex around the days you are on the rock, the snow or the trail.
>
> SEASON PHASES
> Off-season, pre-season, in-season and maintenance, with build, deload, taper and peak weeks inside them. Volume and intensity follow the calendar of your season rather than a generic 12-week template.
>
> A LIBRARY YOU CAN SEE
> 580 exercises, every one drawn in the same clean line-art style with the working muscle highlighted and the start and finish positions animated. 118 ready-made routines. Filter by muscle, equipment and sport.
>
> LOG FAST, KEEP TRAINING
> Supersets, rest timers, last-time numbers beside every set, RPE and notes. If Apple Music is playing, the track sits at the bottom of the log with pause and skip so you never leave the app mid-session.
>
> APPLE HEALTH
> Import recent workouts so the plan knows how active you have really been, and log the ski day or the climb it finds in one tap. Body weight and body composition can populate your log. Every workout you finish is saved to Health once, so it counts toward your rings.
>
> PROGRESS THAT MEANS SOMETHING
> Streaks, PRs, weekly volume, body weight and composition trends, soreness check-ins, and a recovery read that feeds back into next week.
>
> INJURIES AND CONSTRAINTS
> Declare an injury, its side and severity, and the exercises that would aggravate it are filtered out. Dislike a movement and it stops appearing.
>
> PRIVATE BY DEFAULT
> Your data lives on your phone. No account, no analytics, no tracking. Nothing leaves the device unless you export it.
>
> PHASE TRAINING PRO
> Two-sport planning that de-conflicts your primary and support sports, and season-phase programming.
>
> Pro is an auto-renewing subscription, monthly or yearly, with a one-week free trial. Payment is charged to your Apple ID at confirmation. It renews automatically unless cancelled at least 24 hours before the end of the current period, and you can manage or cancel it in your Apple ID settings.
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://wilburwing-art.github.io/phase-training2/privacy.html
>
> Phase Training is a training planner, not medical advice. Talk to a clinician before starting a program, especially if you are carrying an injury.

**Keywords** (100, comma-separated, no spaces):

> workout,planner,strength,climbing,skiing,gym,log,periodization,season,trail,lifting,mountain,sport

Do not repeat words already in the name or subtitle ("training", "phase"); Apple indexes those already.

**What's New** (first release):

> First App Store release. Every exercise now has line-art with the start and finish positions animated, Apple Health access is offered during setup, and the Log screen shows what Apple Music is playing.

**Support URL**: https://wilburwing-art.github.io/phase-training2/support.html
**Marketing URL**: https://wilburwing-art.github.io/phase-training2/
**Privacy Policy URL**: https://wilburwing-art.github.io/phase-training2/privacy.html
**Copyright**: 2026 Wilbur Pyn

**Age rating**: answer No to every content question; Unrestricted Web Access No; Medical/Treatment Information No (it is a training planner and the disclaimer says so). Expected result 4+.

## Subscriptions

**Group**: Phase Training Pro. Group display name (30): Phase Training Pro.

| product id | reference name | display name (30) | description (45) | price | period | intro offer |
|---|---|---|---|---|---|---|
| com.phasetraining.app.pro_monthly | Pro Monthly | Pro Monthly | Two-sport planning around your season | $2.99 | 1 month | 1 week free |
| com.phasetraining.app.pro_yearly | Pro Annual | Pro Annual | Two-sport planning, best value | $24.99 | 1 year | 1 week free |

Prices decided 2026-11-13: $2.99 monthly as the owner asked, $24.99 yearly (about seven months of monthly), one week free on both. Revisit both when the coach comes back behind Pro, since each coach turn costs money and two-sport planning costs nothing to serve. Both products need a review screenshot of the paywall (docs/store, or the `paywall-terms` attachment from `PaywallHeroUITests`) and a review note.

## App Privacy questionnaire

Collected data, all "used for App Functionality", "not linked to the user", "not used for tracking":

- Health & Fitness → Health: workouts, body weight, body fat, lean mass, read from Apple Health with permission.
- Not declared, and why (build 145): heart rate variability, resting heart rate and sleep read from Apple Health behind their own tap-only permission. They are summarised and stored on device only, never sent to the AI Coach or anywhere else, so under Apple's definition they are not "collected" and the label does not change. If a later build puts them in the coach snapshot or uploads them, add them under Health & Fitness → Health before that build ships.
- Health & Fitness → Fitness: logged workouts, sets, RPE, soreness.
- Sensitive Info: none. Contact Info: none. Identifiers: none. Usage Data: none. Diagnostics: none.

Third party: none in the first store release, which ships without the AI Coach (decided 2026-11-13). In the build that brings the coach back, declare the training context sent to Anthropic through the developer's Cloudflare AI Gateway under the Health & Fitness types as data the developer collects for app functionality; it is opt-in, off by default, and the privacy policy lists every field. No tracking, no advertising, `NSPrivacyTracking` is false in the manifest.

## App Review notes

> Phase Training works fully without Apple Health, Apple Music or a subscription; choose "Not now" on the Health step of setup to skip the permission sheet.
>
> Recovery data (heart rate variability, resting heart rate, sleep) has its own read-only Health permission, requested only when the tester taps "Capture recovery data" in Profile → Health & Imports. The nightly summaries stay on the device.
>
> Apple Health writes: when the tester finishes a workout, the app asks for the workout share permission (once) and saves that session as a strength-training workout, tagged with a sync identifier so it is saved once. Reads stay as described above. The app never edits or deletes other Health data.
>
> Apple Music: the Log screen shows a transport card for the currently playing track. It only appears while music is playing, and the media-library permission is requested only when the tester taps "Show controls".
>
> Pro (two-sport planning) unlocks with the sandbox subscription from Profile → Subscription.
>
> To reach a populated app quickly: complete setup with any sport, then Today → Start workout.

## Before submitting

- **Decided 2026-11-13: the first store release ships without the coach.** See
  `DECISION-coach-at-launch.md`. The store build must go out with the repo variable
  `PHASETRAINING_BETA` unset or `1`, which blanks the gateway token and hides every
  coach surface. The copy above is already cut to match.
- **Decided 2026-11-13: the first store build charges for Pro.** Pro is the Support Sport editor and the two-sport reflow, the one thing `SupportEntitlement` gates. Create both products in App Store Connect, then flip `SupportEntitlement.proRequired` to true in the same build (its flip-day checklist is in the file, including the lapsed-subscriber rule). `CoachEntitlement.proRequired` stays false until the coach returns.
- Season-phase programming is listed as a Pro feature on the paywall and in the description, and no gate covers it: every user gets season phases. Gate it or move the line out of the Pro copy before submitting.
- Reshoot the paywall screenshot: the two coach rows no longer show on a build without a gateway token.
- Reshoot `02-week.png` on a real plan (see docs/store/README.md).
- Re-run the paywall UI test against the live products once they exist in App Store Connect.
