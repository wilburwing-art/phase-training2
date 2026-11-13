// HistoryScreen.swift — Past sessions list with expand/collapse accordion.
// Ports `handoff/proto/history.jsx` + `handoff/hd-history.jsx` to SwiftUI.

import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var memoryStore: MemoryStore
    @EnvironmentObject private var customStore: CustomRoutineStore
    @EnvironmentObject private var tabSelection: TabSelectionStore
    /// Build 92: now presented as a sheet from the Progress tab's "See
    /// all" link, not pushed from TodayTab. Uses Environment dismiss so
    /// it works in any presentation context.
    @Environment(\.dismiss) private var dismiss

    /// Build 102 — optional filter. When set, the sessions list narrows to
    /// only those containing an exercise whose name matches (case-insensitive),
    /// and the header swaps to "<EXERCISE> · HISTORY". Used by the composite
    /// tile's action sheet ("Exercise history" row) to drill from Today/
    /// preview surfaces straight into the matching past sessions. nil = no
    /// filter, full history as before.
    let initialExerciseFilter: String?

    @State private var expanded: Set<TimeInterval> = []
    @State private var editingSession: SavedSession?
    @State private var filter = HistoryFilter()
    /// Sessions saved to the Library from this screen, so the button can
    /// read "Saved" instead of offering a second copy.
    @State private var savedAsRoutine: Set<TimeInterval> = []
    /// Session waiting on the "replace the workout in progress?" confirm.
    @State private var repeatTarget: SavedSession?

    init(initialExerciseFilter: String? = nil) {
        self.initialExerciseFilter = initialExerciseFilter
    }

    /// Sessions actually rendered — native plus imported
    /// (`store.displaySessions`) when no filter is set, otherwise narrowed to
    /// sessions containing the named exercise.
    private var displayedSessions: [SavedSession] {
        filter.apply(to: scopedSessions)
    }

    /// The list before search and tag filtering: everything, or the sessions
    /// containing the drilled-in exercise.
    private var scopedSessions: [SavedSession] {
        let all = store.displaySessions(usesImperial: memoryStore.memory.usesImperial)
        guard let name = initialExerciseFilter else { return all }
        return all.filter { sess in
            sess.exercises.contains {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if scopedSessions.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .confirmationDialog(
            "Replace the workout in progress?",
            isPresented: Binding(
                get: { repeatTarget != nil },
                set: { if !$0 { repeatTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace and start", role: .destructive) {
                if let target = repeatTarget { performRepeat(target) }
            }
            Button("Cancel", role: .cancel) { repeatTarget = nil }
        } message: {
            Text("The sets logged in the current workout will be lost.")
        }
        .sheet(item: $editingSession) { session in
            EditSessionSheet(session: session)
                .environmentObject(store)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text(initialExerciseFilter.map { _ in "Exercise history" } ?? "History")
                .styled(.displayM)
                .foregroundColor(.ink)

            HStack {
                Button { dismiss() } label: {
                    Text("‹ Back")
                        .styled(.body)
                        .foregroundColor(.ink2)
                        .padding(.vertical, 4)
                        .padding(.trailing, 8)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(sessionCountLabel)
                    .styled(.micro)
                    .foregroundColor(.ink3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var sessionCountLabel: String {
        let n = displayedSessions.count
        return "\(n) SESSION\(n == 1 ? "" : "S")"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("NO SESSIONS YET")
                .styled(.micro)
                .foregroundColor(.ink2)
            Text("Complete a workout and it'll show up here.")
                .styled(.body)
                .foregroundColor(.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Content

    private var content: some View {
        let sessions = displayedSessions
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(initialExerciseFilter ?? "Past sessions")
                    .styled(.displayM)
                    .foregroundColor(.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                tagFilterRow

                summaryStrip
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Rectangle()
                    .fill(Color.line)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                if sessions.isEmpty {
                    noMatches
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, session in
                            sessionRow(
                                session: session,
                                isLast: idx == sessions.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 40)
            }
        }
    }

    // MARK: - Search and tag filter

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.ink3)
            TextField("", text: $filter.query,
                      prompt: Text("Search name, exercise, note or month").foregroundColor(Color.ink3))
                .styled(.body)
                .foregroundStyle(Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("history-search")
            if !filter.query.isEmpty {
                Button { filter.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.ink3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Clear search")
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// One chip per tag that some session in the list carries. Hidden when
    /// no session is tagged.
    @ViewBuilder
    private var tagFilterRow: some View {
        let present = HistoryFilter.tagsPresent(in: scopedSessions)
        if !present.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(present) { tag in
                        tagFilterChip(tag)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 10)
        }
    }

    private func tagFilterChip(_ tag: SessionTag) -> some View {
        let active = filter.tags.contains(tag)
        return Button {
            if active { filter.tags.remove(tag) } else { filter.tags.insert(tag) }
        } label: {
            Text(tag.label)
                .font(.scaled("JetBrainsMono-Medium", size: 11))
                .foregroundStyle(active ? Color.accentInk : Color.ink2)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.accent : Color.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(active ? Color.clear : Color.line, lineWidth: 0.5)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("history-tag-\(tag.rawValue)")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Text("NO MATCHES")
                .styled(.micro)
                .foregroundColor(.ink2)
            Button {
                filter = HistoryFilter()
            } label: {
                Text("Clear search and filters")
                    .styled(.body)
                    .foregroundColor(.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-clear-filters")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Summary strip (sessions / total sets / avg RPE)

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            statCard(value: "\(displayedSessions.count)", label: "SESSIONS")
            statCard(value: "\(totalDoneSetsAllSessions)", label: "TOTAL SETS")
            statCard(value: avgRpeAllSessions, label: "AVG RPE")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.scaled("SpaceGrotesk-SemiBold", size: 20))
                .foregroundColor(.ink)
            Text(label)
                .styled(.micro)
                .foregroundColor(.ink2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }

    private var totalDoneSetsAllSessions: Int {
        displayedSessions.reduce(0) { acc, sess in
            acc + sess.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && $0.isWorkingSet }.count }
        }
    }

    private var avgRpeAllSessions: String {
        // Per-session avg of done-set RPEs, then average across sessions.
        let perSessionAvgs: [Double] = displayedSessions.compactMap { sess in
            let rpes: [Double] = sess.exercises.flatMap { ex in
                ex.sets.compactMap { s in
                    guard s.done, !s.rpe.isEmpty, let v = Double(s.rpe) else { return nil }
                    return v
                }
            }
            guard !rpes.isEmpty else { return nil }
            return rpes.reduce(0, +) / Double(rpes.count)
        }
        guard !perSessionAvgs.isEmpty else { return "-" }
        let avg = perSessionAvgs.reduce(0, +) / Double(perSessionAvgs.count)
        return String(format: "%.1f", avg)
    }

    // MARK: - Session row

    private func sessionRow(session: SavedSession, isLast: Bool) -> some View {
        let isExpanded = expanded.contains(session.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: { toggle(session.id) }) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.name)
                            .styled(.displayS)
                            .foregroundColor(.ink)
                        HStack(spacing: 8) {
                            Text(dateLabel(session.startTime))
                                .styled(.body)
                                .foregroundColor(.ink3)
                            dot
                            // Imported workouts carry no duration.
                            if session.importSource == nil {
                                Text(SessionRowMeta.durationLabel(session.duration, style: .compact))
                                    .styled(.monoS)
                                    .foregroundColor(.ink3)
                                dot
                            }
                            Text("\(doneSetCount(session)) sets")
                                .styled(.monoXS)
                                .foregroundColor(.ink3)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.ink3)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.top, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse \(session.name)" : "Expand \(session.name)")
            .accessibilityIdentifier("history-toggle-\(session.id)")

            if isExpanded {
                expandedDetail(session)
                    .padding(.top, 10)
                reflection(session)
                if let source = session.importSource {
                    Text("Imported from \(ImportedHistorySessions.sourceName(source))")
                        .styled(.monoXS)
                        .foregroundColor(.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityIdentifier("history-imported-\(session.id)")
                } else {
                    sessionActions(session)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.lineSoft).frame(height: 0.5)
            }
        }
    }

    // MARK: - Session actions (native sessions only)

    @ViewBuilder
    private func sessionActions(_ session: SavedSession) -> some View {
        let canReuse = !session.exercises.isEmpty
        VStack(spacing: 8) {
            if canReuse {
                HStack(spacing: 8) {
                    // Repeat switches tabs, so it is offered only from the
                    // full History list. The exercise drill-in sits on top
                    // of another sheet that would stay open over the Log.
                    if initialExerciseFilter == nil {
                        actionButton("Repeat", id: "history-repeat-\(session.id)",
                                     label: "Repeat \(session.name)") {
                            requestRepeat(session)
                        }
                    }
                    let saved = savedAsRoutine.contains(session.id)
                    actionButton(saved ? "Saved to Library" : "Save as routine",
                                 id: "history-save-routine-\(session.id)",
                                 label: saved ? "\(session.name) saved to Library"
                                              : "Save \(session.name) as a routine") {
                        saveAsRoutine(session)
                    }
                    .disabled(saved)
                }
            }
            actionButton("Edit session", id: "history-edit-\(session.id)",
                         label: "Edit \(session.name)") {
                editingSession = session
            }
        }
    }

    private func actionButton(_ title: String, id: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .styled(.monoS)
                .foregroundColor(.ink2)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func requestRepeat(_ session: SavedSession) {
        if store.active != nil {
            repeatTarget = session
        } else {
            performRepeat(session)
        }
    }

    /// Start the session again and hand off to Today, where TodayTab routes
    /// a fresh active session to the Log.
    private func performRepeat(_ session: SavedSession) {
        store.saveActive(store.createSession(from: session.repeatTemplate()))
        repeatTarget = nil
        tabSelection.selected = .today
        dismiss()
    }

    private func saveAsRoutine(_ session: SavedSession) {
        customStore.save(session.asCustomRoutine(exerciseId: ExerciseNameLookup.anyId))
        savedAsRoutine.insert(session.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var dot: some View {
        Text("·")
            .styled(.body)
            .foregroundColor(.ink3)
    }

    /// Feel, mood and note, each only when the user gave one, so an
    /// unrated workout looks exactly as it did before.
    @ViewBuilder
    private func reflection(_ session: SavedSession) -> some View {
        let line = SessionRowMeta.feelMoodLine(feel: session.feel, mood: session.mood)
        if line != nil || session.note != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let line {
                    Text(line)
                        .styled(.monoXS)
                        .foregroundColor(.ink3)
                        .accessibilityIdentifier("history-reflection-\(session.id)")
                }
                if let note = session.note {
                    Text("\u{201C}\(note)\u{201D}")
                        .styled(.body)
                        .foregroundColor(.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }

    // MARK: - Expanded detail block

    private func expandedDetail(_ session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(session.exercises.enumerated()), id: \.offset) { idx, ex in
                exerciseDetailRow(ex: ex, isLast: idx == session.exercises.count - 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }

    private func exerciseDetailRow(ex: LoggedExercise, isLast: Bool) -> some View {
        // Bodyweight rows log reps + done with NO weight — LogScreen collapses
        // the weight column to a "BW" label for them by design. Requiring a
        // non-empty weight dropped every push-up / plank / dip set, so the row
        // rendered "-" and the reps the user did log were invisible in history.
        let doneSets = ex.sets.filter { $0.done && (!$0.weight.isEmpty || ex.isBodyweight) }
        // `pr` flag is not present on LoggedExercise/LoggedSet today; skip badge.
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(ex.name)
                    .font(.scaled("SpaceGrotesk-SemiBold", size: 13))
                    .foregroundColor(.ink)
                Spacer(minLength: 8)
                if let rpeRange = rpeRangeLabel(doneSets) {
                    Text(rpeRange)
                        .styled(.monoXS)
                        .foregroundColor(.ink3)
                }
            }
            Text(setSummary(doneSets))
                .styled(.monoXS)
                .foregroundColor(.ink2)
            if let note = ex.note, !note.isEmpty {
                Text(note)
                    .font(.scaled("Inter-Regular", size: 12))
                    .foregroundColor(.ink3)
                    .accessibilityIdentifier("history-exercise-note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.lineSoft).frame(height: 0.5)
            }
        }
    }

    private func setSummary(_ sets: [LoggedSet]) -> String {
        guard !sets.isEmpty else { return "-" }
        return sets.map { s in
            let core = (s.setType.badge.map { "\($0) " } ?? "") + "\(s.weight) × \(s.reps)"
            return s.rpe.isEmpty ? core : "\(core) @ \(s.rpe)"
        }.joined(separator: " · ")
    }

    private func rpeRangeLabel(_ sets: [LoggedSet]) -> String? {
        let values: [Double] = sets.compactMap {
            $0.rpe.isEmpty ? nil : Double($0.rpe)
        }
        guard !values.isEmpty else { return nil }
        let lo = values.min()!
        let hi = values.max()!
        let loStr = formatRpe(lo)
        let hiStr = formatRpe(hi)
        return loStr == hiStr ? "rpe \(loStr)" : "rpe \(loStr)-\(hiStr)"
    }

    private func formatRpe(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }

    // MARK: - Helpers

    private func toggle(_ id: TimeInterval) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private func doneSetCount(_ session: SavedSession) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && $0.isWorkingSet }.count }
    }

    private func dateLabel(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let days = Int(interval / 86400)
        if days <= 7 && interval >= 0 {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            f.dateTimeStyle = .named  // produces "Today", "Yesterday", "3 days ago"
            return f.localizedString(for: date, relativeTo: Date())
        }
        return SessionRowMeta.monthDayLabel(date)
    }
}

// MARK: - Preview

#Preview {
    let store = SessionStore(defaults: UserDefaults(suiteName: "preview-history")!)
    // Reset suite so preview is deterministic.
    UserDefaults(suiteName: "preview-history")!.removePersistentDomain(forName: "preview-history")

    let tmpl = WorkoutTemplate.upper1

    func makeExercise(_ ex: ExerciseTemplate, weights: [String], reps: [String], rpes: [String]) -> LoggedExercise {
        let sets: [LoggedSet] = (0..<ex.targetSets).map { i in
            LoggedSet(
                num: i + 1,
                weight: i < weights.count ? weights[i] : "",
                reps:   i < reps.count    ? reps[i]    : String(ex.targetReps),
                rpe:    i < rpes.count    ? rpes[i]    : "",
                done:   i < weights.count
            )
        }
        return LoggedExercise(
            id: ex.id,
            name: ex.name,
            type: ex.type,
            unit: ex.unit,
            targetSets: ex.targetSets,
            targetReps: ex.targetReps,
            rest: ex.rest,
            sets: sets,
            prevSets: []
        )
    }

    let recent = SavedSession(
        templateId: tmpl.id,
        name: tmpl.name,
        category: tmpl.category,
        startTime: Date().addingTimeInterval(-3 * 86400),
        exercises: [
            makeExercise(tmpl.exercises[0], weights: ["135","135","140","140","140"],
                         reps: ["5","5","5","5","4"], rpes: ["6","7","7","8","8"]),
            makeExercise(tmpl.exercises[1], weights: ["+25","+25","+25","+25"],
                         reps: ["5","5","5","4"], rpes: ["6","7","7","8"]),
            makeExercise(tmpl.exercises[2], weights: ["95","95","95","95"],
                         reps: ["8","8","8","7"], rpes: ["6","7","7","7"]),
            makeExercise(tmpl.exercises[3], weights: ["50","50","50","50"],
                         reps: ["10","10","10","10"], rpes: ["6","7","7","7"]),
            makeExercise(tmpl.exercises[4], weights: ["65","65","65"],
                         reps: ["10","10","10"], rpes: ["7","7","7"]),
            makeExercise(tmpl.exercises[5], weights: ["30","30","30"],
                         reps: ["15","15","15"], rpes: ["5","6","6"]),
        ],
        feel: "OK",
        note: nil,
        endTime: Date().addingTimeInterval(-3 * 86400 + 42 * 60),
        duration: 42 * 60
    )

    let older = SavedSession(
        templateId: tmpl.id,
        name: tmpl.name,
        category: tmpl.category,
        startTime: Date().addingTimeInterval(-14 * 86400),
        exercises: [
            makeExercise(tmpl.exercises[0], weights: ["130","130","135","135","135"],
                         reps: ["5","5","5","5","5"], rpes: ["6","6","7","7","7"]),
            makeExercise(tmpl.exercises[1], weights: ["+20","+20","+20","+20"],
                         reps: ["5","5","5","5"], rpes: ["6","6","7","7"]),
        ],
        feel: "HARD",
        note: "Sleep was light.",
        endTime: Date().addingTimeInterval(-14 * 86400 + 38 * 60),
        duration: 38 * 60
    )

    store.saveAll([recent, older])

    return HistoryScreen()
        .environmentObject(store)
        .environmentObject(MemoryStore())
        .environmentObject(CustomRoutineStore(defaults: UserDefaults(suiteName: "preview-history")!))
        .environmentObject(TabSelectionStore())
        .preferredColorScheme(.dark)
}
