// WeekDayEventSheets.swift — event-flow sheets presented from WeekDayEditSheet.
//
// SportPickerSheet, EventEditorSheet, MoveDayPickerSheet, and
// IntensityEditorSheet. All are closure-driven and self-contained — no
// bindings into the parent sheet; results flow back through onPick/onSave.

import SwiftUI

// MARK: - Sport picker (uses memory.sports if any, else full catalog)

struct SportPickerSheet: View {
    @EnvironmentObject private var memory: MemoryStore
    @Environment(\.dismiss) private var dismiss
    let onPick: (Sport) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !memory.memory.sports.isEmpty {
                            section("YOUR SPORTS")
                            VStack(spacing: 8) {
                                ForEach(memory.memory.sports) { sport in
                                    sportRow(sport)
                                }
                            }
                            section("ALL SPORTS")
                                .padding(.top, 14)
                        }
                        VStack(spacing: 8) {
                            ForEach(Sport.catalog) { sport in
                                sportRow(sport)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Pick a sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
    }

    private func sportRow(_ sport: Sport) -> some View {
        Button {
            onPick(sport)
        } label: {
            HStack {
                Text(sport.name)
                    .styled(.displayS)
                    .foregroundStyle(Color.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func section(_ s: String) -> some View {
        Text(s)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }
}

// MARK: - Event editor

struct EventEditorSheet: View {
    let date: Date
    let onSave: (WeekEvent) -> Void
    @EnvironmentObject private var memory: MemoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: WeekEventKind = .race
    @State private var sport: Sport? = nil
    @State private var intensity: EventIntensity = .moderate
    @State private var pickingSport = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("EVENT")
                        TextField("", text: $title,
                                  prompt: Text("e.g. 10K Race").foregroundColor(Color.ink3))
                            .styled(.body)
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        section("TYPE")
                        WrappingFlow(spacing: 8) {
                            ForEach(WeekEventKind.allCases, id: \.self) { k in
                                OnboardingChip(
                                    label: k.label,
                                    selected: kind == k,
                                    action: { kind = k }
                                )
                            }
                        }

                        section("SPORT (OPTIONAL)")
                        Button { pickingSport = true } label: {
                            HStack {
                                Text(sport?.name ?? "None")
                                    .styled(.body)
                                    .foregroundStyle(sport == nil ? Color.ink3 : Color.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.ink3)
                            }
                            .padding(14)
                            .background(Color.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        section("INTENSITY")
                        WrappingFlow(spacing: 8) {
                            ForEach(EventIntensity.allCases, id: \.self) { i in
                                OnboardingChip(
                                    label: i.label,
                                    selected: intensity == i,
                                    action: { intensity = i }
                                )
                            }
                        }
                        // Was an unconditional "Hard events: the day before will
                        // be reset to recover." — shown even for .outOfTown,
                        // which triggers no taper, no buffer and no post-event
                        // recovery anywhere in Planner. Keyed to kind now.
                        if intensity == .hard, let note = hardIntensityNote {
                            Text(note)
                                .font(.monoXS)
                                .foregroundStyle(Color.ink3)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 100)
                }

                VStack {
                    Spacer()
                    Button(action: save) {
                        Text("Save event")
                            .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                            .foregroundStyle(canSave ? Color.accentInk : Color.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canSave ? Color.accent : Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("New event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
        .sheet(isPresented: $pickingSport) {
            SportPickerSheet { picked in
                sport = picked
                pickingSport = false
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What a hard event of THIS kind actually does to the surrounding days.
    /// nil = nothing, so no promise is shown. Mirrors Planner's
    /// applyPreEventTaper (races only) and applyPreSportBuffer (hard sport
    /// sessions, and only when the prior slot is an unprotected lift).
    private var hardIntensityNote: String? {
        switch kind {
        case .race:
            return "Hard race: the two days before are reset to rest."
        case .sportSession:
            return "Hard sport day: a lift the day before is dropped to rest."
        default:
            return nil
        }
    }

    private func save() {
        onSave(WeekEvent(
            date: date,
            title: title.trimmingCharacters(in: .whitespaces),
            kind: kind,
            sport: sport,
            intensity: intensity
        ))
        dismiss()
    }

    private func section(_ s: String) -> some View {
        Text(s)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
    }
}

// MARK: - Move-day picker

/// Pick which day to swap with. Lists the other 6 days of the current plan,
/// each row showing weekday + date + current kind so the user can see what
/// they're trading.
struct MoveDayPickerSheet: View {
    let source: Date
    let onPick: (Date) -> Void

    @EnvironmentObject private var planStore: PlanStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("MOVE TO")
                            .styled(.micro)
                            .foregroundStyle(Color.ink3)
                        VStack(spacing: 8) {
                            ForEach(targetDays, id: \.id) { day in
                                row(day: day)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Move to which day?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationBackground(Color.bg)
    }

    private var targetDays: [DayPlan] {
        let cal = Calendar.current
        return planStore.plan?.days.filter {
            !cal.isDate($0.date, inSameDayAs: source)
        } ?? []
    }

    private func row(day: DayPlan) -> some View {
        Button { onPick(day.date) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekdayLabel(day.date).uppercased())
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(day.title)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(day.kind.label)
                    .styled(.micro)
                    .foregroundStyle(Color.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink3)
            }
            .padding(14)
            .background(Color.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.line, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func weekdayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: date)
    }
}

// MARK: - Intensity editor

/// Tiny sheet that flips an event's intensity (light / moderate / hard).
struct IntensityEditorSheet: View {
    let event: WeekEvent
    let onPick: (EventIntensity) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("INTENSITY")
                        .styled(.micro)
                        .foregroundStyle(Color.ink3)
                    Text(event.title)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                    WrappingFlow(spacing: 8) {
                        ForEach(EventIntensity.allCases, id: \.self) { i in
                            OnboardingChip(
                                label: i.label,
                                selected: event.intensity == i,
                                action: { onPick(i) }
                            )
                        }
                    }
                    Text(intensityHint)
                        .font(.monoXS)
                        .foregroundStyle(Color.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .navigationTitle("Set intensity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.bg)
    }

    /// Must track Planner exactly. The old copy claimed a taper for every kind
    /// at moderate ("the day before is reset to rest") when applyPreEventTaper
    /// filters `kind == .race` (Planner.swift:595), and said day -2 becomes
    /// mobility when Planner demotes it to REST — the mobility catalog is gone
    /// and the code comment says so.
    private var intensityHint: String {
        switch event.intensity {
        case .light:
            return "Light = no taper, no buffer."
        case .moderate:
            return event.kind == .race
                ? "Moderate race = the day before is reset to rest."
                : "Moderate = no taper. Only races taper the days before."
        case .hard:
            switch event.kind {
            case .race:
                return "Hard race = the two days before are reset to rest."
            case .sportSession:
                return "Hard sport day = a lift the day before is dropped to rest."
            default:
                return "Hard = no taper for this event type."
            }
        }
    }
}
