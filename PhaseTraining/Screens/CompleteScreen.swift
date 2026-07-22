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
//   8. Sticky Done button (lime primary) — the session is ALREADY saved
//
// FINISH IS THE SAVE: the session auto-saves via `SessionStore.saveCompleted`
// in `.onAppear` (it also clears the active session), so this screen is a
// post-save summary, not a save gate. `feel`/`note` edits patch the saved
// record in place (`syncEdits` → `updateSession`); PR detection self-excludes
// the now-persisted session. "Done" just returns to Today; "Discard" deletes
// the record (it was saved) and returns. Structured feedback
// (`PostWorkoutFeedbackSheet` → FeedbackEntry, read by the planner) is OPT-IN:
// the "Add details for your coach" button presents it; it's never forced, so
// the happy path stays one tap (Done).

import SwiftUI

struct CompleteScreen: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var memoryStore: MemoryStore
    /// Coach gate — drives the feedback button's LABEL only (the button and
    /// sheet stay available to everyone; FeedbackEntry feeds the planner
    /// regardless). Same @AppStorage pairing as CoachBubble.
    @AppStorage(CoachConsent.storageKey) private var consentGranted: Bool = false
    @AppStorage(CoachEntitlement.proKey) private var proEntitled: Bool = false

    let session: ActiveSession
    let onSave: () -> Void
    var onDiscard: (() -> Void)? = nil

    @State private var feel: String? = nil
    @State private var note: String = ""
    /// Frozen at the moment this screen appears (i.e. the session completed),
    /// so DURATION doesn't keep ticking up while the user fills feel/note.
    /// The same timestamp is handed to `saveCompleted` so the stored duration
    /// matches what was displayed.
    @State private var completedAt = Date()
    @State private var showDiscardConfirm = false
    /// The auto-saved record — the workout is committed the moment this screen
    /// appears (Finish IS the save). Held so `feel`/`note` edits can patch it in
    /// place and Discard can delete it. nil until the on-appear save runs.
    @State private var saved: SavedSession? = nil
    /// Set just before Discard deletes the record, so the trailing feel/note
    /// onChange syncs don't re-insert the row we're removing.
    @State private var discarded = false
    /// Drives the OPTIONAL structured-feedback sheet. Not auto-presented (the
    /// workout already saved) — the user taps "Add details" to open it, which
    /// is the only thing that captures a FeedbackEntry for the coach/planner.
    @State private var showFeedbackSheet = false

    init(session: ActiveSession, onSave: @escaping () -> Void, onDiscard: (() -> Void)? = nil) {
        self.session = session
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    private static let feelOptions = ["Too easy", "Easy", "Right", "Hard", "Too much"]

    // MARK: - Derived values

    private var stats: SessionStats { store.stats(for: session) }

    private var elapsedSeconds: Int {
        max(0, Int(completedAt.timeIntervalSince(session.startTime)))
    }

    private var durationString: String {
        Self.formatElapsed(elapsedSeconds)
    }

    private var prs: [PRItem] {
        // Cross-template + per-rep PR detection via SessionStore. A PR here
        // means "highest weight ever lifted at this rep count for this
        // exercise, matched by name across all stored sessions". Captures
        // PRs that the old same-template comparison missed (e.g. you swap
        // routines, you set a new bench PR — it still counts).
        // Self-exclude once auto-saved: the session is in user.db by the time
        // this recomputes, so PR detection must skip its own rows.
        store.personalRecords(in: session.exercises,
                              excludingSessionId: saved?.startTime.timeIntervalSince1970,
                              sessionDate: session.startTime).map { record in
            PRItem(
                id: "\(record.exerciseName)|\(record.reps)",
                name: record.exerciseName,
                diff: record.previousBest.map { record.weight - $0 } ?? record.weight,
                unit: session.exercises.first { $0.name == record.exerciseName }?.displayUnit ?? "lbs"
            )
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
                TabHeader(
                    eyebrow: dateLabel,
                    eyebrowTrailing: durationString.uppercased(),
                    title: "Workout\nlogged",
                    subtitle: session.name
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Mr Kettle takes a flex — the session-complete payoff.
                        KettleView(loop: .flex)
                            .frame(height: 116)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                            .accessibilityHidden(true)

                        statGrid
                            .padding(.horizontal, 20)
                            .padding(.top, 24)

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

                        noteSection
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        Spacer().frame(height: 140)
                    }
                }
            }

            VStack(spacing: 10) {
                doneButton
                feedbackButton
                if onDiscard != nil {
                    discardButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: autosaveIfNeeded)
        .onChange(of: feel) { _, _ in syncEdits() }
        .onChange(of: note) { _, _ in syncEdits() }
        .sheet(isPresented: $showFeedbackSheet) {
            // Optional, opt-in capture of a structured FeedbackEntry (difficulty
            // + hurt areas → memory.feedback, read by the planner). The session
            // is already saved; onDone just dismisses.
            PostWorkoutFeedbackSheet(
                sessionId: session.templateId,
                onDone: { showFeedbackSheet = false }
            )
        }
        .alert("Discard workout?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                discarded = true
                if let saved { store.deleteSession(id: saved.startTime.timeIntervalSince1970) }
                onDiscard?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout you just logged from your history.")
        }
    }

    // MARK: - Sections

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

    /// HANDOFF §4: rows render through ExerciseTile (.summary trailing).
    /// PR pill, per-set summary text, and RPE range all move into the tile's
    /// summary slot — no more bespoke layout here.
    private var exerciseSummary: some View {
        let prIds = Set(prs.map(\.id))
        let rows: [LoggedExercise] = session.exercises.filter { ex in
            ex.sets.contains(where: { $0.done })
        }
        return TileList(label: "EXERCISES", count: rows.count) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, ex in
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
                let setsLabel = done.count == 1 ? "1 set" : "\(done.count) sets"

                ExerciseTile(
                    vm: .init(
                        leading: .index(idx + 1),
                        title: ex.name,
                        meta: setsLabel,
                        trailing: .summary(text: summary, rpe: rpeString, isPR: prIds.contains(ex.id))
                    ),
                    density: .flat
                )
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

    /// Finish IS the save: commit the session the moment this summary appears,
    /// so there's no separate "Save" tap. `feel`/`note` start empty and are
    /// patched in via `syncEdits` if the user fills them. saveCompleted clears
    /// the active session itself.
    private func autosaveIfNeeded() {
        guard saved == nil else { return }
        saved = store.saveCompleted(session, feel: feel,
                                    note: note.isEmpty ? nil : note,
                                    endTime: completedAt)
    }

    /// Patch the auto-saved record's feel/note in place as the user edits them.
    /// No-op once Discard has removed the row.
    private func syncEdits() {
        guard !discarded, var s = saved else { return }
        s.feel = feel
        s.note = note.isEmpty ? nil : note
        store.updateSession(s)
        saved = s
    }

    private var doneButton: some View {
        Button(action: onSave) {
            HStack(spacing: 8) {
                Text("Done")
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
        .accessibilityIdentifier("complete-done")
    }

    /// Optional, opt-in: open the structured-feedback sheet (difficulty + hurt
    /// areas → coach). Tertiary styling — secondary to Done, not a forced step.
    /// Always shown — feedback is free (the planner reads FeedbackEntry with
    /// or without the coach) — but "for your coach" is only honest when the
    /// coach is actually unlocked, so locked users get neutral copy.
    private var feedbackButton: some View {
        let coachUnlocked = CoachEntitlement.unlocked(consent: consentGranted, pro: proEntitled)
        return Button {
            showFeedbackSheet = true
        } label: {
            Text(coachUnlocked ? "Add details for your coach" : "Log how this felt")
                .font(.custom("Inter-Regular", size: 13).weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("complete-feedback")
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
        .accessibilityIdentifier("complete-discard")
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
