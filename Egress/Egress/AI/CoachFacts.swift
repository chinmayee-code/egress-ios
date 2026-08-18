import EgressEngine
import Foundation

/// The engine numbers the coach is allowed to cite, pulled from a finished run and pre-formatted once so
/// the canned prose and the model's number-substitution both read from the *same* grounded source
/// (§3.5.2 anti-hallucination). Nothing here is invented — every field traces to `Metrics`/`Verdict` or
/// a `SafetyStandards` constant.
struct CoachFacts: Equatable {
    let clearance: Int          // seconds to clear, rounded
    let target: Int             // clearance target for this venue type, seconds
    let cap: Int                // the run's time cap, seconds
    let peakDensity: Double     // worst smoothed density, p·m⁻²
    let peakLocation: String    // human phrase, e.g. "near Exit 0"
    let atRiskPct: Int          // % of the crowd that spent too long in the at-risk band
    let dwell: Int              // at-risk dwell threshold, seconds
    let casualties: Int
    let trapped: Int
    let occupancy: Int
    let cautionBand: Double     // the caution density band, p·m⁻² (5.0)
    let score: Int
    let venueName: String
    let exitCount: Int          // exits in this layout — a citable, grounded count
    let exitIDs: [Int]          // exit identifiers the model may reference by number (e.g. "Exit 0")

    // Spatial context (§2.13) — the grounded layout the model reasons about so its fixes fit THIS room,
    // not a generic "widen the exit". Every number below is folded into `approvedFigures`.
    let venueWidth: Double      // room extent, metres
    let venueHeight: Double     // room extent, metres
    let netFloor: Double        // clear floor area people actually share, m²
    let spacePerPerson: Double  // netFloor ÷ occupancy, precomputed so the model never divides for itself
    let movableObstacleIDs: [Int] // props the coach may propose relocating (relocatable only)
    let citableObstacleIDs: [Int] // every blocking prop/structure id — the model names these in prose
    let exitLines: [String]     // "Exit 1: 1.6 m wide on the bottom wall"
    let movableLines: [String]  // "prop 13: 1.0×1.0 m, movable, near Exit 1"
    let structureLines: [String] // "structure 10: 6.0×1.3 m, fixed, near Exit 1"
    private let spatialNumbers: [Double] // every citable spatial figure, for the grounding gate

    init(result: RunResult, venue: VenueModel) {
        let m = result.metrics
        clearance = Int(m.clearance.rounded())
        target = Int(m.clearanceTarget.rounded())
        cap = Int(m.timeCap.rounded())
        peakDensity = (m.peakDensity * 10).rounded() / 10
        atRiskPct = Int((m.atRiskFraction * 100).rounded())
        dwell = Int(SimConstants.atRiskDwell.rounded())
        casualties = m.casualties
        trapped = m.trappedCount
        occupancy = m.spawnedCount
        cautionBand = SafetyStandards.densityAtRisk
        score = result.score.value
        venueName = venue.name
        exitCount = venue.exits.count
        exitIDs = venue.exits.map(\.id)
        peakLocation = Self.locate(m.peakLocation, in: venue)

        // Spatial context — layout the model reasons about.
        venueWidth = Self.round1(venue.geometry.worldWidth)
        venueHeight = Self.round1(venue.geometry.worldHeight)
        netFloor = Self.round1(venue.netFloorArea)
        spacePerPerson = occupancy > 0 ? Self.round1(venue.netFloorArea / Double(occupancy)) : 0
        let blocking = venue.obstacles.filter(\.blocksMovement)
        movableObstacleIDs = blocking.filter(\.isRelocatable).map(\.id)
        citableObstacleIDs = blocking.map(\.id)
        exitLines = venue.exits.map { exit in
            let wall = FixPlanner.wall(of: exit, in: venue)?.label ?? "an interior span"
            return "Exit \(exit.id): \(Self.fmt(exit.width)) m wide on \(wall)"
        }
        movableLines = blocking.filter(\.isRelocatable).map { obstacle in
            "prop \(obstacle.id): \(Self.fmt(obstacle.size.x))×\(Self.fmt(obstacle.size.y)) m, movable, "
                + Self.nearestExitPhrase(to: obstacle, in: venue)
        }
        structureLines = blocking.filter { !$0.isRelocatable }.map { obstacle in
            "structure \(obstacle.id): \(Self.fmt(obstacle.size.x))×\(Self.fmt(obstacle.size.y)) m, fixed, "
                + Self.nearestExitPhrase(to: obstacle, in: venue)
        }
        spatialNumbers = [venueWidth, venueHeight, netFloor, spacePerPerson]
            + venue.exits.map(\.width)
            + blocking.flatMap { [$0.size.x, $0.size.y] }
    }

    /// Round to one decimal, matching the metre precision the card and prompt show.
    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    /// Format a metre figure the way the digest states it (one decimal, no unit).
    private static func fmt(_ value: Double) -> String { String(format: "%.1f", value) }

    /// "near Exit 1" (multi-exit) or "by the exit" (single) — grounded to a real exit id.
    private static func nearestExitPhrase(to obstacle: Obstacle, in venue: VenueModel) -> String {
        let centre = obstacle.origin + obstacle.size / 2
        guard let nearest = venue.exits.min(by: {
            $0.center.distance(to: centre) < $1.center.distance(to: centre)
        }) else { return "on the floor" }
        return venue.exits.count == 1 ? "by the exit" : "near Exit \(nearest.id)"
    }

    /// Formatted density with its unit, e.g. "5.4 p·m⁻²".
    var peakDensityText: String { String(format: "%.1f p·m⁻²", peakDensity) }
    /// The caution band with its unit.
    var cautionBandText: String { String(format: "%.1f p·m⁻²", cautionBand) }

    /// Every numeric string the on-device model is allowed to state in its prose — built *only* from
    /// grounded engine values (`Metrics`/`Verdict`/`SafetyStandards`). The validation gate (§3.5.3, V4)
    /// checks that each number the model writes is a member of this set, so the model can phrase the
    /// summary freely yet can never state a figure the run didn't actually produce.
    var approvedFigures: Set<String> {
        var figures: Set<String> = []
        // Run-specific integer figures (seconds, counts, percentages, score) plus exit identifiers,
        // which the model references by number in phrases like "Exit 0". The two survivor counts
        // (occupants who did / didn't make it) are natural things to say, so they're pre-approved too.
        let survivors = max(0, occupancy - casualties)
        let escapedOfTrapped = max(0, occupancy - trapped)
        // Element tallies the model naturally states ("3 fixed structures", "4 movable props").
        let structureCount = citableObstacleIDs.count - movableObstacleIDs.count
        let counts = [100, structureCount, movableObstacleIDs.count, citableObstacleIDs.count]
        for value in [clearance, target, cap, casualties, trapped, occupancy, atRiskPct, dwell, score,
                      exitCount, survivors, escapedOfTrapped] + counts + exitIDs + citableObstacleIDs {
            figures.insert("\(value)") // 100 = the score scale's fixed max, stated as "out of 100"
        }
        // Densities in the units the card shows (1 decimal) plus their whole-number reading.
        for density in [peakDensity, cautionBand] {
            Self.insertNumberForms(density, into: &figures)
        }
        // Spatial figures (room extent, clear floor, exit widths, prop sizes) so the model can weave the
        // real layout into its diagnosis without tripping the grounding gate.
        for number in spatialNumbers {
            Self.insertNumberForms(number, into: &figures)
        }
        // Citable safety constants the prompt contract references (Fruin bands + minimum clear widths).
        let constants = [
            SafetyStandards.densityComfortable, SafetyStandards.densityCongested,
            SafetyStandards.densityAtRisk, SafetyStandards.densityCrush,
            SafetyStandards.minDoorWidth, SafetyStandards.minExitWidth, SafetyStandards.minCorridorWidth
        ]
        for constant in constants {
            Self.insertNumberForms(constant, into: &figures)
        }
        return figures
    }

    /// Add a double both as the "%.1f" reading the card uses (e.g. "5.0") and, when whole, its bare
    /// integer form (e.g. "5"), so either spelling of a grounded figure passes validation.
    private static func insertNumberForms(_ value: Double, into set: inout Set<String>) {
        set.insert(String(format: "%.1f", value))
        if value == value.rounded() {
            set.insert(String(Int(value)))
        }
    }

    /// Turn the worst-density cell into a phrase relative to the nearest exit — grounded, but readable
    /// ("near Exit 0"), not a raw grid coordinate. Falls back gracefully when there's no peak or no exit.
    private static func locate(_ cell: GridCoord?, in venue: VenueModel) -> String {
        guard let cell else { return "on the floor" }
        let point = venue.geometry.worldCenter(of: cell)
        guard let nearest = venue.exits.min(by: {
            $0.center.distance(to: point) < $1.center.distance(to: point)
        }) else {
            return "on the floor"
        }
        return venue.exits.count == 1 ? "at the exit" : "near Exit \(nearest.id)"
    }
}
