import EgressEngine
import Foundation
import SwiftData

/// A saved simulation run — the persisted result record.
/// Stores stable primitives (not domain enums) so old records keep loading
/// if the engine's types evolve.
@Model
final class RunRecord {
    @Attribute(.unique)
    var id: UUID
    var date: Date
    var venueName: String
    var venueTypeRaw: String // VenueType.rawValue — stored as a stable primitive
    var score: Int // 0…100 safety score
    var verdictRaw: String // "pass" / "warn" / "fail" (bridged when the Verdict domain lands)
    var clearanceTime: Double // seconds to clear
    var occupancy: Int
    var seed: String // RNG seed for exact reproduction (String avoids UInt64/Int64 limits)
    /// A `RunReportSnapshot` encoded as JSON — the full configuration + metrics the Run Report screen
    /// reads. Defaulted (so SwiftData lightweight-migrates old 7-scalar records, which simply carry
    /// "{}" and render a graceful "details unavailable" report). See `report` for the typed accessor.
    var reportJSON: String = "{}"

    init(
        id: UUID = UUID(),
        date: Date = .now,
        venueName: String,
        venueTypeRaw: String,
        score: Int,
        verdictRaw: String,
        clearanceTime: Double,
        occupancy: Int,
        seed: String,
        reportJSON: String = "{}"
    ) {
        self.id = id
        self.date = date
        self.venueName = venueName
        self.venueTypeRaw = venueTypeRaw
        self.score = score
        self.verdictRaw = verdictRaw
        self.clearanceTime = clearanceTime
        self.occupancy = occupancy
        self.seed = seed
        self.reportJSON = reportJSON
    }

    /// Convenience bridge back to the domain enum (nil if the stored value is unknown).
    var venueType: VenueType? {
        VenueType(rawValue: venueTypeRaw)
    }

    /// The decoded Run Report snapshot, or `nil` for a legacy record with no captured detail. Setting
    /// re-encodes to `reportJSON` (used to patch the coach text in once RALLY's advice resolves).
    var report: RunReportSnapshot? {
        get { RunReportSnapshot(json: reportJSON) }
        set { reportJSON = newValue?.jsonString ?? "{}" }
    }
}

// MARK: - RunReportSnapshot

/// A self-contained, Codable snapshot of everything the Run Report screen shows — captured from the live
/// `RunResult` + `VenueModel` the moment a run resolves, then stored as JSON on the `RunRecord`. Kept
/// independent of the engine's domain types (plain scalars + tiny nested structs) so an old record keeps
/// decoding if those types evolve — exactly the reasoning behind the record's other stored primitives.
struct RunReportSnapshot: Codable, Equatable {
    /// Schema version — lets a future reader recognise and migrate older shapes.
    var version: Int

    // Configuration — the room as it was run.
    var roomWidth: Double        // metres
    var roomHeight: Double       // metres
    var grossArea: Double        // m²
    var netArea: Double          // m²
    var occupancy: Int
    var exits: [ExitInfo]
    var obstacleCount: Int
    var obstacleBreakdown: [ObstacleGroup]
    var hasFire: Bool
    var hasWater: Bool

    // Metrics — how the run went.
    var clearance: Double        // s (the cap if the crowd never fully cleared)
    var clearanceTarget: Double  // s
    var timeCap: Double          // s
    var didClear: Bool
    var peakDensity: Double       // persons·m⁻²
    var casualties: Int
    var trapped: Int
    var atRiskFraction: Double

    // Verdict.
    var verdictRaw: String       // pass / warn / fail
    var score: Int
    var reasons: [String]

    // RALLY's suggested next fix + before→after context for an Apply run.
    var suggestedFixSummary: String?
    var baselineScore: Int?
    var improvement: Int?
    var casualtiesAverted: Int?

    // Coach prose — patched in after RALLY's advice resolves (async), so these start nil.
    var coachHeadline: String?
    var coachBody: String?
    var coachClosing: String?
    var coachSource: String?

    /// One exit as the report lists it: its clear width and which wall it sits on.
    struct ExitInfo: Codable, Equatable {
        var id: Int
        var width: Double        // metres
        var side: String         // Left / Right / Top / Bottom
    }

    /// A count of blocking props of one kind (e.g. 3 × "desk").
    struct ObstacleGroup: Codable, Equatable {
        var kind: String
        var count: Int
    }
}

extension RunReportSnapshot {
    /// Decode from stored JSON. Returns `nil` for legacy "{}" (missing required keys) — the report screen
    /// treats that as "details unavailable" and falls back to the record's stored scalars.
    init?(json: String) {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RunReportSnapshot.self, from: data)
        else { return nil }
        self = decoded
    }

    /// Encode to a compact JSON string for storage (nil coach fields are simply omitted).
    var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// Capture a full snapshot from a resolved run. `hasFire` is passed in (the caller reads live hazard
    /// state) since a fire scenario isn't recoverable from the venue geometry alone. Coach fields are left
    /// nil here and patched later, once RALLY's advice resolves.
    init(result: RunResult, venue: VenueModel, hasFire: Bool) {
        let geometry = venue.geometry
        let metrics = result.metrics
        version = 1
        roomWidth = geometry.worldWidth
        roomHeight = geometry.worldHeight
        grossArea = venue.grossFloorArea
        netArea = venue.netFloorArea
        occupancy = metrics.spawnedCount
        exits = venue.exits.map { exit in
            ExitInfo(id: exit.id, width: exit.width, side: RunReportSnapshot.side(of: exit, in: venue))
        }
        let blocking = venue.obstacles.filter(\.blocksMovement)
        obstacleCount = blocking.count
        obstacleBreakdown = Dictionary(grouping: blocking, by: \.kind)
            .map { ObstacleGroup(kind: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind < $1.kind }
        self.hasFire = hasFire
        hasWater = !venue.water.isEmpty
        clearance = metrics.clearance
        clearanceTarget = metrics.clearanceTarget
        timeCap = metrics.timeCap
        didClear = metrics.clearanceTime != nil
        peakDensity = metrics.peakDensity
        casualties = metrics.casualties
        trapped = metrics.trappedCount
        atRiskFraction = metrics.atRiskFraction
        verdictRaw = result.verdict.level.rawValue
        score = result.score.value
        reasons = result.verdict.reasons.map(\.text)
        suggestedFixSummary = result.fix?.summary
        baselineScore = result.baselineScore
        improvement = result.improvement
        casualtiesAverted = result.casualtiesAverted
        coachHeadline = nil
        coachBody = nil
        coachClosing = nil
        coachSource = nil
    }

    /// Which wall an exit sits on — the edge its centre is nearest to. Orientation-neutral (Top/Bottom/
    /// Left/Right), so it reads the same as the top-down plan the user just watched.
    private static func side(of exit: Exit, in venue: VenueModel) -> String {
        let center = exit.center
        let width = venue.geometry.worldWidth
        let height = venue.geometry.worldHeight
        let distances = [
            ("Left", center.x),
            ("Right", width - center.x),
            ("Top", center.y),
            ("Bottom", height - center.y),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? "—"
    }
}
