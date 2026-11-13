# Handoff: rest-timer Live Activity (widget extension)

Phase 6 item 1 of PLAN-gap-backlog-2026-11b.md. The app now embeds a widget
extension, `PhaseTrainingWidgets` (bundle id `com.phasetraining.app.widgets`),
that draws the rest countdown on the Lock Screen and in the Dynamic Island.

## Release signing

The widget extension signs with its own App Store profile, named
`PhaseTraining Widgets App Store` in Project.yml. `release.yml` installs it from
the repo secret `BUILD_WIDGET_PROVISION_PROFILE_BASE64` (step "Install widget
extension provisioning profile") and maps `com.phasetraining.app.widgets` to it
in ExportOptions.plist. A missing secret stops the run at that step with the
reason in the log. `test.yml` builds with `CODE_SIGNING_ALLOWED=NO` and needs
no profile.

The secret was set on 2026-11-12 (`gh secret list`). No tagged release has
archived with it yet, so the first tag after this lands is the first check that
the profile's name and App ID match.

To recreate the profile (new distribution certificate, expiry):

1. Identifiers: App ID `com.phasetraining.app.widgets`, team A2Z2RXR65P,
   explicit, no extra capabilities. Live Activities need only the
   `NSSupportsLiveActivities` plist key; there is no App Group and no push
   entitlement.
2. Profiles: an iOS App Store distribution profile for that App ID on the
   Apple Distribution certificate, named `PhaseTraining Widgets App Store`.
3. Base64-encode the .mobileprovision into
   `BUILD_WIDGET_PROVISION_PROFILE_BASE64`.

## Behavior notes

- Expiry: the app sets `staleDate` to the rest end date and also sends
  `finished = true` when it sees the rest run out while foregrounded. The widget
  shows "Rest done" if either is set; the `Text(timerInterval:)` also stops at
  0:00. The system cannot run code at expiry, so a suspended app relies on the
  stale transition. This was not observed on a device.
- The existing "Rest's up" local notification is unchanged.
- Rest state is view-local and not persisted, so every cold launch ends any
  leftover activity.
- Starting an activity needs the app in the foreground. A watch-driven rest that
  arrives while the phone app is backgrounded updates an existing activity but
  cannot start a new one.
- Lock Screen "Skip rest" and "+15" buttons are not included. Rest state lives
  in LogScreen `@State`, so an App Intent would need a new shared store or a
  bridge into the screen, which is more than the optional budget.
- `scripts/quality/verify_font_tokens.sh` scans only `PhaseTraining/`. The widget
  folder uses system fonts and no `.custom(`, so it complies; extend the script
  if custom fonts are ever added there.
