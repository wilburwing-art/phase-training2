# App Store listing

Draft 2026-09-21. Field limits from App Store Connect are noted; lengths
were counted. Numbers come from the shipped `coach.db` (580 exercises,
118 routines, 217 sport categories) and the app's own copy.

## Product page

**Name** (30): Phase Training

**Subtitle** (30): Training that fits your season

**Category**: Health & Fitness. Secondary: Sports.

**Promotional text** (170, editable without a new build):

> Plan your lifting week around the sport you actually do. 580 illustrated exercises, season phases, Apple Health import, and a coach that can move your week.

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
> APPLE HEALTH, READ-ONLY
> Import recent workouts so the plan knows how active you have really been, and log the ski day or the climb it finds in one tap. Body weight and body composition can populate your log. Phase Training never writes to Health.
>
> PROGRESS THAT MEANS SOMETHING
> Streaks, PRs, weekly volume, body weight and composition trends, soreness check-ins, and a recovery read that feeds back into next week.
>
> INJURIES AND CONSTRAINTS
> Declare an injury, its side and severity, and the exercises that would aggravate it are filtered out. Dislike a movement and it stops appearing.
>
> PRIVATE BY DEFAULT
> Your data lives on your phone. No account, no analytics, no tracking. Nothing leaves the device unless you turn on the AI Coach.
>
> PHASE TRAINING PRO
> Two-sport planning that de-conflicts your primary and support sports, season-phase programming, and an AI coach you can talk to: it can shift your week, swap a lift, and give weekly insights and recovery feedback. The coach is off until you switch it on and agree to what it sends.
>
> Pro is an auto-renewing subscription, monthly or yearly, with a one-week free trial. Payment is charged to your Apple ID at confirmation. It renews automatically unless cancelled at least 24 hours before the end of the current period, and you can manage or cancel it in your Apple ID settings.
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://wilburwing-art.github.io/phase-training2/privacy.html
>
> Phase Training is a training planner, not medical advice. Talk to a clinician before starting a program, especially if you are carrying an injury.

**Keywords** (100, comma-separated, no spaces):

> workout,planner,strength,climbing,skiing,gym,log,periodization,season,coach,lifting,mountain,sport

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
| com.phasetraining.app.pro_monthly | Pro Monthly | Pro Monthly | Two-sport planning and the AI coach | $2.99 | 1 month | 1 week free |
| com.phasetraining.app.pro_yearly | Pro Annual | Pro Annual | Two-sport planning, AI coach, best value | $24.99 (proposed) | 1 year | 1 week free |

The yearly price is a proposal (about seven months of monthly); the owner asked for $3/month and did not set a yearly price. Both products need a review screenshot of the paywall (docs/store, or the `paywall-terms` attachment from `PaywallHeroUITests`) and a review note.

## App Privacy questionnaire

Collected data, all "used for App Functionality", "not linked to the user", "not used for tracking":

- Health & Fitness → Health: workouts, body weight, body fat, lean mass, read from Apple Health with permission.
- Health & Fitness → Fitness: logged workouts, sets, RPE, soreness.
- Sensitive Info: none. Contact Info: none. Identifiers: none. Usage Data: none. Diagnostics: none.

Third party: when the user turns on the AI Coach, the training context is sent to Anthropic through the developer's Cloudflare AI Gateway. Declare this under the Health & Fitness types as data the developer collects for app functionality; it is opt-in, off by default, and the privacy policy lists every field. No tracking, no advertising, `NSPrivacyTracking` is false in the manifest.

## App Review notes

> Phase Training works fully without Apple Health, Apple Music or a subscription; choose "Not now" on the Health step of setup to skip the permission sheet.
>
> Apple Health is read-only. The `NSHealthUpdateUsageDescription` string is present only because iOS requires it whenever the HealthKit entitlement is included; the app calls requestAuthorization with an empty share set and never writes.
>
> Apple Music: the Log screen shows a transport card for the currently playing track. It only appears while music is playing, and the media-library permission is requested only when the tester taps "Show controls".
>
> Pro features (two-sport planning, AI Coach) unlock with the sandbox subscription from Profile → Subscription. The AI Coach is off by default; turn it on from Profile → AI Coach and accept the consent screen, which lists what is sent. Coach replies are generated by Anthropic Claude through our gateway; no account is needed and no personal identifiers are sent.
>
> To reach a populated app quickly: complete setup with any sport, then Today → Start workout.

## Before submitting

- Both Pro gates ship "held open" (`CoachEntitlement`, `SupportEntitlement`, `proRequired` false) so everything is free until the products exist. Decide whether the first store build charges for Pro; if yes, flip both gates in the same build that ships the products, or the subscription sells nothing.
- Reshoot `02-week.png` on a real plan (see docs/store/README.md).
- Re-run the paywall UI test against the live products once they exist in App Store Connect.
