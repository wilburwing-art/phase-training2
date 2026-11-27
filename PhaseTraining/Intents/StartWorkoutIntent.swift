import AppIntents
import Combine
import Foundation

/// "Start today's workout" from Siri or Shortcuts (11c 7.1). Opens the app on
/// Today and, on an unlogged lift day, starts the workout Today shows.
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start today's workout"
    static var description = IntentDescription("Opens Today and starts the planned workout.")
    static var openAppWhenRun = true
    static var isDiscoverable = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sessions = ActiveWorkoutRegistry.shared.store
        let snapshot = StartWorkoutLaunch.todaySnapshot(
            planStore: StartWorkoutLaunch.planStore,
            sessions: sessions?.savedSessions ?? [],
            stored: { TodayWidgetSnapshot.load(from: UserDefaults(suiteName: TodayWidgetSnapshot.appGroup)) })
        let line = StartWorkoutLaunch.shared.request(
            snapshot: snapshot,
            hasActiveWorkout: sessions?.active != nil,
            onboarded: BodyWeightIntentActions.store?.isOnboarded ?? false)
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

/// Hands the intent's request to the app. `showToday` goes up on every run and
/// the tab shell takes it to switch to Today. `pending` goes up when the
/// workout should start or resume: `TodayScreen` takes it once its template is
/// there, or the shell takes it when a workout is already running (TodayTab
/// routes to the log by itself). Both stay up until taken, so a cold launch
/// from Siri still lands. `pending` lapses after `pendingLifetime`, so a
/// request Today could not serve (no template yet) cannot start a workout
/// hours later, after a plan change or past midnight.
@MainActor
final class StartWorkoutLaunch: ObservableObject {
    static let shared = StartWorkoutLaunch()

    @Published private(set) var pending = false
    @Published private(set) var showToday = false
    private var requestedAt: Date?
    static let pendingLifetime: TimeInterval = 10 * 60

    static let resumingLine = "Resuming your workout."
    static let openingTodayLine = "Opening Today."
    static let alreadyLoggedLine = "Today's workout is already logged."
    static let restDayLine = "Today is a rest day."
    static let notOnboardedLine = BodyWeightIntentActions.notOnboardedLine
    static func startingLine(_ title: String) -> String { "Starting \(title)." }
    static func todayIsLine(_ title: String) -> String { "Today is \(title)." }

    /// The app's live `PlanStore`. Set in `PhaseTrainingApp.init`, before any
    /// view, so the intent names the workout Today starts (11c 7.3).
    static var planStore: PlanStore?

    init() {}

    /// Today as the app sees it now. With a live plan store this is built from
    /// the plan `TodayScreen` starts from, so the line cannot name a workout
    /// the widget snapshot still holds after a plan change. The App Group
    /// snapshot is read only when no store is registered.
    static func todaySnapshot(planStore: PlanStore?, sessions: [SavedSession],
                              stored: () -> TodayWidgetSnapshot?,
                              calendar: Calendar = .current) -> TodayWidgetSnapshot? {
        guard let planStore else { return stored() }
        return TodayWidgetPublisher.snapshot(planStore: planStore, sessions: sessions, calendar: calendar)
    }

    /// Decides what the run does from today's widget snapshot, raises the
    /// flags, and returns what Siri says.
    func request(snapshot: TodayWidgetSnapshot?, hasActiveWorkout: Bool, onboarded: Bool,
                 now: Date = Date(), calendar: Calendar = .current) -> String {
        showToday = true
        if hasActiveWorkout {
            raisePending(at: now)
            return Self.resumingLine
        }
        // Before onboarding Today falls back to a stock template behind the
        // onboarding cover; starting it would be a workout nobody asked for.
        guard onboarded else { return Self.notOnboardedLine }
        guard let day = snapshot?.day(on: now, calendar: calendar) else {
            raisePending(at: now)
            return Self.openingTodayLine
        }
        switch day.kind {
        case .lift:
            guard !day.done else { return Self.alreadyLoggedLine }
            raisePending(at: now)
            return Self.startingLine(day.title)
        case .rest:
            return Self.restDayLine
        case .sport, .event:
            return Self.todayIsLine(day.title)
        }
    }

    private func raisePending(at now: Date) {
        requestedAt = now
        pending = true
    }

    /// Today or the shell calls this when it starts or resumes the workout.
    /// False, and the flag drops, once the request is older than `pendingLifetime`.
    func consume(now: Date = Date()) -> Bool {
        guard pending else { return false }
        pending = false
        guard let at = requestedAt else { return false }
        requestedAt = nil
        return now.timeIntervalSince(at) <= Self.pendingLifetime
    }

    /// The shell calls this when it switches to Today.
    func consumeShowToday() -> Bool {
        guard showToday else { return false }
        showToday = false
        return true
    }
}
