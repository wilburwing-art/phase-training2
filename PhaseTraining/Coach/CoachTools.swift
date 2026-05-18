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
        let kindEnum: [String] = ["lift", "sport", "mobility", "rest", "event"]

        let opItem = JSONSchema(type: "object")
        opItem.properties = [
            "op":         JSONSchema(type: "string", description: "Operation kind.",                              enumValues: opEnum),
            "fromDate":   JSONSchema(type: "string", description: "yyyy-MM-dd. Source day for move."),
            "toDate":     JSONSchema(type: "string", description: "yyyy-MM-dd. Target day for move."),
            "date":       JSONSchema(type: "string", description: "yyyy-MM-dd. Day to edit (used by all ops except move)."),
            "kind":       JSONSchema(type: "string", description: "Day kind for swap_kind / add_session.",         enumValues: kindEnum),
            "title":      JSONSchema(type: "string", description: "Display title for swap_kind / add_session (optional)."),
            "eventTitle": JSONSchema(type: "string", description: "Event title for protect_day."),
            "toMinutes":  JSONSchema(type: "integer", description: "New duration for shorten (15-180).")
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

    static let all: [AnthropicTool] = [proposePlanEdits]
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

// MARK: - Decode bytes → ProposalToolInput → [PlanEdit]

enum CoachToolDecoder {
    /// Parse the raw tool input JSON (assembled from input_json_delta chunks
    /// during the SSE stream) into a CoachProposal.
    static func decodeProposal(from data: Data) -> CoachProposal? {
        guard let payload = try? JSONDecoder().decode(ProposalToolInput.self, from: data) else { return nil }
        return CoachProposal(ops: payload.edits, reasoning: payload.reasoning)
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
                out.append(.swapKind(dayId: target.id, to: kind, title: title, routineId: nil))

            case "protect_day":
                guard let target = day(for: op.date),
                      let evt = op.eventTitle, !evt.isEmpty else { continue }
                out.append(.protectDay(dayId: target.id, eventTitle: evt))

            case "shorten":
                guard let target = day(for: op.date),
                      let mins = op.toMinutes else { continue }
                let clamped = max(15, min(180, mins))
                out.append(.shorten(dayId: target.id, toMinutes: clamped))

            case "add_session":
                guard let dateStr = op.date, let date = df.date(from: dateStr),
                      let kindRaw = op.kind, let kind = DayKind(rawValue: kindRaw) else { continue }
                let title = op.title ?? defaultTitle(for: kind)
                out.append(.addSession(date: date, kind: kind, title: title, routineId: nil))

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
        case .lift:     return "Lift"
        case .sport:    return "Sport"
        case .mobility: return "Mobility"
        case .rest:     return "Rest"
        case .event:    return "Event"
        }
    }
}
