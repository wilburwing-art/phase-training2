// EvalRigExporter — convert a GeneratedWorkout into the eval-rig workout JSON
// shape so phase-training2 sessions can be graded by ~/repos/eval-rig.
//
// JSON-on-disk is the contract per the eval-rig README — no live coupling. The
// exporter joins CoachDatabase for prime_mover / implement / swap_alternates
// (none of which are stored on GeneratedExercise), combines rpe + tempo +
// notes into a single `load_intent` string, and embeds the user's most-recent
// SorenessEntry into the eval-rig `context.soreness` block so the rubric's
// soreness gate (Q9) has the same signal the generator did.
//
// Output shape matches `~/repos/eval-rig/schemas/workout.schema.json`. DEBUG
// builds expose an "Export to eval-rig" affordance that calls
// `exportToFile(_:to:)`; non-DEBUG builds can use the same function from
// future headless tooling.

import Foundation

enum EvalRigExporter {
    /// Encode a workout to a Data blob matching the eval-rig workout schema.
    /// Caller chooses how to persist (file, share sheet, log).
    static func encode(
        workout: GeneratedWorkout,
        memory: TrainingMemory,
        archetype: String = "intermediate-male-hypertrophy-upper-push",
        timeBudgetMinutes: Int? = nil,
        catalog: CoachDatabase = .shared
    ) throws -> Data {
        let payload = buildPayload(
            workout: workout,
            memory: memory,
            archetype: archetype,
            timeBudgetMinutes: timeBudgetMinutes,
            catalog: catalog
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(payload)
    }

    /// Write the encoded JSON to `directory/<id>.json`. Creates the directory
    /// if needed. Returns the URL written.
    @discardableResult
    static func exportToFile(
        workout: GeneratedWorkout,
        memory: TrainingMemory,
        archetype: String = "intermediate-male-hypertrophy-upper-push",
        timeBudgetMinutes: Int? = nil,
        to directory: URL,
        catalog: CoachDatabase = .shared
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encode(
            workout: workout,
            memory: memory,
            archetype: archetype,
            timeBudgetMinutes: timeBudgetMinutes,
            catalog: catalog
        )
        let id = workoutId(workout: workout, memory: memory)
        let url = directory.appendingPathComponent("\(id).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Default directory for eval-rig exports — sibling to the app's other
    /// Application Support data so test users can find it without diving
    /// into a sandboxed Documents path.
    static func defaultExportDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("PhaseTraining", isDirectory: true)
            .appendingPathComponent("eval-rig-export", isDirectory: true)
    }

    // MARK: - Encoding payload

    private struct Payload: Encodable {
        let id: String
        let generator_version: String
        let archetype: String
        let generated_at: Date
        let context: Context?
        let exercises: [ExercisePayload]
    }

    private struct Context: Encodable {
        let time_budget_min: Int?
        let soreness: [String: String]?
    }

    private struct ExercisePayload: Encodable {
        let order: Int
        let name: String
        let role: String
        let prime_mover: String
        let movement_pattern: String
        let implement: String
        let warm_up_sets: [WarmUpPayload]?
        let working_sets: [SetPayload]
        let swap_alternates: [SwapPayload]?
    }

    private struct SetPayload: Encodable {
        let reps: String
        let load_intent: String?
        let rest_seconds: Int?
    }

    private struct WarmUpPayload: Encodable {
        let reps: Int
        let load_pct_1rm: Int
        let load_intent: String?
        let rest_seconds: Int
    }

    private struct SwapPayload: Encodable {
        let name: String
        let implement: String
    }

    private static func buildPayload(
        workout: GeneratedWorkout,
        memory: TrainingMemory,
        archetype: String,
        timeBudgetMinutes: Int?,
        catalog: CoachDatabase
    ) -> Payload {
        let exercises = workout.exercises.enumerated().map { idx, ex in
            renderExercise(ex, order: idx + 1, catalog: catalog)
        }

        let soreness = mostRecentSoreness(memory: memory)
        let hasContext = timeBudgetMinutes != nil || soreness != nil
        let context: Context? = hasContext
            ? Context(time_budget_min: timeBudgetMinutes, soreness: soreness)
            : nil

        return Payload(
            id: workoutId(workout: workout, memory: memory),
            generator_version: "phasetraining-\(memory.planInputsHash.prefix(8))",
            archetype: archetype,
            generated_at: Date(),
            context: context,
            exercises: exercises
        )
    }

    private static func renderExercise(
        _ ex: GeneratedExercise,
        order: Int,
        catalog: CoachDatabase
    ) -> ExercisePayload {
        // CoachDatabase joins for the fields GeneratedExercise doesn't carry.
        let muscles = catalog.musclesForExercise(ex.exerciseId)
        let primeMover = muscles.first(where: { $0.role == "primary" })?.slug
            ?? muscles.first?.slug
            ?? "unknown"

        let implementSlug = inferImplement(exerciseId: ex.exerciseId, catalog: catalog)
        let pattern = normalizePattern(ex.pattern, primeMover: primeMover, role: ex.isCompound ? "compound" : "isolation")

        // Expand the flat `sets: Int` + `reps: String` into N working set
        // entries, each carrying the same load_intent (combination of rpe +
        // tempo + notes — whatever was set).
        let intent = combinedLoadIntent(rpe: ex.rpe, tempo: ex.tempo, notes: ex.notes)
        let workingSets = (0..<max(1, ex.sets)).map { _ in
            SetPayload(
                reps: ex.reps,
                load_intent: intent.isEmpty ? nil : intent,
                rest_seconds: ex.restSeconds
            )
        }

        // exercise_substitutions → at most 3 swaps. Use inferImplement (not
        // raw modality) so substitutes whose modality is "strength" still
        // resolve via name + equipment fallback. The full coach.db has 535
        // substitution rows across 170 exercises, but using
        // `implementFromModality` alone filtered all of them out because
        // most rows are tagged modality="strength" (kind of work, not
        // equipment).
        let subs = catalog.substitutes(forExerciseId: ex.exerciseId).prefix(3)
        let swaps: [SwapPayload] = subs.map { sub in
            SwapPayload(
                name: sub.exercise.name,
                implement: inferImplement(exerciseId: sub.exercise.id, catalog: catalog)
            )
        }

        let warmUps: [WarmUpPayload]? = ex.warmUpSets.flatMap { wus in
            wus.isEmpty ? nil : wus.map { w in
                WarmUpPayload(
                    reps: w.reps,
                    load_pct_1rm: w.loadPctOfWorking,
                    load_intent: "warm-up · \(w.loadPctOfWorking)% of working weight",
                    rest_seconds: w.restSeconds
                )
            }
        }

        return ExercisePayload(
            order: order,
            name: ex.name,
            role: ex.isCompound ? "compound" : "isolation",
            prime_mover: primeMover,
            movement_pattern: pattern,
            implement: implementSlug,
            warm_up_sets: warmUps,
            working_sets: workingSets,
            swap_alternates: swaps.isEmpty ? nil : swaps
        )
    }

    // MARK: - Field derivation

    /// Combine the three intent-bearing fields phase-training2's generator
    /// emits separately ("RPE 8", "tempo 3-1-1-0", "Target: 225x5") into the
    /// single `load_intent` string the eval-rig schema expects. The eval-rig
    /// rubric's Q6 only needs "contains RPE/RIR/%" — joining the strings
    /// without separator transformation preserves that.
    private static func combinedLoadIntent(rpe: String?, tempo: String?, notes: String?) -> String {
        var parts: [String] = []
        if let rpe, !rpe.isEmpty { parts.append("RPE \(rpe)") }
        if let tempo, !tempo.isEmpty { parts.append("tempo \(tempo)") }
        if let notes, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    /// Phase-training2's `pattern` is the movement-pattern slug the generator
    /// filled from (e.g. "horizontal-push"). The eval-rig schema's enum is
    /// narrower — push-family patterns plus side/rear-delt + tricep-isolation
    /// for the rubric's Q2 check. When the generator's slug doesn't map, we
    /// derive the pattern from prime_mover + role: an isolation exercise on
    /// delt-lateral is "side-delt" (regardless of the generator's
    /// hip-abduction tagging on lateral raises in coach.db); an isolation
    /// on triceps is "tricep-isolation" (regardless of "elbow-extension").
    /// This lets the hypertrophy accessory layer's lateral raise + rope
    /// pushdown actually surface to Q2 as side-delt + tricep-isolation
    /// instead of both collapsing to "other".
    private static func normalizePattern(_ pattern: String?, primeMover: String, role: String) -> String {
        // Honor an explicit eval-rig-compatible pattern first.
        let allowed: Set<String> = [
            "horizontal-push", "vertical-push", "incline-push",
            "side-delt", "rear-delt", "tricep-isolation",
        ]
        if let pattern, allowed.contains(pattern) { return pattern }

        // Muscle-derived overrides on isolation exercises — the rubric's Q2
        // is asking "is there isolation work targeting side-delts / triceps",
        // which is a muscle + role question, not a motion question.
        let pm = primeMover.lowercased()
        if role == "isolation" {
            if pm.contains("delt-lateral") || pm.contains("side-delt") || pm == "shoulders" && (pattern ?? "").contains("abduction") {
                return "side-delt"
            }
            if pm.contains("delt-posterior") || pm.contains("rear-delt") {
                return "rear-delt"
            }
            if pm.contains("triceps") {
                return "tricep-isolation"
            }
        }

        // Generator-pattern overrides: elbow-extension is phase-training2's
        // canonical tricep slug for both compound (close-grip pushup) and
        // isolation work. We only emit "tricep-isolation" for the latter to
        // keep the rubric's distinction honest.
        if role == "isolation" && pattern == "elbow-extension" { return "tricep-isolation" }

        return "other"
    }

    /// Infer the eval-rig `implement` slug from the exercise's modality,
    /// name, and required equipment. Most exercises in coach.db have
    /// modality="strength" (kind of work, not equipment) so the modality
    /// alone resolves only a minority. The name probe is the most reliable
    /// signal — "Dumbbell Floor Press" → dumbbell — followed by the
    /// equipment table (which uses inconsistent slug forms: "barbell"
    /// singular but "dumbbells" plural). Fall back to "machine" rather
    /// than throwing so the workout still validates.
    private static func inferImplement(exerciseId: Int, catalog: CoachDatabase) -> String {
        guard let ex = catalog.exercise(id: exerciseId) else { return "machine" }
        if let imp = implementFromModality(ex.modality) { return imp }

        // Name probe — most reliable for "<Equipment> X" / "X (Equipment)" patterns.
        if let imp = implementFromName(ex.name) { return imp }

        // Equipment table probe — coach.db uses both singular and plural
        // forms ("barbell" but "dumbbells"). Accept both.
        let required = catalog.requiredEquipmentSlugs(forExerciseIds: [exerciseId])[exerciseId] ?? []
        if required.contains("barbell")    || required.contains("barbells")    { return "barbell" }
        if required.contains("dumbbell")   || required.contains("dumbbells")   { return "dumbbell" }
        if required.contains("kettlebell") || required.contains("kettlebells") { return "kettlebell" }
        if required.contains("cable")      || required.contains("cables")      { return "cable" }

        // Only-bodyweight or no equipment at all → bodyweight.
        let nonBodyweight = required.subtracting(["bodyweight", "pull-up-bar", "dip-station", "bench", "floor", "rings"])
        if nonBodyweight.isEmpty { return "bodyweight" }

        return "machine"
    }

    /// Substring-match common implements in the exercise name. "Dumbbell
    /// Floor Press" → dumbbell. Catches the majority of mis-categorized
    /// strength-modality rows. Returns nil when no implement word is found.
    private static func implementFromName(_ name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("dumbbell") { return "dumbbell" }
        if lower.contains("barbell")  { return "barbell" }
        if lower.contains("kettlebell") { return "kettlebell" }
        if lower.contains("cable")    { return "cable" }
        // "Bodyweight X" is rare in the catalog; users say "Push-Up" not
        // "Bodyweight Push-Up". Only fire on the explicit prefix.
        if lower.hasPrefix("bodyweight ") { return "bodyweight" }
        return nil
    }

    private static func implementFromModality(_ modality: String?) -> String? {
        switch modality?.lowercased() {
        case "barbell":    return "barbell"
        case "dumbbell":   return "dumbbell"
        case "machine":    return "machine"
        case "cable":      return "cable"
        case "bodyweight": return "bodyweight"
        case "kettlebell": return "kettlebell"
        default:           return nil
        }
    }

    /// Embed the user's most recent soreness check-in (≤ 36h old) so the
    /// eval-rig grader's Q9 has the same signal the generator did. The
    /// `entry.areas` strings are muscle-bucket slugs ("chest", "back",
    /// "quads") after the build-107 cleanup; map them to the eval-rig
    /// soreness severity strings via the entry's overall `soreness`
    /// field. Returns nil when no recent check-in exists.
    private static func mostRecentSoreness(memory: TrainingMemory) -> [String: String]? {
        let cutoff = Date().addingTimeInterval(-36 * 60 * 60)
        guard let entry = memory.soreness
                .filter({ $0.date >= cutoff })
                .max(by: { $0.date < $1.date }),
              !entry.areas.isEmpty
        else { return nil }
        let level = mapSeverity(entry.soreness)
        var out: [String: String] = [:]
        for area in entry.areas {
            out[area] = level
        }
        return out.isEmpty ? nil : out
    }

    /// Canonical soreness vocabulary is none|mild|high (SorenessEntry.soreness,
    /// produced by SorenessCheckInSheet). Map straight through and treat any
    /// unknown/nil as "mild" — a present soreness signal we can't classify
    /// should still down-regulate, matching WorkoutGenerator's "mild"||"high"
    /// cap. Never emit "moderate": it isn't in the vocabulary and the generator
    /// no longer recognizes it.
    private static func mapSeverity(_ raw: String?) -> String {
        switch raw {
        case "none": return "none"
        case "high": return "high"
        default:     return "mild"
        }
    }

    /// Stable id for the exported workout. Combines the user's plan-inputs
    /// hash with a short timestamp suffix so re-exports from the same
    /// generation don't collide on disk.
    private static func workoutId(workout: GeneratedWorkout, memory: TrainingMemory) -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        return "pt2-\(memory.planInputsHash.prefix(8))-\(stamp)"
    }
}
