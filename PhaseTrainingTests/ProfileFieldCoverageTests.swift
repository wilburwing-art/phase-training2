// ProfileFieldCoverageTests.swift — regression guard for build-78 root cause.
//
// Before build 78 you could add a field to TrainingMemory (visible on Profile
// or Onboarding), forget to wire it into either `planInputsHash` (planner
// regen trigger) or `CoachContext.snapshot` (coach context block), and ship.
// Nothing would warn. The seasons + per-sport-season + peakDate work all
// shipped with exactly this gap.
//
// This test forces every TrainingMemory stored property to either:
//   (a) appear in BOTH planInputsHash AND CoachContext.snapshot, OR
//   (b) be explicitly listed with a written reason for skipping either side.
//
// When you add a TrainingMemory field, you'll see a failure here until you
// either probe it (proves the wiring works) or skip it with a reason.

import XCTest
@testable import PhaseTraining

final class ProfileFieldCoverageTests: XCTestCase {

    /// One probe per TrainingMemory stored property. `name` MUST match the
    /// stored-property label exactly (Mirror reflection). Fields that don't
    /// belong in planInputsHash (display preferences) or CoachContext
    /// (append-only history) set their respective probe to nil and document
    /// via `skipReason`.
    struct Probe {
        let name: String
        /// Apply a value that should change planInputsHash from default.
        /// nil = intentionally not in planInputsHash (skipReason must explain).
        let mutateForHash: ((inout TrainingMemory) -> Void)?
        /// Apply a value that should appear as `snapshotMarker` in the
        /// snapshot. nil = intentionally not in CoachContext (skipReason explains).
        let mutateForSnapshot: ((inout TrainingMemory) -> Void)?
        let snapshotMarker: String?
        let skipReason: String?
    }

    // MARK: - Probes

    private static let probes: [Probe] = [
        // Lifecycle / migration — neither planner nor coach reads these.
        Probe(name: "schemaVersion", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Codable migration version; not user-facing config."),
        Probe(name: "onboardedAt", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Lifecycle marker; not used in planning or coach reasoning."),

        // Append-only history — sessions / soreness / feedback are state, not
        // config. Coach reads them via its OWN params (recentSessions,
        // recentFeedback, recentSoreness), not via the memory snapshot.
        Probe(name: "feedback", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Append-only history; coach reads via recentFeedback parameter."),
        Probe(name: "soreness", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Append-only history; coach reads via recentSoreness parameter."),
        Probe(name: "weeklyCheckIns", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Append-only history; not yet surfaced anywhere."),
        Probe(name: "coachInsights", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Coach-written observations; not part of input context."),

        // Display preference — does not change plan or coach prose.
        Probe(name: "usesImperial", mutateForHash: nil, mutateForSnapshot: nil,
              snapshotMarker: nil,
              skipReason: "Display preference; planner+coach use metric internally."),

        // Body metrics — see WeekPlan.planInputsHash comment. Intentionally
        // excluded from hash to avoid weight-log retriggering plan regen; ARE
        // surfaced to coach via bodySection.
        Probe(name: "heightCm",
              mutateForHash: nil,
              mutateForSnapshot: { $0.heightCm = 173 },
              snapshotMarker: "5′ 8″",
              skipReason: "Intentionally excluded from plan hash (weight-log shouldn't regen); IS in coach."),
        Probe(name: "weightKg",
              mutateForHash: nil,
              mutateForSnapshot: { $0.weightKg = 73.5 },
              snapshotMarker: "lb",
              skipReason: "Intentionally excluded from plan hash; IS in coach bodySection."),
        Probe(name: "gender",
              mutateForHash: nil,
              mutateForSnapshot: { $0.gender = .female },
              snapshotMarker: "female",
              skipReason: "Intentionally excluded from plan hash; IS in coach bodySection."),

        // Real config — must be in both.
        Probe(name: "sports",
              mutateForHash: { $0.sports = [Sport.catalog.first { $0.slug == "climbing" }!] },
              mutateForSnapshot: { $0.sports = [Sport.catalog.first { $0.slug == "climbing" }!] },
              snapshotMarker: "Climbing",
              skipReason: nil),
        Probe(name: "primarySport",
              mutateForHash: { $0.primarySport = Sport.catalog.first { $0.slug == "running" } },
              mutateForSnapshot: { m in
                  let r = Sport.catalog.first { $0.slug == "running" }!
                  m.sports = [r]; m.primarySport = r
              },
              snapshotMarker: "Running",
              skipReason: nil),
        Probe(name: "focuses",
              mutateForHash: { $0.focuses = [.hypertrophy] },
              mutateForSnapshot: { $0.focuses = [.hypertrophy] },
              snapshotMarker: "Build muscle",
              skipReason: nil),
        Probe(name: "seasonsBySport",
              mutateForHash: { m in
                  let c = Sport.catalog.first { $0.slug == "climbing" }!
                  m.sports = [c]; m.primarySport = c
                  m.seasonsBySport = [c: .offSeason]
              },
              mutateForSnapshot: { m in
                  let c = Sport.catalog.first { $0.slug == "climbing" }!
                  m.sports = [c]; m.primarySport = c
                  m.seasonsBySport = [c: .offSeason]
              },
              snapshotMarker: "off-season",
              skipReason: nil),
        Probe(name: "defaultSeason",
              mutateForHash: { $0.defaultSeason = .inSeason },
              mutateForSnapshot: { $0.defaultSeason = .inSeason },
              snapshotMarker: "in-season",
              skipReason: nil),
        Probe(name: "peakDate",
              mutateForHash: { $0.peakDate = Date(timeIntervalSince1970: 1_700_000_000) },
              mutateForSnapshot: { m in
                  let c = Sport.catalog.first { $0.slug == "climbing" }!
                  m.sports = [c]; m.primarySport = c
                  m.seasonsBySport = [c: .eventPrep]
                  m.peakDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())
              },
              snapshotMarker: "peak date:",
              skipReason: nil),
        Probe(name: "sessionMinutes",
              mutateForHash: { $0.sessionMinutes = 90 },
              mutateForSnapshot: { $0.sessionMinutes = 90 },
              snapshotMarker: "90 min",
              skipReason: nil),
        Probe(name: "liftDaysPerWeek",
              mutateForHash: { $0.liftDaysPerWeek = 5 },
              mutateForSnapshot: { $0.liftDaysPerWeek = 5 },
              snapshotMarker: "target lifts/wk: 5",
              skipReason: nil),
        Probe(name: "equipment",
              mutateForHash: { $0.equipment = [.barbell] },
              mutateForSnapshot: { $0.equipment = [.barbell] },
              snapshotMarker: "Barbell",
              skipReason: nil),
        Probe(name: "experience",
              mutateForHash: { $0.experience = .advanced },
              mutateForSnapshot: { $0.experience = .advanced },
              snapshotMarker: "Advanced",
              skipReason: nil),
        Probe(name: "startingState",
              mutateForHash: { $0.startingState = .returning },
              mutateForSnapshot: { $0.startingState = .returning },
              snapshotMarker: "coming back",
              skipReason: nil),
        Probe(name: "age",
              mutateForHash: { $0.age = 47 },
              mutateForSnapshot: { m in m.age = 47; m.weightKg = 80 }, // bodySection needs ≥1 field
              snapshotMarker: "age: 47",
              skipReason: nil),
        Probe(name: "dislikes",
              mutateForHash: { $0.dislikes = ["burpees"] },
              mutateForSnapshot: { $0.dislikes = ["burpees"] },
              snapshotMarker: "burpees",
              skipReason: nil),
        Probe(name: "constraints",
              mutateForHash: { $0.constraints = ["bad knee"] },
              mutateForSnapshot: { $0.constraints = ["bad knee"] },
              snapshotMarker: "bad knee",
              skipReason: nil),
        // Build 87 — structured per-injury record. Slug drives the planner's
        // exclusion set; severity / side / onset flow into the coach's
        // STRUCTURED INJURIES block but don't change which exercises get
        // dropped (yet). Probe verifies the human name lands in the snapshot.
        Probe(name: "userInjuries",
              mutateForHash: { $0.userInjuries = [UserInjury(slug: "acl-injury", severity: .mild)] },
              mutateForSnapshot: { $0.userInjuries = [UserInjury(slug: "acl-injury")] },
              snapshotMarker: "ACL Sprain/Tear",
              skipReason: nil),
    ]

    // MARK: - Tests

    /// Every stored property on TrainingMemory must have a probe. If you add
    /// a new field, Mirror picks it up and this fails until you append a Probe.
    func test_everyTrainingMemoryFieldHasAProbe() {
        let mirror = Mirror(reflecting: TrainingMemory())
        let actual = Set(mirror.children.compactMap(\.label))
        let known = Set(Self.probes.map(\.name))
        let missing = actual.subtracting(known)
        XCTAssertTrue(
            missing.isEmpty,
            """
            New TrainingMemory field(s) need a Probe in ProfileFieldCoverageTests.probes: \(missing.sorted())

            Either:
              (a) wire it into planInputsHash + CoachContext.snapshot and add a probe with both mutators set, or
              (b) add a probe with nil mutators and a skipReason explaining why.

            Without one of those two, this field will be silently dead (the bug build 78 closed).
            """
        )
        let extra = known.subtracting(actual)
        XCTAssertTrue(extra.isEmpty,
                      "Probe references field(s) no longer on TrainingMemory: \(extra.sorted())")
    }

    /// Each probe enforces its own contract.
    func test_probesEnforceTheirContracts() {
        for probe in Self.probes {
            // 1) planInputsHash check
            if let mutate = probe.mutateForHash {
                let a = TrainingMemory()
                var b = TrainingMemory()
                mutate(&b)
                XCTAssertNotEqual(
                    a.planInputsHash, b.planInputsHash,
                    "Probe '\(probe.name)' claims to drive plan regeneration but changing it didn't change planInputsHash. " +
                    "Either wire it into TrainingMemory.planInputsHash or remove the hash mutator."
                )
            } else {
                XCTAssertNotNil(probe.skipReason,
                                "Probe '\(probe.name)' skips planInputsHash but has no skipReason.")
            }

            // 2) CoachContext.snapshot check
            if let mutate = probe.mutateForSnapshot, let marker = probe.snapshotMarker {
                var m = TrainingMemory()
                mutate(&m)
                let snap = CoachContext.snapshot(
                    activeTab: .today,
                    memory: m,
                    plan: nil,
                    recentSessions: [],
                    recentFeedback: [],
                    recentSoreness: []
                )
                XCTAssertTrue(
                    snap.contains(marker),
                    """
                    Probe '\(probe.name)' claims to appear in CoachContext.snapshot with marker '\(marker)', but the snapshot didn't contain it.
                    Either wire the field into CoachContext.snapshot or update the probe.

                    Snapshot was:
                    \(snap)
                    """
                )
            } else if probe.mutateForSnapshot == nil {
                XCTAssertNotNil(probe.skipReason,
                                "Probe '\(probe.name)' skips CoachContext.snapshot but has no skipReason.")
            }
        }
    }
}
