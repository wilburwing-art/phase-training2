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
// flags via closures.

import SwiftUI
import UniformTypeIdentifiers

struct ProfileScreen: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var subStore: SubscriptionStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var customStore: CustomRoutineStore

    // Backup / restore UI state (the iOS-level presentation surfaces stay on
    // this screen; DataEditorSheet just fires callbacks).
    @State private var exportURL: URL? = nil
    @State private var presentingImporter = false
    @State private var presentingShare = false
    @State private var backupError: String? = nil
    @State private var restoreCompleted = false
    // Decoded-but-not-yet-applied backup, held while the user confirms the
    // destructive overwrite. Restore only runs after explicit confirmation.
    @State private var pendingRestore: BackupEnvelope? = nil
    @State private var confirmingRestore = false

    // Editor-sheet presentation flags.
    @State private var presentingSportsEditor = false
    @State private var presentingSeasonsEditor = false
    @State private var presentingFocusesEditor = false
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
            case .sessionMinutes: return 15...120
            case .liftDays:       return 0...7
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
                        SettingsRow(label: "Focuses",
                                    value: focusesSummary,
                                    icon: "target",
                                    action: { presentingFocusesEditor = true })
                        SettingsRow(label: "Session length",
                                    value: "\(store.memory.sessionMinutes) min",
                                    icon: "clock",
                                    action: { beginEditing(.sessionMinutes) })
                        SettingsRow(label: "Lift days",
                                    value: liftDaysSummary,
                                    icon: "dumbbell",
                                    action: { beginEditing(.liftDays) })
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
                        SettingsRow(label: "Export eval-rig JSON",
                                    value: "DEBUG",
                                    icon: "square.and.arrow.up.on.square",
                                    action: { exportEvalRigJSON() })
                        #endif
                    }

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
        .sheet(isPresented: $presentingFocusesEditor) {
            FocusesEditorSheet().environmentObject(store)
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
                onExport: exportBackup,
                onImport: { presentingImporter = true }
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
        .sheet(isPresented: $presentingShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(
            isPresented: $presentingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Backup error", isPresented: Binding(
            get: { backupError != nil },
            set: { if !$0 { backupError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupError ?? "")
        }
        .alert("Replace all data?", isPresented: $confirmingRestore, presenting: pendingRestore) { envelope in
            Button("Replace", role: .destructive) { performRestore(envelope) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { envelope in
            Text("This replaces your current profile, workouts, history, and plan with the backup from \(formattedShort(envelope.exportedAt)). It can't be undone.")
        }
        .alert("Restore complete", isPresented: $restoreCompleted) {
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

    // MARK: - Row summaries

    private var sportsSummary: String {
        let sports = store.memory.sports
        guard !sports.isEmpty else { return "None" }
        let primary = store.memory.primarySport ?? sports.first
        let primaryName = primary?.name ?? sports.first?.name ?? ""
        let othersCount = max(0, sports.count - 1)
        if othersCount == 0 { return primaryName }
        return "\(primaryName) +\(othersCount)"
    }

    private var seasonsSummary: String {
        if store.memory.sports.isEmpty {
            return store.memory.defaultSeason.label
        }
        // If every sport's season matches the default, show just the default.
        // Otherwise show "Mixed".
        let perSport = store.memory.sports.map { store.memory.seasonsBySport[$0] ?? store.memory.defaultSeason }
        let unique = Set(perSport)
        if unique.count == 1, let only = unique.first {
            return only.label
        }
        return "Mixed"
    }

    private var focusesSummary: String {
        let focuses = store.memory.focuses
        guard !focuses.isEmpty else { return "None" }
        let primary = focuses[0].label
        if focuses.count == 1 { return primary }
        return "\(primary) +\(focuses.count - 1)"
    }

    private var liftDaysSummary: String {
        let n = store.memory.liftDaysPerWeek
        return "\(n) " + (n == 1 ? "day" : "days") + " / week"
    }

    private var equipmentSummary: String {
        let tier = currentTier
        if tier == .custom {
            let count = store.memory.equipment.count
            return "Custom (\(count))"
        }
        return tier.label
    }

    private var experienceSummary: String {
        store.memory.experience.label
    }

    private var aboutSummary: String {
        var parts: [String] = []
        if let age = store.memory.age { parts.append("\(age)") }
        if let gender = store.memory.gender { parts.append(gender.label) }
        if parts.isEmpty { return "Not set" }
        return parts.joined(separator: " · ")
    }

    private var bodyWeightSummary: String {
        let logCount = store.memory.bodyWeightLog.count
        let imperial = store.memory.usesImperial
        // Prefer the log's newest entry, fall back to the scalar — so a
        // populated log never shows "—" just because the mirror lagged.
        let kg = store.memory.latestBodyWeightEntry?.weightKg ?? store.memory.weightKg
        guard let kg else {
            return logCount == 0 ? "Not set" : "—"
        }
        let weight = BodyMetrics.formatWeight(kg: kg, imperial: imperial)
        if logCount <= 1 { return weight }
        return "\(weight) · \(logCount) entries"
    }

    private var bodyCompositionSummary: String {
        let log = store.memory.bodyCompositionLog.sorted { $0.date > $1.date }
        guard let latest = log.first else { return "Not set" }
        var parts: [String] = []
        if let bf = latest.bodyFatPercent {
            parts.append(String(format: "%.1f%%", bf))
        }
        if let lean = latest.leanMassKg {
            let imperial = store.memory.usesImperial
            let display = imperial ? BodyMetrics.kgToLb(lean) : lean
            parts.append(String(format: "%.0f %@ LBM", display, imperial ? "lb" : "kg"))
        }
        if parts.isEmpty { return "Not set" }
        return parts.joined(separator: " · ")
    }

    private var dislikesSummary: String {
        let count = store.memory.dislikes.count
        if count == 0 { return "None" }
        if count == 1 { return store.memory.dislikes[0] }
        return "\(count) items"
    }

    /// Trailing summary for the Subscription row. Shows "Pro" when the
    /// entitlement is active, otherwise prompts the user to upgrade.
    private var subscriptionRowValue: String {
        subStore.isPro ? "Pro" : "Upgrade"
    }

    private var injuriesSummary: String {
        // Build 87: prefer the typed userInjuries store; free-text constraints
        // that aren't recognised injury slugs still surface (legacy notes).
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        let structuredCount = store.memory.userInjuries.count
        let legacy = store.memory.constraints.filter { !known.contains($0) }
        let total = structuredCount + legacy.count
        if total == 0 { return "None" }
        if total == 1 {
            if let only = store.memory.userInjuries.first,
               let name = CoachDatabase.shared.listInjuries().first(where: { $0.slug == only.slug })?.name {
                return name
            }
            return legacy.first ?? "1 item"
        }
        return "\(total) items"
    }

    private var remindersSummary: String {
        WeeklyReminderScheduler.isEnabled ? "On" : "Off"
    }

    private var currentTier: EquipmentTier {
        let eq = store.memory.equipment
        if eq == [.bodyweight] { return .bodyweight }
        if eq == [.dumbbells]  { return .dumbbells  }
        if eq == [.fullGym]    { return .fullGym    }
        return .custom
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
        store.update { mem in
            switch field {
            case .sessionMinutes: mem.sessionMinutes = clamped
            case .liftDays:       mem.liftDaysPerWeek = clamped
            }
        }
    }

    // MARK: - Backup / restore

    private func exportBackup() {
        do {
            let envelope = BackupManager.snapshot()
            let url = try BackupManager.writeTempFile(envelope)
            exportURL = url
            presentingShare = true
        } catch {
            backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
        }
    }

    #if DEBUG
    /// DEBUG-only: dump a GeneratedWorkout to a JSON file matching the
    /// `~/repos/eval-rig` workout schema, then surface a ShareSheet so the
    /// user can move it into `eval-rig/workouts/<batch>/`. Resolution order:
    ///   1. Today's day in the current plan (if any)
    ///   2. The first generatedWorkout in the plan (any day)
    ///   3. Synthesize one via WorkoutGenerator.generateLift using current
    ///      memory + DemographicProfile (so the button works cold — useful
    ///      when running with --ui-test-onboarded before any plan exists)
    private func exportEvalRigJSON() {
        let workout: GeneratedWorkout = {
            let today = Calendar.current.startOfDay(for: Date())
            if let w = planStore.plan?.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })?.generatedWorkout {
                return w
            }
            if let w = planStore.plan?.days.compactMap(\.generatedWorkout).first {
                return w
            }
            // Cold fallback — synthesize using the real generator path so the
            // exported JSON reflects what the user would actually receive on
            // their first plan-day.
            let memory = store.memory
            let profile = DemographicProfile.from(memory)
            return WorkoutGenerator.generateLift(
                liftIndex: 0,
                totalLifts: max(1, memory.liftDaysPerWeek),
                memory: memory,
                profile: profile,
                hashSeed: "eval-rig-export-\(Int(Date().timeIntervalSince1970))"
            )
        }()

        do {
            let dir = try EvalRigExporter.defaultExportDirectory()
            let url = try EvalRigExporter.exportToFile(
                workout: workout,
                memory: store.memory,
                to: dir
            )
            print("[EvalRigExporter] Wrote \(url.path)")
            exportURL = url
            presentingShare = true
        } catch {
            print("[EvalRigExporter] Export failed: \(error.localizedDescription)")
        }
    }
    #endif

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            backupError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                // Decode + validate now, but defer the destructive write until
                // the user confirms — restore replaces ALL local data.
                let data = try Data(contentsOf: url)
                let envelope = try BackupManager.decode(data)
                pendingRestore = envelope
                confirmingRestore = true
            } catch {
                backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Apply a confirmed restore, then reload every in-memory store from its
    /// source so the UI reflects the imported data immediately — no relaunch.
    private func performRestore(_ envelope: BackupEnvelope) {
        do {
            try BackupManager.restore(envelope, into: .standard)
            store.reload()
            planStore.reloadFromDefaults()
            sessionStore.reload()
            customStore.reload()
            pendingRestore = nil
            restoreCompleted = true
        } catch {
            backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func formattedShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
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
        mem.focuses = [.sportPerformance, .longevity]
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

// MARK: - Share sheet bridge

/// Thin UIActivityViewController wrapper so the Profile screen can present
/// the system share sheet for the export file URL. SwiftUI has ShareLink
/// but the file-URL ergonomics + iPad popover behavior are still cleaner
/// via the UIKit bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
