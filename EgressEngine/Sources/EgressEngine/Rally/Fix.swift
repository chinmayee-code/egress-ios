import Foundation

// MARK: - Fix

/// A concrete, geometry-grounded change RALLY can propose to a venue (§2.13) — the honest core of the
/// coach, independent of any AI prose. Each case names an element and the exact new measurement, so a
/// fix can be shown ("Widen Exit 0 to 1.2 m"), feasibility-checked, applied to produce a new venue,
/// and re-run to prove the score improved.
public enum Fix: Equatable, Sendable {
    /// Widen an existing exit symmetrically about its centre to `width` metres.
    case widenExit(id: Int, width: Double)
    /// Add a new exit doorway spanning `a`…`b`.
    case addExit(a: Vec2, b: Vec2)
    /// Move a relocatable obstacle so its lower corner sits at `origin`.
    case relocateObstacle(id: Int, origin: Vec2)

    /// A one-line description in the coach's voice, with real units.
    public var summary: String {
        switch self {
        case let .widenExit(id, width): "Widen Exit \(id) to \(Self.metres(width))"
        case let .addExit(a, b): "Add a \(Self.metres(a.distance(to: b))) exit"
        case let .relocateObstacle(id, _): "Move obstacle \(id) clear of the route"
        }
    }

    /// V5 geometry check (§2.13): a fix that violates a minimum width, leaves the venue bounds, or moves
    /// a fixed element is dropped rather than applied.
    public func feasibility(in venue: VenueModel) -> FixFeasibility {
        switch self {
        case let .widenExit(id, width):
            guard let exit = venue.exits.first(where: { $0.id == id }) else {
                return .rejected("no exit \(id) to widen")
            }
            guard width >= SafetyStandards.minExitWidth else {
                return .rejected("below the \(Self.metres(SafetyStandards.minExitWidth)) exit minimum")
            }
            let widened = Self.widen(exit, to: width)
            guard Self.within(widened.a, venue.geometry), Self.within(widened.b, venue.geometry) else {
                return .rejected("would extend past the venue bounds")
            }
            return .feasible
        case let .addExit(a, b):
            guard a.distance(to: b) >= SafetyStandards.minExitWidth else {
                return .rejected("below the \(Self.metres(SafetyStandards.minExitWidth)) exit minimum")
            }
            guard Self.within(a, venue.geometry), Self.within(b, venue.geometry) else {
                return .rejected("outside the venue bounds")
            }
            return .feasible
        case let .relocateObstacle(id, origin):
            guard let obstacle = venue.obstacles.first(where: { $0.id == id }) else {
                return .rejected("no obstacle \(id) to move")
            }
            guard obstacle.isRelocatable else { return .rejected("that element is fixed in place") }
            guard Self.within(origin, venue.geometry),
                  Self.within(origin + obstacle.size, venue.geometry) else
            {
                return .rejected("would leave the venue bounds")
            }
            return .feasible
        }
    }

    /// Produce a new venue with the fix applied. Assumes feasibility was already checked.
    public func apply(to venue: VenueModel) -> VenueModel {
        var updated = venue
        switch self {
        case let .widenExit(id, width):
            updated.exits = venue.exits.map { $0.id == id ? Self.widen($0, to: width) : $0 }
        case let .addExit(a, b):
            let nextID = (venue.exits.map(\.id).max() ?? -1) + 1
            updated.exits = venue.exits + [Exit(id: nextID, a: a, b: b)]
        case let .relocateObstacle(id, origin):
            updated.obstacles = venue.obstacles.map {
                guard $0.id == id else { return $0 }
                var moved = $0
                moved.origin = origin
                return moved // keep simClass + kind — only the origin moves
            }
        }
        return updated
    }

    /// Widen an exit symmetrically about its centre, along its own axis (degenerate spans go horizontal).
    static func widen(_ exit: Exit, to width: Double) -> Exit {
        let axis = exit.b - exit.a
        let direction = axis.length > 1e-9 ? axis.normalized : Vec2(1, 0)
        let half = direction * (width / 2)
        return Exit(id: exit.id, a: exit.center - half, b: exit.center + half)
    }

    private static func within(_ point: Vec2, _ geometry: GridGeometry) -> Bool {
        point.x >= 0 && point.x <= geometry.worldWidth && point.y >= 0 && point.y <= geometry.worldHeight
    }

    private static func metres(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) m"
    }
}

// MARK: - FixFeasibility

/// The outcome of a V5 feasibility check — feasible, or rejected with a human reason.
public enum FixFeasibility: Equatable, Sendable {
    case feasible
    case rejected(String)
    public var isFeasible: Bool {
        self == .feasible
    }
}
