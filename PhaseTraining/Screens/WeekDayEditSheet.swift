// WeekDayEditSheet.swift — bottom sheet that edits a single day's overrides.
//
// Presented from WeekScreen when the user taps a day row. All mutations go
// through PlanStore.updateOverrides (regenerates the plan) so the user sees
// the day re-render the moment they apply a change.
//
// Action set:
//   - Mark off this week     (toggles WeekOverrides.unavailableDays)
//   - Add sport session      (WeekEvent kind=.sportSession)
//   - Add event              (WeekEvent kind=.race, intensity .light/.moderate/.hard)
//   - Override workout (for lift/mobility days — opens OverrideTodaySheet:
//     saved customs + coach request flow)
//   - Clear overrides for this day

import SwiftUI

struct WeekDayEditSheet: View {
    let date: Date
    let dayPlan: DayPlan?
    @EnvironmentObject private var memory: MemoryStore
    @EnvironmentObject private var planStore: PlanStore
    @Environment(\.dismiss) private var dismiss

    @State private var pickingSport = false
    @State private var addingEvent = false
    @State private var overridingWorkout = false
    @State private var pickingMoveTarget = false
    @State private var editingIntensity = false
    @State private var previewingWorkout = false
    /// PR 6 (weekly-coach roadmap) — opens the inline LiftFocus picker
    /// for lift days. Sheet-style picker rather than inline-expand because
    /// the picker grid takes vertical room the sheet body doesn't have
    /// without scrolling, especially on iPhone SE.
    @State private var pickingLiftFocus = false
    @State private var showingClearConfirm = false
    /// One-per-day event rule: tapping an add action while the day already
    /// holds an event routes through a replace confirmation instead of
    /// silently clobbering it on save. Tracks which add flow to resume.
    @State private var pendingEventReplace: PendingEventReplace? = nil
    @State private var confirmingEventReplace = false

    private enum PendingEventReplace { case sport, event }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        actionList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.bg)
        .sheet(isPresented: $pickingSport) {
            SportPickerSheet { sport in
                addSportSession(sport: sport)
                pickingSport = false
            }
        }
        .sheet(isPresented: $addingEvent) {
            EventEditorSheet(date: date) { event in
                addEvent(event)
                addingEvent = false
            }
        }
        .sheet(isPresented: $overridingWorkout) {
            // Pass targetDate so the picker writes a per-day override
            // instead of starting a session — the Week tab surface is
            // for "schedule this for that day," not "start this now."
            OverrideTodaySheet(
                onStartSession: {
                    overridingWorkout = false
                    dismiss()
                },
                targetDate: date
            )
        }
        .sheet(isPresented: $pickingMoveTarget) {
            MoveDayPickerSheet(
                source: date,
                onPick: { target in
                    swap(source: date, target: target)
                    pickingMoveTarget = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $editingIntensity) {
            if let event = currentEvent {
                IntensityEditorSheet(event: event) { newIntensity in
                    setIntensity(for: event, to: newIntensity)
                    editingIntensity = false
                }
            }
        }
        .sheet(isPresented: $previewingWorkout) {
            if let dayPlan {
                DayWorkoutPreviewSheet(day: dayPlan, onStartSession: {
                    previewingWorkout = false
                    dismiss()
                })
            }
        }
        .sheet(isPresented: $pickingLiftFocus) {
            LiftFocusPickerSheet(
                current: currentLiftFocus,
                onPick: { focus in
                    setLiftFocus(focus)
                    pickingLiftFocus = false
                }
            )
        }
        .alert("Clear overrides for this day?", isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive) { clearOverrides() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This removes sport sessions, events, and the unavailable mark for this day. It can't be undone.")
        }
        .alert("Replace existing event?", isPresented: $confirmingEventReplace) {
            Button("Replace", role: .destructive) {
                if let pending = pendingEventReplace { proceedWithAdd(pending) }
                pendingEventReplace = nil
            }
            Button("Keep", role: .cancel) { pendingEventReplace = nil }
        } message: {
            Text("\(currentEvent?.title ?? "An event") is already on this day. Days hold one event, so adding another replaces it.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekdayLabel)
                .styled(.micro)
                .foregroundStyle(Color.accent)
            Text(dateLabel)
                .font(.custom("SpaceGrotesk-SemiBold", size: 26))
                .tracking(-0.025 * 26)
                .foregroundStyle(Color.ink)
            if let dayPlan {
                Text("Currently: \(dayPlan.kind.label.lowercased()) — \(dayPlan.title)")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
        }
    }

    private var weekdayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date).uppercased()
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Action list

    private var actionList: some View {
        VStack(spacing: 8) {
            if dayPlan?.kind == .lift {
                ActionRow(
                    title: Calendar.current.isDateInToday(date)
                        ? "Preview & start workout"
                        : "Preview workout",
                    subtitle: Calendar.current.isDateInToday(date)
                        ? "See exercises, swap before starting"
                        : "See the planned exercises",
                    icon: "list.bullet.rectangle",
                    action: { previewingWorkout = true }
                )
            }

            ActionRow(
                title: isMarkedUnavailable ? "Re-enable this day" : "Mark off this week",
                subtitle: isMarkedUnavailable
                    ? "Will use your normal plan again"
                    : "Forces rest for today only",
                icon: isMarkedUnavailable ? "checkmark.circle" : "moon.zzz.fill",
                action: toggleUnavailable
            )

            ActionRow(
                title: "Add sport session",
                subtitle: "Climb, ski, run — slot a sport on this day",
                icon: "figure.outdoor.cycle",
                action: { requestAdd(.sport) }
            )

            ActionRow(
                title: "Add event or race",
                subtitle: "Hard events trigger a taper the day before",
                icon: "flag.checkered",
                action: { requestAdd(.event) }
            )

            if dayPlan?.kind == .lift || dayPlan?.kind == .sport {
                ActionRow(
                    title: "Move workout to another day",
                    subtitle: "Swap with another day this week",
                    icon: "arrow.left.arrow.right",
                    action: { pickingMoveTarget = true }
                )
            }

            if dayPlan?.kind == .lift {
                ActionRow(
                    title: "Override workout",
                    subtitle: "Pick a saved workout or build a new one",
                    icon: "arrow.triangle.swap",
                    action: { overridingWorkout = true }
                )

                // PR 6 — LiftFocus picker. Shows current selection when set
                // so the user can tell at a glance whether they've already
                // picked a focus for this day.
                ActionRow(
                    title: currentLiftFocus.map { "Focus: \($0.label)" } ?? "Pick a focus",
                    subtitle: currentLiftFocus.map { _ in "Tap to change push / pull / legs / etc." }
                        ?? "Push / Pull / Legs / Upper / Lower / Full body",
                    icon: "scope",
                    action: { pickingLiftFocus = true }
                )
                .accessibilityIdentifier("week-day-focus-action")
            }

            // PR 6 gap — turn a rest day into a training day. (The roadmap
            // proposed a long-press, but long-press is taken by drag-to-swap on
            // the Week tab, so this is a sheet action instead.) Reuses the
            // LiftFocus picker; picking a focus calls setLiftFocus which writes
            // a .lift override, converting the rest day to a lift.
            if dayPlan?.kind == .rest {
                ActionRow(
                    title: "Add lift workout",
                    subtitle: "Turn this rest day into a training day",
                    icon: "plus.circle",
                    action: { pickingLiftFocus = true }
                )
                .accessibilityIdentifier("week-day-add-lift-action")
            }

            // PR 6 — out-of-town option. Available on any non-rest day
            // since the user might want to mark even a planned rest day
            // as travel (to hide it from "missed workout" tracking later).
            if currentEvent?.kind != .outOfTown {
                ActionRow(
                    title: "Mark as travel day",
                    subtitle: "Bodyweight flow you can do anywhere",
                    icon: "airplane",
                    action: addOutOfTownEvent
                )
                .accessibilityIdentifier("week-day-travel-action")
            }

            if currentEvent != nil {
                ActionRow(
                    title: "Edit intensity",
                    subtitle: intensitySubtitle,
                    icon: "flame",
                    action: { editingIntensity = true }
                )
            }

            if hasAnyOverride {
                ActionRow(
                    title: "Clear overrides for this day",
                    subtitle: "Remove sport sessions, events, and unavailable mark",
                    icon: "arrow.counterclockwise",
                    destructive: true,
                    action: { showingClearConfirm = true }
                )
            }
        }
    }

    private var intensitySubtitle: String {
        guard let event = currentEvent else { return "" }
        return "Currently \(event.intensity.label.lowercased())"
    }

    private var currentEvent: WeekEvent? {
        planStore.overrides.events(on: date).first
    }

    // MARK: - Mutations

    private var weekday: Weekday {
        Weekday.from(date: date)
    }

    private var isMarkedUnavailable: Bool {
        planStore.overrides.unavailableDays.contains(weekday)
    }

    private var hasAnyOverride: Bool {
        planStore.overrides.hasAnythingFor(date: date)
    }

    private func toggleUnavailable() {
        planStore.updateOverrides(memory: memory.memory) { o in
            if o.unavailableDays.contains(weekday) {
                o.unavailableDays.remove(weekday)
            } else {
                o.unavailableDays.insert(weekday)
            }
        }
    }

    /// Gate for the two add-event actions. If the date already holds an
    /// event, confirm the replacement before opening the picker/editor —
    /// addSportSession/addEvent clear the day's events on save.
    private func requestAdd(_ pending: PendingEventReplace) {
        if currentEvent != nil {
            pendingEventReplace = pending
            confirmingEventReplace = true
        } else {
            proceedWithAdd(pending)
        }
    }

    private func proceedWithAdd(_ pending: PendingEventReplace) {
        switch pending {
        case .sport: pickingSport = true
        case .event: addingEvent = true
        }
    }

    private func addSportSession(sport: Sport) {
        planStore.updateOverrides(memory: memory.memory) { o in
            // Replace any existing event on this date so we don't pile up.
            o.events.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
            o.events.append(WeekEvent(
                date: date,
                title: "\(sport.name) session",
                kind: .sportSession,
                sport: sport
            ))
        }
    }

    private func addEvent(_ event: WeekEvent) {
        planStore.updateOverrides(memory: memory.memory) { o in
            o.events.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
            o.events.append(event)
        }
    }

    private func clearOverrides() {
        planStore.updateOverrides(memory: memory.memory) { o in
            o.unavailableDays.remove(weekday)
            o.clearDate(date)
        }
    }

    /// Delegate to PlanStore.swap so the edit-sheet picker and Week-tab drag
    /// share one code path. Events stay anchored to their dates.
    private func swap(source: Date, target: Date) {
        planStore.swap(sourceDate: source, targetDate: target, memory: memory.memory)
    }

    /// Update an event's intensity in-place.
    private func setIntensity(for event: WeekEvent, to intensity: EventIntensity) {
        planStore.updateOverrides(memory: memory.memory) { o in
            if let idx = o.events.firstIndex(where: { $0.id == event.id }) {
                o.events[idx].intensity = intensity
            }
        }
    }

    // MARK: - PR 6 — Focus + Travel

    /// Currently-selected LiftFocus for this day, derived from
    /// `dayOverrides`. nil = not set; planner picks from auto-rotation.
    private var currentLiftFocus: LiftFocus? {
        for (k, v) in planStore.overrides.dayOverrides
        where Calendar.current.isDate(k, inSameDayAs: date) {
            return v.liftFocus
        }
        return nil
    }

    /// Set (or update) the LiftFocus override for this date. Preserves any
    /// routineId already set on the same date — focus + routine compose,
    /// with routine winning at generation time per Planner.makeOverrideSlot.
    private func setLiftFocus(_ focus: LiftFocus) {
        planStore.updateOverrides(memory: memory.memory) { o in
            // Find existing override on this date to preserve routineId.
            var existingRoutineId: Int? = nil
            for (k, v) in o.dayOverrides
            where Calendar.current.isDate(k, inSameDayAs: date) {
                if case .lift(let rid, _) = v { existingRoutineId = rid }
            }
            // Remove any stale entry for this date (key equality is exact,
            // so we have to walk and remove by predicate).
            let stale = o.dayOverrides.keys.filter { Calendar.current.isDate($0, inSameDayAs: date) }
            for k in stale { o.dayOverrides.removeValue(forKey: k) }
            o.dayOverrides[Calendar.current.startOfDay(for: date)] =
                .lift(routineId: existingRoutineId, focus: focus)
        }
    }

    /// Add a `.outOfTown` event for this date. Replaces any existing event
    /// on this date so we don't pile up — mirrors the existing
    /// `addSportSession` / `addEvent` behavior.
    private func addOutOfTownEvent() {
        planStore.updateOverrides(memory: memory.memory) { o in
            o.events.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
            o.events.append(WeekEvent(
                date: date,
                title: "Travel day",
                kind: .outOfTown,
                sport: nil
            ))
        }
    }
}

// LiftFocusPickerSheet, FocusChip, ActionRow live in WeekDayEditComponents.swift.
// SportPickerSheet, EventEditorSheet, MoveDayPickerSheet, IntensityEditorSheet
// live in WeekDayEventSheets.swift.
