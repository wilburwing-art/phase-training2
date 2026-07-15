// ProfileScreen.swift — Profile tab, Option-C settings-row pattern.
//
// Header + planTuningSection live at the top as before. Everything below
// is a SettingsRow that opens a focused editor sheet, grouped by intent:
//   · Training setup (sports, seasons, focuses, session length, lift days,
//                     equipment, experience)
//   · About you     (age + gender + height/weight)
//   · Adjustments   (dislikes, injuries)
//   · App           (reminders, coach, data)
//
// Session length + lift days keep the build-67 tap-to-edit alert pattern,
// but render via SettingsRow with a value summary; tapping the row opens
// the existing alert TextField. The .fileImporter / ShareSheet / backup
// alerts stay on this screen — DataEditorSheet just toggles the parent
// flags via closures. The backup/restore/erase state machine itself lives
// in BackupCoordinator (Data/); row value summaries live in
// ProfileScreen+RowSummaries.swift.

import SwiftUI
import UniformTypeIdentifiers

struct ProfileScreen: View {
    // `store` + `subStore` are internal (not private) so the RowSummaries
    // extension file can read them.
    @EnvironmentObject var store: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject var subStore: SubscriptionStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore

    // Backup / restore / erase state machine. The iOS-level presentation
    // surfaces stay on this screen, bound to the coordinator's published
    // state; DataEditorSheet just fires callbacks.
    @StateObject private var backup = BackupCoordinator()

    // Editor-sheet presentation flags.
    @State private var presentingSportsEditor = false
    @State private var presentingSeasonsEditor = false
    @State private var presentingSupportEditor = false
    @State private var presentingEquipmentEditor = false
    @State private var presentingExperienceEditor = false
    @State private var presentingAboutEditor = false
    @State private var presentingDislikesEditor = false
    @State private var presentingInjuriesEditor = false
    @State private var presentingRemindersEditor = false
    @State private var presentingDataEditor = false
    @State private var presentingHealthImports = false
    @State private var presentingPaywall = false
    @State private var presentingBodyWeightLog = false
    @State private var presentingBodyCompositionLog = false
    @State private var presentingPlateCalculator = false
    #if DEBUG
    @State private var presentingMuscleChipGenerator = false
    #endif

    // Tap-to-edit alert for the two number fields (build 67). Still triggered
    // by tapping the SettingsRow value cell.
    @State private var editingField: EditingField? = nil
    @State private var editingText: String = ""
    // Transient notice shown under the edited rows when an out-of-range
    // value gets clamped, so 999 → 120 isn't a silent rewrite.
    @State private var clampNotice: String? = nil

    // Danger zone: confirm before the irreversible full data wipe.
    @State private var showEraseConfirm = false

    enum EditingField: String, Identifiable {
        case sessionMinutes, liftDays
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sessionMinutes: return "Session length"
            case .liftDays:       return "Lift days per week"
            }
        }
        var unit: String {
            switch self {
            case .sessionMinutes: return "minutes"
            case .liftDays:       return "days"
            }
        }
        var clamp: ClosedRange<Int> {
            switch self {
            case .sessionMinutes: return TrainingConstraints.sessionMinutesUIRange
            case .liftDays:       return TrainingConstraints.liftDaysRange
            }
        }
    }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    planTuningSection

                    settingsGroup("TRAINING SETUP") {
                        SettingsRow(label: "Sports",
                                    value: sportsSummary,
                                    icon: "figure.run",
                                    action: { presentingSportsEditor = true })
                        SettingsRow(label: "Seasons",
                                    value: seasonsSummary,
                                    icon: "calendar",
                                    action: { presentingSeasonsEditor = true })
                        // The primary/support wedge is ski/board-primary +
                        // climbing-support, so the row only appears for a
                        // ski/snow primary sport (the interference table is
                        // authored for exactly that pairing).
                        if PhaseRule.skiSlugs.contains(store.memory.primarySport?.slug ?? "") {
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
                        SettingsRow(label: "Session length",
                                    value: "\(store.memory.sessionMinutes) min",
                                    icon: "clock",
                                    action: { beginEditing(.sessionMinutes) })
                        SettingsRow(label: "Lift days",
                                    value: liftDaysSummary,
                                    icon: "dumbbell",
                                    action: { beginEditing(.liftDays) })
                        if let notice = clampNotice {
                            Text(notice)
                                .font(.monoXS)
                                .foregroundStyle(Color.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        SettingsRow(label: "Equipment",
                                    value: equipmentSummary,
                                    icon: "wrench.and.screwdriver",
                                    action: { presentingEquipmentEditor = true })
                        SettingsRow(label: "Experience",
                                    value: experienceSummary,
                                    icon: "chart.line.uptrend.xyaxis",
                                    action: { presentingExperienceEditor = true })
                    }

                    settingsGroup("ABOUT YOU") {
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
                    }

                    settingsGroup("TOOLS") {
                        SettingsRow(label: "Plate calculator",
                                    value: "Barbell math",
                                    icon: "circle.grid.cross",
                                    action: { presentingPlateCalculator = true })
                    }

                    settingsGroup("ADJUSTMENTS") {
                        SettingsRow(label: "Exercises to avoid",
                                    value: dislikesSummary,
                                    icon: "hand.raised",
                                    action: { presentingDislikesEditor = true })
                        SettingsRow(label: "Injuries",
                                    value: injuriesSummary,
                                    icon: "cross.case",
                                    action: { presentingInjuriesEditor = true })
                    }

                    settingsGroup("APP") {
                        SettingsRow(label: "Reminders",
                                    value: remindersSummary,
                                    icon: "bell",
                                    action: { presentingRemindersEditor = true })
                        CoachSettingsRow()
                        SettingsRow(label: "Health & Imports",
                                    value: "Workout history",
                                    icon: "heart.text.square",
                                    action: { presentingHealthImports = true })
                        SettingsRow(label: "Subscription",
                                    value: subscriptionRowValue,
                                    icon: "sparkles",
                                    action: { presentingPaywall = true })
                        SettingsRow(label: "Data",
                                    value: "Backup / Restore",
                                    icon: "externaldrive",
                                    action: { presentingDataEditor = true })
                        #if DEBUG
                        SettingsRow(label: "Regenerate muscle chips",
                                    value: "DEBUG",
                                    icon: "figure.strengthtraining.traditional",
                                    action: { presentingMuscleChipGenerator = true })
                        #endif
                    }

                    dangerZoneSection

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
        // Editor sheets.
        .sheet(isPresented: $presentingSportsEditor) {
            SportsEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingSeasonsEditor) {
            SeasonsEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingSupportEditor) {
            SupportSportEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingEquipmentEditor) {
            EquipmentEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingExperienceEditor) {
            ExperienceEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingAboutEditor) {
            AboutYouEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingDislikesEditor) {
            DislikesEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingInjuriesEditor) {
            InjuriesEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingRemindersEditor) {
            RemindersEditorSheet().environmentObject(store)
        }
        .sheet(isPresented: $presentingDataEditor) {
            DataEditorSheet(
                onExport: backup.exportBackup,
                onImport: { backup.presentingImporter = true }
            )
        }
        .sheet(isPresented: $presentingHealthImports) {
            HealthImportsScreen()
                .environmentObject(store)
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
        #if DEBUG
        .sheet(isPresented: $presentingMuscleChipGenerator) {
            MuscleChipGeneratorView()
        }
        #endif
        // iOS-level surfaces — owned by the parent screen so they survive
        // child-sheet dismissal.
        .sheet(isPresented: $backup.presentingShare) {
            if let url = backup.exportURL {
                ShareSheet(items: [url])
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
            Text("This replaces your current profile, workouts, history, and plan with the backup from \(formattedShort(envelope.exportedAt)). It can't be undone.")
        }
        .alert("Restore complete", isPresented: $backup.restoreCompleted) {
            Button("Done") {}
        } message: {
            Text("Your data was restored.")
        }
        .alert(editingField?.title ?? "", isPresented: editingFieldBinding) {
            TextField(editingField?.unit ?? "", text: $editingText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { editingField = nil }
            Button("Save") { commitEditingValue() }
        } message: {
            if let field = editingField {
                Text("Enter \(field.clamp.lowerBound)–\(field.clamp.upperBound) \(field.unit).")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROFILE")
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text("You.")
                .font(.custom("SpaceGrotesk-SemiBold", size: 38))
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
            sectionLabel("HOW WE'RE TUNING YOUR PLAN")
            VStack(alignment: .leading, spacing: 8) {
                tuningRow(
                    label: "LIFT DAYS",
                    value: "\(lifts.lowerBound)-\(lifts.upperBound) / WEEK",
                    matches: lifts.contains(store.memory.liftDaysPerWeek),
                    actualHint: lifts.contains(store.memory.liftDaysPerWeek) ? nil : "You set \(store.memory.liftDaysPerWeek)"
                )
                tuningRow(
                    label: "SESSION",
                    value: "\(mins.lowerBound)-\(mins.upperBound) MIN",
                    matches: mins.contains(store.memory.sessionMinutes),
                    actualHint: mins.contains(store.memory.sessionMinutes) ? nil : "You set \(store.memory.sessionMinutes)"
                )
                tuningRow(
                    label: "DIFFICULTY",
                    value: profile.preferredDifficulties.first?.uppercased() ?? "—",
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
                            .font(.custom("Inter-Regular", size: 12))
                            .foregroundStyle(Color.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func tuningRow(label: String, value: String, matches: Bool, actualHint: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.custom("JetBrainsMono-SemiBold", size: 13))
                .foregroundStyle(Color.ink)
            Spacer()
            if let actualHint {
                Text(actualHint.uppercased())
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
            } else if matches {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ok)
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

    // MARK: - Tap-to-edit alert plumbing

    private var editingFieldBinding: Binding<Bool> {
        Binding(
            get: { editingField != nil },
            set: { if !$0 { editingField = nil } }
        )
    }

    private func beginEditing(_ field: EditingField) {
        editingField = field
        switch field {
        case .sessionMinutes: editingText = String(store.memory.sessionMinutes)
        case .liftDays:       editingText = String(store.memory.liftDaysPerWeek)
        }
    }

    private func commitEditingValue() {
        guard let field = editingField else { return }
        defer { editingField = nil }
        guard let raw = Int(editingText.trimmingCharacters(in: .whitespaces)) else { return }
        let clamped = max(field.clamp.lowerBound, min(field.clamp.upperBound, raw))
        clampNotice = clamped == raw
            ? nil
            : "\(field.title) adjusted to \(clamped) — valid range is \(field.clamp.lowerBound)–\(field.clamp.upperBound) \(field.unit)."
        store.update { mem in
            switch field {
            case .sessionMinutes: mem.sessionMinutes = clamped
            case .liftDays:       mem.liftDaysPerWeek = clamped
            }
        }
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
                        .font(.system(size: 16, weight: .medium))
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
                                        customStore: customStore)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes your profile, weekly plan, saved sessions, custom routines, imported history, and reminder. You'll be returned to onboarding.")
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
}
