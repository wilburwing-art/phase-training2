// LogSetRow.swift — Per-set row + input cells for LogScreen.
//
// Extracted from LogScreen.swift (Tier 3 split). All views here are
// extensions of LogScreen so the nested bindings into
// `session.exercises[exIdx].sets[setIdx]` stay on the owning `@State` —
// auto-save rides `onChange(of: session)` in LogScreen.body unchanged.

import SwiftUI
import UIKit

extension LogScreen {
    // MARK: - Set row

    @ViewBuilder
    func setRow(exIdx: Int, setIdx: Int, isActive: Bool) -> some View {
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
                        .font(.system(size: warmupPillFont, weight: .bold))
                        .foregroundStyle(Color.bg)
                        .frame(width: warmupPillWidth, height: warmupPillHeight)
                        .background(Color.ink3)
                        .clipShape(Capsule())
                        .frame(width: setNumWidth, alignment: .center)
                        .accessibilityLabel("Warmup set")
                } else {
                    Text("\(set.num)")
                        .styled(.monoXS)
                        .foregroundStyle(setNumberColor)
                        .frame(width: setNumWidth, alignment: .center)
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
                    .frame(width: labelWidth, alignment: .leading)

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
                .accessibilityLabel("Reps, set \(setIdx + 1)")

                effortCell(
                    text: $session.exercises[exIdx].sets[setIdx].rpe,
                    done: set.done,
                    active: isActive
                )
                .frame(width: effortWidth)

                checkDot(done: set.done) {
                    toggleSet(exIdx: exIdx, setIdx: setIdx)
                }
                // 44 to match the button's own hit area (see checkDot). The
                // dot still DRAWS at 22.
                .frame(width: 44)
                .accessibilityIdentifier("log-set-check-\(exIdx)-\(setIdx)")
                .accessibilityLabel(set.done
                                    ? "Set \(setIdx + 1) done, tap to undo"
                                    : "Complete set \(setIdx + 1)")
            }
        }
        .padding(.vertical, 6)
        // Warmup sets dim slightly so the working sets read as the primary
        // content — the "W" pill carries the distinction, so keep the dim
        // light enough that weight/reps stay readable mid-workout.
        // Toggle via the contextMenu below.
        .font(.callout)
        .opacity(set.isWarmup ? 0.85 : 1.0)
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
            // Label only. A TextField already exposes its text as the
            // accessibility value; overriding it with "135 lbs" changed what
            // XCUITest reads back through `.value` and broke two LogFlowTests
            // that assert the raw "135". The unit goes in the label instead.
            .accessibilityLabel("Weight in \(session.exercises[exIdx].unit), set \(setIdx + 1)")
            .onChange(of: session.exercises[exIdx].sets[setIdx].weight) { oldValue, newValue in
                // Debounce per cell: fill downstream sets only once typing
                // pauses, so partial values (1, 13, 135) don't briefly land in
                // later sets. Capture the pre-burst oldValue on the first change.
                let key = "\(exIdx)-\(setIdx)"
                if weightPropagateTasks[key] == nil { weightPropagateOld[key] = oldValue }
                weightPropagateTasks[key]?.cancel()
                weightPropagateTasks[key] = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    if Task.isCancelled { return }
                    propagateWeight(exIdx: exIdx, fromSetIdx: setIdx,
                                    oldValue: weightPropagateOld[key] ?? oldValue,
                                    newValue: newValue)
                    weightPropagateTasks[key] = nil
                    weightPropagateOld[key] = nil
                }
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

    /// Reps-in-reserve (build 103). Wired to the per-set contextMenu Menu.
    /// Stored as a free-text String to match RPE; "0" through "5+" are the
    /// canonical options but the field accepts whatever the user picks.
    private static let rirOptions = ["0", "1", "2", "3", "4", "5+"]

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
            // VoiceOver: this is a Menu, so without a label it reads its
            // current text ("—") and nothing else.
            .accessibilityLabel("Effort")
            .accessibilityValue(text.wrappedValue.isEmpty ? "not set" : "RPE \(text.wrappedValue)")
        }
    }

    private func checkDot(done: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            // The dot DRAWS at 22. The surrounding 44x44 contentShape is the
            // tappable area: this is the most-tapped control in the app and it
            // was a 22pt target against Apple's 44pt minimum, one-handed, in a
            // gym. Inside the label so the hit region is the padded box rather
            // than the glyph.
            ZStack {
                if done {
                    Circle().fill(Color.ok)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.bg)
                } else {
                    Circle().strokeBorder(Color.line, lineWidth: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        // .borderless instead of .plain. Visually identical here (the label
        // is a Circle with an explicit fill, not a tinted system image), but
        // iOS 26 XCUITest synthesized taps do not fire .plain Button actions
        // when the label is < ~44pt — they DO fire .borderless. That broke
        // every rest-card-after-set-done UI test (the 22pt check dot tap
        // synthesized cleanly but never flipped done, so no rest card ever
        // rendered for the test to assert against). The label is 44 now, but
        // .borderless stays: no reason to re-test that interaction.
        .buttonStyle(.borderless)
    }
}
