// LogExerciseBlock.swift — Per-exercise block for LogScreen.
//
// Extracted from LogScreen.swift (Tier 3 split). Header row (thumbnail, name,
// swap button, detail tap/contextMenu), coaching hints, progression pill,
// column headers, set-row list with rest dividers + active rest card,
// "+ Add Set" / "Log all sets" buttons, and the superset accent band.
// All extensions of LogScreen so state access stays direct.

import SwiftUI

extension LogScreen {
    // MARK: - Exercise block

    @ViewBuilder
    func exerciseBlock(exIdx: Int, grouping: SupersetGroupedItem<LoggedExercise>? = nil) -> some View {
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
                if rest.exIdx == exIdx, rest.setIdx == setIdx {
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
}
