// HistoryScreen.swift — Past sessions list with expand/collapse accordion.
// Ports `handoff/proto/history.jsx` + `handoff/hd-history.jsx` to SwiftUI.

import SwiftUI

struct HistoryScreen: View {
    @EnvironmentObject var store: SessionStore
    /// Build 92: now presented as a sheet from the Progress tab's "See
    /// all" link, not pushed from TodayTab. Uses Environment dismiss so
    /// it works in any presentation context.
    @Environment(\.dismiss) private var dismiss

    @State private var expanded: Set<TimeInterval> = []
    @State private var editingSession: SavedSession?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle()
                .fill(Color.line)
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if store.savedSessions.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .sheet(item: $editingSession) { session in
            EditSessionSheet(session: session)
                .environmentObject(store)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text("History")
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
        let n = store.savedSessions.count
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Past sessions")
                    .styled(.displayM)
                    .foregroundColor(.ink)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                summaryStrip
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Rectangle()
                    .fill(Color.line)
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(Array(store.savedSessions.enumerated()), id: \.element.id) { idx, session in
                        sessionRow(
                            session: session,
                            isLast: idx == store.savedSessions.count - 1
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 40)
            }
        }
    }

    // MARK: - Summary strip (sessions / total sets / avg RPE)

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            statCard(value: "\(store.savedSessions.count)", label: "SESSIONS")
            statCard(value: "\(totalDoneSetsAllSessions)", label: "TOTAL SETS")
            statCard(value: avgRpeAllSessions, label: "AVG RPE")
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.custom("SpaceGrotesk-SemiBold", size: 20))
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
        store.savedSessions.reduce(0) { acc, sess in
            acc + sess.exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count }
        }
    }

    private var avgRpeAllSessions: String {
        // Per-session avg of done-set RPEs, then average across sessions.
        let perSessionAvgs: [Double] = store.savedSessions.compactMap { sess in
            let rpes: [Double] = sess.exercises.flatMap { ex in
                ex.sets.compactMap { s in
                    guard s.done, !s.rpe.isEmpty, let v = Double(s.rpe) else { return nil }
                    return v
                }
            }
            guard !rpes.isEmpty else { return nil }
            return rpes.reduce(0, +) / Double(rpes.count)
        }
        guard !perSessionAvgs.isEmpty else { return "—" }
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
                            Text(durationLabel(session.duration))
                                .styled(.monoS)
                                .foregroundColor(.ink3)
                            dot
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

            if isExpanded {
                expandedDetail(session)
                    .padding(.top, 10)
                Button(action: { editingSession = session }) {
                    Text("Edit session")
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
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.lineSoft).frame(height: 0.5)
            }
        }
    }

    private var dot: some View {
        Text("·")
            .styled(.body)
            .foregroundColor(.ink3)
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
        let doneSets = ex.sets.filter { $0.done && !$0.weight.isEmpty }
        // `pr` flag is not present on LoggedExercise/LoggedSet today; skip badge.
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(ex.name)
                    .font(.custom("SpaceGrotesk-SemiBold", size: 13))
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
        guard !sets.isEmpty else { return "—" }
        return sets.map { s in
            let core = "\(s.weight) × \(s.reps)"
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
        return loStr == hiStr ? "rpe \(loStr)" : "rpe \(loStr)–\(hiStr)"
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
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count }
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
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let minutes = max(0, seconds / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
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
        .preferredColorScheme(.dark)
}
