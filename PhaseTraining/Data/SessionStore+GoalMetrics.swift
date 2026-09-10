// SessionStore+GoalMetrics.swift — PR 11 (commit 4).
//
// The goal-progress inputs (best e1RM per exercise, fastest annotated 5k,
// climb-day count) shared by two consumers:
//   - ProgressScreen+GoalCards (the GOALS card)
//   - CompleteScreen's milestone hook (GoalMilestoneNotifier)
//
// An extension on SessionStore because both screens already hold it as an
// EnvironmentObject. Sport-log data arrives as a parameter, not a store
// reference: SessionStore deliberately stays one/two-arg constructible for
// tests + previews (the same seam pattern PlanStore uses), and the sport
// log is optional context — nil entries simply yield nil 5k / zero climbs.

import Foundation

extension SessionStore {

    /// Best epley-1RM per lowercased exercise name over ALL saved sessions.
    /// Same epley formula the generator context uses for priorBest, but an
    /// independent walk (this one covers full history, not the 4-week
    /// window) and a per-session best (not per-set max across sessions —
    /// identical result, but keeps the loop shape the same as the card's
    /// original implementation).
    func bestE1RMByExercise() -> [String: Double] {
        var best: [String: Double] = [:]
        for s in savedSessions {
            for ex in s.exercises {
                var best1RM = 0.0
                for set in ex.sets where set.done && !set.isWarmup {
                    guard let w = set.weightValue, let r = set.repsValue,
                          w > 0, r > 0 else { continue }
                    let e = StrengthStandards.epley1RM(weight: w, reps: r)
                    best1RM = max(best1RM, e)
                }
                if best1RM > 0 {
                    let key = ex.name.lowercased()
                    best[key] = max(best[key] ?? 0, best1RM)
                }
            }
        }
        return best
    }

    /// Fastest logged 5k in seconds, from sport-log entries. Sport logs
    /// don't carry distance — a 5k shows up as a running entry whose note
    /// names the distance ("5k"). Tolerant match: nil when the user never
    /// annotates runs (honest unknown, not a guessed zero).
    func fastestFiveKSeconds(sportLogs: [SportLogEntry]) -> Double? {
        let candidates = sportLogs.filter { entry in
            entry.sport.slug == "running" || entry.sport.slug.contains("run")
        }
        guard !candidates.isEmpty else { return nil }
        let fives = candidates.filter {
            ($0.note ?? "").lowercased().contains("5k")
        }
        guard !fives.isEmpty else { return nil }
        return Double(fives.map(\.durationMinutes).min()! * 60)
    }

    /// Climbing sessions in the trailing 30 days — one logged session is
    /// one climb-day, which is what the log can honestly count.
    func climbsLast30Days(sportLogs: [SportLogEntry], now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        return sportLogs.filter {
            $0.sport.slug == "climbing" && $0.date >= cutoff
        }.count
    }
}
