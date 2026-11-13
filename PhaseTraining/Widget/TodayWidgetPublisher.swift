// TodayWidgetPublisher.swift: writes the week's plan to the App Group for the
// Today widget and reloads its timeline when the snapshot changes.
//
// Split in two like RestActivityCoordinator: a pure `snapshot` function and
// a class that watches the stores.

import Combine
import Foundation
import WidgetKit

final class TodayWidgetPublisher {
    private let defaults: UserDefaults?
    private let reload: () -> Void
    private let calendar: Calendar
    private var cancellables = Set<AnyCancellable>()

    /// The last value written. `published` separates "nothing written yet"
    /// from "a nil snapshot was written", so the first publish always runs
    /// and clears a snapshot left by an earlier process.
    private var published = false
    private var lastWritten: TodayWidgetSnapshot?

    init(planStore: PlanStore,
         store: SessionStore,
         defaults: UserDefaults? = UserDefaults(suiteName: TodayWidgetSnapshot.appGroup),
         calendar: Calendar = .current,
         reload: @escaping () -> Void = {
             WidgetCenter.shared.reloadTimelines(ofKind: TodayWidgetSnapshot.widgetKind)
         }) {
        self.defaults = defaults
        self.calendar = calendar
        self.reload = reload

        publish(plan: planStore.plan,
                sessions: store.savedSessions,
                abandoned: planStore.abandonedWorkouts)

        // `@Published` fires in willSet, so each sink reads its new value from
        // the argument and the other two from the last value it delivered.
        var plan = planStore.plan
        var sessions = store.savedSessions
        var abandoned = planStore.abandonedWorkouts
        planStore.$plan
            .dropFirst()
            .sink { [weak self] in
                plan = $0
                self?.publish(plan: plan, sessions: sessions, abandoned: abandoned)
            }
            .store(in: &cancellables)
        store.$savedSessions
            .dropFirst()
            .sink { [weak self] in
                sessions = $0
                self?.publish(plan: plan, sessions: sessions, abandoned: abandoned)
            }
            .store(in: &cancellables)
        planStore.$abandonedWorkouts
            .dropFirst()
            .sink { [weak self] in
                abandoned = $0
                self?.publish(plan: plan, sessions: sessions, abandoned: abandoned)
            }
            .store(in: &cancellables)
    }

    private func publish(plan: WeekPlan?, sessions: [SavedSession], abandoned: [AbandonedWorkoutEntry]) {
        let next = Self.snapshot(plan: plan,
                                 completedDays: Self.completedDays(plan: plan, sessions: sessions,
                                                                   abandoned: abandoned, calendar: calendar),
                                 calendar: calendar)
        if published && next == lastWritten { return }
        published = true
        lastWritten = next
        if let next {
            next.save(to: defaults)
        } else {
            defaults?.removeObject(forKey: TodayWidgetSnapshot.defaultsKey)
        }
        reload()
    }

    // MARK: - Pure

    /// Start of day of each day in the plan's week with a completed session.
    /// An abandoned entry cancels one session on its day, so a day with a
    /// full session and a stopped-early one still counts.
    static func completedDays(plan: WeekPlan?,
                              sessions: [SavedSession],
                              abandoned: [AbandonedWorkoutEntry],
                              calendar: Calendar) -> Set<Date> {
        guard let plan, let first = plan.days.first?.date else { return [] }
        let weekStart = calendar.startOfDay(for: first)
        var sessionCounts: [Date: Int] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.startTime)
            if day >= weekStart { sessionCounts[day, default: 0] += 1 }
        }
        for a in abandoned {
            let day = calendar.startOfDay(for: a.date)
            if let n = sessionCounts[day] { sessionCounts[day] = n - 1 }
        }
        return Set(sessionCounts.filter { $0.value > 0 }.keys)
    }

    static func snapshot(plan: WeekPlan?,
                         completedDays: Set<Date>,
                         calendar: Calendar) -> TodayWidgetSnapshot? {
        guard let plan else { return nil }
        let days = plan.days.map { day -> TodayWidgetDay in
            let start = calendar.startOfDay(for: day.date)
            let title: String
            let detail: String?
            let kind: TodayWidgetDay.Kind
            switch day.kind {
            case .lift:
                kind = .lift
                let template = day.workoutTemplate
                title = template?.name ?? day.title
                detail = template.map { t in
                    let sets = t.exercises.reduce(0) { $0 + $1.targetSets }
                    return "\(t.exercises.count) exercises · \(sets) sets"
                }
            case .sport:
                kind = .sport
                title = day.sport?.name ?? "Sport day"
                detail = day.durationMinutes.map { "About \($0) min" }
            case .rest:
                kind = .rest
                title = "Rest day"
                detail = nil
            case .event:
                kind = .event
                title = day.title.isEmpty ? "Event day" : day.title
                detail = nil
            }
            return TodayWidgetDay(date: start, kind: kind, title: title, detail: detail,
                                  done: day.kind != .rest && completedDays.contains(start))
        }
        return TodayWidgetSnapshot(days: days)
    }
}
