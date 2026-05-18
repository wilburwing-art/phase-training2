// ProfileScreen.swift — Profile tab. Mirror of onboarding inputs, edits
// round-trip directly into MemoryStore.memory. Each section reuses the same
// chip / pick-row primitives the onboarding flow uses.
//
// Lives at the top level of the Profile tab — no inner navigation. A single
// scroll view with section dividers; everything is editable in place.

import SwiftUI
import UniformTypeIdentifiers

struct ProfileScreen: View {
    @EnvironmentObject private var store: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @State private var dislikeInput = ""
    @State private var remindersOn = WeeklyReminderScheduler.isEnabled
    @State private var remindersPending = false

    // Backup / restore UI state
    @State private var exportURL: URL? = nil
    @State private var presentingImporter = false
    @State private var presentingShare = false
    @State private var backupError: String? = nil
    @State private var restorePending = false
    @State private var restoreCompleted = false

    // Injury picker state
    @State private var presentingInjuryPicker = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if planStore.needsRegeneration(for: store.memory) {
                        driftBanner
                    }

                    planTuningSection
                    Divider().background(Color.lineSoft)
                    sportsSection
                    Divider().background(Color.lineSoft)
                    seasonsSection
                    Divider().background(Color.lineSoft)
                    focusSection
                    Divider().background(Color.lineSoft)
                    sessionLengthSection
                    Divider().background(Color.lineSoft)
                    liftDaysSection
                    Divider().background(Color.lineSoft)
                    equipmentSection
                    Divider().background(Color.lineSoft)
                    experienceSection
                    Divider().background(Color.lineSoft)
                    aboutSection
                    Divider().background(Color.lineSoft)
                    dislikesSection
                    Divider().background(Color.lineSoft)
                    constraintsSection
                    Divider().background(Color.lineSoft)
                    remindersSection
                    Divider().background(Color.lineSoft)
                    CoachSettingsRow()
                    Divider().background(Color.lineSoft)
                    dataSection

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
        }
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
        .alert("Restore complete", isPresented: $restoreCompleted) {
            Button("Done") {}
        } message: {
            Text("Your data was restored. Restart the app to refresh every screen.")
        }
        .sheet(isPresented: $presentingInjuryPicker) {
            InjuryPickerSheet(
                initialSelection: selectedInjurySlugs,
                onCommit: { newSlugs in commitInjuries(newSlugs) }
            )
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

    // MARK: - Drift banner

    /// Shown when the current memory hash doesn't match the saved plan's
    /// inputs hash — i.e. the user changed something here but the plan still
    /// reflects the old profile. One-tap refresh regenerates the whole week.
    private var driftBanner: some View {
        Button {
            planStore.regenerateWeek(memory: store.memory)
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan is out of date")
                        .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                        .foregroundStyle(Color.ink)
                    Text("Tap to regenerate this week from your new profile.")
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentWash)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentBorder, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-refresh-plan")
    }

    // MARK: - Sections

    /// Demographic-derived recommendations. Pulls from DemographicProfile so
    /// the user can see *why* their plan looks the way it does — and how
    /// changing experience / age / equipment below will shift it.
    private var planTuningSection: some View {
        let profile = DemographicProfile.from(store.memory)
        let lifts = profile.recommendedLiftDays
        let mins  = profile.recommendedSessionMinutes
        return VStack(alignment: .leading, spacing: 12) {
            section("HOW WE'RE TUNING YOUR PLAN")
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

    private var sportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("SPORTS")
            WrappingFlow(spacing: 8) {
                ForEach(Sport.catalog) { sport in
                    OnboardingChip(
                        label: sport.name,
                        selected: store.memory.sports.contains(sport),
                        action: { toggleSport(sport) }
                    )
                }
            }
            if store.memory.sports.count > 1 {
                Text("PRIMARY")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    ForEach(store.memory.sports) { sport in
                        OnboardingPickRow(
                            title: sport.name,
                            subtitle: nil,
                            selected: store.memory.primarySport == sport,
                            action: {
                                store.update { $0.primarySport = sport }
                            }
                        )
                    }
                }
            }
        }
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("SEASONS")
            if store.memory.sports.isEmpty {
                Text("DEFAULT")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                seasonChips(
                    selected: store.memory.defaultSeason,
                    onPick: { s in store.update { $0.defaultSeason = s } }
                )
            } else {
                ForEach(store.memory.sports) { sport in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sport.name.uppercased())
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        seasonChips(
                            selected: store.memory.seasonsBySport[sport] ?? store.memory.defaultSeason,
                            onPick: { s in store.update { $0.seasonsBySport[sport] = s } }
                        )
                    }
                }
                Text("OTHERWISE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 4)
                seasonChips(
                    selected: store.memory.defaultSeason,
                    onPick: { s in store.update { $0.defaultSeason = s } }
                )
            }
        }
    }

    private func seasonChips(selected: SeasonPhase, onPick: @escaping (SeasonPhase) -> Void) -> some View {
        WrappingFlow(spacing: 6) {
            ForEach(SeasonPhase.allCases) { phase in
                OnboardingChip(
                    label: phase.label,
                    selected: selected == phase,
                    action: { onPick(phase) }
                )
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("FOCUSES")
            VStack(spacing: 8) {
                ForEach(PrimaryFocus.allCases) { focus in
                    OnboardingPickRow(
                        title: focus.label,
                        subtitle: focus.subtitle,
                        selected: store.memory.focuses.contains(focus),
                        action: { toggleFocus(focus) }
                    )
                }
            }
            if store.memory.focuses.count > 1 {
                Text("PRIMARY")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    ForEach(store.memory.focuses) { focus in
                        OnboardingPickRow(
                            title: focus.label,
                            subtitle: nil,
                            selected: store.memory.focuses.first == focus,
                            action: { setPrimaryFocus(focus) }
                        )
                    }
                }
            }
        }
    }

    private var sessionLengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("SESSION LENGTH")
            valueStepper(
                value: "\(store.memory.sessionMinutes)",
                unit: "MIN",
                onMinus: { adjustMinutes(-15) },
                onPlus:  { adjustMinutes(15) }
            )
        }
    }

    private var liftDaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("LIFT DAYS PER WEEK")
            valueStepper(
                value: "\(store.memory.liftDaysPerWeek)",
                unit: store.memory.liftDaysPerWeek == 1 ? "DAY" : "DAYS",
                onMinus: { adjustLifts(-1) },
                onPlus:  { adjustLifts(1) }
            )
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("EQUIPMENT")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(EquipmentTier.allCases) { tier in
                    Button {
                        selectTier(tier)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tier.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(currentTier == tier ? Color.accent : Color.ink2)
                            Text(tier.label)
                                .styled(.body)
                                .foregroundStyle(Color.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(currentTier == tier ? Color.accentWash : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(currentTier == tier ? Color.accentBorder : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            if currentTier == .custom {
                Text("PICK WHAT YOU HAVE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 6)
                WrappingFlow(spacing: 8) {
                    ForEach(Equipment.allCases.filter { $0 != .fullGym }) { eq in
                        OnboardingChip(
                            label: eq.label,
                            selected: store.memory.equipment.contains(eq),
                            action: { toggleCustomEquipment(eq) }
                        )
                    }
                }
            }
        }
    }

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("EXPERIENCE")
            VStack(spacing: 8) {
                ForEach(ExperienceLevel.allCases) { lvl in
                    OnboardingPickRow(
                        title: lvl.label,
                        subtitle: lvl.subtitle,
                        selected: store.memory.experience == lvl,
                        action: { store.update { $0.experience = lvl } }
                    )
                }
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("ABOUT YOU")

            HStack {
                Text("AGE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if store.memory.age != nil {
                    Button("Clear") { store.update { $0.age = nil } }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            valueStepper(
                value: store.memory.age.map(String.init) ?? "—",
                unit: "YEARS",
                onMinus: { adjustAge(-1) },
                onPlus:  { adjustAge(1) }
            )

            HStack {
                Text("GENDER")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                if store.memory.gender != nil {
                    Button("Clear") { store.update { $0.gender = nil } }
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                }
            }
            WrappingFlow(spacing: 8) {
                ForEach(Gender.allCases) { g in
                    OnboardingChip(
                        label: g.label,
                        selected: store.memory.gender == g,
                        action: { store.update { $0.gender = $0.gender == g ? nil : g } }
                    )
                }
            }

            HStack(spacing: 10) {
                Text("HEIGHT & WEIGHT")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Button(store.memory.usesImperial ? "Use metric" : "Use imperial") {
                    store.update { $0.usesImperial.toggle() }
                }
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
            }
            // BodyMetricsEditor mutates a Binding<TrainingMemory>; route it
            // back through store.update so the change persists immediately
            // (same pattern as every other section on this screen).
            BodyMetricsEditor(draft: Binding(
                get: { store.memory },
                set: { newMemory in store.update { $0 = newMemory } }
            ))
            Text("Used for strength-to-bodyweight ratios on Progress.")
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
        }
    }

    private var dislikesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("EXERCISES TO AVOID")
            tagList(items: store.memory.dislikes,
                    input: $dislikeInput,
                    placeholder: "e.g. burpees",
                    onAdd: { v in store.update { $0.dislikes.append(v) } },
                    onRemove: { v in store.update { $0.dislikes.removeAll { $0 == v } } })
        }
    }

    private var constraintsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("INJURIES")
            injuriesPicker
            if !legacyConstraints.isEmpty {
                Text("OTHER NOTES (LEGACY)")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 6)
                WrappingFlow(spacing: 8) {
                    ForEach(legacyConstraints, id: \.self) { item in
                        legacyChip(item)
                    }
                }
            }
        }
    }

    /// Slugs in TrainingMemory.constraints that match a known coach.db injury.
    private var selectedInjurySlugs: Set<String> {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        return Set(store.memory.constraints.filter { known.contains($0) })
    }

    /// Free-text constraint entries (anything in memory.constraints not
    /// matching a known injury slug). These came from the pre-picker UI;
    /// keep them visible + removable until the user upgrades to the picker.
    private var legacyConstraints: [String] {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        return store.memory.constraints.filter { !known.contains($0) }
    }

    /// Selected injuries as chips + an "Add injury" button.
    private var injuriesPicker: some View {
        let selected = selectedInjurySlugs
        let all = CoachDatabase.shared.listInjuries()
        let nameFor: (String) -> String = { slug in
            all.first(where: { $0.slug == slug })?.name ?? slug
        }
        return VStack(alignment: .leading, spacing: 10) {
            if !selected.isEmpty {
                WrappingFlow(spacing: 8) {
                    ForEach(Array(selected).sorted(), id: \.self) { slug in
                        injuryChip(label: nameFor(slug), onRemove: {
                            removeInjury(slug)
                        })
                    }
                }
            }
            Button {
                presentingInjuryPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text(selected.isEmpty ? "Add injuries" : "Edit injuries")
                        .styled(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(selected.isEmpty ? Color.accent : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(selected.isEmpty ? Color.accentWash : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected.isEmpty ? Color.accentBorder : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-add-injury")
            if selected.isEmpty && legacyConstraints.isEmpty {
                Text("We'll filter out exercises that aren't safe for the injuries you pick.")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private func injuryChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.accentWash)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.accentBorder, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

    private func legacyChip(_ item: String) -> some View {
        HStack(spacing: 6) {
            Text(item)
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.ink)
            Button {
                store.update { $0.constraints.removeAll { $0 == item } }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
        .background(Color.elevated)
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 999))
    }

    /// Replace the structured-injury slugs with the picker's new set, leaving
    /// any legacy free-text entries alone.
    private func commitInjuries(_ newSlugs: Set<String>) {
        let known = Set(CoachDatabase.shared.listInjuries().map(\.slug))
        store.update { mem in
            // Drop the previous known-slug entries, keep legacy free-text, append new picks.
            mem.constraints = mem.constraints.filter { !known.contains($0) } + Array(newSlugs).sorted()
        }
    }

    private func removeInjury(_ slug: String) {
        store.update { mem in
            mem.constraints.removeAll { $0 == slug }
        }
    }

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("REMINDERS")
            Button(action: toggleReminders) {
                HStack(spacing: 12) {
                    Image(systemName: remindersOn ? "bell.fill" : "bell.slash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(remindersOn ? Color.accent : Color.ink3)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly plan reminder")
                            .styled(.body)
                            .foregroundStyle(Color.ink)
                        Text("Sundays at 6:00 PM · walks through next week's plan")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: remindersOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(remindersOn ? Color.accent : Color.ink3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(remindersOn ? Color.accentWash : Color.surface)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(remindersOn ? Color.accentBorder : Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(remindersPending)
        }
    }

    private func toggleReminders() {
        if remindersOn {
            WeeklyReminderScheduler.disable()
            remindersOn = false
            return
        }
        remindersPending = true
        Task {
            let ok = await WeeklyReminderScheduler.enable()
            await MainActor.run {
                remindersOn = ok
                remindersPending = false
            }
        }
    }

    // MARK: - Data (backup / restore)

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("DATA")
            Button(action: exportBackup) {
                dataRow(icon: "square.and.arrow.up",
                        title: "Export backup",
                        subtitle: "Save a JSON file with your profile, plan, sessions, and custom workouts.")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-export")

            Button(action: { presentingImporter = true }) {
                dataRow(icon: "square.and.arrow.down",
                        title: "Restore from backup",
                        subtitle: "Replace everything on this device with a backup file. Restart after to refresh.")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile-import")
        }
    }

    private func dataRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            backupError = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped URL — required for files picked outside the app sandbox.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let envelope = try BackupManager.decode(data)
                try BackupManager.restore(envelope, into: .standard)
                restoreCompleted = true
            } catch {
                backupError = (error as? BackupError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func section(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }

    private func valueStepper(value: String, unit: String,
                              onMinus: @escaping () -> Void,
                              onPlus:  @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            stepperBtn("minus", action: onMinus)
            VStack(spacing: 0) {
                Text(value)
                    .font(.custom("JetBrainsMono-SemiBold", size: 28))
                    .foregroundStyle(Color.ink)
                Text(unit)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity)
            stepperBtn("plus", action: onPlus)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func stepperBtn(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.elevated)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var currentTier: EquipmentTier {
        let eq = store.memory.equipment
        if eq == [.bodyweight] { return .bodyweight }
        if eq == [.dumbbells]  { return .dumbbells  }
        if eq == [.fullGym]    { return .fullGym    }
        return .custom
    }

    private func tagList(
        items: [String],
        input: Binding<String>,
        placeholder: String,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: input, prompt: Text(placeholder).foregroundColor(Color.ink3))
                    .styled(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit {
                        commit(input: input, items: items, onAdd: onAdd)
                    }
                Button {
                    commit(input: input, items: items, onAdd: onAdd)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canCommit(input.wrappedValue) ? Color.accentInk : Color.ink3)
                        .frame(width: 44, height: 44)
                        .background(canCommit(input.wrappedValue) ? Color.accent : Color.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(canCommit(input.wrappedValue) ? Color.clear : Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canCommit(input.wrappedValue))
            }
            if !items.isEmpty {
                WrappingFlow(spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 6) {
                            Text(item)
                                .font(.custom("Inter-Regular", size: 13))
                                .foregroundStyle(Color.ink)
                            Button { onRemove(item) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.ink3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 12).padding(.trailing, 10).padding(.vertical, 8)
                        .background(Color.elevated)
                        .overlay(RoundedRectangle(cornerRadius: 999).stroke(Color.line, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 999))
                    }
                }
            }
        }
    }

    private func canCommit(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func commit(input: Binding<String>, items: [String], onAdd: (String) -> Void) {
        let trimmed = input.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !items.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        onAdd(trimmed)
        input.wrappedValue = ""
    }

    // MARK: - Mutations

    private func toggleSport(_ sport: Sport) {
        store.update { mem in
            if let idx = mem.sports.firstIndex(of: sport) {
                mem.sports.remove(at: idx)
                mem.seasonsBySport.removeValue(forKey: sport)
                if mem.primarySport == sport { mem.primarySport = mem.sports.first }
            } else {
                mem.sports.append(sport)
                if mem.primarySport == nil { mem.primarySport = sport }
            }
        }
    }

    private func toggleFocus(_ focus: PrimaryFocus) {
        store.update { mem in
            if let idx = mem.focuses.firstIndex(of: focus) {
                mem.focuses.remove(at: idx)
            } else {
                mem.focuses.append(focus)
            }
        }
    }

    private func setPrimaryFocus(_ focus: PrimaryFocus) {
        store.update { mem in
            guard let idx = mem.focuses.firstIndex(of: focus), idx != 0 else { return }
            mem.focuses.remove(at: idx)
            mem.focuses.insert(focus, at: 0)
        }
    }

    private func selectTier(_ tier: EquipmentTier) {
        store.update { mem in
            switch tier {
            case .bodyweight: mem.equipment = [.bodyweight]
            case .dumbbells:  mem.equipment = [.dumbbells]
            case .fullGym:    mem.equipment = [.fullGym]
            case .custom:
                if mem.equipment == [.bodyweight] || mem.equipment == [.fullGym] {
                    mem.equipment = []
                }
            }
        }
    }

    private func toggleCustomEquipment(_ eq: Equipment) {
        store.update { mem in
            if let idx = mem.equipment.firstIndex(of: eq) {
                mem.equipment.remove(at: idx)
            } else {
                mem.equipment.removeAll { $0 == .bodyweight || $0 == .fullGym }
                mem.equipment.append(eq)
            }
        }
    }

    private func adjustMinutes(_ delta: Int) {
        store.update { mem in
            mem.sessionMinutes = min(max(mem.sessionMinutes + delta, 15), 120)
        }
    }

    private func adjustLifts(_ delta: Int) {
        store.update { mem in
            mem.liftDaysPerWeek = min(max(mem.liftDaysPerWeek + delta, 0), 7)
        }
    }

    private func adjustAge(_ delta: Int) {
        store.update { mem in
            let next = (mem.age ?? 30) + delta
            mem.age = min(max(next, 13), 99)
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
}

#Preview("Populated") {
    let suite = "Profile.preview.populated"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.sports = [Sport.catalog[1], Sport.catalog[2]]
        mem.primarySport = Sport.catalog[1]
        mem.focuses = [.sportPerformance, .mobility]
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
}

// MARK: - Share sheet bridge

/// Thin UIActivityViewController wrapper so the Profile screen can present
/// the system share sheet for the export file URL. iOS 17's standard
/// pattern — SwiftUI has ShareLink but the file-URL ergonomics + iPad
/// popover behavior are still cleaner via the UIKit bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
