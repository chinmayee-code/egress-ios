import EgressEngine
import SwiftUI

// MARK: - CanvasProjection

/// Maps venue world-space (metres; y grows toward the exit wall) onto the Canvas (points; y
/// grows downward — so the mapping is direct, no flip). Uniform scale preserves the room's true
/// aspect ratio and centres it with an inset. S2's pan/zoom camera composes on top of this.
struct CanvasProjection {
    let scale: CGFloat // points per metre
    private let origin: CGPoint // screen point of world (0, 0)

    init(worldWidth: Double, worldHeight: Double, viewSize: CGSize, inset: CGFloat = 20) {
        let usableWidth = max(1, viewSize.width - inset * 2)
        let usableHeight = max(1, viewSize.height - inset * 2)
        scale = CGFloat(min(usableWidth / worldWidth, usableHeight / worldHeight))
        let drawnWidth = CGFloat(worldWidth) * scale
        let drawnHeight = CGFloat(worldHeight) * scale
        origin = CGPoint(x: (viewSize.width - drawnWidth) / 2, y: (viewSize.height - drawnHeight) / 2)
    }

    /// Camera-driven projection for the free-form editor board (design's pan/zoom canvas). Unlike the
    /// fit-to-view initialiser, this maps world→screen through an explicit `EditorCamera`: a uniform
    /// `camera.pointsPerMetre` scale with the camera's world `center` pinned to the middle of the view.
    init(camera: EditorCamera, viewSize: CGSize) {
        scale = camera.pointsPerMetre
        origin = CGPoint(
            x: viewSize.width / 2 - CGFloat(camera.center.x) * scale,
            y: viewSize.height / 2 - CGFloat(camera.center.y) * scale
        )
    }

    /// World point (metres) → screen point (points).
    func point(_ world: Vec2) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(world.x) * scale, y: origin.y + CGFloat(world.y) * scale)
    }

    /// Screen point (points) → world point (metres). Inverse of `point(_:)` — the editor maps a
    /// finger's location back into venue metres to place walls, exits and obstacles.
    func world(_ screen: CGPoint) -> Vec2 {
        Vec2(Double((screen.x - origin.x) / scale), Double((screen.y - origin.y) / scale))
    }

    /// A length in metres → points.
    func length(_ metres: Double) -> CGFloat {
        CGFloat(metres) * scale
    }
}

// MARK: - SimulationRenderer

/// Pure drawing of one `SimulationSnapshot`. No state, no timing — same snapshot ⇒ same frame.
/// Layer order is the design spec's stack, with the venue's built geometry (walls + obstacles)
/// sitting on the grid beneath the live layers: grid → walls → obstacles → density → hazards →
/// exits → agents. Grid, walls, obstacles and exits are shared with the editor via `VenueScenery`.
enum SimulationRenderer {
    static func draw(
        _ snapshot: SimulationSnapshot,
        venue: VenueModel,
        projection: CanvasProjection,
        patternFills: Bool = true,
        into context: inout GraphicsContext
    ) {
        VenueScenery.drawGrid(venue: venue, projection: projection, into: &context)
        VenueScenery.drawExteriorShade(
            venue.blockedCells, origin: .zero, cellSize: venue.geometry.cellSize, projection: projection, into: &context
        )
        VenueScenery.drawWater(venue.water, projection: projection, into: &context)
        VenueScenery.drawObstacles(venue.obstacles, projection: projection, into: &context)
        VenueScenery.drawWalls(venue.walls, projection: projection, into: &context)
        drawDensity(
            snapshot.density,
            cellSize: venue.geometry.cellSize,
            projection: projection,
            patternFills: patternFills,
            into: &context
        )
        drawHazards(
            snapshot.hazards,
            cellSize: venue.geometry.cellSize,
            projection: projection,
            time: snapshot.live.elapsed,
            into: &context
        )
        VenueScenery.drawExits(venue.exits, projection: projection, into: &context)
        // The fallen sit on the floor, beneath the living crowd who step over/around them.
        AgentSprites.drawCasualties(snapshot.agents, projection: projection, into: &context)
        AgentSprites.drawCrowd(snapshot.agents, projection: projection, time: snapshot.live.elapsed, into: &context)
    }

    /// Per-cell density bands (persons·m⁻²). Comfortable renders nothing — only crowding shows. When
    /// `patternFills` is on (§5.6 colour-vision pass) each band also carries a texture — sparse dots for
    /// congestion, a diagonal hatch for at-risk, a cross-hatch for a crush — so the bands are legible
    /// without relying on hue.
    private static func drawDensity(
        _ density: DensityGrid,
        cellSize: Double,
        projection: CanvasProjection,
        patternFills: Bool,
        into context: inout GraphicsContext
    ) {
        let side = projection.length(cellSize) + 0.5 // +0.5 hides seams between cells
        var congested = Path()
        var atRisk = Path()
        var crush = Path()
        for index in 0 ..< density.size.count {
            let coord = density.size.coord(atIndex: index)
            let value = density.value(at: coord)
            guard value >= 2 else { continue }
            let topLeft = projection.point(Vec2(Double(coord.x) * cellSize, Double(coord.y) * cellSize))
            let rect = CGRect(x: topLeft.x, y: topLeft.y, width: side, height: side)
            if value >= 6 {
                crush.addRect(rect)
            } else if value >= 4 {
                atRisk.addRect(rect)
            } else {
                congested.addRect(rect)
            }
        }
        context.fill(congested, with: .color(.egDensityCongested))
        context.fill(atRisk, with: .color(.egDensityAtRisk))
        context.fill(crush, with: .color(.egDensityCrush))
        guard patternFills else { return }
        // Texture overlays, clipped to each band's cells, drawn brightest-band-last so a crush reads on
        // top. The stroke colour is a lightened tint of the band so the pattern stays visible on its fill.
        strokePattern(
            .dots,
            over: congested,
            spacing: projection.length(0.5),
            colour: .egDensityCongestedPattern,
            into: &context
        )
        strokePattern(
            .diagonal,
            over: atRisk,
            spacing: projection.length(0.45),
            colour: .egDensityAtRiskPattern,
            into: &context
        )
        strokePattern(
            .cross,
            over: crush,
            spacing: projection.length(0.4),
            colour: .egDensityCrushPattern,
            into: &context
        )
    }

    /// The three colour-blind textures. Each is a set of hairlines (or dots) generated across the band's
    /// bounding box, then clipped to the band's own cells so only crowded floor is textured.
    private enum DensityPattern { case dots, diagonal, cross }

    private static func strokePattern(
        _ pattern: DensityPattern,
        over band: Path,
        spacing: CGFloat,
        colour: Color,
        into context: inout GraphicsContext
    ) {
        let bounds = band.boundingRect
        guard !bounds.isEmpty, spacing > 1 else { return }
        context.drawLayer { layer in
            layer.clip(to: band)
            switch pattern {
            case .dots:
                let r = max(0.6, spacing * 0.12)
                var y = bounds.minY
                while y <= bounds.maxY {
                    var x = bounds.minX
                    while x <= bounds.maxX {
                        layer.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(colour)
                        )
                        x += spacing
                    }
                    y += spacing
                }
            case .diagonal:
                layer.stroke(
                    diagonalLines(in: bounds, spacing: spacing, rising: true),
                    with: .color(colour),
                    lineWidth: 1
                )
            case .cross:
                layer.stroke(
                    diagonalLines(in: bounds, spacing: spacing, rising: true),
                    with: .color(colour),
                    lineWidth: 1
                )
                layer.stroke(
                    diagonalLines(in: bounds, spacing: spacing, rising: false),
                    with: .color(colour),
                    lineWidth: 1
                )
            }
        }
    }

    /// A field of parallel 45° lines covering `bounds`, rising (↗) or falling (↘). Offsetting the line
    /// origin from `-height` to `+width` guarantees the whole box is swept regardless of aspect.
    private static func diagonalLines(in bounds: CGRect, spacing: CGFloat, rising: Bool) -> Path {
        var path = Path()
        var offset = -bounds.height
        while offset <= bounds.width {
            let x = bounds.minX + offset
            if rising {
                path.move(to: CGPoint(x: x, y: bounds.maxY))
                path.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
            } else {
                path.move(to: CGPoint(x: x, y: bounds.minY))
                path.addLine(to: CGPoint(x: x + bounds.height, y: bounds.maxY))
            }
            offset += spacing
        }
        return path
    }

    /// Fire and smoke, drawn to *read as fire* rather than a flat fill: a soft warm glow beneath the
    /// flames, per-cell "burning tiles" on a dark-ember→gold intensity ramp with a deterministic flicker,
    /// rising ember specks over the hottest cells, and a drifting smoke veil on top. Everything is a pure
    /// function of the snapshot and its elapsed `time`, so a paused/scrubbed frame renders identically.
    private static func drawHazards(
        _ hazards: HazardSnapshot,
        cellSize: Double,
        projection: CanvasProjection,
        time: Double,
        into context: inout GraphicsContext
    ) {
        let side = projection.length(cellSize)
        func topLeft(_ coord: GridCoord) -> CGPoint {
            projection.point(Vec2(Double(coord.x) * cellSize, Double(coord.y) * cellSize))
        }

        // 1) Warm glow — a blurred halo of the fire footprint so the flames cast light on the floor.
        if !hazards.fire.isEmpty {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: side * 0.85))
                for (coord, intensity) in hazards.fire where intensity > 0.05 {
                    let point = topLeft(coord)
                    let rect = CGRect(x: point.x, y: point.y, width: side, height: side)
                        .insetBy(dx: -side * 0.3, dy: -side * 0.3)
                    layer.fill(Path(rect), with: .color(.egHazardFire.opacity(0.4 * intensity)))
                }
            }
        }

        // 2) Burning tiles — inset a hair so the dark canvas shows a pixel grid between cells, and
        //    flicker each cell on a per-cell phase so the fire shimmers instead of sitting as a slab.
        let inset = side * 0.1
        for (coord, intensity) in hazards.fire where intensity > 0.02 {
            let point = topLeft(coord)
            let flicker = 0.78 + 0.22 * sin(time * 9 + cellPhase(coord) * .pi * 2)
            let hot = min(1, intensity * flicker)
            let rect = CGRect(
                x: point.x + inset,
                y: point.y + inset,
                width: side - inset * 2 + 0.5,
                height: side - inset * 2 + 0.5
            )
            context.fill(Path(rect), with: .color(fireColour(hot)))
        }

        // 3) Rising embers — a bright speck over each hot cell, drifting upward and looping on time.
        for (coord, intensity) in hazards.fire where intensity > 0.5 {
            let point = topLeft(coord)
            let phase = cellPhase(coord)
            let flicker = 0.6 + 0.4 * sin(time * 12 + phase * .pi * 2)
            let riseX = point.x + side * CGFloat(fract(phase * 3.1))
            let riseY = point.y + side * CGFloat(1 - fract(phase * 1.7 + time * 0.55))
            let radius = side * 0.09
            let rect = CGRect(x: riseX - radius, y: riseY - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(.egHazardFireCore.opacity(0.75 * flicker)))
        }

        // 4) Smoke veil on top — a thin drifting haze. It's kept light so it reads as smoke, and it
        //    thins right down over active flame (fire burns through it), so the vivid fire core is never
        //    masked into a muddy blob; smoke lingers mostly at the edges and where the fire has passed.
        for (coord, opacity) in hazards.smoke where opacity > 0.02 {
            let fireHere = hazards.fire[coord] ?? 0
            let show = min(0.5, opacity) * (fireHere > 0.3 ? 0.28 : 1.0)
            guard show > 0.02 else { continue }
            let point = topLeft(coord)
            let drift = CGFloat(sin(time * 0.8 + cellPhase(coord) * .pi * 2)) * side * 0.12
            let rect = CGRect(x: point.x + drift, y: point.y, width: side + 0.5, height: side + 0.5)
            context.fill(Path(rect), with: .color(.egHazardSmoke.opacity(show)))
        }
    }

    /// The fire colour ramp: dark ember → terracotta → orange → gold core as a cell heats up.
    private static func fireColour(_ intensity: Double) -> Color {
        switch intensity {
        case ..<0.32: .egAccentBrick // deep red ember at the cool edge
        case ..<0.58: .egHazardFire // terracotta flame
        case ..<0.82: Color(hex: 0xE8842E) // orange mid-flame
        default: .egHazardFireCore // gold core
        }
    }

    /// A stable per-cell phase in 0…1 (classic hash) so each fire cell flickers on its own beat but the
    /// same cell always flickers the same way — keeping the render deterministic.
    private static func cellPhase(_ coord: GridCoord) -> Double {
        let value = sin(Double(coord.x) * 12.9898 + Double(coord.y) * 78.233) * 43758.5453
        return value - floor(value)
    }

    /// Fractional part, for looping ember drift.
    private static func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
