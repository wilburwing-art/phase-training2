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
    }

    // MARK: - Body content

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

                    ForEach(Array(session.exercises.enumerated()), id: \.element.id) { exIdx, _ in
                        exerciseBlock(exIdx: exIdx)
                        if exIdx < session.exercises.count - 1 {
                            Rectangle()
                                .fill(Color.line)
                                .frame(height: 0.5)
                                .padding(.horizontal, 20)
                        }
                    }
                    Color.clear.frame(height: 40)
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
    private func exerciseBlock(exIdx: Int) -> some View {
        let ex = session.exercises[exIdx]
        let firstUndone = ex.sets.firstIndex { !$0.done }
        let allDone = ex.sets.allSatisfy { $0.done }

        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 6) {
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
                Text(ex.name)
                    .styled(.displayS)
                    .foregroundStyle(allDone ? Color.ink2 : Color.ink)
                if let type = ex.type, !type.isEmpty {
                    Text("(\(type))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // Column headers
            columnHeaders(unit: ex.unit)

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
        }
        .padding(.horizontal, 20)
    }

    private func columnHeaders(unit: String) -> some View {
        HStack(spacing: 4) {
            headerLabel("SET").frame(width: 22)
            headerLabel("PREV", align: .leading).frame(width: 58)
            headerLabel((unit.isEmpty ? "lbs" : unit).uppercased()).frame(maxWidth: .infinity)
            headerLabel("REPS").frame(maxWidth: .infinity)
            headerLabel("RPE").frame(width: 34)
            Color.clear.frame(width: 24)
        }
        .padding(.bottom, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 0.5)
        }
    }

    private func headerLabel(_ text: String, align: TextAlignment = .center) -> some View {
        Text(text)
            .styled(.micro)
            .foregroundStyle(Color.ink3)
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
                Text("\(set.num)")
                    .styled(.monoXS)
                    .foregroundStyle(setNumberColor)
                    .frame(width: 22, alignment: .center)
                    .monospacedDigit()

                Text(prevLabel)
                    .styled(.monoXS)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .leading)

                numCell(
                    text: $session.exercises[exIdx].sets[setIdx].weight,
                    placeholder: "—",
                    done: set.done,
                    active: isActive
                )
                .frame(maxWidth: .infinity)

                numCell(
                    text: $session.exercises[exIdx].sets[setIdx].reps,
                    placeholder: "—",
                    done: set.done,
                    active: isActive
                )
                .frame(maxWidth: .infinity)

                numCell(
                    text: $session.exercises[exIdx].sets[setIdx].rpe,
                    placeholder: "—",
                    done: set.done,
                    active: isActive
                )
                .frame(width: 34)

                checkDot(done: set.done) {
                    toggleSet(exIdx: exIdx, setIdx: setIdx)
                }
                .frame(width: 24)
            }
        }
        .padding(.vertical, 6)
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
        .buttonStyle(.plain)
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
            if let r = remaining, r > 0 {
                RestTimer(
                    remaining: r,
                    onAdd15: { restDuration = (restDuration ?? 0) + 15 },
                    onSkip: { clearRest() }
                )
                .padding(.vertical, 6)
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 0)
            }
        }
    }

    // MARK: - Mutations

    private func toggleSet(exIdx: Int, setIdx: Int) {
        let wasDone = session.exercises[exIdx].sets[setIdx].done
        session.exercises[exIdx].sets[setIdx].done = !wasDone

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if !wasDone {
            // Just marked done. Start rest timer if not the final set.
            let ex = session.exercises[exIdx]
            let hasMoreSets = setIdx < ex.sets.count - 1
            if hasMoreSets {
                restExIdx = exIdx
                restSetIdx = setIdx
                restStartedAt = Date()
                restDuration = ex.rest
            }
        } else {
            // Untoggled — clear rest if it was anchored to this set.
            if restExIdx == exIdx, restSetIdx == setIdx {
                clearRest()
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

    private func clearRest() {
        restExIdx = nil
        restSetIdx = nil
        restStartedAt = nil
        restDuration = nil
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
        didLoad = true
    }

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

#Preview {
    let store = SessionStore(defaults: UserDefaults(suiteName: "preview.log")!)
    _ = {
        UserDefaults(suiteName: "preview.log")!.removePersistentDomain(forName: "preview.log")
    }()
    return LogScreen(onFinish: {})
        .environmentObject(store)
}
