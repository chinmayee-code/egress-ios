@testable import EgressEngine
import Testing

@Suite("FixPlanner")
struct FixPlannerTests {
    /// A 5 m × 5 m hall (20×20 cells at 0.25 m) with one exit centred on the bottom wall and one prop.
    private func venue(relocatable: Bool = true) -> VenueModel {
        VenueModel(
            id: 0, name: "hall", type: .concertHall,
            geometry: GridGeometry(size: GridSize(width: 20, height: 20)),
            exits: [Exit(id: 0, a: Vec2(2.25, 5.0), b: Vec2(2.75, 5.0))], // 0.5 m door, bottom wall
            obstacles: [Obstacle(id: 9, origin: Vec2(2, 2), size: Vec2(1, 1), isRelocatable: relocatable)]
        )
    }

    // MARK: relocation

    @Test("Relocation returns a feasible, in-bounds move for a movable prop")
    func relocationFeasible() {
        let v = venue()
        guard let fix = FixPlanner.relocation(ofObstacle: 9, awayFrom: Vec2(2.5, 4.8), in: v) else {
            Issue.record("expected a relocation"); return
        }
        guard case let .relocateObstacle(id, origin) = fix else {
            Issue.record("expected relocateObstacle, got \(fix)"); return
        }
        #expect(id == 9)
        #expect(fix.feasibility(in: v).isFeasible)
        #expect(origin.x >= 0 && origin.y >= 0)
        #expect(origin.x + 1 <= v.geometry.worldWidth + 1e-9)
        #expect(origin.y + 1 <= v.geometry.worldHeight + 1e-9)
    }

    @Test("Relocation moves the prop no closer to the jam than it started")
    func relocationAwayFromJam() {
        let v = venue()
        let jam = Vec2(2.5, 4.8)
        let before = Vec2(2.5, 2.5).distance(to: jam) // original centre = origin(2,2) + half(0.5,0.5)
        guard case let .relocateObstacle(_, origin)? = FixPlanner.relocation(ofObstacle: 9, awayFrom: jam, in: v) else {
            Issue.record("expected a relocation"); return
        }
        let after = (origin + Vec2(0.5, 0.5)).distance(to: jam)
        #expect(after >= before - 1e-9)
    }

    @Test("Relocation does not drop the prop on top of another obstacle")
    func relocationAvoidsOverlap() {
        // Fill most of the room with fixed structure, leaving only the top-left corner clear.
        let v = VenueModel(
            id: 0, name: "hall", type: .concertHall,
            geometry: GridGeometry(size: GridSize(width: 20, height: 20)),
            exits: [Exit(id: 0, a: Vec2(2.25, 5.0), b: Vec2(2.75, 5.0))],
            obstacles: [
                Obstacle(id: 9, origin: Vec2(0, 0), size: Vec2(1, 1), isRelocatable: true),
                Obstacle(id: 1, origin: Vec2(1.2, 0), size: Vec2(3.8, 5), isRelocatable: false) // blocks the right 3.8 m
            ]
        )
        guard case let .relocateObstacle(_, origin)? = FixPlanner.relocation(ofObstacle: 9, awayFrom: Vec2(2.5, 5), in: v) else {
            return // no feasible spot is an acceptable outcome; if one IS returned it must not overlap
        }
        // The chosen box must not intersect the fixed structure at x ≥ 1.2.
        #expect(origin.x + 1 <= 1.2 + 1e-9)
    }

    @Test("A fixed obstacle cannot be relocated")
    func relocationRejectsFixed() {
        #expect(FixPlanner.relocation(ofObstacle: 9, awayFrom: nil, in: venue(relocatable: false)) == nil)
    }

    @Test("Relocating an unknown obstacle id returns nil")
    func relocationUnknownID() {
        #expect(FixPlanner.relocation(ofObstacle: 404, awayFrom: nil, in: venue()) == nil)
    }

    // MARK: newExit

    @Test("A new exit lands on the requested wall, feasible and at least the exit minimum wide")
    func newExitOnLeftWall() {
        let v = venue()
        guard let fix = FixPlanner.newExit(on: .left, in: v, width: nil) else {
            Issue.record("expected a new exit"); return
        }
        guard case let .addExit(a, b) = fix else { Issue.record("expected addExit, got \(fix)"); return }
        #expect(fix.feasibility(in: v).isFeasible)
        #expect(a.distance(to: b) >= SafetyStandards.minExitWidth - 1e-9)
        #expect(abs(a.x) < 1e-9 && abs(b.x) < 1e-9) // left wall → x == 0
    }

    @Test("A new exit on an occupied wall avoids the existing door")
    func newExitAvoidsExisting() {
        let v = venue() // existing 0.5 m door centred at x=2.5 on the bottom wall (y=5)
        guard case let .addExit(a, b)? = FixPlanner.newExit(on: .bottom, in: v, width: nil) else {
            Issue.record("expected a new exit"); return
        }
        let newCentre = (a + b) / 2
        #expect(abs(a.y - 5.0) < 1e-9 && abs(b.y - 5.0) < 1e-9) // on the bottom wall
        #expect(newCentre.distance(to: Vec2(2.5, 5.0)) > 1.0) // clear of the existing door
    }

    @Test("A wall wholly blocked by structure yields no new exit")
    func newExitBlockedWall() {
        // Top wall fully occupied by a flush structural bar across its whole width.
        let v = VenueModel(
            id: 0, name: "hall", type: .nightclub,
            geometry: GridGeometry(size: GridSize(width: 20, height: 20)),
            exits: [Exit(id: 0, a: Vec2(2.25, 5.0), b: Vec2(2.75, 5.0))],
            obstacles: [Obstacle(id: 1, origin: Vec2(0, 0), size: Vec2(5, 0.6), isRelocatable: false)]
        )
        #expect(FixPlanner.newExit(on: .top, in: v, width: nil) == nil)
    }

    // MARK: wall(of:)

    @Test("wall(of:) names the boundary an exit sits on")
    func wallOfExit() {
        let v = venue()
        #expect(FixPlanner.wall(of: v.exits[0], in: v) == .bottom)
    }
}
