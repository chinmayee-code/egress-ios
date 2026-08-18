import Foundation

// MARK: - WallSide

/// One of a rectangular venue's four boundary walls, in the editor's screen convention: `top` is y = 0,
/// `bottom` is y = worldHeight, `left` is x = 0, `right` is x = worldWidth (matching the preset comments,
/// e.g. an exit at y = worldHeight is "bottom-centre"). Used to say where a new exit should go.
public enum WallSide: String, CaseIterable, Sendable, Equatable {
    case top, bottom, left, right

    /// Human phrase for the coach's prose and the fix summary, e.g. "the bottom wall".
    public var label: String {
        switch self {
        case .top: "the top wall"
        case .bottom: "the bottom wall"
        case .left: "the left wall"
        case .right: "the right wall"
        }
    }
}

// MARK: - FixPlanner

/// Authors the *geometry* for RALLY's non-trivial fixes so the on-device model never has to invent
/// coordinates (§2.13, §3.5.2). The model chooses the *intent* — "move that movable prop", "add an exit
/// on the left wall" — and this turns it into a concrete, in-bounds, non-overlapping `Fix` that still
/// passes `Fix.feasibility` before it is ever offered. Every placement is engine-grounded and
/// reproducible; the coach only phrases it. Pure geometry, no AI, so it is unit-testable and available
/// on every device (including the canned-coach path).
public enum FixPlanner {
    /// Which wall an exit sits on, or `nil` if it isn't flush to a boundary.
    public static func wall(of exit: Exit, in venue: VenueModel) -> WallSide? {
        let W = venue.geometry.worldWidth, H = venue.geometry.worldHeight
        let tol = 0.01
        if abs(exit.a.y) < tol, abs(exit.b.y) < tol { return .top }
        if abs(exit.a.y - H) < tol, abs(exit.b.y - H) < tol { return .bottom }
        if abs(exit.a.x) < tol, abs(exit.b.x) < tol { return .left }
        if abs(exit.a.x - W) < tol, abs(exit.b.x - W) < tol { return .right }
        return nil
    }

    /// Move a *movable* prop to the feasible, non-overlapping spot that sits farthest from the jam (or,
    /// with no recorded jam, the nearest exit) — i.e. genuinely clear of the crowd's route. Returns `nil`
    /// for a fixed prop, an unknown id, or a venue with no free space to move it to.
    public static func relocation(ofObstacle id: Int, awayFrom jam: Vec2?, in venue: VenueModel) -> Fix? {
        guard let obstacle = venue.obstacles.first(where: { $0.id == id }), obstacle.isRelocatable else { return nil }
        let size = obstacle.size
        let W = venue.geometry.worldWidth, H = venue.geometry.worldHeight
        guard size.x <= W, size.y <= H else { return nil }

        let target = jam ?? venue.exits.first?.center ?? Vec2(W / 2, H / 2)
        let originalCentre = obstacle.origin + size / 2
        let originalDist = originalCentre.distance(to: target)
        let margin = SafetyStandards.bodyRadius
        let step = max(venue.geometry.cellSize * 2, 0.25)

        var best: (origin: Vec2, dist: Double)?
        var x = 0.0
        while x + size.x <= W + 1e-9 {
            var y = 0.0
            while y + size.y <= H + 1e-9 {
                let origin = Vec2(x, y)
                defer { y += step }
                // Must be a real move, feasible, and not dropped onto anything else.
                guard origin.distance(to: obstacle.origin) > step * 0.5 else { continue }
                let candidate = Fix.relocateObstacle(id: id, origin: origin)
                guard candidate.feasibility(in: venue).isFeasible else { continue }
                guard !overlapsSomething(origin: origin, size: size, excluding: id, in: venue, margin: margin) else { continue }
                let dist = (origin + size / 2).distance(to: target)
                if best == nil || dist > best!.dist { best = (origin, dist) }
            }
            x += step
        }

        guard let chosen = best, chosen.dist >= originalDist else { return nil }
        return Fix.relocateObstacle(id: id, origin: chosen.origin)
    }

    /// Open a new exit on `side`, centred on the clear stretch farthest from any existing door on that
    /// wall (so it splits the flow), at least the exit minimum wide. Returns `nil` if the wall is too
    /// short or wholly blocked by structure.
    public static func newExit(on side: WallSide, in venue: VenueModel, width: Double? = nil) -> Fix? {
        let W = venue.geometry.worldWidth, H = venue.geometry.worldHeight
        let wallLength = (side == .left || side == .right) ? H : W
        let w = min(max(width ?? SafetyStandards.minExitWidth, SafetyStandards.minExitWidth), wallLength)
        guard w >= SafetyStandards.minExitWidth, wallLength >= w else { return nil }

        let half = w / 2
        let margin = SafetyStandards.bodyRadius
        let step = max(venue.geometry.cellSize, 0.25)
        let existing = venue.exits.compactMap { axisPosition(of: $0, on: side, W: W, H: H) }
        let clearGap = half + 0.6 // keep new door a sensible gap from any door already on this wall

        var best: (centre: Double, clearance: Double)?
        var c = half
        while c <= wallLength - half + 1e-9 {
            defer { c += step }
            guard existing.allSatisfy({ abs($0 - c) >= clearGap }) else { continue }
            guard !wallStripBlocked(side: side, centre: c, half: half, W: W, H: H, venue: venue) else { continue }
            let clearance = existing.map { abs($0 - c) }.min() ?? wallLength
            if best == nil || clearance > best!.clearance { best = (c, clearance) }
        }

        guard let chosen = best else { return nil }
        let (a, b) = endpoints(side: side, centre: chosen.centre, half: half, W: W, H: H)
        let fix = Fix.addExit(a: a, b: b)
        return fix.feasibility(in: venue).isFeasible ? fix : nil
    }

    // MARK: Geometry helpers

    /// The position of an exit's centre along a wall's axis, or `nil` if the exit isn't on that wall.
    private static func axisPosition(of exit: Exit, on side: WallSide, W: Double, H: Double) -> Double? {
        let tol = 0.01
        switch side {
        case .top: return (abs(exit.a.y) < tol && abs(exit.b.y) < tol) ? exit.center.x : nil
        case .bottom: return (abs(exit.a.y - H) < tol && abs(exit.b.y - H) < tol) ? exit.center.x : nil
        case .left: return (abs(exit.a.x) < tol && abs(exit.b.x) < tol) ? exit.center.y : nil
        case .right: return (abs(exit.a.x - W) < tol && abs(exit.b.x - W) < tol) ? exit.center.y : nil
        }
    }

    /// The doorway span (a…b) for a new exit of half-width `half` centred at `centre` along `side`.
    private static func endpoints(side: WallSide, centre: Double, half: Double, W: Double, H: Double) -> (Vec2, Vec2) {
        switch side {
        case .top: return (Vec2(centre - half, 0), Vec2(centre + half, 0))
        case .bottom: return (Vec2(centre - half, H), Vec2(centre + half, H))
        case .left: return (Vec2(0, centre - half), Vec2(0, centre + half))
        case .right: return (Vec2(W, centre - half), Vec2(W, centre + half))
        }
    }

    /// Whether a blocking prop sits flush against the doorway's interior strip — you can't put a door
    /// where furniture or structure is pressed to the wall.
    private static func wallStripBlocked(side: WallSide, centre: Double, half: Double, W: Double, H: Double, venue: VenueModel) -> Bool {
        let depth = 0.5
        let lo: Vec2, hi: Vec2
        switch side {
        case .top: lo = Vec2(centre - half, 0); hi = Vec2(centre + half, depth)
        case .bottom: lo = Vec2(centre - half, H - depth); hi = Vec2(centre + half, H)
        case .left: lo = Vec2(0, centre - half); hi = Vec2(depth, centre + half)
        case .right: lo = Vec2(W - depth, centre - half); hi = Vec2(W, centre + half)
        }
        for o in venue.obstacles where o.blocksMovement {
            if boxesOverlap(lo, hi, o.origin, o.origin + o.size) { return true }
        }
        return false
    }

    /// Whether a candidate box (with a body-radius margin) intersects any other blocking prop, exit
    /// doorway, wall segment, or water zone.
    private static func overlapsSomething(origin: Vec2, size: Vec2, excluding id: Int, in venue: VenueModel, margin: Double) -> Bool {
        let aMin = origin - Vec2(margin, margin)
        let aMax = origin + size + Vec2(margin, margin)
        for o in venue.obstacles where o.id != id && o.blocksMovement {
            if boxesOverlap(aMin, aMax, o.origin, o.origin + o.size) { return true }
        }
        for e in venue.exits {
            let (lo, hi) = spanBox(e.a, e.b, pad: margin)
            if boxesOverlap(aMin, aMax, lo, hi) { return true }
        }
        for wall in venue.walls {
            let (lo, hi) = spanBox(wall.a, wall.b, pad: margin)
            if boxesOverlap(aMin, aMax, lo, hi) { return true }
        }
        for zone in venue.water {
            if boxesOverlap(aMin, aMax, zone.origin, zone.origin + zone.size) { return true }
        }
        return false
    }

    private static func boxesOverlap(_ aMin: Vec2, _ aMax: Vec2, _ bMin: Vec2, _ bMax: Vec2) -> Bool {
        aMin.x < bMax.x && aMax.x > bMin.x && aMin.y < bMax.y && aMax.y > bMin.y
    }

    /// A thin span (a…b) grown into a padded axis-aligned box.
    private static func spanBox(_ a: Vec2, _ b: Vec2, pad: Double) -> (Vec2, Vec2) {
        (Vec2(min(a.x, b.x) - pad, min(a.y, b.y) - pad),
         Vec2(max(a.x, b.x) + pad, max(a.y, b.y) + pad))
    }
}
