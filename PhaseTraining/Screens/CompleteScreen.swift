// CompleteScreen.swift — Post-session summary screen with PR detection.
//
// Ports `handoff/proto/complete.jsx` + `handoff/hd-session-complete.jsx` to SwiftUI.
//
// Sections (top → bottom):
//   1. Top bar: SESSION COMPLETE micro + dated micro, accent progress bar
//   2. Hero: "Done." Display L + session name (Body, ink2)
//   3. Stat grid: 3 cells — Duration / Sets / Avg RPE (Display M values, Micro labels)
//   4. PR block (conditional): accent-wash card listing exercises that beat
//      their previous-session max weight. Computed per `proto/complete.jsx:11-19`.
//   5. Exercise summary: list of done sets per exercise (Display 14 + Mono XS)
//   6. Feel chips: 5 mutually-exclusive pills (Too easy / Easy / Right / Hard / Too much)
//   7. Note: multiline TextField (Inter 13)
//   8. Sticky Save button (lime primary)
//
// Save action delegates to `SessionStore.saveCompleted(_:feel:note:)` then
// invokes `onSave()` to let the orchestrator return to Start.

import SwiftUI

struct CompleteScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var memoryStore: MemoryStore

    let session: ActiveSession
    let onSave: () -> Void
    var onDiscard: (() -> Void)? = nil

    @State private var feel: String? = nil
    @State private var note: String = ""
    @State private var showDiscardConfirm = false
    @State private var feedback: FeedbackEntry

    init(session: ActiveSession, onSave: @escaping () -> Void, onDiscard: (() -> Void)? = nil) {
        self.session = session
        self.onSave = onSave
        self.onDiscard = onDiscard
        self._feedback = State(initialValue: FeedbackEntry(date: Date(), sessionId: session.templateId))
    }

    private static let feelOptions = ["Too easy", "Easy", "Right", "Hard", "Too much"]

    // MARK: - Derived values

    private var stats: SessionStats { store.stats(for: session) }

    private var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(session.startTime)))
    }

    private var durationString: String {
        Self.formatElapsed(elapsedSeconds)
    }

    private var prs: [PRItem] {
        let prev = store.getPreviousSession(templateId: session.templateId)
        guard let prev else { return [] }

        return session.exercises.compactMap { ex -> PRItem? in
            guard let prevEx = prev.exercises.first(where: { $0.id == ex.id }) else { return nil }

            let curWeights = ex.sets.compactMap { s -> Double? in
                guard s.done, !s.weight.isEmpty else { return nil }
                return Double(s.weight)
            }
            let prevWeights = prevEx.sets.compactMap { s -> Double? in
                guard !s.weight.isEmpty else { return nil }
                return Double(s.weight)
            }
            guard let maxW = curWeights.max(), let prevMaxW = prevWeights.max() else { return nil }
            guard maxW > prevMaxW else { return nil }

            let diff = maxW - prevMaxW
            return PRItem(id: ex.id, name: ex.name, diff: diff, unit: ex.unit)
        }
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

                        statGrid
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        if !prs.isEmpty {
                            prBlock
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                        }

                        exerciseSummary
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        feelSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        FeedbackChips(entry: $feedback, exerciseOptions: feedbackExerciseOptions)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)

                        noteSection
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        Spacer().frame(height: 140)
                    }
                }
            }

            VStack(spacing: 10) {
                saveButton
                if onDiscard != nil {
                    discardButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .preferredColorScheme(.dark)
        .alert("Discard workout?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                onDiscard?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This session won't be saved to history. You can't undo this.")
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("SESSION COMPLETE")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text(dateLabel)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accent)
                .frame(height: 3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Done.")
                .styled(.displayL)
                .foregroundStyle(Color.ink)
            Text(session.name)
                .styled(.body)
                .foregroundStyle(Color.ink2)
        }
    }

    private var statGrid: some View {
        let items: [(value: String, label: String)] = [
            (durationString, "DURATION"),
            (String(stats.doneSets), "SETS"),
            (stats.avgRpe, "AVG RPE"),
        ]

        return HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                statCell(value: items[i].value, label: items[i].label)
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            Text(value)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
    }

    private var prBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accent)
                Text(prs.count == 1 ? "1 PR THIS SESSION" : "\(prs.count) PRS THIS SESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.accent)
            }
            // Wrapping chip row.
            FlowLayout(spacing: 5) {
                ForEach(prs) { pr in
                    prChip(pr)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentWash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentBorder, lineWidth: 0.5)
        )
    }

    private func prChip(_ pr: PRItem) -> some View {
        Text("\(pr.name.uppercased()) +\(formattedDiff(pr.diff)) \(pr.unit)")
            .styled(.micro)
            .foregroundStyle(Color.accentInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accent)
            )
    }

    private var exerciseSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink3)

            let prIds = Set(prs.map(\.id))
            let rows: [LoggedExercise] = session.exercises.filter { ex in
                ex.sets.contains(where: { $0.done })
            }

            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    exerciseRow(rows[i], isPR: prIds.contains(rows[i].id), isLast: i == rows.count - 1)
                }
            }
            .padding(.top, 8)
        }
    }

    private func exerciseRow(_ ex: LoggedExercise, isPR: Bool, isLast: Bool) -> some View {
        let done = ex.sets.filter { $0.done }
        let summary = done
            .map { "\($0.weight.isEmpty ? "—" : $0.weight)×\($0.reps.isEmpty ? "—" : $0.reps)" }
            .joined(separator: " · ")
        let rpes = done.compactMap { Double($0.rpe) }
        let rpeString: String? = {
            guard let lo = rpes.min(), let hi = rpes.max() else { return nil }
            if lo == hi { return "rpe \(formattedRpe(lo))" }
            return "rpe \(formattedRpe(lo))–\(formattedRpe(hi))"
        }()

        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(ex.name)
                            .font(.custom("SpaceGrotesk-Medium", size: 14))
                            .foregroundStyle(Color.ink)
                        if isPR {
                            Text("PR")
                                .font(.custom("JetBrainsMono-Medium", size: 9))
                                .tracking(0.14 * 9)
                                .foregroundStyle(Color.accentInk)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4).fill(Color.accent)
                                )
                        }
                    }
                    Text(summary)
                        .font(.custom("JetBrainsMono-Regular", size: 10.5))
                        .foregroundStyle(Color.ink3)
                }
                Spacer(minLength: 8)
                if let rpeString {
                    Text(rpeString)
                        .font(.custom("JetBrainsMono-Regular", size: 11))
                        .foregroundStyle(Color.ink2)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.lineSoft)
                    .frame(height: 0.5)
            }
        }
    }

    private var feelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW DID IT FEEL?")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            HStack(spacing: 5) {
                ForEach(Self.feelOptions, id: \.self) { option in
                    feelChip(option)
                }
            }
        }
    }

    private func feelChip(_ option: String) -> some View {
        let active = feel == option
        return Button {
            // Tap toggles selection; re-tap clears.
            feel = active ? nil : option
        } label: {
            Text(option)
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .foregroundStyle(active ? Color.accentInk : Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.accent : Color.elevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(active ? Color.clear : Color.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE (OPTIONAL)")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.line, lineWidth: 0.5)

                if note.isEmpty {
                    Text("Tap to add a note...")
                        .font(.custom("Inter-Regular", size: 13))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $note)
                    .font(.custom("Inter-Regular", size: 13))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 80)
        }
    }

    /// Exercises that had at least one logged set, used as hurt-area options.
    private var feedbackExerciseOptions: [(id: String, name: String)] {
        session.exercises
            .filter { ex in ex.sets.contains(where: { $0.done }) }
            .map { ex in (id: ex.id, name: ex.name) }
    }

    /// True when the user touched any structured-feedback control.
    /// Avoids polluting memory with empty entries when they only logged sets.
    private var hasStructuredFeedback: Bool {
        feedback.difficulty != nil || !feedback.hurtAreas.isEmpty || feedback.ranLong
    }

    private var saveButton: some View {
        Button {
            store.saveCompleted(session, feel: feel, note: note.isEmpty ? nil : note)
            if hasStructuredFeedback {
                var stamped = feedback
                stamped.date = Date()
                if !note.isEmpty { stamped.notes = note }
                memoryStore.update { $0.feedback.append(stamped) }
            }
            onSave()
        } label: {
            HStack(spacing: 8) {
                Text("Save session")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                    .foregroundStyle(Color.accentInk)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accent)
            )
        }
        .buttonStyle(.plain)
    }

    private var discardButton: some View {
        Button {
            showDiscardConfirm = true
        } label: {
            Text("Discard workout")
                .font(.custom("JetBrainsMono-Medium", size: 11))
                .tracking(0.14 * 11)
                .textCase(.uppercase)
                .foregroundStyle(Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.line, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formattedDiff(_ d: Double) -> String {
        // Drop trailing .0 for integer-valued diffs.
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(d))
        }
        return String(format: "%.1f", d)
    }

    private func formattedRpe(_ r: Double) -> String {
        if r.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(r))
        }
        return String(format: "%.1f", r)
    }

    static func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - PR Item

private struct PRItem: Identifiable, Equatable {
    let id: String
    let name: String
    let diff: Double
    let unit: String
}

// MARK: - FlowLayout (wrapping chip row)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview("With PRs") {
    let defaults = previewDefaults(seedHistory: true)
    let store = SessionStore(defaults: defaults)
    let session = previewSession(withSomeDone: true)
    return CompleteScreen(session: session, onSave: {})
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: defaults))
        .background(Color.bg)
}

#Preview("No history (no PR block)") {
    let defaults = previewDefaults(seedHistory: false)
    let store = SessionStore(defaults: defaults)
    let session = previewSession(withSomeDone: true)
    return CompleteScreen(session: session, onSave: {})
        .environmentObject(store)
        .environmentObject(MemoryStore(defaults: defaults))
        .background(Color.bg)
}

// MARK: - Preview helpers (private to file)

private func previewDefaults(seedHistory: Bool) -> UserDefaults {
    let suiteName = "CompleteScreenPreview.\(seedHistory ? "withHistory" : "noHistory")"
    let d = UserDefaults(suiteName: suiteName)!
    d.removePersistentDomain(forName: suiteName)
    if seedHistory {
        // Seed a prior session whose Bench Press top set was 135 lbs — current
        // session below logs 155 lbs so the PR block fires.
        let prev = SavedSession(
            templateId: "upper-1",
            name: "Upper Body Day 1",
            category: "Push / Pull / Accessories",
            startTime: Date().addingTimeInterval(-7 * 86400),
            exercises: [
                LoggedExercise(
                    id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
                    targetSets: 5, targetReps: 5, rest: 120,
                    sets: [
                        LoggedSet(num: 1, weight: "115", reps: "5", rpe: "6", done: true),
                        LoggedSet(num: 2, weight: "125", reps: "5", rpe: "7", done: true),
                        LoggedSet(num: 3, weight: "135", reps: "5", rpe: "8", done: true),
                    ],
                    prevSets: []
                )
            ],
            feel: "Right",
            note: nil,
            endTime: Date().addingTimeInterval(-7 * 86400 + 2400),
            duration: 2400
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode([prev]) {
            d.set(data, forKey: "pt_sessions")
        }
    }
    return d
}

private func previewSession(withSomeDone: Bool) -> ActiveSession {
    let tmpl = WorkoutTemplate.upper1
    let exercises = tmpl.exercises.map { ex -> LoggedExercise in
        let sets = (0..<ex.targetSets).map { i -> LoggedSet in
            let done = withSomeDone && i < 3
            let weight: String = {
                guard done else { return "" }
                switch ex.id {
                case "bench":    return ["135", "145", "155"][i]
                case "pullup":   return ["25", "25", "25"][i]
                case "ohp":      return ["95", "100", "100"][i]
                case "row":      return ["50", "50", "55"][i]
                case "skull":    return ["65", "70", "70"][i]
                case "facepull": return ["30", "30", "30"][i]
                default:         return "100"
                }
            }()
            return LoggedSet(num: i + 1, weight: weight, reps: String(ex.targetReps), rpe: done ? "7" : "", done: done)
        }
        return LoggedExercise(
            id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
            targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest,
            sets: sets, prevSets: []
        )
    }
    return ActiveSession(
        templateId: tmpl.id,
        name: tmpl.name,
        category: tmpl.category,
        startTime: Date().addingTimeInterval(-2528),
        exercises: exercises,
        feel: nil,
        note: nil
    )
}
