// ProfileScreen.swift — Profile tab, Option-C settings-row pattern.
//
// Header + planTuningSection live at the top. Everything below is a
// SettingsRow that opens a focused editor sheet, grouped by intent:
//   · PLAN      (plan setup, sports, discipline, seasons, support, goals)
//   · BODY      (about you, body weight, composition, injuries)
//   · EXERCISES (favorites, avoid, plate calculator)
//   · APP       (reminders, coach, health, subscription, data, privacy)
// Session length, lift days, equipment, experience and training focus are
// edited from the Plan setup checklist. The .fileImporter / ShareSheet /
// backup alerts stay on this screen; DataEditorSheet just toggles the parent
// flags via closures. The backup/restore/erase state machine lives in
// BackupCoordinator (Data/); row value summaries live in
// ProfileScreen+RowSummaries.swift.

import SwiftUI
import UniformTypeIdentifiers

struct ProfileScreen: View {
    // `store` + `subStore` are internal (not private) so the RowSummaries
    // extension file can read them.
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject var subStore: SubscriptionStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore
    // Needed only by the erase path: these three persist themselves and would
    // otherwise write their pre-erase caches back after a wipe.
    @EnvironmentObject private var sportLogStore: SportLogStore
    @EnvironmentObject private var recentPicks: RecentPicksStore
    @EnvironmentObject private var conversation: CoachConversationStore
    @EnvironmentObject private var activityDetection: ActivityDetectionStore

    // Backup / restore / erase state machine. The iOS-level presentation
    // surfaces stay on this screen, bound to the coordinator's published
    // state; DataEditorSheet just fires callbacks.
    @StateObject private var backup = BackupCoordinator()
    @AppStorage(WatchSyncCoordinator.appInstalledKey) private var watchAppInstalled = false
    @State private var showingWatchInfo = false

    // Editor-sheet presentation flags.
    @State private var presentingSportsEditor = false
    @State private var presentingSeasonsEditor = false
    @State private var presentingSupportEditor = false
    @State private var presentingDisciplineEditor = false
    @State private var presentingAboutEditor = false
    @State private var presentingFavoritesEditor = false
    @State private var presentingDislikesEditor = false
    @State private var presentingInjuriesEditor = false
    @State private var presentingGoalPicker = false
    @State private var presentingRemindersEditor = false
    @State private var presentingVoiceSettings = false
    @State private var presentingPlaces = false
    @AppStorage(SessionLocationCapture.captureOffKey) private var locationCaptureOff = false
    @State private var presentingDataEditor = false
    /// Action to run once DataEditorSheet has finished dismissing — see the
    /// `.sheet(onDismiss:)` below.
    @State private var pendingDataAction: (() -> Void)?
    @State private var presentingHealthImports = false
    /// Whether anything has ever been imported from Health. Cached rather than
    /// queried per render (see healthImportsRowValue). Refreshed on appear and
    /// when the Health sheet closes, which is the only place a grant happens.
    /// Internal (not private) so the row summary in
    /// ProfileScreen+RowSummaries.swift can read it. That extension must not
    /// query SQLite per render.
    @State var hasHealthImports = false
    @State private var presentingPaywall = false
    @State private var presentingBodyWeightLog = false
    @State private var presentingBodyCompositionLog = false
    @State private var presentingPlateCalculator = false
    @State private var presentingSetupChecklist = false
    #if DEBUG
    @State private var presentingMuscleChipGenerator = false
    @State private var presentingTwinScorecard = false
    #endif

    // Danger zone: confirm before the irreversible full data wipe.
    @State private var showEraseConfirm = false

    private var placesRowValue: String {
        if locationCaptureOff { return "Off" }
        switch PlaceClusterer.cluster(planStore.sessionPlaces).count {
        case 0: return "None yet"
        case 1: return "1 place"
        case let n: return "\(n) places"
        }
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    planTuningSection

                    settingsGroup("PLAN") {
                        // Leads the group: it's the answer to "what is my plan
                        // actually built on", and it edits schedule, equipment,
                        // experience and goal in one place.
                        SettingsRow(label: "Plan setup",
                                    value: setupChecklistSummary,
                                    icon: "checklist",
                                    action: { presentingSetupChecklist = true })
                        SettingsRow(label: "Sports",
                                    value: sportsSummary,
                                    icon: "figure.run",
                                    action: { presentingSportsEditor = true })
                        if store.memory.skisPrimary {
                            SettingsRow(label: "Discipline",
                                        value: store.memory.primaryVariant.disciplineLabel,
                                        icon: "figure.skiing.downhill",
                                        action: { presentingDisciplineEditor = true })
                        }
                        SettingsRow(label: "Seasons",
                                    value: seasonsSummary,
                                    icon: "calendar",
                                    action: { presentingSeasonsEditor = true })
                        // The primary/support wedge is ski/board-primary +
                        // climbing-support, so the row appears for a ski/snow
                        // primary sport (the interference table is authored for
                        // exactly that pairing) or whenever a pattern already
                        // exists, so it stays reachable.
                        //
                        // Planner.applySupportPattern guards only on the
                        // pattern being non-empty and never checks the primary
                        // sport, so a user who declared Tue/Thu climbing days
                        // under a ski primary and then switched to Running lost
                        // the row while the planner kept stamping climbing days
                        // onto rest slots and lightening lift days, with no
                        // reachable UI to turn it off.
                        if SportProfile.of(store.memory.primarySport?.slug).supportFeature
                            || !(store.memory.supportPattern?.isEmpty ?? true) {
                            SettingsRow(label: "Support sport",
                                        value: supportSummary,
                                        icon: "figure.climbing",
                                        action: {
                                            if SupportEntitlement.unlocked(pro: subStore.isPro) {
                                                presentingSupportEditor = true
                                            } else {
                                                presentingPaywall = true
                                            }
                                        })
                        }
                        SettingsRow(label: "Performance goals",
                                    value: goalsSummary,
                                    icon: "target",
                                    action: { presentingGoalPicker = true })
                    }

                    settingsGroup("BODY") {
                        SettingsRow(label: "About you",
                                    value: aboutSummary,
                                    icon: "person",
                                    action: { presentingAboutEditor = true })
                        SettingsRow(label: "Body weight",
                                    value: bodyWeightSummary,
                                    icon: "scalemass",
                                    action: { presentingBodyWeightLog = true })
                        SettingsRow(label: "Body composition",
                                    value: bodyCompositionSummary,
                                    icon: "chart.bar.xaxis",
                                    action: { presentingBodyCompositionLog = true })
                        SettingsRow(label: "Injuries",
                                    value: injuriesSummary,
                                    icon: "cross.case",
                                    action: { presentingInjuriesEditor = true })
                    }

                    settingsGroup("EXERCISES") {
                        SettingsRow(label: "Favorite exercises",
                                    value: favoritesSummary,
                                    icon: "hand.thumbsup",
                                    action: { presentingFavoritesEditor = true })
                        SettingsRow(label: "Exercises to avoid",
                                    value: dislikesSummary,
                                    icon: "hand.raised",
                                    action: { presentingDislikesEditor = true })
                        SettingsRow(label: "Plate calculator",
                                    value: "Barbell math",
                                    icon: "circle.grid.cross",
                                    action: { presentingPlateCalculator = true })
                    }

                    settingsGroup("APP") {
                        SettingsRow(label: "Reminders",
                                    value: remindersSummary,
                                    icon: "bell",
                                    action: { presentingRemindersEditor = true })
                        SettingsRow(label: "Voice",
                                    value: voiceSummary,
                                    icon: "waveform",
                                    action: { presentingVoiceSettings = true })
                        // No row in a build without a gateway token (every
                        // beta build): the toggle would read "On" for a coach
                        // that cannot send.
                        if CoachEntitlement.coachAvailable {
                            CoachSettingsRow()
                        }
                        SettingsRow(label: "Health & Imports",
                                    value: healthImportsRowValue,
                                    icon: "heart.text.square",
                                    action: { presentingHealthImports = true })
                        // Nothing is for sale until a gate closes or App Store
                        // products load; before that the paywall is a dead end.
                        // --ui-test-show-subscription shows the row before
                        // products load, so the paywall test does not depend
                        // on StoreKit test mode timing (FB22237318).
                        if CoachEntitlement.proRequired || SupportEntitlement.proRequired
                            || !subStore.products.isEmpty
                            || ProcessInfo.processInfo.arguments.contains("--ui-test-show-subscription") {
                            SettingsRow(label: "Subscription",
                                        value: subscriptionRowValue,
                                        icon: "sparkles",
                                        action: { presentingPaywall = true })
                        }
                        if watchAppInstalled {
                            SettingsRow(label: "Apple Watch",
                                        value: "App installed",
                                        icon: "applewatch",
                                        action: { showingWatchInfo = true })
                                .accessibilityIdentifier("profile-watch-row")
                        }
                        SettingsRow(label: "Data",
                                    value: BackupStatus.rowValue(
                                        lastExport: backup.lastBackupExport,
                                        iCloudWrite: backup.lastICloudWrite,
                                        iCloudSignedIn: backup.iCloudSignedIn,
                                        sessions: sessionStore.savedSessions),
                                    icon: "externaldrive",
                                    valueTint: BackupStatus.needsNudge(
                                        lastExport: backup.lastBackupExport,
                                        iCloudWrite: backup.lastICloudWrite,
                                        sessions: sessionStore.savedSessions) ? .accent : .ink3,
                                    action: { presentingDataEditor = true })
                        SettingsRow(label: "Places",
                                    value: placesRowValue,
                                    icon: "mappin.and.ellipse",
                                    action: { presentingPlaces = true })
                            .accessibilityIdentifier("profile-places-row")
                        SettingsRow(label: "Privacy Policy",
                                    value: "What the app reads and sends",
                                    icon: "hand.raised",
                                    action: { openURL(CoachConsent.privacyPolicyURL) })
                        #if DEBUG
                        SettingsRow(label: "Regenerate muscle chips",
                                    value: "DEBUG",
                                    icon: "figure.strengthtraining.traditional",
                                    action: { presentingMuscleChipGenerator = true })
                        SettingsRow(label: "Signals & shadow twin",
                                    value: "DEBUG",
                                    icon: "waveform.path.ecg",
                                    action: { presentingTwinScorecard = true })
                        #endif
                    }

                    dangerZoneSection

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        .statusBarBackdrop()
        // Editor sheets.
        .sheet(isPresented: $presentingPlaces) {
            PlacesSheet().environmentObject(planStore)
        }
        .sheet(isPresented: $presentingSportsEditor) {
            SportsEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingSeasonsEditor) {
            SeasonsEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingGoalPicker) {
            GoalPickerSheet(
                activeGoals: store.memory.userGoals,
                onConfirm: { goals in
                    store.memory.userGoals = Array(goals.prefix(2))
                    store.save()
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $presentingSupportEditor) {
            SupportSportEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingDisciplineEditor) {
            SkiDisciplineSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingAboutEditor) {
            AboutYouEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingFavoritesEditor) {
            FavoritesEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingDislikesEditor) {
            DislikesEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingInjuriesEditor) {
            InjuriesEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingVoiceSettings) {
            VoiceSettingsSheet()
        }
        .sheet(isPresented: $presentingRemindersEditor) {
            RemindersEditorSheet().environmentObject(store)
        }
        // Both the data editor and the share sheet hang off this same view, so
        // firing the share while the editor is still the presented controller
        // logged "attempt to present … which is already presenting" and the
        // share sheet never appeared. Defer the follow-on presentation into
        // `onDismiss`, which runs once the editor has actually gone away.
        .sheet(isPresented: $presentingDataEditor, onDismiss: {
            if let action = pendingDataAction {
                pendingDataAction = nil
                action()
            }
        }) {
            DataEditorSheet(
                onExport: { pendingDataAction = { backup.exportBackup() } },
                onImport: { pendingDataAction = { backup.presentingImporter = true } },
                onExportCSV: sessionStore.savedSessions.isEmpty ? nil : {
                    let sessions = sessionStore.savedSessions
                    let imperial = store.memory.usesImperial
                    pendingDataAction = { backup.exportWorkoutsCSV(sessions: sessions, usesImperial: imperial) }
                }
            )
        }
        .sheet(isPresented: $presentingHealthImports, onDismiss: { refreshHealthImportState() }) {
            HealthImportsScreen()
                .environmentObject(store)
                .environmentObject(sessionStore)
        }
        .onAppear {
            refreshHealthImportState()
            backup.refreshCloudStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            backup.refreshCloudStatus()
        }
        .alert("Apple Watch", isPresented: $showingWatchInfo) {
            Button("OK") {}
        } message: {
            Text("Start today's workout on the watch, or start it here and mark sets on either. Sets sync both ways.")
        }
        .sheet(isPresented: $presentingBodyWeightLog) {
            BodyWeightLogSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingBodyCompositionLog) {
            BodyCompositionLogSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingPlateCalculator) {
            PlateCalculatorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingPaywall) {
            PaywallView()
                .environmentObject(subStore)
        }
        .sheet(isPresented: $presentingSetupChecklist) {
            SetupChecklistSheet().environmentObject(store)
        }
        #if DEBUG
        .sheet(isPresented: $presentingMuscleChipGenerator) {
            MuscleChipGeneratorView()
        }
        .sheet(isPresented: $presentingTwinScorecard) {
            TwinScorecardSheet()
                .environmentObject(planStore)
                .environmentObject(sessionStore)
                .environmentObject(store)
        }
        #endif
        // iOS-level surfaces — owned by the parent screen so they survive
        // child-sheet dismissal.
        .sheet(isPresented: $backup.presentingShare) {
            if let url = backup.exportURL {
                ShareSheet(items: [url]) { completed in
                    backup.shareFinished(completed: completed)
                }
            }
        }
        .fileImporter(
            isPresented: $backup.presentingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            backup.handleImport(result)
        }
        .alert("Backup error", isPresented: Binding(
            get: { backup.backupError != nil },
            set: { if !$0 { backup.backupError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backup.backupError ?? "")
        }
        .alert("Replace all data?", isPresented: $backup.confirmingRestore, presenting: backup.pendingRestore) { envelope in
            Button("Replace", role: .destructive) {
                backup.performRestore(envelope,
                                      store: store,
                                      planStore: planStore,
                                      sessionStore: sessionStore,
                                      customStore: customStore)
            }
            Button("Cancel", role: .cancel) { backup.pendingRestore = nil }
        } message: { envelope in
            // T2-5: isMemorySchemaStale was fully implemented and documented as
            // "callers can surface a 'backup is from an older version' notice
            // off this" — and no caller did; grep found it only in its own
            // declaration and the tests. So a user restoring a backup written
            // by an older TrainingMemory schema silently got defaults for every
            // field added since, with nothing telling them.
            Text("This replaces your current profile, workouts, history, and plan with the backup from \(formattedShort(envelope.exportedAt)). It can't be undone."
                 + (envelope.isMemorySchemaStale
                    ? "\n\nThis backup predates some settings this version stores. Those will come back as defaults, so check Profile afterwards."
                    : ""))
        }
        .alert("Restore complete", isPresented: $backup.restoreCompleted) {
            Button("Done") {}
        } message: {
            Text("Your data was restored.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("You.")
                .font(.scaled("SpaceGrotesk-SemiBold", size: 38))
                .tracking(-0.025 * 38)
                .foregroundStyle(Color.ink)
            if let onboarded = store.memory.onboardedAt {
                Text("Set up \(formattedShort(onboarded))")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    // MARK: - Plan tuning section (unchanged)

    private var planTuningSection: some View {
        let profile = DemographicProfile.from(store.memory)
        let lifts = profile.recommendedLiftDays
        let mins  = profile.recommendedSessionMinutes
        return VStack(alignment: .leading, spacing: 12) {
            // These are recommendations; the settings below are what the plan
            // uses. Named as such, with the setting beside each, so "2-3" above
            // "3 days / week" no longer reads as two answers to one question.
            sectionLabel("RECOMMENDED FOR YOU")
            VStack(alignment: .leading, spacing: 8) {
                tuningRow(
                    label: "LIFT DAYS",
                    value: "\(lifts.lowerBound)-\(lifts.upperBound) / WEEK",
                    matches: lifts.contains(store.memory.liftDaysPerWeek),
                    actualHint: "You set \(store.memory.liftDaysPerWeek)"
                )
                tuningRow(
                    label: "SESSION",
                    value: "\(mins.lowerBound)-\(mins.upperBound) MIN",
                    matches: mins.contains(store.memory.sessionMinutes),
                    actualHint: "You set \(store.memory.sessionMinutes)"
                )
                tuningRow(
                    label: "DIFFICULTY",
                    value: profile.preferredDifficulties.first?.uppercased() ?? "-",
                    matches: true,
                    actualHint: profile.preferredDifficulties.count > 1
                        ? "Fallback: \(profile.preferredDifficulties.dropFirst().joined(separator: ", "))"
                        : nil
                )
                if !profile.allowedEnvironments.isEmpty {
                    tuningRow(
                        label: "ROUTINES",
                        value: profile.allowedEnvironments.sorted().joined(separator: " · ").uppercased(),
                        matches: true,
                        actualHint: nil
                    )
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(profile.rationale, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .styled(.body)
                            .foregroundStyle(Color.ink3)
                        Text(line)
                            .font(.scaled("Inter-Regular", size: 12))
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }


    /// One COUNT(*) on appear and after the Health sheet closes, cached into
    /// `hasHealthImports`. The row reads the flag so the Profile tab does not
    /// hit SQLite on every render.
    private func refreshHealthImportState() {
        hasHealthImports = (UserDatabase.shared.importedWorkoutSummary()?.count ?? 0) > 0
    }
    private func tuningRow(label: String, value: String, matches: Bool, actualHint: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.scaled("JetBrainsMono-SemiBold", size: 13))
                .foregroundStyle(Color.ink)
            Spacer()
            if let actualHint {
                // Quiet when the setting sits inside the range, accent when not.
                Text(actualHint.uppercased())
                    .styled(.micro)
                    .foregroundStyle(matches ? Color.ink3 : Color.accent)
            }
            if matches {
                Image(systemName: "checkmark")
                    .scaledSystemFont(11, weight: .semibold)
                    .foregroundStyle(Color.ok)
                    .accessibilityLabel("within the recommendation")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Settings groups

    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(title)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    // MARK: - Danger zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("DANGER ZONE")
            Button(role: .destructive) {
                showEraseConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .scaledSystemFont(16, weight: .medium, within: 24)
                        .foregroundStyle(Color.red)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erase all my data")
                            .styled(.body)
                            .foregroundStyle(Color.ink)
                        Text("Removes everything stored on this device. Cannot be undone.")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer(minLength: 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-erase-all-data")
            .confirmationDialog(
                "Erase all data?",
                isPresented: $showEraseConfirm,
                titleVisibility: .visible
            ) {
                Button("Erase everything", role: .destructive) {
                    backup.eraseAllData(store: store,
                                        planStore: planStore,
                                        sessionStore: sessionStore,
                                        customStore: customStore,
                                        sportLogStore: sportLogStore,
                                        recentPicks: recentPicks,
                                        conversation: conversation,
                                        activityDetection: activityDetection)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your profile, weekly plan, saved sessions, custom routines, imported history, and reminder. You'll be returned to onboarding. The weekly backup in iCloud Drive stays. Remove it in Settings > your name > iCloud > Manage Account Storage.")
            }
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func formattedShort(_ d: Date) -> String {
        Self.shortDateFormatter.string(from: d)
    }
}

#Preview("Empty") {
    let defaults = UserDefaults(suiteName: "Profile.preview.empty")!
    return ProfileScreen()
        .environmentObject(MemoryStore(defaults: defaults))
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(CustomRoutineStore(defaults: defaults))
        .environmentObject(SubscriptionStore())
        .environmentObject(SportLogStore(defaults: defaults))
        .environmentObject(RecentPicksStore(defaults: defaults))
        .environmentObject(CoachConversationStore(defaults: defaults))
}

#Preview("Populated") {
    let suite = "Profile.preview.populated"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.sports = [Sport.catalog[1], Sport.catalog[2]]
        mem.primarySport = Sport.catalog[1]
        mem.defaultSeason = .preSeason
        mem.seasonsBySport = [Sport.catalog[1]: .inSeason]
        mem.liftDaysPerWeek = 2
        mem.equipment = [.dumbbells]
        mem.experience = .intermediate
        mem.age = 32
        mem.gender = .male
        mem.dislikes = ["burpees"]
        mem.constraints = ["left knee"]
        mem.onboardedAt = Date()
    }
    return ProfileScreen()
        .environmentObject(store)
        .environmentObject(PlanStore(defaults: defaults))
        .environmentObject(SessionStore(defaults: defaults))
        .environmentObject(CustomRoutineStore(defaults: defaults))
        .environmentObject(SubscriptionStore())
        .environmentObject(SportLogStore(defaults: defaults))
        .environmentObject(RecentPicksStore(defaults: defaults))
        .environmentObject(CoachConversationStore(defaults: defaults))
}
