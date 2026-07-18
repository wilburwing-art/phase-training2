// CoachTools.swift — Anthropic tool definitions + decoder.
//
// Phase 13c ships one tool: `propose_plan_edits`. The wire shape is a
// flat dict with an `op` discriminator + only the fields each op needs.
// Dates use yyyy-MM-dd (model-friendly) — the decoder resolves them to
// DayPlan.id by matching against the current WeekPlan.
//
// We never let the coach mutate state directly. The output of the
// decoder is a [PlanEdit], which the drawer feeds to PlanStore.propose
// to build a PlanDiff. UI surfaces the diff; the user accepts or rejects.

import Foundation

// MARK: - Tool definition (sent to Anthropic in `tools` array)

enum CoachTools {
    static let proposePlanEdits: AnthropicTool = {
        let opEnum: [String] = ["move", "swap_kind", "protect_day", "shorten", "add_session", "remove_session"]
        let kindEnum: [String] = ["lift", "sport", "rest", "event"]

        let opItem = JSONSchema(type: "object")
        opItem.properties = [
            "op":         JSONSchema(type: "string", description: "Operation kind.",                              enumValues: opEnum),
            "fromDate":   JSONSchema(type: "string", description: "yyyy-MM-dd. Source day for move."),
            "toDate":     JSONSchema(type: "string", description: "yyyy-MM-dd. Target day for move."),
            "date":       JSONSchema(type: "string", description: "yyyy-MM-dd. Day to edit (used by all ops except move)."),
            "kind":       JSONSchema(type: "string", description: "Day kind for swap_kind / add_session.",         enumValues: kindEnum),
            "title":      JSONSchema(type: "string", description: "Display title for swap_kind / add_session (optional)."),
            "eventTitle": JSONSchema(type: "string", description: "Event title for protect_day."),
            "toMinutes":  JSONSchema(type: "integer", description: "New duration for shorten (15-180)."),
            "sportSlug":  JSONSchema(type: "string", description: "Sport identifier when swap_kind / add_session targets kind=sport, e.g. 'cycling', 'climbing', 'mountain-biking'. Sets which sport the day is so the user can log it."),
            "note":       JSONSchema(type: "string", description: "For a sport session: the ride/session prescription the user reads on the day and logs after — e.g. 'MTB: 4×8min threshold climbs, 90s spin recovery, Z2 between'. Use this to actually put a sport workout on a day.")
        ]
        opItem.required = ["op"]

        let editsArray = JSONSchema(type: "array", description: "One or more plan operations. Order doesn't matter; the app applies them as a batch.")
        editsArray.items = opItem

        let reasoning = JSONSchema(type: "string", description: "One short sentence explaining why, in the user's voice. Will appear above the diff card.")

        let root = JSONSchema(type: "object")
        root.properties = ["edits": editsArray, "reasoning": reasoning]
        root.required = ["edits", "reasoning"]

        return AnthropicTool(
            name: "propose_plan_edits",
            description: """
            Propose one or more edits to the user's current week plan. The user must accept or reject the proposal — calling this tool does NOT apply the change. Only call this when the user explicitly asks for a change to their plan ("move", "swap", "add", "drop", "make easier", "lighter", "harder", "more sport", etc.). Don't volunteer edits when the user is just asking questions.

            Address days by their calendar date (yyyy-MM-dd) — the user's current plan window is in the per-turn context.
            """,
            inputSchema: root
        )
    }()

    static let proposeWorkoutChanges: AnthropicTool = {
        let opEnum = ["swap", "adjust"]

        let changeItem = JSONSchema(type: "object")
        changeItem.properties = [
            "op":           JSONSchema(type: "string", description: "Change kind.", enumValues: opEnum),
            "fromName":     JSONSchema(type: "string", description: "swap: exercise to replace (match by name, case-insensitive)."),
            "toName":       JSONSchema(type: "string", description: "swap: new exercise. Free text — use a common name (e.g. 'Goblet Squat')."),
            "exerciseName": JSONSchema(type: "string", description: "adjust: exercise to modify (match by name)."),
            "sets":         JSONSchema(type: "integer", description: "adjust: new set count (1-20)."),
            "reps":         JSONSchema(type: "string", description: "adjust: new reps target ('5', '8-12', 'AMRAP')."),
            "restSeconds":  JSONSchema(type: "integer", description: "adjust: new rest between sets (15-600 s)."),
            "reason":       JSONSchema(type: "string", description: "Optional one-phrase reason for THIS row (overrides top-level reasoning).")
        ]
        changeItem.required = ["op"]

        let changesArray = JSONSchema(type: "array", description: "One or more workout changes for the targeted day's session.")
        changesArray.items = changeItem

        let reasoning = JSONSchema(type: "string", description: "One short sentence explaining why. Will appear above the diff card.")
        // Build 99: chat can now edit any day in the current week plan, not
        // just today. The per-turn context renders every day's exercises so
        // the model can address Tuesday's Push or Thursday's Pull by name.
        let date = JSONSchema(type: "string", description: "Optional yyyy-MM-dd target day. Defaults to today. Must match a day in the current week plan that has a generated workout (lift); for sport / rest / event days there's nothing to edit.")

        let root = JSONSchema(type: "object")
        root.properties = ["changes": changesArray, "reasoning": reasoning, "date": date]
        root.required = ["changes", "reasoning"]

        return AnthropicTool(
            name: "propose_workout_changes",
            description: """
            Propose exercise-level changes to a lift workout (swap an exercise for another, or adjust sets/reps/rest). The user accepts or rejects via UI — this tool does NOT apply changes. Call ONLY when:
              - The user explicitly asks for a workout-level change ("swap X for Y", "drop deadlifts on Thursday", "fewer sets on bench", "lighter reps").
              - The targeted day has a generated workout in the CURRENT CONTEXT. If you target sport / rest / event, the proposal will be rejected — refuse instead.
              - For TODAY specifically, if an active workout is in progress, suggest the user finish first. Edits to OTHER days are fine during an active session.

            Pass `date` (yyyy-MM-dd) to target a non-today day. Omit it when the user means today. Address exercises by their CURRENT NAME as shown in the context. The decoder matches case-insensitively.
            """,
            inputSchema: root
        )
    }()

    static let proposeMemoryUpdate: AnthropicTool = {
        let opEnum = ["add_dislike", "remove_dislike", "add_constraint", "remove_constraint"]

        let opItem = JSONSchema(type: "object")
        opItem.properties = [
            "op":    JSONSchema(type: "string", description: "Memory op.", enumValues: opEnum),
            "value": JSONSchema(type: "string", description: "The dislike or constraint text. Short — one line.")
        ]
        opItem.required = ["op", "value"]

        let opsArray = JSONSchema(type: "array", description: "One or more memory operations.")
        opsArray.items = opItem

        let reasoning = JSONSchema(type: "string", description: "One short sentence explaining why. Shown above the diff card.")

        let root = JSONSchema(type: "object")
        root.properties = ["ops": opsArray, "reasoning": reasoning]
        root.required = ["ops", "reasoning"]

        return AnthropicTool(
            name: "propose_memory_update",
            description: """
            Propose APPEND-ONLY changes to the user's training memory (dislikes + constraints lists). The user must accept or reject — this tool does NOT mutate memory directly. Call ONLY when the user clearly states a preference or limitation worth remembering forever:
              - "I don't like burpees" → add_dislike
              - "no overhead pressing — bad shoulder" → add_constraint
              - "scratch that, I'm fine with burpees now" → remove_dislike

            Do NOT propose updates to typed fields (sports, primary sport, age, equipment, experience). Those have dedicated UIs in Profile.
            """,
            inputSchema: root
        )
    }()

    static let buildWorkout: AnthropicTool = {
        let focusEnum = [
            "push", "pull", "legs",
            "upper", "lower",
            "fullBodyA", "fullBodyB"
        ]
        let intensityEnum = ["deload", "normal", "push"]
        // Movement-pattern slugs the planner's slot recipes anchor on. The
        // LLM picks from this fixed list so it can't hallucinate a pattern
        // that doesn't exist in coach.db.
        let patternEnum = [
            "squat", "hip-hinge",
            "horizontal-push", "vertical-push",
            "horizontal-pull", "vertical-pull",
            "anti-extension", "anti-rotation", "anti-lateral-flexion",
            "loaded-carry", "calf-raise", "single-leg-squat",
            "scapular-protraction", "scapular-retraction",
            "elbow-extension", "elbow-flexion"
        ]

        let targetWeightItem = JSONSchema(type: "object")
        targetWeightItem.properties = [
            "exerciseName": JSONSchema(type: "string", description: "Exercise name to target (matched case-insensitively against the user's logged history)."),
            "weightLb":     JSONSchema(type: "number", description: "Prescribed top-set weight in pounds. 1-1000.")
        ]
        targetWeightItem.required = ["exerciseName", "weightLb"]

        let prescriptionItem = JSONSchema(type: "object")
        prescriptionItem.properties = [
            "exerciseName": JSONSchema(type: "string", description: "Exercise name to target (matched case-insensitively)."),
            "rpe":          JSONSchema(type: "string", description: "Target effort. Single number ('9') or range ('7-8'). Scale 1-10 where 10 = true failure."),
            "tempo":        JSONSchema(type: "string", description: "Eccentric-pause-concentric-pause as 4-digit string ('3-1-1-0') or with 'X' for explosive ('2-0-X-0').")
        ]
        prescriptionItem.required = ["exerciseName"]

        let emphasizeArr = JSONSchema(type: "array", description: "Movement patterns to prioritize. Empty = auto.")
        emphasizeArr.items = JSONSchema(type: "string", enumValues: patternEnum)
        let deprioritizeArr = JSONSchema(type: "array", description: "Movement patterns to skip in this workout (e.g. squat when knee is sore). Empty = none.")
        deprioritizeArr.items = JSONSchema(type: "string", enumValues: patternEnum)
        let targetArr = JSONSchema(type: "array", description: "Per-exercise top-set weight prescriptions. Used for explicit deload / push cues (\"bench at 90%\"). Empty = use the user's last-week weights via progressive overload.")
        targetArr.items = targetWeightItem
        let prescriptionArr = JSONSchema(type: "array", description: "Per-exercise RPE + tempo prescriptions. Use to coach intensity + control beyond sets x reps. Either field optional. Empty = focus-based defaults apply.")
        prescriptionArr.items = prescriptionItem

        let root = JSONSchema(type: "object")
        root.properties = [
            "focus":               JSONSchema(type: "string", description: "Day shape for the workout.", enumValues: focusEnum),
            "durationMinutes":     JSONSchema(type: "integer", description: "Session budget. 15-180. Defaults to the user's declared session length when omitted."),
            "emphasizePatterns":   emphasizeArr,
            "deprioritizePatterns": deprioritizeArr,
            "intensityBias":       JSONSchema(type: "string", description: "Volume bias relative to the user's normal set count.", enumValues: intensityEnum),
            "targetWeightOverrides": targetArr,
            "exercisePrescriptions": prescriptionArr,
            "reasoning":           JSONSchema(type: "string", description: "One short sentence in the coach's voice — why this workout, this focus, this intensity. Shown above the workout when rendered.")
        ]
        root.required = ["focus", "reasoning"]

        return AnthropicTool(
            name: "build_workout",
            description: """
            Build a workout tailored to the user's current context. The deterministic generator picks specific exercises from coach.db; YOU pick the parameters that shape its choices. Call this when the user asks for a workout ("build me a workout", "what should I do today", "give me a push day", "i'm tired, something light").

            Reason from the CURRENT CONTEXT: body / strength / muscle balance / pattern frequency / recovery trend. Examples of good strategy choices:
              - Last 4w shows 12 push sessions and 0 pull → focus 'pull', emphasize 'horizontal-pull' + 'vertical-pull'.
              - Knee reported sore 3 days running → focus 'push' or 'pull', deprioritize 'squat' + 'single-leg-squat'.
              - Bench velocity flat 4w → focus 'push', emphasize 'horizontal-push' (the user gets a variation via the generator's stagnation swap).
              - User said "i'm fried" / "yesterday was brutal" → intensityBias 'deload'.

            Don't pick exercises directly — the tool's parameters only — the generator does that part. Don't ask follow-up questions if context is sufficient; just call build_workout.
            """,
            inputSchema: root
        )
    }()

    /// Tools offered to the conversational coach (CoachDrawer). Excludes
    /// `buildWorkout`: the chat drawer has no card to render a freshly built
    /// workout (the conversation store has no build-workout proposal setter),
    /// so the model calling it produced an empty bubble — the tool call was
    /// silently dropped by the drawer's `default:` case. `buildWorkout` stays
    /// available to the request + refinement flows, which pass it explicitly
    /// and render the result. Surfacing it in chat behind a preview card is a
    /// follow-up.
    static let chat: [AnthropicTool] = [proposePlanEdits, proposeWorkoutChanges, proposeMemoryUpdate]
}

// MARK: - Anthropic tool wire shape

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// Reference-type so it can recurse (items + properties hold more JSONSchema).
/// Tool definitions are built once at app launch, so the cost is fine.
final class JSONSchema: Encodable {
    let type: String
    var description: String?
    var enumValues: [String]?
    var properties: [String: JSONSchema]?
    var required: [String]?
    var items: JSONSchema?

    init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }

    enum CodingKeys: String, CodingKey {
        case type, description, properties, required, items
        case enumValues = "enum"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(enumValues, forKey: .enumValues)
        try c.encodeIfPresent(properties, forKey: .properties)
        try c.encodeIfPresent(required, forKey: .required)
        try c.encodeIfPresent(items, forKey: .items)
    }
}

// MARK: - Decoded tool input

/// Mirror of one row inside the `edits` array. Optional fields kept lax —
/// the model can fill only what each op needs. `decode` upstream rejects
/// rows missing required fields.
struct ProposalOp: Codable, Hashable {
    var op: String
    var fromDate: String?
    var toDate: String?
    var date: String?
    var kind: String?
    var title: String?
    var eventTitle: String?
    var toMinutes: Int?
    /// Sport identifier for a sport session (swap_kind / add_session with
    /// kind == sport), e.g. "cycling", "climbing", "mountain-biking".
    var sportSlug: String?
    /// Read-and-log prescription shown on a sport day (e.g. an MTB ride's
    /// structure). Only meaningful when kind == sport.
    var note: String?
}

struct ProposalToolInput: Codable {
    var edits: [ProposalOp]
    var reasoning: String?
}

// MARK: - Decoded proposal attached to a CoachMessage

/// What the drawer carries on the assistant turn that produced a tool call.
/// `status` lets us persist whether the user accepted / rejected, so the
/// card doesn't re-prompt after app relaunch.
struct CoachProposal: Codable, Hashable {
    enum Status: String, Codable { case pending, applied, rejected }
    var id: UUID = UUID()
    var ops: [ProposalOp]
    var reasoning: String?
    var status: Status = .pending
}

// MARK: - Memory ops (Phase 13f)

struct MemoryOp: Codable, Hashable {
    var op: String      // add_dislike | remove_dislike | add_constraint | remove_constraint
    var value: String
}

struct MemoryProposalToolInput: Codable {
    var ops: [MemoryOp]
    var reasoning: String?
}

// MARK: - build_workout tool (Phase 13g / build 68)

struct TargetWeightItem: Codable, Hashable {
    var exerciseName: String
    var weightLb: Double
}

/// One entry in build_workout's exercisePrescriptions array — per-exercise
/// RPE + tempo coach overrides. Either field optional; the LLM can set
/// just RPE for one lift and just tempo for another.
struct ExercisePrescriptionItem: Codable, Hashable {
    var exerciseName: String
    var rpe: String?
    var tempo: String?
}

struct BuildWorkoutInput: Codable {
    var focus: String?
    var durationMinutes: Int?
    var emphasizePatterns: [String]?
    var deprioritizePatterns: [String]?
    var intensityBias: String?
    var targetWeightOverrides: [TargetWeightItem]?
    var exercisePrescriptions: [ExercisePrescriptionItem]?
    var reasoning: String?
}

/// What the drawer carries on a build_workout turn. The strategy is what
/// the generator consumes; reasoning is what the user reads.
struct CoachBuildWorkoutProposal: Codable, Hashable {
    enum Status: String, Codable { case pending, applied, rejected }
    var id: UUID = UUID()
    /// The decoded strategy ready to hand to WorkoutGenerator.
    var strategy: GeneratorStrategy
    var reasoning: String?
    var status: Status = .pending
}

struct CoachMemoryProposal: Codable, Hashable {
    enum Status: String, Codable { case pending, applied, rejected }
    var id: UUID = UUID()
    var ops: [MemoryOp]
    var reasoning: String?
    var status: Status = .pending
}

// MARK: - Decode bytes → ProposalToolInput → [PlanEdit]

enum CoachToolDecoder {
    /// Parse the raw tool input JSON (assembled from input_json_delta chunks
    /// during the SSE stream) into a CoachProposal.
    static func decodeProposal(from data: Data) -> CoachProposal? {
        guard let payload = try? JSONDecoder().decode(ProposalToolInput.self, from: data) else { return nil }
        return CoachProposal(ops: payload.edits, reasoning: payload.reasoning)
    }

    /// Decode a propose_memory_update payload.
    static func decodeMemoryProposal(from data: Data) -> CoachMemoryProposal? {
        guard let payload = try? JSONDecoder().decode(MemoryProposalToolInput.self, from: data) else { return nil }
        return CoachMemoryProposal(ops: payload.ops, reasoning: payload.reasoning)
    }

    /// Decode a build_workout payload into a GeneratorStrategy the
    /// WorkoutGenerator can consume. Validates the focus + intensityBias
    /// enums; unknown values fall through to defaults so a hallucinated
    /// "leg_day" focus doesn't crash — it just falls back to .auto.
    static func decodeBuildWorkout(from data: Data) -> CoachBuildWorkoutProposal? {
        guard let payload = try? JSONDecoder().decode(BuildWorkoutInput.self, from: data) else { return nil }
        let focus: WorkoutFocus? = payload.focus.flatMap { WorkoutFocus(rawValue: $0) }
        let intensity: GeneratorStrategy.IntensityBias =
            payload.intensityBias.flatMap { GeneratorStrategy.IntensityBias(rawValue: $0) } ?? .normal
        // Clamp + sanitize. Bad values from the LLM should degrade
        // gracefully, not corrupt downstream prescriptions.
        let hard = TrainingConstraints.sessionMinutesHardRange
        let duration = payload.durationMinutes.map { min(hard.upperBound, max(hard.lowerBound, $0)) }
        let overrides: [String: Double] = Dictionary(
            uniqueKeysWithValues: (payload.targetWeightOverrides ?? [])
                .filter { $0.weightLb > 0 && $0.weightLb <= 1000 }
                .map { ($0.exerciseName.lowercased(), $0.weightLb) }
        )
        // Pull RPE + tempo prescriptions into the two override maps,
        // clamped to plausible ranges — RPE caps at 10 (the scale's true
        // ceiling, via the generator's shared capRPE) and tempo components
        // at 10 s. Strings the parsers don't understand pass through
        // unchanged: clamp to safe ranges, don't reject the payload.
        var rpeOverrides: [String: String] = [:]
        var tempoOverrides: [String: String] = [:]
        for item in payload.exercisePrescriptions ?? [] {
            let key = item.exerciseName.lowercased()
            if let r = item.rpe, !r.isEmpty { rpeOverrides[key] = capRPE(r, to: 10) }
            if let t = item.tempo, !t.isEmpty { tempoOverrides[key] = clampTempo(t) }
        }
        let strategy = GeneratorStrategy(
            focus: focus,
            durationMinutes: duration,
            emphasizePatterns: payload.emphasizePatterns ?? [],
            deprioritizePatterns: payload.deprioritizePatterns ?? [],
            targetWeightOverrides: overrides,
            rpeOverrides: rpeOverrides,
            tempoOverrides: tempoOverrides,
            intensityBias: intensity
        )
        return CoachBuildWorkoutProposal(strategy: strategy, reasoning: payload.reasoning)
    }

    /// Clamp an LLM tempo string's numeric components to sane seconds (≤ 10).
    /// "99-99-99-99" becomes "10-10-10-10"; "2-0-X-0" passes through ('X' =
    /// explosive). Anything that isn't a 4-part dash string passes through
    /// unchanged — same philosophy as capRPE: clamp, don't reject.
    private static func clampTempo(_ raw: String) -> String {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return raw }
        return parts.map { part -> String in
            guard let seconds = Double(String(part)), seconds > 10 else { return String(part) }
            return "10"
        }.joined(separator: "-")
    }

    /// Decode a propose_workout_changes payload. Caller passes today's
    /// yyyy-MM-dd as `fallbackDate` so the proposal carries an unambiguous
    /// target day even when the model omits the optional `date` field.
    /// When the model provides `date`, that wins — chat can edit any day
    /// in the current plan, not just today.
    static func decodeWorkoutProposal(from data: Data, fallbackDate: String) -> CoachWorkoutProposal? {
        guard let payload = try? JSONDecoder().decode(WorkoutProposalToolInput.self, from: data) else { return nil }
        let resolved = payload.date?.isEmpty == false ? payload.date! : fallbackDate
        return CoachWorkoutProposal(
            dateString: resolved,
            changes: payload.changes,
            reasoning: payload.reasoning
        )
    }

    /// Convert proposal ops into PlanEdit, resolving dates against the
    /// supplied plan. Skips ops that don't match any day (no UUID resolution).
    static func planEdits(for proposal: CoachProposal, in plan: WeekPlan) -> [PlanEdit] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        func day(for ymd: String?) -> DayPlan? {
            guard let ymd, let target = df.date(from: ymd) else { return nil }
            return plan.days.first { cal.isDate($0.date, inSameDayAs: target) }
        }

        var out: [PlanEdit] = []
        for op in proposal.ops {
            switch op.op {
            case "move":
                guard let src = day(for: op.fromDate),
                      let dstYmd = op.toDate,
                      let dstDate = df.date(from: dstYmd) else { continue }
                out.append(.move(dayId: src.id, toDate: dstDate))

            case "swap_kind":
                guard let target = day(for: op.date),
                      let kindRaw = op.kind,
                      let kind = DayKind(rawValue: kindRaw) else { continue }
                let title = op.title ?? defaultTitle(for: kind)
                let sport = (kind == .sport) ? op.sportSlug.map(Sport.resolve(slug:)) : nil
                let note = (kind == .sport) ? op.note : nil
                out.append(.swapKind(dayId: target.id, to: kind, title: title, routineId: nil, sport: sport, note: note))

            case "protect_day":
                guard let target = day(for: op.date),
                      let evt = op.eventTitle, !evt.isEmpty else { continue }
                out.append(.protectDay(dayId: target.id, eventTitle: evt))

            case "shorten":
                guard let target = day(for: op.date),
                      let mins = op.toMinutes else { continue }
                let hard = TrainingConstraints.sessionMinutesHardRange
                let clamped = max(hard.lowerBound, min(hard.upperBound, mins))
                out.append(.shorten(dayId: target.id, toMinutes: clamped))

            case "add_session":
                guard let dateStr = op.date, let date = df.date(from: dateStr),
                      let kindRaw = op.kind, let kind = DayKind(rawValue: kindRaw) else { continue }
                let title = op.title ?? defaultTitle(for: kind)
                let sport = (kind == .sport) ? op.sportSlug.map(Sport.resolve(slug:)) : nil
                let note = (kind == .sport) ? op.note : nil
                out.append(.addSession(date: date, kind: kind, title: title, routineId: nil, sport: sport, note: note))

            case "remove_session":
                guard let target = day(for: op.date) else { continue }
                out.append(.removeSession(dayId: target.id))

            default:
                continue
            }
        }
        return out
    }

    private static func defaultTitle(for kind: DayKind) -> String {
        switch kind {
        case .lift:  return "Lift"
        case .sport: return "Sport"
        case .rest:  return "Rest"
        case .event: return "Event"
        }
    }
}
