// StartScreen.swift — Session start screen.
// Port of handoff/proto/start.jsx + handoff/hd-session-start.jsx.
// Shows today's workout (hardcoded upper-1), last-session summary, exercise
// preview, and the primary "Start workout" CTA + secondary "History" button.

import SwiftUI

struct StartScreen: View {
    @EnvironmentObject var store: SessionStore

    let onStart: () -> Void
    let onHistory: () -> Void
    var onBrowseRoutines: (() -> Void)? = nil

    private var template: WorkoutTemplate {
        if let active = store.active, !active.exercises.isEmpty {
            return WorkoutTemplate(
                id: active.templateId,
                name: active.name,
                category: active.category,
                exercises: active.exercises.map { ex in
                    ExerciseTemplate(
                        id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
                        targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest
                    )
                }
            )
        }
        return WorkoutTemplate.upper1
    }

    // MARK: - Derived

    private var totalSets: Int {
        template.exercises.reduce(0) { $0 + $1.targetSets }
    }

    private var previous: SavedSession? {
        store.getPreviousSession(templateId: template.id)
    }

    /// Match JSX hard-wrap "Upper Body\nDay 1".
    private var heroTitle: String {
        template.name.replacingOccurrences(of: " Day ", with: "\nDay ")
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var daysAgoShort: String {
        guard let prev = previous else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: prev.startTime, to: Date()).day ?? 0
        return "\(days)d ago"
    }

    private var lastSessionDetail: String {
        guard let prev = previous else { return "First time — weights will be empty" }
        let stats = computeStats(prev)
        return "\(formatDuration(prev.duration)) · \(stats.doneSets) sets · avg rpe \(stats.avgRpe)"
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
                        lastSessionCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        exerciseList
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        Spacer().frame(height: 160)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Bottom CTA stack
            VStack(spacing: 10) {
                startButton
                HStack(spacing: 10) {
                    if onBrowseRoutines != nil {
                        browseButton
                    }
                    historyButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(Color.ink)
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(dateLabel)
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text("~45 MIN · \(template.exercises.count) EX · \(totalSets) SETS")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
                .padding(.top, 8)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heroTitle)
                .styled(.displayL)
                .foregroundStyle(Color.ink)
                .lineSpacing(-2) // tight per JSX line-height:1
                .fixedSize(horizontal: false, vertical: true)
            Text(template.category)
                .styled(.body)
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Last session card

    private var lastSessionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("LAST SESSION")
                    .styled(.micro)
                    .foregroundStyle(Color.ink3)
                Spacer()
                Text(daysAgoShort)
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Text(lastSessionDetail)
                .font(.monoXS)
                .foregroundStyle(Color.ink2)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Exercise list

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S EXERCISES")
                .styled(.micro)
                .foregroundStyle(Color.ink3)
                .padding(.bottom, 8)

            ForEach(Array(template.exercises.enumerated()), id: \.element.id) { idx, ex in
                exerciseRow(index: idx, ex: ex)
                if idx < template.exercises.count - 1 {
                    Rectangle()
                        .fill(Color.lineSoft)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private func exerciseRow(index: Int, ex: ExerciseTemplate) -> some View {
        let prevEx = previous?.exercises.first(where: { $0.id == ex.id })
        let prevW = prevEx?.sets.first?.weight ?? ""
        let middle = prevW.isEmpty ? "no prev" : "\(prevW) \(ex.unit)"
        return HStack(alignment: .center, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(.monoXS)
                .foregroundStyle(Color.ink3)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ex.name)
                        .styled(.displayS)
                        .foregroundStyle(Color.ink)
                    if let t = ex.type {
                        Text("(\(t))")
                            .font(.monoXS)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Text("\(ex.targetSets) sets · \(middle) · \(ex.targetReps) reps")
                    .font(.monoXS)
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }

    // MARK: - Buttons

    private var startButton: some View {
        Button(action: onStart) {
            HStack(spacing: 6) {
                Text(store.active == nil ? "Start workout" : "Resume workout")
                    .font(.custom("SpaceGrotesk-SemiBold", size: 15))
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var historyButton: some View {
        Button(action: onHistory) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .medium))
                Text("HISTORY")
                    .styled(.micro)
            }
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var browseButton: some View {
        Button(action: { onBrowseRoutines?() }) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12, weight: .medium))
                Text("ROUTINES")
                    .styled(.micro)
            }
            .foregroundStyle(Color.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.line, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Computes done-set count + 1-decimal avg RPE for a SavedSession.
    /// Mirrors `SessionStore.stats(for:)` but operates on the saved shape.
    private func computeStats(_ session: SavedSession) -> (doneSets: Int, avgRpe: String) {
        var doneSets = 0
        var totalRpe: Double = 0
        var rpeCount = 0
        for ex in session.exercises {
            for s in ex.sets where s.done {
                doneSets += 1
                if !s.rpe.isEmpty, let v = Double(s.rpe), !v.isNaN {
                    totalRpe += v
                    rpeCount += 1
                }
            }
        }
        let avgRpe = rpeCount > 0 ? String(format: "%.1f", totalRpe / Double(rpeCount)) : "—"
        return (doneSets, avgRpe)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview

#Preview("Empty history") {
    StartScreen(onStart: {}, onHistory: {})
        .environmentObject(SessionStore(defaults: UserDefaults(suiteName: "StartScreen.preview.empty")!))
}

#Preview("With previous session") {
    let suite = "StartScreen.preview.populated"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SessionStore(defaults: defaults)

    // Seed a previous session four days ago.
    let prevExercises = WorkoutTemplate.upper1.exercises.map { ex in
        LoggedExercise(
            id: ex.id, name: ex.name, type: ex.type, unit: ex.unit,
            targetSets: ex.targetSets, targetReps: ex.targetReps, rest: ex.rest,
            sets: (0..<ex.targetSets).map { i in
                LoggedSet(num: i + 1, weight: "135", reps: String(ex.targetReps), rpe: "7", done: true)
            },
            prevSets: []
        )
    }
    let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
    let saved = SavedSession(
        templateId: "upper-1",
        name: "Upper Body Day 1",
        category: "Push / Pull / Accessories",
        startTime: fourDaysAgo,
        exercises: prevExercises,
        feel: "Right",
        note: nil,
        endTime: fourDaysAgo.addingTimeInterval(2528),
        duration: 2528
    )
    store.saveAll([saved])

    return StartScreen(onStart: {}, onHistory: {})
        .environmentObject(store)
}
