# 11. App Review and privacy label

**Status:** closed 2026-09-03
**Lens:** business

## Question

Does what leaves the device match what the app says leaves the device, and what
would get this rejected?

## Depth actually reached

Full on egress, the three disclosure surfaces, Info.plist, entitlements and the
privacy manifest. F3 reasons from Apple's required-reason API rules rather than
from a fetched copy of the current guideline text; **check Apple's current
privacy-manifest requirements before acting on it**, since that rule has moved
more than once.

## What holds up

The privacy posture is better than most apps this size, and the good parts
should be said before the findings:

- **Exactly one network destination.** A grep for `https://` across the app
  returns the Cloudflare AI Gateway and a Swift package URL in a comment.
  `docs/privacy.md:33` states it: "no analytics, advertising, or tracking SDKs."
  That is true as far as the code shows.
- **HealthKit data does not reach the Coach.** Greps for `imported`, `health`,
  `bodyFat`, `leanMass` and `BodyComposition` across `PhaseTraining/Coach/`
  return **nothing**. Health-derived workouts and body-composition readings stay
  on device. This is the single most important thing to get right for a health
  app that talks to a third-party LLM, and it is right.
- **The Health usage strings are unusually honest.**
  `NSHealthUpdateUsageDescription` explains that the app never writes and that
  iOS requires the string anyway. That is the kind of copy that makes a reviewer
  relax.
- **The entitlement is minimal**: `com.apple.developer.healthkit` with an empty
  access array. No background delivery, no clinical records.

## Findings

### F1 (critical, App Review) Three surfaces describe the Coach payload and all three are different, with the legally-operative one the least accurate

| surface | what it says is sent |
|---|---|
| `CoachConsent.modalBody` | plan, workout history, logged sets, body metrics (height/weight/age/gender), injuries and soreness including notes, estimated strength numbers, messages |
| `CoachConsent.shortDisclosure` | plan, workouts, body metrics, injury notes |
| `docs/privacy.md:27` | "the text of your messages plus a snapshot of your current plan, recent workout feedback, and today's plan day" |

The privacy policy omits body metrics and injuries entirely. It is the document
Apple's reviewer reads and the one a user is directed to.

What is actually assembled, from the section headers in
`PhaseTraining/Coach/CoachContext*.swift`:

```
USER PROFILE          STRUCTURED INJURIES     INJURY FILTERS
CURRENT WEEK PLAN     PAST WEEKS              PLAN ISSUES
RECENT SESSIONS       LAST SESSION DETAIL     WEEK ADHERENCE
MISSED WORKOUTS       RECENT SPORT LOGS       RECENT POST-WORKOUT FEEDBACK
DISLIKES              CONSTRAINTS             STRENGTH
MUSCLE BALANCE        PATTERN FREQUENCY       EXERCISE FAMILIARITY
RECOVERY TREND        IN-SEASON READINESS     TRAINING ERA AFFINITY
```

Twenty-two blocks. Four of them carry free text the user typed and no surface
names: `DISLIKES`, `CONSTRAINTS`, sport-log notes under `RECENT SPORT LOGS`,
and feedback notes under `RECENT POST-WORKOUT FEEDBACK`. The system prompt
itself enumerates exactly those four as untrusted user-authored text
(`CoachSystemPrompt.swift`), so the code knows they are personal statements
while the disclosures do not mention them.

T0-5 fixed this class of defect in the in-app copy and did not carry the fix to
`docs/privacy.md`.

### F2 (high, App Review) The privacy policy link the consent flow promises does not exist

`CoachConsent.swift:8` describes the flow as presenting "the consent modal with
provider name, what's sent, and **a link to the privacy policy**." There is no
such link. A grep for a privacy URL across `PhaseTraining/` returns the
Info.plist manifest key and that comment, and nothing else.

The 2026-08-23 backlog named this explicitly inside T0-5: "Include the
privacy-policy link CoachConsent.swift:6 promises (docs/privacy.md exists; needs
a hosted URL)." T0-5 is checked off. This sub-item was not done. See critique 12.

`docs/index.md` already links `privacy.html`, so the page exists in the docs
tree; what is missing is a hosted URL and a button in the modal.

### F3 (high, submission blocker) There is no PrivacyInfo.xcprivacy file

`find . -name "*.xcprivacy"` returns nothing, and `xcprivacy` appears nowhere in
`Project.yml`, `scripts/` or `.github/`.

Instead, `NSPrivacyCollectedDataTypes` is declared inside **Info.plist**
(`PhaseTraining/Info.plist`), which is not where Apple reads a privacy manifest.

Two consequences to check before submission:

1. **Required-reason APIs.** This app uses `UserDefaults` pervasively (it is the
   primary persistence layer alongside SQLite), and `UserDefaults` is a
   required-reason API whose declared reason belongs in a privacy manifest.
   Missing declarations produce an automated notice at upload.
2. **The declared data type is wrong for what is sent.** The single declared
   type is `NSPrivacyCollectedDataTypeOtherUserContent`. The Coach transmits
   body metrics, injuries, soreness and derived strength estimates, which fall
   under Apple's Health and Fitness data types. Declaring only Other User
   Content under-declares the sensitive categories, and the App Store privacy
   label generated from it will not match F1's own consent modal.

### F4 REFUTED 2026-09-04 — the policy's Health sentence is correct

This finding claimed `docs/privacy.md:23` over-disclosed by saying
Health-confirmed sessions "may be part of the coach's context". It does not.

Raw HealthKit data never reaches `CoachContext`, which is what the greps
established and what the "What holds up" section above still correctly says.
But confirming a detected activity **writes a `SportLogEntry`**
(`Health/ActivityDetection.swift:8,136`), and sport logs are one of the 22
context blocks. So a session the user confirmed from Health does travel, as a
logged sport session, exactly as the sentence describes.

Left in place and corrected rather than deleted: this was a wrong finding that
would have led someone to "fix" an accurate sentence into an inaccurate one.
The under-disclosure half of the original claim stands and is F1.

### F5 (medium, staleness) A code comment contradicts the shipped consent default

`CoachConsent.swift:4-5`: "AI Coach off by default for existing installs;
**on by default for new installs** (set in onboarding)."

T0-5 changed onboarding so neither option is pre-selected and Continue is gated
on an affirmative pick (`OnboardingCoachConsentScreen.swift:8,35`). The comment
was not updated. `docs/privacy.md:9,13` says off by default, which is now the
closer description.

Low impact on behaviour, high impact if a reviewer or a future maintainer reads
the comment as the spec.

### F6 (medium, App Review) The prescribing app has no disclaimer

Carried from critique 03 F4. A grep across `PhaseTraining/` and `docs/` for
`disclaimer`, `not medical`, `informational purposes`, `at your own risk`,
`consult`, `physician` or `healthcare` returns one hit, inside the model's
prompt. For an app that collects declared injuries including disc herniations
and stress fractures, prescribes barbell loads, and ships hangboard and campus
board protocols, a reviewer asking "where does it say this is not medical
advice" has no answer to find.

### F7 (low) The gateway account id is compiled in alongside the token

`https://gateway.ai.cloudflare.com/v1/192ffcc4f56e84386ddc0875eab97826/phasetraining/anthropic`
is a string literal in the app. The account id is not itself a secret, but with
the T0-1 token it forms the complete callable path. Recorded as part of the
T0-1 external work rather than as a separate item.

## Refuted

- **"HealthKit data is sent to Anthropic."** It is not. This was the first thing
  checked and the greps are clean. `docs/privacy.md:23` claims it might be,
  which is F4.
- **"The app has analytics or tracking."** It does not. One egress host, no SDKs.
- **"The Health usage strings are boilerplate."** They are not; they are among
  the better-written strings in the app.

## Ordering

F3 first, because it is the one that stops an upload rather than starting a
conversation. F1 and F2 together next: rewrite `docs/privacy.md` from
`CoachConsent.modalBody` plus the four undisclosed free-text blocks, host it,
and put the link in the modal the code already promises it is in. F6 is one
screen of copy and closes critique 03's safety gap at the same time.
