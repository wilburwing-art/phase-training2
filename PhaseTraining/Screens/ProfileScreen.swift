// ProfileScreen.swift — Profile tab. Mirror of onboarding inputs, edits
// round-trip directly into MemoryStore.memory. Each section reuses the same
// chip / pick-row primitives the onboarding flow uses.
//
// Lives at the top level of the Profile tab — no inner navigation. A single
// scroll view with section dividers; everything is editable in place.

import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var store: MemoryStore
    @State private var dislikeInput = ""
    @State private var constraintInput = ""

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    sportsSection
                    Divider().background(Color.lineSoft)
                    focusSection
                    Divider().background(Color.lineSoft)
                    seasonSection
                    Divider().background(Color.lineSoft)
                    daysSection
                    Divider().background(Color.lineSoft)
                    sessionLengthSection
                    Divider().background(Color.lineSoft)
                    equipmentSection
                    Divider().background(Color.lineSoft)
                    experienceSection
                    Divider().background(Color.lineSoft)
                    dislikesSection
                    Divider().background(Color.lineSoft)
                    constraintsSection

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
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

    // MARK: - Sections

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

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("FOCUS")
            VStack(spacing: 8) {
                ForEach(PrimaryFocus.allCases) { focus in
                    OnboardingPickRow(
                        title: focus.label,
                        subtitle: focus.subtitle,
                        selected: store.memory.primaryFocus == focus,
                        action: { store.update { $0.primaryFocus = focus } }
                    )
                }
            }
        }
    }

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("SEASON")
            VStack(spacing: 8) {
                ForEach(SeasonPhase.allCases) { season in
                    OnboardingPickRow(
                        title: season.label,
                        subtitle: season.subtitle,
                        selected: store.memory.season == season,
                        action: { store.update { $0.season = season } }
                    )
                }
            }
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("DAYS PER WEEK")
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        toggleDay(day)
                    } label: {
                        Text(day.letter)
                            .font(.custom("SpaceGrotesk-SemiBold", size: 14))
                            .foregroundStyle(store.memory.availableDays.contains(day) ? Color.accentInk : Color.ink)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(store.memory.availableDays.contains(day) ? Color.accent : Color.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(store.memory.availableDays.contains(day) ? Color.clear : Color.line, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sessionLengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("SESSION LENGTH")
            HStack(spacing: 14) {
                stepperBtn("minus") { adjustMinutes(-15) }
                VStack(spacing: 0) {
                    Text("\(store.memory.sessionMinutes)")
                        .font(.custom("JetBrainsMono-SemiBold", size: 28))
                        .foregroundStyle(Color.ink)
                    Text("MIN")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                }
                .frame(maxWidth: .infinity)
                stepperBtn("plus") { adjustMinutes(15) }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("EQUIPMENT")
            WrappingFlow(spacing: 8) {
                ForEach(Equipment.allCases) { eq in
                    OnboardingChip(
                        label: eq.label,
                        selected: store.memory.equipment.contains(eq),
                        action: { toggleEquipment(eq) }
                    )
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
        VStack(alignment: .leading, spacing: 10) {
            section("INJURIES OR CONSTRAINTS")
            tagList(items: store.memory.constraints,
                    input: $constraintInput,
                    placeholder: "e.g. left knee",
                    onAdd: { v in store.update { $0.constraints.append(v) } },
                    onRemove: { v in store.update { $0.constraints.removeAll { $0 == v } } })
        }
    }

    // MARK: - Helpers

    private func section(_ text: String) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
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
                if mem.primarySport == sport { mem.primarySport = mem.sports.first }
            } else {
                mem.sports.append(sport)
                if mem.primarySport == nil { mem.primarySport = sport }
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        store.update { mem in
            if let idx = mem.availableDays.firstIndex(of: day) {
                mem.availableDays.remove(at: idx)
            } else {
                mem.availableDays.append(day)
                mem.availableDays.sort { $0.rawValue < $1.rawValue }
            }
        }
    }

    private func toggleEquipment(_ eq: Equipment) {
        store.update { mem in
            if mem.equipment.contains(eq) {
                mem.equipment.removeAll { $0 == eq }
                return
            }
            if eq == .bodyweight {
                mem.equipment = [.bodyweight]
            } else {
                mem.equipment.removeAll { $0 == .bodyweight }
                mem.equipment.append(eq)
            }
        }
    }

    private func adjustMinutes(_ delta: Int) {
        store.update { mem in
            mem.sessionMinutes = min(max(mem.sessionMinutes + delta, 15), 120)
        }
    }

    private func formattedShort(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}

#Preview("Empty") {
    ProfileScreen()
        .environmentObject(MemoryStore(defaults: UserDefaults(suiteName: "Profile.preview.empty")!))
}

#Preview("Populated") {
    let suite = "Profile.preview.populated"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = MemoryStore(defaults: defaults)
    store.update { mem in
        mem.sports = [Sport.catalog[1], Sport.catalog[2]]
        mem.primarySport = Sport.catalog[1]
        mem.primaryFocus = .sportPerformance
        mem.season = .preSeason
        mem.availableDays = [.monday, .wednesday, .friday]
        mem.equipment = [.dumbbells, .pullUpBar]
        mem.experience = .intermediate
        mem.dislikes = ["burpees"]
        mem.constraints = ["left knee"]
        mem.onboardedAt = Date()
    }
    return ProfileScreen().environmentObject(store)
}
