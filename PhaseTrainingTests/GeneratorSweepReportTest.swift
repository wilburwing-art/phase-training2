// GeneratorSweepReportTest — fast inner-loop validation harness for
// WorkoutGenerator. NOT a pass/fail unit test: it runs the generator across a
// controlled one-variable-at-a-time (OFAT) sweep and writes a scrollable HTML
// report to /tmp/generator-sweep/report.html for eyeballing.
//
// Why this exists: the eval-rig export path (EvalRigExportSmokeTest) is the
// LONG loop — JSON round-trips to the eval-rig repo and an LLM grades it.
// This is the SHORT loop: tweak focusBias / prescription / a context signal,
// re-run this one test, scroll the doc, see exactly what moved.
//
// Controlled testing: a single fixed baseline (intermediate / hypertrophy /
// age 32 / 60 min / full gym / no soreness / empty context / .auto strategy).
// For each variable we hold everything else constant and sweep that one knob
// across its range, then regenerate a full simulated week and diff the output
// against the baseline column.
//
// Isolation detail that makes the sweep honest: the app normally seeds the
// generator with `memory.planInputsHash`, which itself changes whenever any
// memory field changes — so a naive sweep would confound "the logic reacted"
// with "the deterministic pick landed elsewhere because the seed moved". We
// pin a FIXED seed (gen-sweep-day{N}) across every column, so any delta is
// attributable purely to the swept variable.
//
// Blast-radius (scope) check: each variant carries a `maxScope` ceiling —
// the worst ChangeClass it is allowed to produce (notesOnly < prescription <
// selection < structure), verified against the generator code. A SCOPE
// anomaly fires when the observed change class exceeds it: tier leakage
// (e.g. priorBest — a notes-only knob — swapping an exercise), which the
// binary live/DEAD + expectsChange checks can't see because any movement
// at all reads as healthy.

import XCTest
@testable import PhaseTraining

final class GeneratorSweepReportTest: XCTestCase {

    // MARK: - Captured output model

    private struct ExLine {
        let name: String
        let exerciseId: Int    // for seeding the recentlyPicked variety probe
        let sets: Int
        let reps: String
        let rest: Int
        let rpe: String?
        let tempo: String?
        let warmUps: Int       // count; 0 = suppressed (e.g. sore prime mover)
        let superset: Int?
        let isCompound: Bool
        let notes: String?
        let pattern: String?   // captured for seeding the pattern-steering probes
    }
    private struct DayResult {
        let title: String
        let estMin: Int
        let lines: [ExLine]
    }
    private typealias Week = [DayResult]

    /// Ordered blast-radius classes. A variant's `maxScope` is the CEILING it
    /// is allowed to reach; `classify` reports the worst class actually
    /// observed. notesOnly < prescription < selection < structure — e.g.
    /// priorBest may only annotate (notesOnly); deload may move set counts
    /// (prescription) but must never swap an exercise (selection) or retitle
    /// a day (structure). A variant exceeding its ceiling is TIER LEAKAGE —
    /// the bug class the binary live/DEAD + expectsChange checks can't see,
    /// because any movement at all reads as healthy.
    private enum ChangeClass: Int, Comparable, CustomStringConvertible {
        case none = 0, notesOnly, prescription, selection, structure
        static func < (a: ChangeClass, b: ChangeClass) -> Bool { a.rawValue < b.rawValue }
        var description: String {
            switch self {
            case .none: return "none"
            case .notesOnly: return "notes-only"
            case .prescription: return "prescription"
            case .selection: return "selection"
            case .structure: return "structure"
            }
        }
    }

    private struct Column {
        let label: String
        let isBaseline: Bool
        let expectsChange: Bool   // carried from the Variant; baseline column = false
        let maxScope: ChangeClass // ceiling carried from the Variant
        let week: Week            // seed[0] — what the report renders
        let movedAnySeed: Bool    // differs from baseline under ANY seed (multi-seed verdict)
        let observedClass: ChangeClass // worst change class across ALL seeds
    }
    private struct SweepVar {
        let name: String
        let note: String
        let columns: [Column]
    }
    /// One swept value. The closure mutates fresh copies of the baseline
    /// memory / context / strategy — exactly one knob per variant.
    /// `expectsChange` encodes the INTENT: a variant that should move the
    /// output but doesn't is a NO-OP anomaly (the per-variable live/DEAD verdict
    /// would otherwise launder it — see report anomalies). Default true; set
    /// false for baseline-equal values and designed no-ops (no-data controls).
    /// `maxScope` encodes the allowed BLAST RADIUS: the worst ChangeClass this
    /// knob may produce (verified against the generator code — citations at
    /// each annotation). Default .structure = unrestricted.
    private struct Variant {
        let label: String
        var expectsChange: Bool = true
        var maxScope: ChangeClass = .structure
        var recentlyPicked: Set<Int> = []   // exercise ids fed to every day (variety probe)
        let mutate: (inout TrainingMemory, inout GeneratorContext, inout GeneratorStrategy) -> Void
    }

    // MARK: - Baseline (the control)

    /// Fresh baseline memory each call (value type — safe to mutate the copy).
    private func controlMemory() -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = .intermediate
        m.focuses = [.hypertrophy]
        m.equipment = [.fullGym]
        m.sessionMinutes = 60
        m.liftDaysPerWeek = 3
        m.age = 32
        m.gender = .male
        return m
    }

    /// Baseline B — advanced / generalStrength / 90 min. Unmasks schemes the
    /// intermediate 4-set cap and 60-min budget hide at baseline A (Cowork
    /// finding #5): advanced has no set cap, so generalStrength shows its true
    /// 5×5, and a 90-min budget lets the duration sweep show the drop ladder.
    private func controlMemoryB() -> TrainingMemory {
        var m = TrainingMemory()
        m.experience = .advanced
        m.focuses = [.generalStrength]
        m.equipment = [.fullGym]
        m.sessionMinutes = 90
        m.liftDaysPerWeek = 4
        m.age = 32
        m.gender = .male
        return m
    }

    /// Fixed base seeds for the multi-seed DEAD/anomaly verdict. seeds[0] is the
    /// one the report renders; a no-move under seeds[0] is re-checked against the
    /// rest so a sparse probe (e.g. an injury whose contraindication isn't in
    /// this seed's picks) isn't falsely flagged DEAD. Can't use Math.random in
    /// this harness, so the seeds are fixed distinct strings.
    private let seeds = ["gen-sweep-1", "gen-sweep-2", "gen-sweep-3", "gen-sweep-4"]

    /// Generate a full simulated week from a memory/context/strategy triple.
    /// totalLifts == liftDaysPerWeek so the day-count sweep is visible.
    ///
    /// ONE seed for the whole week (no per-day salt) — matches the app, which
    /// passes a single `planInputsHash` to every lift day (Planner.swift:517)
    /// and gets cross-day variety from `recentlyPicked`, not the seed. So
    /// repeated-focus days (U/L/U/L day 1 vs 3) come out IDENTICAL here, exactly
    /// as the app produces them — the report surfaces that instead of faking
    /// variety with a salt. `recentlyPicked` is passed unchanged to every day,
    /// also matching the app (it's a persistent cross-week set, not accumulated
    /// within the week).
    private func generateWeek(_ m: TrainingMemory,
                              _ c: GeneratorContext,
                              _ s: GeneratorStrategy,
                              seed: String,
                              recentlyPicked: Set<Int> = []) -> Week {
        let profile = DemographicProfile.from(m)
        let days = max(0, min(7, m.liftDaysPerWeek))
        var out: Week = []
        for i in 0..<days {
            let w = WorkoutGenerator.generateLift(
                liftIndex: i,
                totalLifts: days,
                memory: m,
                profile: profile,
                hashSeed: seed,
                recentlyPicked: recentlyPicked,
                context: c,
                strategy: s
            )
            out.append(DayResult(
                title: w.title,
                estMin: w.estimatedMinutes,
                lines: w.exercises.map {
                    ExLine(name: $0.name, exerciseId: $0.exerciseId, sets: $0.sets, reps: $0.reps,
                           rest: $0.restSeconds, rpe: $0.rpe, tempo: $0.tempo,
                           warmUps: $0.warmUpSets?.count ?? 0,
                           superset: $0.supersetGroup, isCompound: $0.isCompound,
                           notes: $0.notes, pattern: $0.pattern)
                }
            ))
        }
        return out
    }

    /// A control point the variants diff against: the rendered (seed[0]) week
    /// plus the full per-seed weeks for the multi-seed verdict + scope classify.
    private struct BaselineCtx {
        let control: () -> TrainingMemory   // fresh control memory (baseline A or B)
        let primaryWeek: Week
        let seedWeeks: [Week]
    }
    private func makeBaseline(_ control: @escaping () -> TrainingMemory) -> BaselineCtx {
        let m = control()
        let weeks = seeds.map { generateWeek(m, .empty, .auto, seed: $0) }
        return BaselineCtx(control: control, primaryWeek: weeks[0], seedWeeks: weeks)
    }

    // MARK: - Sweep assembly

    /// Build a SweepVar: baseline column first, then one column per variant.
    /// Renders seed[0]; runs ALL seeds for every variant — the scope verdict
    /// needs the worst change class across every seed (a variant can stay
    /// in-bounds on seed[0] and exceed its ceiling on seed[2]), and the same
    /// pass doubles as the multi-seed re-check that stops a sparse probe from
    /// being falsely flagged DEAD. ~4× the generate calls of the old lazy
    /// path; the whole sweep still runs in seconds.
    private func sweep(_ name: String, _ note: String,
                       baseline: BaselineCtx, _ variants: [Variant]) -> SweepVar {
        var cols: [Column] = [Column(label: "baseline", isBaseline: true, expectsChange: false,
                                     maxScope: .structure, week: baseline.primaryWeek,
                                     movedAnySeed: false, observedClass: .none)]
        for v in variants {
            func week(_ seed: String) -> Week {
                var m = baseline.control(); var c = GeneratorContext.empty; var s = GeneratorStrategy.auto
                v.mutate(&m, &c, &s)
                return generateWeek(m, c, s, seed: seed, recentlyPicked: v.recentlyPicked)
            }
            var primary: Week = []
            var observed = ChangeClass.none
            for (k, seed) in seeds.enumerated() {
                let w = week(seed)
                if k == 0 { primary = w }
                observed = max(observed, classify(baseline: baseline.seedWeeks[k], variant: w))
            }
            cols.append(Column(label: v.label, isBaseline: false, expectsChange: v.expectsChange,
                               maxScope: v.maxScope, week: primary,
                               movedAnySeed: observed > .none, observedClass: observed))
        }
        return SweepVar(name: name, note: note, columns: cols)
    }

    // MARK: - The report

    func test_generate_sweep_report() throws {
        // Shared control week — every variable diffs against this.
        let baseA = makeBaseline(controlMemory)
        XCTAssertFalse(baseA.primaryWeek.isEmpty, "Baseline week must generate days")

        // Context probes are seeded from the control week's ACTUAL picks so
        // the wiring test is guaranteed relevant (no guessing catalog names).
        let controlNames = baseA.primaryWeek.flatMap { $0.lines.map { $0.name.lowercased() } }
        let day1Patterns = baseA.primaryWeek.first.map { $0.lines.compactMap { $0.pattern } } ?? []
        // Day-1 exercise ids — for the recentlyPicked variety probe.
        let controlDay0Ids = Set(baseA.primaryWeek.first?.lines.map { $0.exerciseId } ?? [])
        // Baseline B — for the clamp-sensitive sweeps that A masks (finding #5).
        let baseB = makeBaseline(controlMemoryB)

        var sweeps: [SweepVar] = []

        // ===== Profile knobs (clear min -> max) =====

        sweeps.append(sweep(
            "experience", "→ set-count clamp (beginner ≤3, intermediate ≤4, advanced uncapped)",
            baseline: baseA,
            [
                // .selection: set clamps (prescription) + difficulty pools feed
                // pickForSlot (selection); never retitles a day.
                Variant(label: "beginner", maxScope: .selection)     { m, _, _ in m.experience = .beginner },
                Variant(label: "intermediate", expectsChange: false, maxScope: .selection) { m, _, _ in m.experience = .intermediate },
                Variant(label: "advanced", maxScope: .selection)     { m, _, _ in m.experience = .advanced },
            ]))

        sweeps.append(sweep(
            "primaryFocus", "→ focusBias() sets/reps/rest scheme + accessory layer",
            baseline: baseA,
            PrimaryFocus.allCases.map { f in
                Variant(label: f.rawValue, expectsChange: f != .hypertrophy) { m, _, _ in m.focuses = [f] }
            }))

        sweeps.append(sweep(
            "age", "→ ≥55 drops one set; also shifts derived era cohort",
            baseline: baseA,
            [18, 32, 45, 55, 70].map { (a: Int) in
                // .structure: the age-derived era cohort can carry a
                // splitPreference that flips the split — PPL → U/L — and with
                // it the day titles (WG:72-78). Confirmed live 2026-06-06:
                // age 45 derives a cohort whose splitPreference retitles days.
                Variant(label: "\(a)", expectsChange: a != 32, maxScope: .structure) { m, _, _ in m.age = a }
            }))

        sweeps.append(sweep(
            "sessionMinutes", "→ duration budget; optional slots dropped when under, restored when the budget allows",
            baseline: baseA,
            [20, 30, 45, 60, 90, 120].map { (mins: Int) in
                // Any non-baseline budget should move: below 60 drops slots;
                // above 60 restores optional slots the 60-min baseline was
                // already dropping (confirmed 2026-06-06: 90/120 add a 7th
                // exercise per day — the old "slots are fixed, raising is a
                // no-op" assumption was stale).
                // .selection: rows added/dropped; day titles/count recipe-pinned.
                Variant(label: "\(mins) min", expectsChange: mins != 60, maxScope: .selection) { m, _, _ in m.sessionMinutes = mins }
            }))

        sweeps.append(sweep(
            "liftDaysPerWeek", "→ split shape: 1=FB, 2=A/B, 3=PPL, 4=U/L, 5+=rotation",
            baseline: baseA,
            [1, 2, 3, 4, 5, 6].map { (d: Int) in
                Variant(label: "\(d) days", expectsChange: d != 3) { m, _, _ in m.liftDaysPerWeek = d }
            }))

        sweeps.append(sweep(
            "equipment", "→ candidate pool at the SQL boundary",
            baseline: baseA,
            [
                // .selection: pool change swaps/drops rows; titles recipe-pinned.
                Variant(label: "bodyweight", maxScope: .selection) { m, _, _ in m.equipment = [.bodyweight] },
                Variant(label: "minimal (DB+bands+bar)", maxScope: .selection) { m, _, _ in m.equipment = [.dumbbells, .bands, .pullUpBar] },
                Variant(label: "full gym", expectsChange: false, maxScope: .selection) { m, _, _ in m.equipment = [.fullGym] },
            ]))

        sweeps.append(sweep(
            "soreness", "→ sore-area movement softening + RPE-7 cap",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .prescription: with empty context, memory.soreness only caps
                // RPE (WG:906-908) + suppresses warmups (WG:407). Selection-level
                // softening rides context.recentSoreAreas — the .from probe below.
                Variant(label: "mild chest+shoulders", maxScope: .prescription) { m, _, _ in
                    m.soreness.append(makeSoreEntry(areas: ["chest", "shoulders"], level: "mild"))
                },
                Variant(label: "high chest+shoulders", maxScope: .prescription) { m, _, _ in
                    m.soreness.append(makeSoreEntry(areas: ["chest", "shoulders"], level: "high"))
                },
            ]))

        sweeps.append(sweep(
            "era cohort", "→ split preference (can flip PPL → U/L) + aesthetic implement tiebreak + hypertrophy rep band",
            baseline: baseA,
            EraCohort.allCases.map { era in
                // age-32 baseline derives redditFitness, so that override reproduces it.
                // .structure: beyond the aesthetic tiebreak (WG:582-622) and
                // rep band, eraStyle.splitPreference replaces the default focus
                // rotation when totalLifts >= 3 (WG:72-78) — veteran_strength /
                // t_nation_forum / science_based flip PPL to U/L/U and retitle
                // every day. First sweep run flagged this as SCOPE before the
                // splitPreference path was traced; it is designed, not leakage.
                Variant(label: era.rawValue, expectsChange: era.rawValue != "reddit_fitness", maxScope: .structure) { m, _, _ in m.eraOverride = era.rawValue }
            }))

        // ===== Context + strategy signals (the dead-signal hunt) =====

        sweeps.append(sweep(
            "context.readinessScore", "→ silent volume scale (0.6–1.0×) + compound RPE cap; needs hasReadinessData",
            baseline: baseA,
            [0.0, 0.5, 1.0].map { score in
                // score 1.0 = full readiness = 1.0× volume + RPE-9 cap, which
                // reproduces the no-scaling baseline → no change expected.
                // .prescription: sets ×0.6-1.0 + compound RPE cap (WG:391-405);
                // a SCOPE flag here = the multiplier leaking into slot drops
                // via the duration budget — investigate, don't silently widen.
                Variant(label: "score \(score) (hasData)", expectsChange: score != 1.0, maxScope: .prescription) { _, c, _ in
                    c.readinessScore = score
                    c.hasReadinessData = true
                }
            } + [
                Variant(label: "score 0.0 (NO data)", expectsChange: false, maxScope: .prescription) { _, c, _ in
                    c.readinessScore = 0.0
                    c.hasReadinessData = false   // no-op by design — gate is hasReadinessData
                }
            ]))

        sweeps.append(sweep(
            "context.priorBest", "→ progressive-overload 'target: X' notes",
            baseline: baseA,
            [
                Variant(label: "empty", expectsChange: false) { _, _, _ in },
                // .notesOnly: progressiveOverloadHint writes the "target: X"
                // note and nothing else (WG:752-782). Anything beyond notes
                // here is tier leakage — an annotative knob driving selection.
                Variant(label: "seeded from control picks", maxScope: .notesOnly) { _, c, _ in
                    for n in controlNames { c.priorBest[n] = PriorBest(weight: 185, reps: 5, date: Date()) }
                },
            ]))

        sweeps.append(sweep(
            "context.stagnantExercises", "→ stagnation swap to a substitute (sparse: needs a substitute that passes constraints)",
            baseline: baseA,
            [
                Variant(label: "empty", expectsChange: false) { _, _, _ in },
                // .selection: swap-to-substitute only (WG:716-749); no row drop.
                Variant(label: "control picks stagnant", maxScope: .selection) { _, c, _ in
                    c.stagnantExercises = Set(controlNames)
                },
            ]))

        sweeps.append(sweep(
            "strategy.intensityBias", "→ sets multiplier deload ×0.7 / normal / push ×1.15",
            baseline: baseA,
            [
                // .prescription: sets multiplier only (GS:74-80, WG:393-394).
                // A SCOPE flag = the multiplier leaking into slot drops via the
                // duration budget — investigate, don't silently widen.
                Variant(label: "deload", maxScope: .prescription) { _, _, s in s.intensityBias = .deload },
                Variant(label: "normal", expectsChange: false, maxScope: .prescription) { _, _, s in s.intensityBias = .normal },
                Variant(label: "push", maxScope: .prescription)   { _, _, s in s.intensityBias = .push },
            ]))

        sweeps.append(sweep(
            "strategy.durationMinutes", "→ overrides sessionMinutes (clamped 15–180); drops or restores optional slots like sessionMinutes",
            baseline: baseA,
            [20, 60, 120].map { (mins: Int) in
                // .selection: same drop/restore ladder as sessionMinutes.
                Variant(label: "\(mins) min", expectsChange: mins != 60, maxScope: .selection) { _, _, s in s.durationMinutes = mins }
            }))

        sweeps.append(sweep(
            "strategy per-exercise overrides", "→ rpe/tempo/targetWeight overrides, keyed by lowercased name, seeded from control picks",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // rpe/tempo: early-return field override (WG:862-865) → .prescription.
                Variant(label: "rpeOverrides → '6'", maxScope: .prescription) { _, _, s in
                    for n in controlNames { s.rpeOverrides[n] = "6" }
                },
                Variant(label: "tempoOverrides → '4-0-1-0'", maxScope: .prescription) { _, _, s in
                    for n in controlNames { s.tempoOverrides[n] = "4-0-1-0" }
                },
                // targetWeight: replaces the priorBest note (WG:764-768) → .notesOnly.
                Variant(label: "targetWeightOverrides → 225 lb", maxScope: .notesOnly) { _, _, s in
                    for n in controlNames { s.targetWeightOverrides[n] = 225 }
                },
            ]))

        sweeps.append(sweep(
            "strategy.focus override", "→ forces day shape regardless of liftIndex",
            baseline: baseA,
            [
                Variant(label: "auto (nil)", expectsChange: false) { _, _, _ in },
                Variant(label: "force .legs") { _, _, s in s.focus = .legs },
                Variant(label: "force .pull") { _, _, s in s.focus = .pull },
            ]))

        // ===== Pool filters & pattern steering (coverage gaps closed 2026-06-04) =====

        sweeps.append(sweep(
            "context.recentSoreAreas", "→ pick-TIME candidate exclusion in pickForSlot — DISTINCT from memory.soreness (which only caps RPE)",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .selection: pick-time exclusion (WG:546-555); slot fall-through
                // may drop rows, but day titles stay recipe-pinned.
                Variant(label: "chest+shoulders+triceps sore", maxScope: .selection) { _, c, _ in
                    c.recentSoreAreas = ["chest", "shoulders", "triceps"]
                },
                Variant(label: "quads+hamstrings+glutes sore", maxScope: .selection) { _, c, _ in
                    c.recentSoreAreas = ["quads", "hamstrings", "glutes"]
                },
            ]))

        sweeps.append(sweep(
            "injuries → excludedExerciseIds", "→ coach.db exercise_injury_relevance contraindications drop from the candidate pool",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .selection: id exclusion from the candidate pool (WG:722).
                Variant(label: "lumbar-disc-herniation (10 contra)", maxScope: .selection) { m, _, _ in
                    m.userInjuries = [UserInjury(slug: "lumbar-disc-herniation")]
                },
                // Sparse: only changes output if a contraindicated id is in this
                // seed's picks. A no-op here = sparsity, not necessarily a bug.
                Variant(label: "rotator-cuff-injury", maxScope: .selection) { m, _, _ in
                    m.userInjuries = [UserInjury(slug: "rotator-cuff-injury")]
                },
            ]))

        sweeps.append(sweep(
            "dislikes + sports (pool filters)", "→ dislikes keyword-exclude names; sports rerank picks toward sport-relevant drills",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .selection: keyword exclusion / sport rerank only touch the pool.
                Variant(label: "dislike 'barbell'", maxScope: .selection) { m, _, _ in m.dislikes = ["barbell"] },
                Variant(label: "dislike 'machine'", maxScope: .selection) { m, _, _ in m.dislikes = ["machine"] },
                Variant(label: "sport: climbing", maxScope: .selection) { m, _, _ in
                    m.sports = [Sport(slug: "climbing", name: "Climbing")]
                    m.primarySport = m.sports.first
                },
                Variant(label: "sport: bjj", maxScope: .selection) { m, _, _ in
                    m.sports = [Sport(slug: "bjj", name: "Brazilian Jiu-Jitsu")]
                    m.primarySport = m.sports.first
                },
            ]))

        sweeps.append(sweep(
            "strategy pattern steering", "→ emphasize jumps a pattern to the front of every slot; deprioritize removes it (slot may fall through)",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // expectsChange:true ON PURPOSE — emphasize is structurally inert at
                // single-alternative slots (audit N9), so this SHOULD flag as a NO-OP
                // anomaly every run until recipes gain multi-alternative slots.
                // .selection: reorder/remove alternatives; fall-through may drop rows.
                Variant(label: "emphasize elbow-flexion/extension", maxScope: .selection) { _, _, s in
                    s.emphasizePatterns = ["elbow-flexion", "elbow-extension"]
                },
                Variant(label: "deprioritize day-1 patterns", maxScope: .selection) { _, _, s in
                    s.deprioritizePatterns = day1Patterns
                },
            ]))

        sweeps.append(sweep(
            "recentlyPicked (variety)", "→ applyVariety soft-filter drops recently-picked exercises (the live cross-week variety mechanism — fed identically to every day, matching the app)",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .selection: variety soft-filter swaps picks (WG:531-535).
                Variant(label: "day-1 picks recently used", maxScope: .selection, recentlyPicked: controlDay0Ids) { _, _, _ in },
            ]))

        // ===== Baseline B (advanced / generalStrength / 90 min) — unmask clamped schemes =====

        sweeps.append(sweep(
            "primaryFocus @ B (advanced)", "→ no 4-set cap at advanced: generalStrength shows its true 5×5 (masked to 4×5 at baseline A)",
            baseline: baseB,
            PrimaryFocus.allCases.map { f in
                Variant(label: f.rawValue, expectsChange: f != .generalStrength) { m, _, _ in m.focuses = [f] }
            }))

        sweeps.append(sweep(
            "sessionMinutes @ B (90 min)", "→ 90-min budget shows the full drop ladder as minutes fall (baseline A's 60 min already near-minimal)",
            baseline: baseB,
            [20, 45, 60, 90, 120].map { (mins: Int) in
                // .selection: drop/restore ladder only; titles recipe-pinned.
                Variant(label: "\(mins) min", expectsChange: mins != 90, maxScope: .selection) { m, _, _ in m.sessionMinutes = mins }
            }))

        // ===== End-to-end context via GeneratorContext.from (builder + consumer) =====
        // The manual context sweeps above set context fields DIRECTLY (consumer
        // only). These build context the way the app does — through `.from` —
        // so a builder/consumer mismatch (the H11 sore-filter bug class) shows
        // up as `.from` reading DEAD while the manual probe reads live.

        sweeps.append(sweep(
            "context.from(soreness:) end-to-end", "→ recentSoreAreas via buildRecentSoreAreas (not hand-set) — catches builder↔consumer drift",
            baseline: baseA,
            [
                Variant(label: "none", expectsChange: false) { _, _, _ in },
                // .selection — DELIBERATELY one class above the manual
                // memory.soreness probe (.prescription): the builder populates
                // recentSoreAreas, which excludes candidates at pick time. The
                // ceiling pair IS the H11 builder/consumer assertion.
                Variant(label: ".from chest+shoulders sore", maxScope: .selection) { _, c, _ in
                    c = GeneratorContext.from(
                        sessions: [], soreness: [makeSoreEntry(areas: ["chest", "shoulders"], level: "high")], feedback: [])
                },
            ]))

        // ===== Render =====
        let outDir = URL(fileURLWithPath: "/tmp/generator-sweep")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // HTML — side-by-side, sticky baseline, amber diff cells. For eyeballing.
        let htmlURL = outDir.appendingPathComponent("report.html")
        try renderHTML(sweeps).data(using: .utf8)!.write(to: htmlURL, options: .atomic)

        // Markdown twin — paste-friendly for handing to Cowork / another session.
        // A remote agent can't read this /tmp path, so the .md is the thing you
        // copy INTO the chat. Same data; no side-by-side table (MD cells can't
        // hold nested lists), one labeled block per variant instead.
        let mdURL = outDir.appendingPathComponent("report.md")
        try renderMarkdown(sweeps).data(using: .utf8)!.write(to: mdURL, options: .atomic)

        print("\n[GeneratorSweepReport] HTML: \(htmlURL.path)   (open \(htmlURL.path))")
        print("[GeneratorSweepReport] MD:   \(mdURL.path)   (pbcopy < \(mdURL.path))\n")
        // Dead-signal + anomaly summary to stdout, so a CI/console run flags
        // both without opening either file. Anomalies are the load-bearing
        // line: a per-variant expected-change that didn't happen (NO-OP) is
        // what the per-variable live/DEAD verdict launders.
        for s in sweeps {
            let live = isLive(s)
            let anom = anomalies(s)
            let suffix = anom.isEmpty ? "" : "   ⚠ " + anom.joined(separator: ", ")
            print("[GeneratorSweepReport]   \(live ? "live" : "DEAD") — \(s.name)\(suffix)")
        }
    }

    // MARK: - Signatures (diff + dead-signal detection)

    private func daySignature(_ d: DayResult) -> String {
        d.title + "::" + d.lines.map {
            "\($0.name)|\($0.sets)|\($0.reps)|\($0.rest)|\($0.rpe ?? "")|\($0.tempo ?? "")|wu\($0.warmUps)|\($0.superset.map(String.init) ?? "")|\($0.notes ?? "")"
        }.joined(separator: ",")
    }
    private func weekSignature(_ w: Week) -> String {
        "[\(w.count)]" + w.map(daySignature).joined(separator: "||")
    }

    /// Worst change class observed between a baseline and variant week, paired
    /// day-by-day and row-by-row. Boundaries: day count or any day title →
    /// .structure; row count or ordered name list per day → .selection;
    /// sets/reps/rest/rpe/tempo/warmups/superset on a paired row →
    /// .prescription; notes text only → .notesOnly.
    private func classify(baseline: Week, variant: Week) -> ChangeClass {
        if baseline.count != variant.count { return .structure }
        var worst = ChangeClass.none
        for (b, v) in zip(baseline, variant) {
            if b.title != v.title { return .structure }
            if b.lines.count != v.lines.count
                || b.lines.map({ $0.name }) != v.lines.map({ $0.name }) {
                worst = max(worst, .selection); continue
            }
            for (bl, vl) in zip(b.lines, v.lines) {
                if bl.sets != vl.sets || bl.reps != vl.reps || bl.rest != vl.rest
                    || bl.rpe != vl.rpe || bl.tempo != vl.tempo
                    || bl.warmUps != vl.warmUps || bl.superset != vl.superset {
                    worst = max(worst, .prescription)
                } else if bl.notes != vl.notes {
                    worst = max(worst, .notesOnly)
                }
            }
        }
        return worst
    }

    /// A variable is live if any variant differs from baseline under any seed.
    private func isLive(_ s: SweepVar) -> Bool {
        s.columns.dropFirst().contains { $0.movedAnySeed }
    }

    /// Variants whose INTENT disagrees with what happened — the checks the
    /// per-variable live/DEAD verdict can't make, because one working sibling
    /// makes the whole variable read "live". NO-OP = expected to move but
    /// didn't (the laundered case); UNEXPECTED = held but moved; SCOPE =
    /// moved beyond its allowed blast radius (tier leakage — e.g. priorBest,
    /// a notes-only knob, swapping an exercise). Uses the multi-seed
    /// `movedAnySeed`/`observedClass`, so a sparse single-seed miss isn't
    /// flagged as a NO-OP and an exceed on any seed is caught.
    private func anomalies(_ s: SweepVar) -> [String] {
        var out: [String] = []
        for c in s.columns where !c.isBaseline {
            if c.expectsChange && !c.movedAnySeed { out.append("NO-OP: \(c.label)") }
            if !c.expectsChange && c.movedAnySeed { out.append("UNEXPECTED: \(c.label)") }
            if c.movedAnySeed && c.observedClass > c.maxScope {
                out.append("SCOPE: \(c.label) (observed \(c.observedClass) > allowed \(c.maxScope))")
            }
        }
        return out
    }

    // MARK: - HTML rendering

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func renderDayCell(_ d: DayResult) -> String {
        var rows = ""
        for l in d.lines {
            let tags = [
                l.rpe.map { "RPE \($0)" },
                l.tempo.map { "T \($0)" },
                l.warmUps > 0 ? "WU×\(l.warmUps)" : nil,
                l.superset.map { "SS\($0)" },
                l.isCompound ? "C" : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            let note = l.notes.map { " — <span class=\"note\">\(esc($0))</span>" } ?? ""
            rows += "<li><span class=\"ex\">\(esc(l.name))</span> "
                + "<span class=\"scheme\">\(l.sets)×\(esc(l.reps)) · \(l.rest)s</span>"
                + (tags.isEmpty ? "" : " <span class=\"tags\">\(tags)</span>")
                + note + "</li>"
        }
        return "<div class=\"daytitle\">\(esc(d.title)) <span class=\"est\">~\(d.estMin)m · \(d.lines.count) ex</span></div><ul>\(rows)</ul>"
    }

    // MARK: - Markdown rendering (paste-friendly)

    /// One labeled block per variant (no side-by-side table — Markdown cells
    /// can't hold the nested exercise lists). A day tagged **(changed)** differs
    /// from the baseline column's same-index day. Built for an LLM reviewer.
    private func renderMarkdown(_ sweeps: [SweepVar]) -> String {
        var out = "# WorkoutGenerator — controlled variable sweep\n\n"
        out += "Baseline: intermediate · hypertrophy · age 32 · 60 min · full gym · "
        out += "no soreness · empty context · auto strategy. Each variable is swept "
        out += "one-at-a-time; everything else held at baseline. A day tagged "
        out += "**(changed)** differs from that variable's baseline column. A fixed "
        out += "seed across columns isolates the variable. **Anomalies** flag a variant "
        out += "that was *expected* to move the workout but didn't (NO-OP) — the per-"
        out += "variable live/DEAD verdict alone can't catch those (one working sibling "
        out += "makes the row read live) — and a variant whose observed change class "
        out += "exceeds its allowed blast radius (SCOPE: notes-only < prescription < "
        out += "selection < structure — e.g. priorBest, a notes-only knob, swapping an "
        out += "exercise is tier leakage).\n\n"
        out += "_Scope: exercises `WorkoutGenerator.generateLift` in isolation. "
        out += "Planner-level signals (recentHardSportDays, feedback bias, taper, "
        out += "missed-workout reshuffle, lift-day floor) are NOT covered here, nor is "
        out += "`recentlyPicked` (the live cross-day/week variety mechanism)._\n\n"

        // Summary table — plain Markdown, the one place a table reads cleanly.
        out += "## Summary\n\n| Variable | Variants | Distinct outputs | Status | Worst scope | Anomalies |\n|---|---|---|---|---|---|\n"
        for s in sweeps {
            let variantCols = Array(s.columns.dropFirst())
            let distinct = Set(s.columns.map { weekSignature($0.week) }).count
            let live = isLive(s)
            let anom = anomalies(s)
            let worst = variantCols.map { $0.observedClass }.max() ?? .none
            let exceeded = variantCols.contains { $0.movedAnySeed && $0.observedClass > $0.maxScope }
            out += "| \(s.name) | \(variantCols.count) | \(distinct) | \(live ? "live" : "⚠ DEAD") | \(exceeded ? "⚠ " : "")\(worst) | \(anom.isEmpty ? "—" : "⚠ " + anom.joined(separator: "; ")) |\n"
        }
        out += "\n"

        for s in sweeps {
            let baseWeek = s.columns[0].week
            let live = isLive(s)
            let anom = anomalies(s)
            out += "## \(s.name)\(live ? "" : "  ⚠ DEAD SIGNAL")\n\n"
            if !anom.isEmpty { out += "> ⚠ **Anomalies:** \(anom.joined(separator: "; "))\n\n" }
            out += "_\(s.note)_\n\n"
            for c in s.columns {
                let totalMin = c.week.reduce(0) { $0 + $1.estMin }
                out += "**\(c.label)**\(c.isBaseline ? " _(baseline)_" : "") · "
                out += "\(c.week.count) days · ~\(totalMin)m"
                if !c.isBaseline && c.movedAnySeed {
                    out += " · scope: \(c.observedClass)"
                    if c.observedClass > c.maxScope { out += " ⚠ exceeds allowed \(c.maxScope)" }
                }
                out += "\n\n"
                for (i, d) in c.week.enumerated() {
                    let baseDaySig = i < baseWeek.count ? daySignature(baseWeek[i]) : "∅"
                    let changed = !c.isBaseline && daySignature(d) != baseDaySig
                    out += "- **\(d.title)**\(changed ? " (changed)" : "") — \(d.lines.count) ex, ~\(d.estMin)m\n"
                    for l in d.lines {
                        let tags = [
                            l.rpe.map { "RPE \($0)" },
                            l.tempo.map { "tempo \($0)" },
                            l.warmUps > 0 ? "warmups×\(l.warmUps)" : nil,
                            l.isCompound ? "compound" : nil,
                            l.notes,
                        ].compactMap { $0 }
                        let tagStr = tags.isEmpty ? "" : " · " + tags.joined(separator: " · ")
                        out += "    - \(l.name) — \(l.sets)×\(l.reps), \(l.rest)s\(tagStr)\n"
                    }
                }
                out += "\n"
            }
        }
        return out
    }

    private func renderHTML(_ sweeps: [SweepVar]) -> String {
        var body = ""

        // Summary table — the scan-at-a-glance "which knobs are live/dead".
        body += "<h2>Summary</h2><table class=\"summary\"><tr><th>Variable</th><th>Variants</th><th>Distinct outputs</th><th>Status</th><th>Worst scope</th><th>Anomalies</th></tr>"
        for s in sweeps {
            let variantCols = Array(s.columns.dropFirst())
            let distinct = Set(s.columns.map { weekSignature($0.week) }).count
            let live = isLive(s)
            let status = live
                ? "<span class=\"ok\">live</span>"
                : "<span class=\"dead\">⚠ DEAD — every variant identical to baseline</span>"
            let anom = anomalies(s)
            let anomCell = anom.isEmpty
                ? "<span class=\"ok\">—</span>"
                : "<span class=\"dead\">⚠ \(esc(anom.joined(separator: "; ")))</span>"
            let worst = variantCols.map { $0.observedClass }.max() ?? .none
            let exceeded = variantCols.contains { $0.movedAnySeed && $0.observedClass > $0.maxScope }
            let scopeCell = exceeded
                ? "<span class=\"dead\">⚠ \(worst)</span>"
                : "\(worst)"
            body += "<tr><td><a href=\"#\(anchor(s.name))\">\(esc(s.name))</a></td>"
                + "<td>\(variantCols.count)</td><td>\(distinct)</td><td>\(status)</td><td>\(scopeCell)</td><td>\(anomCell)</td></tr>"
        }
        body += "</table>"

        // One section per variable.
        for s in sweeps {
            let live = isLive(s)
            let anom = anomalies(s)
            body += "<h2 id=\"\(anchor(s.name))\">\(esc(s.name)) "
                + (live ? "" : "<span class=\"dead\">⚠ DEAD SIGNAL</span>") + "</h2>"
            if !anom.isEmpty {
                body += "<p class=\"dead\">⚠ Anomalies (NO-OP = expected change, none seen — could be inert wiring, sparse data, or a real asymmetry; UNEXPECTED = held but moved; SCOPE = moved beyond its allowed blast radius): \(esc(anom.joined(separator: "; ")))</p>"
            }
            body += "<p class=\"note\">\(esc(s.note))</p>"

            let maxDays = s.columns.map { $0.week.count }.max() ?? 0
            body += "<div class=\"scroll\"><table class=\"sweep\">"

            // Header row — variant headers carry the observed change class.
            body += "<tr><th class=\"rowhdr\">day</th>"
            for c in s.columns {
                let cls = c.isBaseline ? "baseline" : "variant"
                var label = esc(c.label)
                if !c.isBaseline && c.movedAnySeed {
                    label += c.observedClass > c.maxScope
                        ? " <span class=\"dead\">· \(c.observedClass) &gt; \(c.maxScope)</span>"
                        : " <span class=\"est\">· \(c.observedClass)</span>"
                }
                body += "<th class=\"\(cls)\">\(label)</th>"
            }
            body += "</tr>"

            // Days / estimate summary row.
            body += "<tr><td class=\"rowhdr\">week</td>"
            for c in s.columns {
                let totalMin = c.week.reduce(0) { $0 + $1.estMin }
                body += "<td class=\"meta\">\(c.week.count) days · ~\(totalMin)m</td>"
            }
            body += "</tr>"

            // One row per day index.
            for dayIdx in 0..<maxDays {
                body += "<tr><td class=\"rowhdr\">Day \(dayIdx + 1)</td>"
                let baseDay = dayIdx < s.columns[0].week.count ? s.columns[0].week[dayIdx] : nil
                let baseDaySig = baseDay.map(daySignature) ?? "∅"
                for c in s.columns {
                    if dayIdx < c.week.count {
                        let d = c.week[dayIdx]
                        let changed = !c.isBaseline && daySignature(d) != baseDaySig
                        body += "<td class=\"cell\(changed ? " changed" : "")\">\(renderDayCell(d))</td>"
                    } else {
                        body += "<td class=\"cell empty\">—</td>"
                    }
                }
                body += "</tr>"
            }
            body += "</table></div>"
        }

        return htmlShell(body)
    }

    private func anchor(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-")
         .replacingOccurrences(of: ".", with: "-")
    }

    private func htmlShell(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <title>WorkoutGenerator sweep</title>
        <style>
          :root { color-scheme: dark; }
          body { font: 13px/1.45 -apple-system, system-ui, sans-serif; background:#0f1115; color:#d8dee9; margin:24px; }
          h1 { font-size:20px; } h2 { font-size:16px; margin-top:32px; border-top:1px solid #2a2f3a; padding-top:16px; }
          p.note, .note { color:#8b95a7; }
          a { color:#6cb6ff; }
          .scroll { overflow-x:auto; border:1px solid #2a2f3a; border-radius:8px; }
          table.sweep { border-collapse:separate; border-spacing:0; }
          table.sweep th, table.sweep td { border-right:1px solid #2a2f3a; border-bottom:1px solid #2a2f3a; padding:8px 10px; vertical-align:top; min-width:240px; }
          table.sweep th { background:#1a1e27; position:sticky; top:0; z-index:2; text-align:left; }
          th.rowhdr, td.rowhdr { position:sticky; left:0; background:#161a22; z-index:3; min-width:60px; font-weight:600; color:#aab3c5; }
          th.baseline { background:#243044; }
          td.cell.changed { background:#2a2113; }       /* amber = differs from baseline */
          td.cell.empty { color:#555; text-align:center; }
          td.meta { color:#aab3c5; }
          .daytitle { font-weight:600; color:#e8edf5; margin-bottom:4px; }
          .est { font-weight:400; color:#7d8696; font-size:11px; }
          ul { margin:0; padding-left:16px; } li { margin:2px 0; }
          .ex { color:#e8edf5; } .scheme { color:#b6c2d6; } .tags { color:#8b95a7; font-size:11px; }
          .note { font-size:11px; color:#c08a5a; }
          table.summary { border-collapse:collapse; margin-top:8px; }
          table.summary th, table.summary td { border:1px solid #2a2f3a; padding:6px 12px; text-align:left; }
          .ok { color:#7ee787; } .dead { color:#ff7b72; font-weight:600; }
          .legend { color:#8b95a7; font-size:12px; margin:4px 0 16px; }
        </style></head><body>
        <h1>WorkoutGenerator — controlled variable sweep</h1>
        <p class="legend">Baseline: intermediate · hypertrophy · age 32 · 60 min · full gym · no soreness · empty context · auto strategy.
        Each variable swept one-at-a-time; everything else held at baseline. Fixed seed across columns isolates the variable.
        <span style="background:#2a2113;padding:1px 6px;border-radius:3px;">amber cells</span> differ from the baseline column.
        <b>Anomalies</b> flag a variant <i>expected</i> to change that didn't — the live/DEAD verdict alone can't catch those —
        and a variant whose change class exceeds its allowed blast radius (<b>SCOPE</b>: notes-only &lt; prescription &lt; selection &lt; structure;
        e.g. priorBest, a notes-only knob, swapping an exercise is tier leakage). Variant headers show the observed class.
        Scope: <code>WorkoutGenerator.generateLift</code> in isolation — Planner-level signals (recentHardSportDays, feedback bias, taper, missed-workout reshuffle, lift-day floor) and <code>recentlyPicked</code> (the live cross-day variety mechanism) are NOT exercised here.</p>
        \(body)
        </body></html>
        """
    }
}

// File-scope so the sweep's stored mutation closures don't capture `self`.
private func makeSoreEntry(areas: [String], level: String) -> SorenessEntry {
    var e = SorenessEntry(date: Date())
    e.areas = areas
    e.soreness = level
    e.energy = "normal"
    return e
}
