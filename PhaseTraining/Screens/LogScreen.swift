// LogScreen.swift — The core training log screen.
//
// Ports `handoff/proto/log.jsx` (behavior) + `handoff/hd-training-log.jsx` (visuals)
// to SwiftUI. Sticky header with elapsed timer + progress bar, scrollable exercise
// list with inline number inputs, set checkboxes, inline rest-timer card with
// pulse animation, "+ Add Set", active-row indicator, auto-save on every change.
//
// State model (mirrors prototype):
//   - `session: ActiveSession` — full session, mutated in place, persisted via store.saveActive
//     on every change.
//   - Rest timer (view-local, not persisted): `restExIdx`, `restSetIdx`, `restStartedAt`,
//     `restDuration`. Initial duration is `ex.rest`; +15 increments `restDuration` so the
//     countdown extends. Skip clears all four. Auto-clears when remaining hits 0 (UI just
//     hides; stale state is overwritten on next toggle).
//
// Timers:
//   - Elapsed time and rest countdown both tick via `TimelineView(.periodic(...))`.
//   - TimelineViews wrap ONLY the time-display text (not TextFields), so re-renders
//     don't disrupt user typing.

import SwiftUI
import UIKit
import AudioToolbox

struct LogScreen: View {
    @EnvironmentObject private var store: SessionStore
    let onFinish: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var session: ActiveSession = Self.placeholder
    @State private var didLoad = false
    @State private var showCancelConfirm = false

    // Rest timer state (view-local, intentionally non-persistent per spec).
    @State private var restExIdx: Int? = nil
    @State private var restSetIdx: Int? = nil
    @State private var restStartedAt: Date? = nil
    @State private var restDuration: Int? = nil
    /// Date a rest timer was anchored at. Reset whenever a new rest starts so
    /// the expiry-alert fires once per rest instance. nil = no alert pending.
    @State private var restAlertFiredFor: Date? = nil
    /// When set, the rest card renders in "expired" flash state. Cleared
    /// ~1.2s after expiry so the card transitions back to a normal hidden state.
    @State private var restExpiredFlashUntil: Date? = nil

    /// Long-press driven "swap exercise" sheet. nil = closed. Keys by index
    /// into session.exercises so we can mutate it on pick.
    @State private var swappingExIdx: Int? = nil
    /// Read-only Exercise detail (name → coach.db lookup). Opens via row tap
    /// (mid-workout how-to) or contextMenu "Show details".
    @State private var detailExercise: Exercise? = nil
    /// Mid-workout "Add exercise" picker. true = sheet open.
    @State private var addingExercise: Bool = false

    /// Exercise indices (into `session.exercises`) where the user tapped the
    /// "BW" label to reveal a weight input for a bodyweight movement — the
    /// rare weighted-bird-dog / weight-vest case. Bodyweight exercises hide
    /// the weight column by default so reps-only sets need zero weight taps.
    @State private var weightEntryExercises: Set<Int> = []

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if didLoad {
                content
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: session) { _, newValue in
            // Auto-save on every mutation (per README.md:286).
            store.saveActive(newValue)
        }
        .alert("Discard workout?", isPresented: $showCancelConfirm) {
            Button("Discard", role: .destructive) { onCancel?() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your in-progress sets won't be saved.")
        }
        .sheet(item: swappingBinding) { wrapped in
            let original = session.exercises[wrapped.index]
            // Build 99 — switched from SubstituteExerciseSheet (sparse
            // curated table — many exercises had zero substitutes, so the
            // list was empty) to ExercisePickerSheet pre-filtered to
            // "similar exercises": same muscle bucket + same movement
            // category as the source. Same fix the preview sheet shipped
            // in build 78 + Today inline in build 94. User can clear
            // either filter to broaden if they want anything in the library.
            ExercisePickerSheet(
                title: "Replace \(original.name)",
                initialFilters: similarFiltersForExerciseName(original.name),
                onPick: { picked in
                    swapExercise(at: wrapped.index, with: picked)
                }
            )
        }
        .sheet(item: $detailExercise) { ex in
            ExerciseDetailSheet(exercise: ex)
        }
        .sheet(isPresented: $addingExercise) {
            // Mid-workout add. No initial filter — user came to the log
            // wanting to insert something specific that wasn't in the plan,
            // so we open the picker wide and let them search.
            ExercisePickerSheet(
                title: "Add exercise",
                onPick: { picked in
                    appendExerciseFromPicker(picked)
                }
            )
        }
    }

    private var swappingBinding: Binding<LogRowIndex?> {
        Binding(
            get: { swappingExIdx.map(LogRowIndex.init) },
            set: { swappingExIdx = $0?.index }
        )
    }

    /// Coach.db image lookup by exercise name. Used for the row thumbnail —
    /// LoggedExercise only carries name (not the original exerciseId), so we
    /// resolve via case-insensitive name match. Returns nil for exercises
    /// without media or whose name doesn't match a catalog row.
    private func thumbnailURL(forName name: String) -> String? {
        CoachDatabase.shared
            .listExercises(search: name)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            .flatMap { $0.thumbnailURL ?? $0.imageURL }
    }

    /// Resolve "similar exercises" filters for the picker — same muscle
    /// bucket AND same movement category as the source. Mirrors the
    /// helper on DayWorkoutPreviewSheet + TodayScreen so all three swap
    /// surfaces filter the same way. Returns empty filters when the
    /// source exercise can't be resolved in coach.db (custom routines
    /// without a backing exerciseId).
    private func similarFiltersForExerciseName(_ name: String) -> ExerciseFilters {
        var filters = ExerciseFilters()
        guard let dbEx = CoachDatabase.shared
                .listExercises(search: name)
                .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return filters }

        let muscles = CoachDatabase.shared.musclesForExercise(dbEx.id).sorted { lhs, rhs in
            let rank: (String) -> Int = { r in r == "primary" ? 0 : (r == "secondary" ? 1 : 2) }
            return rank(lhs.role) < rank(rhs.role)
        }
        for entry in muscles {
            if let bucket = MuscleBucket.bucket(forSlug: entry.slug) {
                filters.bucket = bucket
                break
            }
        }
        for slug in CoachDatabase.shared.patternsForExercise(dbEx.id) {
            if let cat = MovementCategory.category(forSlug: slug) {
                filters.category = cat
                break
            }
        }
        return filters
    }

    /// In-session substitution. Replace the exercise's name + display type
    /// in-place; keep already-logged sets intact (the user did the work,
    /// just under a different label).
    private func swapExercise(at idx: Int, with picked: Exercise) {
        guard session.exercises.indices.contains(idx) else { return }
        session.exercises[idx].name = picked.name
        if let modality = picked.modality, !modality.isEmpty {
            session.exercises[idx].type = picked.modalityLabel
        }
    }

    // MARK: - Body content

    /// Re-ordered + labeled view of `session.exercises` for rendering.
    /// Members of the same superset render adjacently with an "A1/A2/…"
    /// prefix on the title and a 3pt accent left band spanning the group.
    /// Solo (un-supersetted) rows pass through unchanged.
    private var groupedExercises: [SupersetGroupedItem<LoggedExercise>] {
        SupersetGrouping.layout(session.exercises) { $0.supersetGroup }
    }

    private var content: some View {
        VStack(spacing: 0) {
            stickyHeader
            ScrollView {
                VStack(spacing: 0) {
                    titleBlock
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    let grouped = groupedExercises
                    ForEach(Array(grouped.enumerated()), id: \.offset) { i, gi in
                        exerciseBlock(exIdx: gi.originalIndex, grouping: gi)
                        if i < grouped.count - 1 {
                            Rectangle()
                                .fill(Color.line)
                                .frame(height: 0.5)
                                .padding(.horizontal, 20)
                        }
                    }

                    // Mid-workout "Add exercise" — opens the full picker so
                    // the user can insert anything from coach.db without
                    // leaving the log to edit the plan.
                    Rectangle()
                        .fill(Color.line)
                        .frame(height: 0.5)
                        .padding(.horizontal, 20)
                    Button { addingExercise = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Add exercise")
                                .styled(.body)
                        }
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-add-exercise")

                    // Bottom clearance for the system tab bar. Without this
                    // the last few exercise rows render UNDER the tab bar
                    // (snapshot_ui showed tab bar at y=791-874 occluding
                    // log-set-check-2-N for the 3rd-of-5 exercise in the
                    // supersets demo seed). Tab bar visible height is
                    // 49pt + home-indicator inset ~34pt = ~83pt. 120pt
                    // gives an extra safety margin so reorder-handles and
                    // contextMenus don't get shadowed either.
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Sticky header

    private var stickyHeader: some View {
        let stats = store.stats(for: session)
        let totalSets = max(stats.totalSets, 1)
        let progress = CGFloat(stats.doneSets) / CGFloat(totalSets)
        let anyUndone = stats.doneSets < stats.totalSets

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if onCancel != nil {
                    Button {
                        showCancelConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .frame(width: 28, height: 28)
                            .background(Color.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-cancel")
                }

                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.ink3)

                TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                    Text(Self.fmtElapsed(ctx.date.timeIntervalSince(session.startTime)))
                        .styled(.monoM)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                }

                Spacer()

                // Whole-workout shortcut: log every remaining set in one tap
                // (rack-first users). Secondary styling keeps Finish the
                // primary CTA. Hidden once everything's logged.
                if anyUndone {
                    Button(action: logAllSetsAllExercises) {
                        Text("Log all")
                            .font(.custom("Inter-Regular", size: 13).weight(.bold))
                            .tracking(-0.01 * 13)
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accentBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("log-all-workout")
                }

                Button(action: onFinish) {
                    Text("Finish")
                        .font(.custom("Inter-Regular", size: 13).weight(.bold))
                        .tracking(-0.01 * 13)
                        .foregroundStyle(Color.accentInk)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-finish")
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.lineSoft)
                    Rectangle()
                        .fill(Color.accent)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
            .frame(height: 3)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
        }
        .background(Color.bg)
    }

    // MARK: - Title block (in scrolled body, like proto)

    private var titleBlock: some View {
        let stats = store.stats(for: session)
        return VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .styled(.displayM)
                .foregroundStyle(Color.ink)
            Text("\(session.exercises.count) exercises · \(stats.doneSets)/\(stats.totalSets) sets logged")
                .styled(.body)
                .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Exercise block

    @ViewBuilder
    private func exerciseBlock(exIdx: Int, grouping: SupersetGroupedItem<LoggedExercise>? = nil) -> some View {
        let ex = session.exercises[exIdx]
        let firstUndone = ex.sets.firstIndex { !$0.done }
        let allDone = ex.sets.allSatisfy { $0.done }
        let displayName: String = {
            if let label = grouping?.label { return "\(label)  \(ex.name)" }
            return ex.name
        }()
        let inSuperset = (grouping?.groupSize ?? 1) >= 2

        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                ExerciseThumbnail(urlString: thumbnailURL(forName: ex.name), size: 32, cornerRadius: 6)
                    .opacity(allDone ? 0.6 : 1.0)
                if allDone {
                    ZStack {
                        Circle()
                            .fill(Color.ok.opacity(0.15))
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.ok)
                    }
                }
                Text(displayName)
                    .styled(.displayS)
                    .foregroundStyle(allDone ? Color.ink2 : Color.ink)
                    .accessibilityIdentifier("log-exercise-name-\(exIdx)")
                if let type = ex.type, !type.isEmpty {
                    Text("(\(type))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
                Button { swappingExIdx = exIdx } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap with similar exercise")
                .accessibilityIdentifier("log-swap-\(exIdx)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.top, 14)
            .padding(.bottom, 6)
            // Tap the exercise header (anywhere except the Swap button, which
            // is its own tappable Button) to open the read-only how-to /
            // video / instructions sheet. Mid-workout form check.
            .onTapGesture {
                detailExercise = CoachDatabase.shared
                    .listExercises(search: ex.name)
                    .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }
            }
            .contextMenu {
                Button {
                    swappingExIdx = exIdx
                } label: {
                    Label("Swap with similar…", systemImage: "rectangle.on.rectangle")
                }
                Button {
                    detailExercise = CoachDatabase.shared
                        .listExercises(search: ex.name)
                        .first { $0.name.caseInsensitiveCompare(ex.name) == .orderedSame }
                } label: {
                    Label("Show details", systemImage: "info.circle")
                }
            }

            // Coaching hints (build 70): RPE + tempo prescription from the
            // generator (or the LLM strategist). Hidden when both are nil so
            // pre-build-70 sessions + non-generated workouts keep the
            // existing compact layout.
            if ex.rpe != nil || ex.tempo != nil {
                coachingHintsRow(rpe: ex.rpe, tempo: ex.tempo)
            }

            // Build 103: deterministic progression suggestion. Reads the
            // prev-session top set already on `ex.prevSets`, applies the
            // ProgressionSuggestion rule, renders "SUGGESTED · 190 lb (+5)"
            // so the user knows the target for today before logging set 1.
            // Hidden when there's no prior signal — no nag on first-time
            // exercises.
            progressionPill(for: ex)

            // Column headers
            columnHeaders(weightLabel: weightColumnLabel(exIdx: exIdx))

            // Set rows + inline rest dividers + active rest card
            ForEach(Array(ex.sets.enumerated()), id: \.offset) { setIdx, _ in
                setRow(exIdx: exIdx, setIdx: setIdx, isActive: setIdx == firstUndone)

                // Static rest divider between two completed sets.
                if ex.sets[setIdx].done,
                   setIdx + 1 < ex.sets.count,
                   ex.sets[setIdx + 1].done {
                    restDivider(seconds: ex.rest)
                }

                // Active rest timer card (inline, anchored to just-completed set).
                if restExIdx == exIdx, restSetIdx == setIdx {
                    activeRestCard()
                }
            }

            // Add Set button
            Button(action: { addSet(exIdx: exIdx) }) {
                Text("+ Add Set (\(Self.fmtTime(ex.rest)))")
                    .styled(.body)
                    .foregroundStyle(Color.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Log all sets — for users who do the work at the rack first
            // and come back to the phone to log everything at once. Marks
            // every set done in one tap; for sets with empty weight/reps,
            // propagates the most recent filled value from this exercise
            // (set 1 typically already has prev-session weight + target reps
            // pre-filled at session-create time).
            if !allDone {
                Button(action: { logAllSets(exIdx: exIdx) }) {
                    Text("Log all sets")
                        .styled(.body)
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("log-all-\(exIdx)")
            }
        }
        .padding(.horizontal, 20)
        .overlay(alignment: .leading) {
            // Superset visual band — 3pt accent left edge spanning the row.
            // Drawn per-row so consecutive members of the same group form
            // one continuous band; rounding the corners on first/last members
            // gives the group endpoints a clean cap without per-group
            // wrapper geometry.
            if inSuperset {
                supersetBand(grouping: grouping!)
            }
        }
    }

    /// 3pt-wide accent band drawn at the leading edge of a supersetted row.
    /// Rounded only on the first/last member so adjacent group members
    /// visually join into one continuous band.
    @ViewBuilder
    private func supersetBand(grouping: SupersetGroupedItem<LoggedExercise>) -> some View {
        let topRadius: CGFloat = grouping.isFirstInGroup ? 1.5 : 0
        let bottomRadius: CGFloat = grouping.isLastInGroup ? 1.5 : 0
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        .fill(Color.accent)
        .frame(width: 3)
        .padding(.leading, 8)
        .padding(.top, grouping.isFirstInGroup ? 8 : 0)
        .padding(.bottom, grouping.isLastInGroup ? 8 : 0)
        .accessibilityHidden(true)
    }

    /// Build-70 coaching hint row — small mono line above the column
    /// headers that surfaces the generator's (or LLM's) RPE + tempo
    /// prescription. Renders only the fields that are set; e.g. an exercise
    /// with just RPE skips the dot separator.
    private func coachingHintsRow(rpe: String?, tempo: String?) -> some View {
        var parts: [String] = []
        if let rpe, !rpe.isEmpty { parts.append("RPE \(rpe)") }
        if let tempo, !tempo.isEmpty { parts.append("tempo \(tempo)") }
        return HStack(spacing: 0) {
            Text(parts.joined(separator: " · "))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.elevated.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// Tiny progression hint just under the coaching-hints row. Reads the
    /// heaviest done working set in `ex.prevSets` and applies the
    /// deterministic ProgressionSuggestion rule. nil when there's no prior
    /// signal so first-time-exercise rows stay clean.
    @ViewBuilder
    private func progressionPill(for ex: LoggedExercise) -> some View {
        if let suggestion = computeProgressionSuggestion(for: ex) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.circle")
                    .font(.system(size: 11, weight: .medium))
                Text(suggestion.text)
                    .font(.monoXS)
                Spacer(minLength: 0)
            }
            .foregroundStyle(suggestion.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentWash)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.top, 4)
            .padding(.bottom, 4)
            .accessibilityIdentifier("log-progression-pill")
        }
    }

    private struct ProgressionPillModel {
        let text: String
        let tint: Color
    }

    private func computeProgressionSuggestion(for ex: LoggedExercise) -> ProgressionPillModel? {
        // Shared extraction: the heaviest set that MET target reps (so a
        // pyramid's heavy top single doesn't read as a missed target).
        guard let r = ProgressionSuggestion.suggest(
            prevSets: ex.prevSets,
            targetReps: ex.targetReps,
            exerciseName: ex.name,
            unit: ex.unit
        ) else { return nil }
        let weightStr = r.suggestedWeightString
        let label: String
        let tint: Color
        switch r.delta {
        case let d where d > 0:
            label = "SUGGESTED · \(weightStr) \(ex.unit) · \(r.label)"
            tint = .accent
        case let d where d < 0:
            label = "BACK OFF · \(weightStr) \(ex.unit) · \(r.label)"
            tint = .danger
        default:
            label = "HOLD · \(weightStr) \(ex.unit) — earn the reps"
            tint = .ink2
        }
        return ProgressionPillModel(text: label, tint: tint)
    }

    private func columnHeaders(weightLabel: String) -> some View {
        HStack(spacing: 4) {
            headerLabel("SET").frame(width: 22)
            Rectangle()
                .fill(Color.line)
                .frame(width: 0.5, height: 12)
            headerLabel("Last", align: .leading, color: .ink2).frame(width: 58)
            headerLabel(weightLabel.uppercased()).frame(maxWidth: .infinity)
            headerLabel("REPS").frame(maxWidth: .infinity)
            headerLabel("Effort").frame(width: 52)
            Color.clear.frame(width: 24)
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    private func headerLabel(_ text: String, align: TextAlignment = .center, color: Color = .ink3) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(color)
            .textCase(.uppercase)
            .multilineTextAlignment(align)
            .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .center)
    }

    // MARK: - Set row

    @ViewBuilder
    private func setRow(exIdx: Int, setIdx: Int, isActive: Bool) -> some View {
        let set = session.exercises[exIdx].sets[setIdx]
        let prevSet = session.exercises[exIdx].prevSets.indices.contains(setIdx)
            ? session.exercises[exIdx].prevSets[setIdx]
            : nil
        let prevLabel: String = {
            guard let p = prevSet, !p.weight.isEmpty || !p.reps.isEmpty else { return "—" }
            return "\(p.weight)×\(p.reps)"
        }()

        let setNumberColor: Color = {
            if set.done { return .ink3 }
            if isActive { return .accent }
            return .ink2
        }()

        ZStack(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
                    .offset(x: -20)
            }

            HStack(spacing: 4) {
                if set.isWarmup {
                    // "W" pill replaces the set-number for warmup sets.
                    // Visually flags the row as a non-counting ramp set.
                    Text("W")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.bg)
                        .frame(width: 18, height: 14)
                        .background(Color.ink3)
                        .clipShape(Capsule())
                        .frame(width: 22, alignment: .center)
                        .accessibilityLabel("Warmup set")
                } else {
                    Text("\(set.num)")
                        .styled(.monoXS)
                        .foregroundStyle(setNumberColor)
                        .frame(width: 22, alignment: .center)
                        .monospacedDigit()
                        .accessibilityIdentifier("log-set-num-\(exIdx)-\(setIdx)")
                }

                Rectangle()
                    .fill(Color.line)
                    .frame(width: 0.5, height: 18)

                Text(prevLabel)
                    .styled(.monoXS)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .leading)

                weightCell(exIdx: exIdx, setIdx: setIdx, done: set.done, isActive: isActive)
                    .frame(maxWidth: .infinity)

                numCell(
                    text: $session.exercises[exIdx].sets[setIdx].reps,
                    placeholder: "—",
                    done: set.done,
                    active: isActive
                )
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("log-set-reps-\(exIdx)-\(setIdx)")

                effortCell(
                    text: $session.exercises[exIdx].sets[setIdx].rpe,
                    done: set.done,
                    active: isActive
                )
                .frame(width: 52)

                checkDot(done: set.done) {
                    toggleSet(exIdx: exIdx, setIdx: setIdx)
                }
                .frame(width: 24)
                .accessibilityIdentifier("log-set-check-\(exIdx)-\(setIdx)")
            }
        }
        .padding(.vertical, 6)
        // Warmup sets render smaller + dimmed so the working sets read as
        // the primary content. Toggle via the contextMenu below.
        .font(.callout)
        .opacity(set.isWarmup ? 0.6 : 1.0)
        .contentShape(Rectangle())
        // Tap a logged set to re-open it for editing (e.g. adding an RPE the
        // user forgot). Only fires when set.done — un-done rows already
        // expose TextFields directly.
        .onTapGesture {
            if set.done { reopenSet(exIdx: exIdx, setIdx: setIdx) }
        }
        .contextMenu {
            if set.done {
                Button {
                    reopenSet(exIdx: exIdx, setIdx: setIdx)
                } label: {
                    Label("Edit set", systemImage: "pencil")
                }
            }
            Menu {
                ForEach(Self.rirOptions, id: \.self) { v in
                    Button(v) { setRIR(exIdx: exIdx, setIdx: setIdx, value: v) }
                }
                Button("Clear") { setRIR(exIdx: exIdx, setIdx: setIdx, value: "") }
            } label: {
                Label(set.rir.isEmpty ? "Set RIR…" : "RIR · \(set.rir)",
                      systemImage: "gauge.with.dots.needle.bottom.50percent")
            }
            Button {
                toggleWarmup(exIdx: exIdx, setIdx: setIdx)
            } label: {
                Label(set.isWarmup ? "Unmark warmup" : "Mark as warmup",
                      systemImage: "flame")
            }
            Button(role: .destructive) {
                deleteSet(exIdx: exIdx, setIdx: setIdx)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
        }
    }

    /// Weight column for one set. Bodyweight exercises (bird dog, dead bug, …)
    /// render a tappable "BW" label instead of a number field so the user logs
    /// reps + done without entering 0 every set. Tapping "BW" reveals the
    /// normal weight input for the rare weighted case.
    @ViewBuilder
    private func weightCell(exIdx: Int, setIdx: Int, done: Bool, isActive: Bool) -> some View {
        if showsWeightInput(exIdx: exIdx) {
            numCell(
                text: $session.exercises[exIdx].sets[setIdx].weight,
                placeholder: "—",
                done: done,
                active: isActive
            )
            .accessibilityIdentifier("log-set-weight-\(exIdx)-\(setIdx)")
            .onChange(of: session.exercises[exIdx].sets[setIdx].weight) { oldValue, newValue in
                propagateWeight(exIdx: exIdx, fromSetIdx: setIdx, oldValue: oldValue, newValue: newValue)
            }
        } else {
            bodyweightCell(exIdx: exIdx, setIdx: setIdx, done: done)
        }
    }

    /// Dimmed "BW" label shown in the weight column for a bodyweight set.
    /// Tapping (when the set isn't already logged) reveals the weight input
    /// for every set of this exercise — for adding a weight vest / plate.
    @ViewBuilder
    private func bodyweightCell(exIdx: Int, setIdx: Int, done: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                weightEntryExercises.insert(exIdx)
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text("BW")
                .styled(.monoS)
                .foregroundStyle(Color.ink3)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, done ? 6 : 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityIdentifier("log-set-bodyweight-\(exIdx)-\(setIdx)")
        .accessibilityLabel(done ? "Bodyweight" : "Bodyweight, tap to add weight")
    }

    /// Whether the weight column shows an editable number field for this
    /// exercise. Always true for weighted exercises. Bodyweight exercises
    /// collapse to a "BW" label unless the user opted into weight entry or a
    /// set already carries a weight (a weighted round logged earlier).
    private func showsWeightInput(exIdx: Int) -> Bool {
        guard session.exercises.indices.contains(exIdx) else { return true }
        let ex = session.exercises[exIdx]
        if !ex.isBodyweight { return true }
        if weightEntryExercises.contains(exIdx) { return true }
        return ex.sets.contains { !$0.weight.isEmpty }
    }

    /// Header text for the weight column: the exercise's unit normally, "BW"
    /// for a collapsed bodyweight exercise, "+lbs" once weight entry is shown.
    private func weightColumnLabel(exIdx: Int) -> String {
        guard session.exercises.indices.contains(exIdx) else { return "lbs" }
        let ex = session.exercises[exIdx]
        if ex.isBodyweight {
            return showsWeightInput(exIdx: exIdx) ? "+lbs" : "BW"
        }
        return ex.unit.isEmpty ? "lbs" : ex.unit
    }

    @ViewBuilder
    private func numCell(text: Binding<String>, placeholder: String, done: Bool, active: Bool) -> some View {
        if done {
            Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                .styled(.monoS)
                .foregroundStyle(Color.ink2)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .styled(.monoS)
                .foregroundStyle(active ? Color.accent : Color.ink)
                .monospacedDigit()
                .padding(.vertical, 7)
                .padding(.horizontal, 2)
                .background(active ? Color.accent.opacity(0.06) : Color.elevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active ? Color.accentBorder : Color.line, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    private static let effortOptions = ["6", "7", "8", "9", "10"]

    @ViewBuilder
    private func effortCell(text: Binding<String>, done: Bool, active: Bool) -> some View {
        let display = text.wrappedValue.isEmpty ? "—" : text.wrappedValue
        if done {
            Text(display)
                .styled(.monoS)
                .foregroundStyle(Color.ink2)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else {
            Menu {
                ForEach(Self.effortOptions, id: \.self) { v in
                    Button(v) { text.wrappedValue = v }
                }
                Button("Clear") { text.wrappedValue = "" }
            } label: {
                Text(display)
                    .styled(.monoS)
                    .foregroundStyle(active ? Color.accent : Color.ink)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 2)
                    .background(active ? Color.accent.opacity(0.06) : Color.elevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(active ? Color.accentBorder : Color.line, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func checkDot(done: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            if done {
                ZStack {
                    Circle().fill(Color.ok)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.bg)
                }
                .frame(width: 22, height: 22)
            } else {
                Circle()
                    .strokeBorder(Color.line, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
        // .borderless instead of .plain. Visually identical here (the label
        // is a Circle with an explicit fill, not a tinted system image), but
        // iOS 26 XCUITest synthesized taps do not fire .plain Button actions
        // when the label is < ~44pt — they DO fire .borderless. That broke
        // every rest-card-after-set-done UI test (the 22pt check dot tap
        // synthesized cleanly but never flipped done, so no rest card ever
        // rendered for the test to assert against).
        .buttonStyle(.borderless)
    }

    // MARK: - Inline rest UI

    private func restDivider(seconds: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.lineSoft).frame(height: 0.5).frame(maxWidth: .infinity)
            Text(Self.fmtTime(seconds))
                .styled(.monoXS)
                .foregroundStyle(Color.accentDim)
            Rectangle().fill(Color.lineSoft).frame(height: 0.5).frame(maxWidth: .infinity)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func activeRestCard() -> some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
            let remaining = currentRestRemaining(at: ctx.date)
            let isFlashing = restExpiredFlashUntil.map { ctx.date < $0 } ?? false
            if let r = remaining, r > 0 {
                RestTimer(
                    remaining: r,
                    expired: false,
                    onAdd15: { restDuration = (restDuration ?? 0) + 15 },
                    onSkip: { clearRest() },
                    onSetDuration: { newDuration in
                        // Reset start time so the new duration runs from now.
                        // Otherwise a shorter pick would have us already expired.
                        restDuration = newDuration
                        restStartedAt = Date()
                        restAlertFiredFor = restStartedAt
                    }
                )
                .padding(.vertical, 6)
                .transition(.opacity)
                // No parent accessibilityIdentifier — in iOS 26 that overrides
                // every child identifier (log-rest-add15, log-rest-skip,
                // log-rest-time, log-rest-preset-30, …) so the UI tests can't
                // find the chips inside.
                .onAppear { /* TimelineView re-renders trigger checkExpiry */ }
            } else if isFlashing {
                // Brief "DONE" flash after expiry — show 0:00 in the expired
                // style for ~1.2s, then disappear.
                RestTimer(
                    remaining: 0,
                    expired: true,
                    onAdd15: {},
                    onSkip: { restExpiredFlashUntil = nil; clearRest() },
                    onSetDuration: nil
                )
                .padding(.vertical, 6)
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 0)
            }

            // Fire the expiry alert exactly once per rest instance. Side
            // effect lives inside the TimelineView render so it polls every
            // tick (1Hz) without an extra timer.
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: ctx.date) { _, now in
                    maybeFireRestExpiry(at: now)
                }
                .onAppear { maybeFireRestExpiry(at: ctx.date) }
        }
    }

    /// Trigger sound + haptic + visual flash once when the active rest
    /// transitions to zero. Guarded by `restAlertFiredFor` so consecutive
    /// TimelineView re-renders don't replay the alert.
    private func maybeFireRestExpiry(at date: Date) {
        guard let started = restStartedAt,
              let duration = restDuration,
              restAlertFiredFor != started else { return }
        let elapsed = date.timeIntervalSince(started)
        guard elapsed >= Double(duration) else { return }

        restAlertFiredFor = started
        restExpiredFlashUntil = date.addingTimeInterval(1.2)

        // System sound 1322 = "Begin recording" (short, attention-grabbing).
        // Pair with success haptic so the user notices even with the phone
        // silenced or laid screen-down on a bench.
        AudioServicesPlaySystemSound(1322)
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }

    // MARK: - Mutations

    /// Long-press menu hook on a set row. Flips the warmup flag, which is
    /// the single source of truth for the PR / volume / 1RM exclusion path
    /// (see UserDatabase.bestWeightsByExerciseAndReps, MuscleVolume,
    /// StrengthStandards). UI re-renders pick up smaller font + dimmed
    /// opacity + leading "W" pill automatically via the @State binding.
    private func toggleWarmup(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].isWarmup.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Reps-in-reserve (build 103). Wired to the per-set contextMenu Menu.
    /// Stored as a free-text String to match RPE; "0" through "5+" are the
    /// canonical options but the field accepts whatever the user picks.
    private static let rirOptions = ["0", "1", "2", "3", "4", "5+"]

    private func setRIR(exIdx: Int, setIdx: Int, value: String) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].rir = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func toggleSet(exIdx: Int, setIdx: Int) {
        let wasDone = session.exercises[exIdx].sets[setIdx].done
        session.exercises[exIdx].sets[setIdx].done = !wasDone

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if !wasDone {
            // Just marked done. Start rest timer if not the final set.
            //
            // Superset-aware: when this exercise belongs to a superset and
            // there are still un-completed siblings at THIS set index in the
            // group, skip the rest timer — the user is mid-round-robin and
            // should move to the next member's matching set. The rest only
            // fires after the LAST member of the group completes set `setIdx`.
            //
            // Inter-exercise auto-rest: when this is the final set of the
            // exercise (and the superset round is complete) AND there's a
            // next exercise still owed sets, start a rest anchored to this
            // set using the current exercise's rest interval. Lifters
            // expect the same rest window between exercises as between sets,
            // so we don't change the duration on the transition.
            let ex = session.exercises[exIdx]
            let hasMoreSets = setIdx < ex.sets.count - 1

            if isMidSupersetRound(exIdx: exIdx, setIdx: setIdx) {
                // Clear any pending rest from a prior round so the active band
                // moves cleanly to the next group member.
                clearRest()
            } else if hasMoreSets {
                restExIdx = exIdx
                restSetIdx = setIdx
                restStartedAt = Date()
                restDuration = ex.rest
                restAlertFiredFor = nil
                restExpiredFlashUntil = nil
            } else if hasFollowingWork(afterExIdx: exIdx) {
                // Last set of this exercise, but the session has more work
                // ahead — auto-start the rest so the user gets the same
                // countdown + expiry alert between exercises.
                restExIdx = exIdx
                restSetIdx = setIdx
                restStartedAt = Date()
                restDuration = ex.rest
                restAlertFiredFor = nil
                restExpiredFlashUntil = nil
            }
        } else {
            // Untoggled — clear rest if it was anchored to this set.
            if restExIdx == exIdx, restSetIdx == setIdx {
                clearRest()
            }
        }
    }

    /// True when any exercise after `exIdx` in the session still has at least
    /// one un-done set. Used by the inter-exercise auto-rest path so we
    /// don't start a countdown after the very last set of the workout.
    private func hasFollowingWork(afterExIdx exIdx: Int) -> Bool {
        guard exIdx + 1 < session.exercises.count else { return false }
        for ex in session.exercises[(exIdx + 1)...] {
            if ex.sets.contains(where: { !$0.done }) { return true }
        }
        return false
    }

    /// True when this exercise belongs to a superset AND at least one
    /// sibling in the same group still has `set[setIdx]` un-done. Used to
    /// suppress the rest timer mid-round so it only fires after the last
    /// group member completes the round.
    private func isMidSupersetRound(exIdx: Int, setIdx: Int) -> Bool {
        guard session.exercises.indices.contains(exIdx) else { return false }
        guard let group = session.exercises[exIdx].supersetGroup else { return false }
        let siblings = session.exercises.enumerated().filter {
            $0.offset != exIdx && $0.element.supersetGroup == group
        }
        guard !siblings.isEmpty else { return false }
        for (_, sibling) in siblings {
            // A sibling is "still owed this round" when it has a set at
            // this index that's not yet done. Siblings with fewer sets
            // don't gate the rest timer (their round ended earlier).
            if sibling.sets.indices.contains(setIdx), !sibling.sets[setIdx].done {
                return true
            }
        }
        return false
    }

    /// Propagate the most-recent filled weight + reps into any empty set and
    /// mark every set in this exercise done. No haptic / rest side-effects —
    /// callers own those. Set 1 is usually pre-filled, so sets 2-N inherit even
    /// when the user only edited set 1.
    private func markAllSetsDone(exIdx: Int) {
        var sourceWeight: String? = nil
        var sourceReps: String? = nil
        for set in session.exercises[exIdx].sets {
            if !set.weight.isEmpty { sourceWeight = set.weight }
            if !set.reps.isEmpty { sourceReps = set.reps }
        }
        for setIdx in session.exercises[exIdx].sets.indices {
            if session.exercises[exIdx].sets[setIdx].weight.isEmpty, let w = sourceWeight {
                session.exercises[exIdx].sets[setIdx].weight = w
            }
            if session.exercises[exIdx].sets[setIdx].reps.isEmpty, let r = sourceReps {
                session.exercises[exIdx].sets[setIdx].reps = r
            }
            session.exercises[exIdx].sets[setIdx].done = true
        }
    }

    /// Mark every set in this exercise done in one tap. Doesn't start a rest
    /// timer — the bulk-log path means the user already rested at the rack.
    private func logAllSets(exIdx: Int) {
        markAllSetsDone(exIdx: exIdx)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if restExIdx == exIdx { clearRest() }
    }

    /// Whole-workout version of `logAllSets`: mark EVERY set in EVERY exercise
    /// done in one tap, for users who did the whole session at the rack and
    /// just want to record it. Same per-exercise weight/reps propagation; one
    /// haptic; clears any pending rest.
    private func logAllSetsAllExercises() {
        for exIdx in session.exercises.indices { markAllSetsDone(exIdx: exIdx) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        clearRest()
    }

    /// After the user edits a set's weight, copy the new value into any later
    /// sets in the same exercise that are still empty or still matched the
    /// previous value. Lets straight-sets users type once into set 1 and have
    /// 2-N fill in; pyramid users can still overwrite any later row by tapping
    /// into it (their edit propagates forward from there, or stops if the
    /// downstream sets have already been customized).
    private func propagateWeight(exIdx: Int, fromSetIdx: Int, oldValue: String, newValue: String) {
        let count = session.exercises[exIdx].sets.count
        guard fromSetIdx + 1 < count else { return }
        for i in (fromSetIdx + 1)..<count {
            let target = session.exercises[exIdx].sets[i]
            if target.done { continue }
            if target.weight.isEmpty || target.weight == oldValue {
                session.exercises[exIdx].sets[i].weight = newValue
            }
        }
    }

    private func addSet(exIdx: Int) {
        let ex = session.exercises[exIdx]
        let lastSet = ex.sets.last
        let newSet = LoggedSet(
            num: ex.sets.count + 1,
            weight: lastSet?.weight ?? "",
            reps: lastSet?.reps ?? String(ex.targetReps),
            rpe: "",
            done: false
        )
        session.exercises[exIdx].sets.append(newSet)
    }

    /// Remove a logged set and renumber the remaining rows. If this set
    /// anchored the active rest card, clear the rest too.
    private func deleteSet(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        // If the rest card was anchored to this set, clear it.
        if restExIdx == exIdx, restSetIdx == setIdx {
            clearRest()
        } else if restExIdx == exIdx, let r = restSetIdx, r > setIdx {
            // Anchor sits below the deleted row — shift it up by one so it
            // stays attached to the same logical set.
            restSetIdx = r - 1
        }
        session.exercises[exIdx].sets.remove(at: setIdx)
        // Renumber. LoggedSet.num is 1-indexed and otherwise diverges from
        // its row position after deletes.
        for i in session.exercises[exIdx].sets.indices {
            session.exercises[exIdx].sets[i].num = i + 1
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// "Re-open" a set the user marked done so they can edit weight / reps /
    /// effort. We don't expose this as a hard-delete button on the row
    /// because un-toggling preserves the previously-entered values, which is
    /// what the user usually wants (e.g. they hit Done before adding RPE).
    private func reopenSet(exIdx: Int, setIdx: Int) {
        guard session.exercises.indices.contains(exIdx),
              session.exercises[exIdx].sets.indices.contains(setIdx) else { return }
        session.exercises[exIdx].sets[setIdx].done = false
        // Clear the rest if it was anchored to this row, otherwise we end up
        // with an active rest pointing at an un-done set.
        if restExIdx == exIdx, restSetIdx == setIdx { clearRest() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Append a freshly picked exercise to the active session. Mirrors the
    /// "new exercise" branch in SessionStore.applyWorkoutDiffToActiveSession:
    /// 3 sets × 8 reps × 90s rest, no prevSets, no supersetGroup.
    private func appendExerciseFromPicker(_ picked: Exercise) {
        let target = 3
        let reps = 8
        let sets = (0..<target).map { i in
            LoggedSet(num: i + 1, weight: "", reps: "", rpe: "", done: false)
        }
        let newEx = LoggedExercise(
            id: "ad-hoc-\(UUID().uuidString.prefix(8))",
            name: picked.name,
            type: picked.modalityLabel,
            unit: "lbs",
            targetSets: target,
            targetReps: reps,
            rest: 90,
            sets: sets,
            prevSets: [],
            rpe: nil,
            tempo: nil,
            supersetGroup: nil
        )
        session.exercises.append(newEx)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func clearRest() {
        restExIdx = nil
        restSetIdx = nil
        restStartedAt = nil
        restDuration = nil
        restAlertFiredFor = nil
        restExpiredFlashUntil = nil
    }

    private func currentRestRemaining(at date: Date) -> Int? {
        guard let started = restStartedAt, let duration = restDuration else { return nil }
        let elapsed = Int(date.timeIntervalSince(started))
        let r = duration - elapsed
        return r > 0 ? r : nil
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let existing = store.active {
            session = existing
        } else {
            let fresh = store.createSession(templateId: "upper-1")
            session = fresh
            store.saveActive(fresh)
        }
        // UI-test hook: --ui-test-rest-seconds=N clamps every exercise's rest
        // so timer-expiry tests can fire in ~2s instead of 60-90s. Has no
        // effect outside test runs.
        if let s = Self.uiTestRestOverride {
            for i in session.exercises.indices {
                session.exercises[i].rest = s
            }
        }
        didLoad = true
    }

    private static let uiTestRestOverride: Int? = {
        let prefix = "--ui-test-rest-seconds="
        guard let arg = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix(prefix)
        }) else { return nil }
        return Int(arg.dropFirst(prefix.count))
    }()

    // MARK: - Formatters

    static func fmtTime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func fmtElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    // MARK: - Placeholder

    private static let placeholder = ActiveSession(
        templateId: "",
        name: "",
        category: "",
        startTime: Date(),
        exercises: [],
        feel: nil,
        note: nil
    )
}

/// Identifiable wrapper so `.sheet(item:)` can bind to `swappingExIdx`.
private struct LogRowIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

#Preview {
    let store = SessionStore(defaults: UserDefaults(suiteName: "preview.log")!)
    _ = {
        UserDefaults(suiteName: "preview.log")!.removePersistentDomain(forName: "preview.log")
    }()
    return LogScreen(onFinish: {})
        .environmentObject(store)
}

#Preview("Supersets") {
    // Mock superset session: A1 (Bench) + A2 (DB Row) form group 1,
    // then a solo squat in between, then B1 (Curl) + B2 (Pushdown) form
    // group 2. Demonstrates the band, the A1/A2/B1/B2 labels, the
    // round-robin reorder (group 2 anchored at its first appearance).
    let suite = "preview.log.supersets"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SessionStore(defaults: defaults)
    let mock = ActiveSession(
        templateId: "mock-superset",
        name: "Upper · superset preview",
        category: "Demo",
        startTime: Date().addingTimeInterval(-12 * 60),
        exercises: [
            LoggedExercise(
                id: "bench", name: "Bench Press", type: "Barbell", unit: "lbs",
                targetSets: 3, targetReps: 8, rest: 90,
                sets: [
                    LoggedSet(num: 1, weight: "135", reps: "8", rpe: "7", done: true),
                    LoggedSet(num: 2, weight: "135", reps: "8", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "135", reps: "8", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 1
            ),
            LoggedExercise(
                id: "row", name: "DB Row", type: "Dumbbell", unit: "lbs",
                targetSets: 3, targetReps: 10, rest: 90,
                sets: [
                    LoggedSet(num: 1, weight: "55", reps: "10", rpe: "7", done: true),
                    LoggedSet(num: 2, weight: "55", reps: "10", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "55", reps: "10", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 1
            ),
            LoggedExercise(
                id: "squat", name: "Back Squat", type: "Barbell", unit: "lbs",
                targetSets: 3, targetReps: 5, rest: 180,
                sets: [
                    LoggedSet(num: 1, weight: "225", reps: "5", rpe: "8", done: false),
                    LoggedSet(num: 2, weight: "225", reps: "5", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "225", reps: "5", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: nil
            ),
            LoggedExercise(
                id: "curl", name: "Cable Curl", type: "Cable", unit: "lbs",
                targetSets: 3, targetReps: 12, rest: 60,
                sets: [
                    LoggedSet(num: 1, weight: "40", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 2, weight: "40", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "40", reps: "12", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 2
            ),
            LoggedExercise(
                id: "pushdown", name: "Tricep Pushdown", type: "Cable", unit: "lbs",
                targetSets: 3, targetReps: 12, rest: 60,
                sets: [
                    LoggedSet(num: 1, weight: "50", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 2, weight: "50", reps: "12", rpe: "", done: false),
                    LoggedSet(num: 3, weight: "50", reps: "12", rpe: "", done: false),
                ],
                prevSets: [],
                supersetGroup: 2
            ),
        ],
        feel: nil,
        note: nil
    )
    store.saveActive(mock)
    return LogScreen(onFinish: {})
        .environmentObject(store)
}
