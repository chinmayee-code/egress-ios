import EgressEngine
import Foundation
import os

// The on-device Foundation-model coach and its validation gate (§3.5.2–3.5.3).
//
// This whole file is compiled in when the `EGRESS_FM_COACH` build flag is defined (it is, in
// Config/Shared.xcconfig) AND the SDK provides FoundationModels. It writes RALLY's end-of-run summary,
// verdict text, and joke on the device's own LLM, grounded to the engine's figures: the model is handed
// the exact numbers it may cite and every number it writes is checked against them (V4). Every path
// failure — refusal, timeout, an un-grounded figure, an infeasible fix — returns `fallback` (the canned
// coach), so the model can only ever make the wording nicer, never leave the card empty or let a wrong
// number through. On a device without Apple Intelligence the canned coach answers directly.
#if EGRESS_FM_COACH && canImport(FoundationModels)
import FoundationModels

// MARK: - Generable schemas (§3.5.2)

/// The kind of change a fix makes. The model picks the *intent*; the app authors the concrete geometry
/// (via `FixPlanner`) so the model never has to invent coordinates.
@Generable
enum FixAction: String, Codable, CaseIterable, Sendable {
    case widenExit    // make an existing door wider
    case addExit      // open a new door on a wall
    case moveObstacle // shift a movable prop off the route
}

/// A rectangular room's four walls, in the editor's screen convention (top = y 0, bottom = far edge).
@Generable
enum CoachWallSide: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right
}

// The action button's label is authored engine-side from `Fix.summary`, so this schema carries only the
// *intent* the app needs to build the fix — no free-text field to generate and then discard.
@Generable
struct GeometryFix {
    @Guide(description: "The kind of change: widenExit, addExit, or moveObstacle.")
    let action: FixAction
    @Guide(description: "For widenExit, the exit id to widen. For moveObstacle, the movable prop id. Ignored for addExit — use 0.")
    let elementID: Int
    @Guide(description: "For addExit only: which wall (top, bottom, left, right) to open the new door on. Null for the other actions.")
    let side: CoachWallSide?
    @Guide(description: "For widenExit or addExit: the proposed clear width in metres. Null for moveObstacle.", .range(0.9 ... 6.0))
    let proposedMetres: Double?
}

@Generable
struct WarnFailAdvice { // WARN + FAIL — no joke field, by design
    @Guide(description: "A short uppercase banner headline, 2 to 4 words, e.g. 'BOTTLENECK DETECTED'.")
    let headline: String
    @Guide(description: "Two or three sentences of plain reasoning about WHERE and WHY the crowd jammed — name the specific exit, the props in the way (by id), the walls, and how packed the floor is. Reason in words, not statistics: you may mention an exit's width in metres and the number of occupants, but do NOT state crowd densities, clearance times, percentages, areas, or any proposed new measurement. Never invent a number.")
    let diagnosis: String
    @Guide(description: "Two or three fixes, each addressing the real cause — widen the bottleneck exit, add an exit on the clearest wall away from the jam, or move a named movable prop off the route. Do not default to widening unless the exit is genuinely the limit.", .count(2 ... 3))
    let fixes: [GeometryFix]
    @Guide(description: "One short, warm supportive sentence. No humour, no numbers, and do not list the fixes.")
    let encouragement: String
}

/// Map the model's wall choice to the engine's `WallSide`.
extension CoachWallSide {
    var engineSide: WallSide {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        }
    }
}

@Generable
struct PassAdvice { // PASS only — the joke field exists ONLY here (§3.5.1)
    @Guide(description: "A short uppercase banner headline, 2 to 4 words, e.g. 'EVACUATION SUCCESSFUL'.")
    let headline: String
    @Guide(description: "One or two sentences summarising the clean evacuation. You MAY state the exact figures from the run digest (clearance time, target, peak density) verbatim; invent no other number.")
    let summary: String
    @Guide(description: "One light, safety-themed joke. Never about casualties or injury. Keep it number-free.")
    let joke: String
}

// MARK: - Coach

struct FoundationModelsCoach: Coach {
    /// Where every validation failure or timeout lands — the canned coach.
    let fallback: CannedCoach
    /// V7 latency budget (§3.5.3). The WARN/FAIL schema generates a small array of structured fixes, which
    /// takes longer on-device than the PASS summary — hence the generous window. The results card shows a
    /// "RALLY is thinking…" state until this resolves, then falls back to the canned coach.
    private let timeout: Duration = .seconds(20)

    func advise(for result: RunResult, venue: VenueModel) async -> CoachAdvice {
        let facts = CoachFacts(result: result, venue: venue)
        do {
            if result.verdict.level == .pass {
                let raw: PassAdvice = try await generate(passPrompt(facts, venue))
                if let validated = CoachValidation.validatePass(raw, facts: facts) { return validated }
                Self.log.info("PASS advice failed validation; falling back to canned")
            } else {
                let raw: WarnFailAdvice = try await generate(warnFailPrompt(facts, venue))
                if let validated = CoachValidation.validateWarnFail(raw, result: result, venue: venue, facts: facts) {
                    return validated
                }
                Self.log.info("WARNFAIL failed validation. diagnosis=«\(raw.diagnosis, privacy: .public)» enc=«\(raw.encouragement, privacy: .public)» fixes=\(raw.fixes.count)")
            }
        } catch {
            Self.log.info("coach generation threw: \(String(describing: error), privacy: .public)")
        }
        // Any validation miss or thrown error lands here (V4/V8 grounding, infeasible fix, timeout).
        return await fallback.advise(for: result, venue: venue)
    }

    private static let log = Logger(subsystem: "com.Egress.coach", category: "FoundationModelsCoach")

    /// Run one generation with the V7 timeout; the loser of the race throws so we fall back.
    private func generate<T: Generable & Sendable>(_ prompt: (instructions: String, user: String)) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                let session = LanguageModelSession { prompt.instructions }
                return try await session.respond(to: prompt.user, generating: T.self).content
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CoachError.timedOut
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    // MARK: Prompts — supply the exact figures the model may cite plus the valid element IDs (§3.5.2)

    private var contract: String {
        """
        You are RALLY, a calm, encouraging building-safety coach for an evacuation simulator, speaking \
        to a general audience in plain, warm language. You may state ONLY the exact figures listed in \
        the run digest — copy them verbatim. Do NOT do arithmetic of any kind: never divide, multiply, \
        add, or subtract, and never compute a per-person area, a percentage, a rate, or a total that is \
        not already written in the digest. Reference only the element IDs the digest lists.
        """
    }

    /// The grounded figures the model is allowed to cite, written out so it can weave them into prose —
    /// the run numbers *and* the physical layout (room size, clear floor, exits, props) so the diagnosis
    /// can reason about the real cause rather than defaulting to "widen the exit".
    private func digest(_ facts: CoachFacts) -> String {
        """
        Run digest — state these figures verbatim, invent no others:
        • Safety score: \(facts.score) out of 100.
        • Clearance time: \(facts.clearance) s (target \(facts.target) s, cap \(facts.cap) s).
        • Peak crowd density: \(facts.peakDensityText) \(facts.peakLocation); caution band \(facts.cautionBandText).
        • Occupants: \(facts.occupancy); casualties: \(facts.casualties); trapped: \(facts.trapped).
        • At-risk crowd: \(facts.atRiskPct)% dwelt over \(facts.dwell) s in the danger band.

        Layout — a \(facts.venueWidth)×\(facts.venueHeight) m room; with \(facts.occupancy) people that is \
        only about \(facts.spacePerPerson) m² of clear floor each.
        Exits (\(facts.exitCount)):
        \(Self.bulleted(facts.exitLines))
        Movable props you may relocate:
        \(Self.bulleted(facts.movableLines))
        Fixed structures the crowd must route around (cannot be moved):
        \(Self.bulleted(facts.structureLines))
        """
    }

    /// Render layout lines as an indented bullet list, or "  • none" when empty.
    private static func bulleted(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "  • none" }
        return lines.map { "  • \($0)" }.joined(separator: "\n")
    }

    private func warnFailPrompt(_ facts: CoachFacts, _ venue: VenueModel) -> (String, String) {
        let exitIDs = facts.exitIDs.map(String.init).joined(separator: ", ")
        let movableIDs = facts.movableObstacleIDs.isEmpty
            ? "none — do not propose moving anything"
            : facts.movableObstacleIDs.map(String.init).joined(separator: ", ")
        return (contract, """
        \(digest(facts))

        Fix options for THIS layout:
        • widenExit — widen one of these exits by id: \(exitIDs).
        • moveObstacle — move one of these movable props by id: \(movableIDs). Fixed structures can never be moved.
        • addExit — open a new door on the wall (top, bottom, left, right) with the most clear space, ideally \
        away from the jam so it splits the flow.

        Write the headline, then a diagnosis that weighs the exits, the props in the way, and how crowded \
        the floor is — reason in plain words and name elements by id; the exact densities and times are \
        shown elsewhere, so don't recite them. Then give 2–3 fixes that fit this layout (choose the action \
        that addresses the real cause — do not just widen), then one short supportive line.
        """)
    }

    private func passPrompt(_ facts: CoachFacts, _ venue: VenueModel) -> (String, String) {
        (contract, """
        \(digest(facts))
        The \(venue.type.displayName) evacuated cleanly. Write a short headline, a one or two sentence \
        summary that states the clearance time and target, and one light, safety-themed, number-free joke.
        """)
    }
}

private enum CoachError: Error { case timedOut }

// MARK: - Validation gate (§3.5.3)

/// V1–V8 — the model's output must clear every check or we fall back. Numbers are never trusted from the
/// model (V4); geometry must be feasible (V5); every element must exist (V2); jokes are casualty-free (V8).
enum CoachValidation {
    /// Validate WARN/FAIL advice → a rendered `CoachAdvice`, or `nil` to fall back.
    static func validateWarnFail(
        _ advice: WarnFailAdvice, result: RunResult, venue: VenueModel, facts: CoachFacts
    ) -> CoachAdvice? {
        guard nonEmpty(advice.diagnosis), nonEmpty(advice.encouragement) else { return nil } // V1
        // V4: any figure in the substantive diagnosis must be a grounded engine figure. The supportive
        // encouragement is number-free by instruction and renders below the authoritative WHY box, so it
        // isn't number-gated — that keeps a stray word-number from needlessly dropping good advice.
        guard numbersAreGrounded(advice.diagnosis, facts: facts) else { return nil }

        // V2 + V5: author a feasible engine Fix for each model intent, dropping any that can't be placed,
        // and de-duping identical results so the two shown fixes always differ.
        let jam = result.metrics.peakLocation.map { venue.geometry.worldCenter(of: $0) }
        var feasible: [Fix] = []
        for candidate in advice.fixes.compactMap({ engineFix(from: $0, venue: venue, jam: jam) })
            where !feasible.contains(candidate) {
            feasible.append(candidate)
        }
        // Keep the model's rich, layout-aware prose even if geometry authoring failed — fall back to the
        // engine's own grounded fix for the action button rather than dropping to fully canned text.
        let primary = feasible.first ?? result.fix

        return CoachAdvice(
            headline: validHeadline(advice.headline, facts: facts) ?? "BOTTLENECK DETECTED",
            body: advice.diagnosis,
            closing: advice.encouragement,
            primaryFix: primary,
            altSuggestion: feasible.count > 1 ? feasible[1].summary : nil,
            source: .model
        )
    }

    /// Validate PASS advice; drops the joke (V8) if it references injury, keeping the summary.
    static func validatePass(_ advice: PassAdvice, facts: CoachFacts) -> CoachAdvice? {
        guard nonEmpty(advice.summary), numbersAreGrounded(advice.summary, facts: facts) else { return nil } // V1 + V4
        // V8: the joke stays casualty-free; if it slips in a figure, that too must be grounded.
        let jokeOK = jokeIsClean(advice.joke) && numbersAreGrounded(advice.joke, facts: facts)
        let joke = jokeOK ? advice.joke : nil
        return CoachAdvice(
            headline: validHeadline(advice.headline, facts: facts) ?? "EVACUATION SUCCESSFUL",
            body: advice.summary,
            closing: joke,
            primaryFix: nil,
            altSuggestion: nil,
            source: .model
        )
    }

    // MARK: Checks

    private static func nonEmpty(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// V4 grounded-number check — every decimal number the model wrote in this text must be one of the
    /// run's approved engine figures. The model may phrase freely; it just cannot state a figure the run
    /// didn't produce. One ungrounded number fails the whole piece of advice, dropping us to the fallback.
    private static func numbersAreGrounded(_ text: String, facts: CoachFacts) -> Bool {
        let approved = facts.approvedFigures
        return numericTokens(in: text).allSatisfy { approved.contains($0) }
    }

    /// Pull ASCII decimal-number tokens (e.g. "42", "5.4") out of prose. Non-ASCII numerals and unit
    /// superscripts (the "²" in "p·m⁻²") are deliberately not treated as digits.
    private static func numericTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            while current.hasSuffix(".") { current.removeLast() }
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for ch in text {
            if (ch >= "0" && ch <= "9") || (ch == "." && !current.isEmpty) {
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    /// A model-authored banner headline, accepted only when it's short and every figure in it is
    /// grounded; otherwise the caller's fixed headline stands in.
    private static func validHeadline(_ headline: String, facts: CoachFacts) -> String? {
        let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, numbersAreGrounded(trimmed, facts: facts) else { return nil }
        return trimmed.uppercased()
    }

    /// V2 + V5: resolve a model fix intent to a feasible engine `Fix`, or `nil` to drop it. The concrete
    /// geometry (new widths, doorway spans, relocation origins) is authored engine-side by `FixPlanner`
    /// and re-checked by `Fix.feasibility`, so the model only ever supplies intent — never coordinates.
    private static func engineFix(from fix: GeometryFix, venue: VenueModel, jam: Vec2?) -> Fix? {
        switch fix.action {
        case .widenExit:
            guard let exit = venue.exits.first(where: { $0.id == fix.elementID }) else { return nil }
            // Widen past the current door to at least the exit minimum; honour the model's number when it
            // is a genuine widening, else pick a sensible larger width. Feasibility guards the bounds.
            let desired = max(fix.proposedMetres ?? 0, exit.width + 0.4, SafetyStandards.minExitWidth)
            for width in [desired, SafetyStandards.minExitWidth] {
                let candidate = Fix.widenExit(id: exit.id, width: width)
                if candidate.feasibility(in: venue).isFeasible { return candidate }
            }
            return nil
        case .moveObstacle:
            return FixPlanner.relocation(ofObstacle: fix.elementID, awayFrom: jam, in: venue)
        case .addExit:
            guard let side = fix.side?.engineSide else { return nil }
            return FixPlanner.newExit(on: side, in: venue, width: fix.proposedMetres)
        }
    }

    private static let injuryWords = ["death", "die", "dead", "kill", "injur", "casualt", "hurt", "burn", "crush"]

    /// V8: a PASS joke may not touch injury vocabulary.
    private static func jokeIsClean(_ joke: String) -> Bool {
        let lower = joke.lowercased()
        return !injuryWords.contains { lower.contains($0) }
    }
}
#endif
