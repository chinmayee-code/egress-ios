import EgressEngine
import SwiftUI
import UIKit

// MARK: - LandingView

/// The front door (design: the EGRESS landing page). A full-bleed cream plate: the heavy wordmark up top,
/// then the hand-illustrated evacuation hero — the marshal holding a smoking city block whose green routes
/// stream the crowd out past a RALLY sign to the exits — then the single green call to action over the
/// OFFLINE · PRIVATE · PRECISE seal. Committed to the light shell; honours Reduce Motion.
///
/// The hero is the `landing_hero` image set in `Assets.xcassets` (cream flattened to `egGround` so it sits
/// seamlessly on the page). If that asset is ever removed, `heroArtwork` returns `nil` and the drawn
/// `LandingDiorama` stands in automatically — no code change.
struct LandingView: View {
  /// Raised when the user taps START — the app root cross-fades in.
  let onStart: () -> Void

  /// The landing CTA's vivid emerald — the design mockup's button green (`#148B53`), deliberately
  /// brighter than the app's sage `egDataGreen` tint so the front-door "START" reads as a strong go.
  private static let ctaGreen = Color(hex: 0x148B53)
  private static let ctaGreenDeep = Color(hex: 0x0F6B40)

  @Environment(\.accessibilityReduceMotion)
  private var reduceMotion
  @Environment(FeedbackServices.self)
  private var feedback: FeedbackServices?

  /// Drives the breathing call-to-action.
  @State private var pulse = false
  /// Staggers the hero content in on first appearance.
  @State private var shown = false

  /// The optional hand-drawn hero. Present only once a `landing_hero` asset is added to the catalog;
  /// until then this is `nil` and the drawn `LandingDiorama` stands in.
  private var heroArtwork: UIImage? { UIImage(named: "landing_hero") }

  var body: some View {
    ZStack {
      Color.egGround.ignoresSafeArea()

      VStack(spacing: EgressSpacing.md) {
        Text("EGRESS")
          .font(.system(size: 72, weight: .black))
          .tracking(2)
          .foregroundStyle(Color.egTextPrimary)
          .padding(.top, EgressSpacing.xs)
          .opacity(shown ? 1 : 0)
          .offset(y: shown ? 0 : -12)

        hero
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.horizontal, -EgressSpacing.md)  // let the plate breathe wider than the text column
          .opacity(shown ? 1 : 0)
          .scaleEffect(shown ? 1 : 0.96)

        callToAction
          .opacity(shown ? 1 : 0)
      }
      .padding(.horizontal, EgressSpacing.xl)
      .padding(.vertical, EgressSpacing.lg)
    }
    .preferredColorScheme(.light)
    .onAppear {
      // Audio, not motion — the low music bed plays regardless of Reduce Motion (it honours only the
      // sound toggle / silent switch). Started before the motion guard below can return early.
      feedback?.sound.startBackgroundMusic(.landing)
      withAnimation(Motion.card) { shown = true }
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
    }
    .onDisappear { feedback?.sound.stopBackgroundMusic() }
  }

  /// The illustration band — the real artwork if it has been added, otherwise the drawn diorama.
  @ViewBuilder
  private var hero: some View {
    if let heroArtwork {
      Image(uiImage: heroArtwork)
        .resizable()
        .scaledToFit()
        .accessibilityHidden(true)
    } else {
      LandingDiorama()
    }
  }

  private var callToAction: some View {
    VStack(spacing: EgressSpacing.md) {
      Button(action: start) {
        Text("START YOUR SIMULATION")
          .font(EgressFont.body(.headline, weight: .heavy))
          .foregroundStyle(Color.egSurfaceRaised)
          .frame(maxWidth: .infinity)
          .padding(.vertical, EgressSpacing.lg)
          .background(
            RoundedRectangle.egSquircle(EgressRadius.md)
              .fill(Self.ctaGreen)
              .clipShape(RoundedRectangle.egSquircle(EgressRadius.md))
          )
      }
      .buttonStyle(.plain)
      .scaleEffect(pulse ? 1.02 : 1)
      .accessibilityLabel("Start your simulation")
      .accessibilityHint("Opens the Spaces library")

      Text("OFFLINE . PRIVATE . PRECISE")
        .font(.system(.subheadline, design: .monospaced, weight: .bold))
        .tracking(2)
        .foregroundStyle(Color.egTextTertiary)
    }
  }

  private func start() {
    feedback?.haptics.play(.toolTap)
    onStart()
  }
}

// MARK: - LandingDiorama

/// The isometric vignette (design: the landing illustration). An ink-on-cream city drawn in the app's chunky
/// charcoal line — two clusters of cuboid buildings around a tiled central plaza, storefront signs on the
/// facades, pixel smoke columns rolling off the burning rooftops, green escape routes flowing out to the EXIT
/// doors with a small crowd streaming along them past a RALLY sign, and the marshal holding the centre.
/// Everything is a pure function of elapsed time, frozen under Reduce Motion.
private struct LandingDiorama: View {
  @Environment(\.accessibilityReduceMotion)
  private var reduceMotion

  // MARK: Scene graph (isometric grid units; the marshal stands at the origin)

  /// A building block on the iso ground: footprint origin + size (grid units), height (grid units), whether
  /// its roof is on fire (smoking), and an optional storefront sign colour painted on its lit face.
  private struct Building {
    let gx: Double, gy: Double  // footprint near corner
    let w: Double, d: Double  // footprint width (x) and depth (y)
    let h: Double  // height in grid units
    let smoking: Bool
    var sign: Color?
  }

  private static let buildings: [Building] = [
    // Left cluster
    Building(gx: -4.3, gy: -2.2, w: 1.4, d: 1.2, h: 2.3, smoking: true, sign: nil),
    Building(gx: -4.1, gy: -0.2, w: 1.3, d: 1.3, h: 1.6, smoking: false, sign: .egAccentGold),
    Building(gx: -4.5, gy: 1.6, w: 1.5, d: 1.2, h: 1.9, smoking: true, sign: nil),
    Building(gx: -2.7, gy: -3.5, w: 1.3, d: 1.2, h: 2.7, smoking: true, sign: nil),
    Building(gx: -2.9, gy: 2.7, w: 1.4, d: 1.3, h: 1.5, smoking: false, sign: .egDataGreen),
    // Right cluster
    Building(gx: 3.0, gy: -2.4, w: 1.4, d: 1.3, h: 2.4, smoking: true, sign: nil),
    Building(gx: 3.3, gy: -0.4, w: 1.3, d: 1.4, h: 1.7, smoking: false, sign: .egAccentTerracotta),
    Building(gx: 2.8, gy: 1.6, w: 1.5, d: 1.3, h: 2.1, smoking: true, sign: nil),
    Building(gx: 1.6, gy: -3.7, w: 1.3, d: 1.2, h: 2.5, smoking: true, sign: nil),
    Building(gx: 1.8, gy: 2.9, w: 1.4, d: 1.2, h: 1.6, smoking: false, sign: .egAccentGold),
  ]

  /// Exit doors the routes flow to — pushed well out from the centre so the routes are long and the marshal
  /// stands alone in the middle.
  private static let exits: [CGPoint] = [
    CGPoint(x: -2.6, y: -0.7),  // left
    CGPoint(x: -1.3, y: -2.6),  // top-left
    CGPoint(x: 2.5, y: -0.5),  // right
    CGPoint(x: 1.5, y: 2.3),  // bottom-right
    CGPoint(x: -1.4, y: 2.5),  // bottom-left
  ]

  var body: some View {
    GeometryReader { geo in
      let size = geo.size
      let tile = min(size.width / 8.2, size.height / 6.2)
      let origin = CGPoint(x: size.width / 2, y: size.height * 0.56)

      TimelineView(.animation(paused: reduceMotion)) { timeline in
        let t = reduceMotion ? 6.0 : timeline.date.timeIntervalSinceReferenceDate
        ZStack {
          Canvas { context, _ in
            drawScene(&context, origin: origin, tile: tile, t: t)
          }

          // The marshal (RALLY) holds the centre-front, clearly the largest figure — the star.
          PixelCharacter(mobility: .staff, emotion: .calm, seed: 101)
            .frame(width: 82, height: 116)
            .position(iso(0, 0.9, origin: origin, tile: tile).offsetBy(dy: -54))
        }
      }
    }
  }

  // MARK: Canvas scene

  private func drawScene(
    _ context: inout GraphicsContext, origin: CGPoint, tile: CGFloat, t: Double
  ) {
    drawGroundShadows(&context, origin: origin, tile: tile)
    drawPlaza(&context, origin: origin, tile: tile)

    // Escape routes fan out from the centre to each exit — on the ground so the crowd reads on top.
    for exit in Self.exits {
      drawRoute(&context, to: exit, origin: origin, tile: tile, t: t)
    }

    // Buildings, painted back-to-front (farther = smaller gx+gy) so nearer blocks overlap farther ones.
    for building in Self.buildings.sorted(by: { $0.gx + $0.gy < $1.gx + $1.gy }) {
      drawBuilding(&context, building, origin: origin, tile: tile)
      if building.smoking {
        let roof = iso(
          building.gx + building.w / 2, building.gy + building.d / 2, origin: origin, tile: tile
        )
        .offsetBy(dy: -CGFloat(building.h) * tile * 0.5)
        drawSmoke(&context, base: roof, tile: tile, t: t, seed: Int(building.gx * 7 + building.gy))
      }
    }

    // The RALLY assembly sign, planted just off the centre.
    drawRallySign(&context, at: iso(2.4, -1.1, origin: origin, tile: tile), tile: tile)

    // The crowd streams the routes on top of the block.
    drawCrowd(&context, origin: origin, tile: tile, t: t)
  }

  /// Soft contact shadows under each building, so the block reads as sitting on the cream rather than floating.
  private func drawGroundShadows(_ context: inout GraphicsContext, origin: CGPoint, tile: CGFloat) {
    for b in Self.buildings {
      let c = iso(b.gx + b.w / 2, b.gy + b.d / 2, origin: origin, tile: tile)
      let rx = CGFloat(b.w) * tile * 0.62
      let ry = CGFloat(b.d) * tile * 0.34
      let rect = CGRect(x: c.x - rx, y: c.y - ry * 0.5, width: rx * 2, height: ry)
      context.fill(Path(ellipseIn: rect), with: .color(Color.egOutline.opacity(0.10)))
    }
  }

  /// A faint iso plaza under the marshal — a diamond of paper with a light tile lattice, so the centre reads
  /// as a public square the crowd musters in.
  private func drawPlaza(_ context: inout GraphicsContext, origin: CGPoint, tile: CGFloat) {
    let r = 2.2
    var plate = Path()
    plate.move(to: iso(-r, -r, origin: origin, tile: tile))
    plate.addLine(to: iso(r, -r, origin: origin, tile: tile))
    plate.addLine(to: iso(r, r, origin: origin, tile: tile))
    plate.addLine(to: iso(-r, r, origin: origin, tile: tile))
    plate.closeSubpath()
    context.fill(plate, with: .color(Color.egSurfaceSunken.opacity(0.4)))

    var grid = Path()
    var g = -r
    while g <= r {
      grid.move(to: iso(g, -r, origin: origin, tile: tile))
      grid.addLine(to: iso(g, r, origin: origin, tile: tile))
      grid.move(to: iso(-r, g, origin: origin, tile: tile))
      grid.addLine(to: iso(r, g, origin: origin, tile: tile))
      g += 1.1
    }
    context.stroke(grid, with: .color(Color.egSeparator.opacity(0.6)), lineWidth: 1)
  }

  /// One cuboid building in ink-on-cream: top face, two shaded side faces, window slits, an optional
  /// storefront sign — all in the charcoal line.
  private func drawBuilding(
    _ context: inout GraphicsContext, _ b: Building, origin: CGPoint, tile: CGFloat
  ) {
    let top = CGFloat(b.h) * tile * 0.5
    // Ground corners (near, right, far, left going clockwise) and their raised roof counterparts.
    let n = iso(b.gx, b.gy + b.d, origin: origin, tile: tile)  // near (front) corner
    let r = iso(b.gx + b.w, b.gy + b.d, origin: origin, tile: tile)  // right
    let f = iso(b.gx + b.w, b.gy, origin: origin, tile: tile)  // far
    let l = iso(b.gx, b.gy, origin: origin, tile: tile)  // left
    let nT = n.offsetBy(dy: -top)
    let rT = r.offsetBy(dy: -top)
    let fT = f.offsetBy(dy: -top)
    let lT = l.offsetBy(dy: -top)

    // Left face (l→n) — the shadowed side (warm tan, so the block reads as solid on the cream).
    var left = Path()
    left.move(to: l)
    left.addLine(to: n)
    left.addLine(to: nT)
    left.addLine(to: lT)
    left.closeSubpath()
    context.fill(left, with: .color(Color(hex: 0xC9B189)))

    // Right face (n→r) — the lit side.
    var right = Path()
    right.move(to: n)
    right.addLine(to: r)
    right.addLine(to: rT)
    right.addLine(to: nT)
    right.closeSubpath()
    context.fill(right, with: .color(Color(hex: 0xDFC9A0)))

    // Roof — the lightest face, so the sun clearly hits the top.
    var roof = Path()
    roof.move(to: nT)
    roof.addLine(to: rT)
    roof.addLine(to: fT)
    roof.addLine(to: lT)
    roof.closeSubpath()
    context.fill(roof, with: .color(Color(hex: 0xFBF4E4)))

    // Ink outlines over everything.
    for edge in [left, right, roof] {
      context.stroke(edge, with: .color(Color.egOutline), lineWidth: 1.8)
    }

    // Window slits climbing the lit face, for read.
    var windows = Path()
    for col in [0.34, 0.62] {
      let base = lerp(n, r, col)
      for row in stride(from: 0.28, through: 0.82, by: 0.27) {
        windows.move(to: base.offsetBy(dy: -top * row))
        windows.addLine(to: base.offsetBy(dy: -top * (row + 0.12)))
      }
    }
    context.stroke(windows, with: .color(Color.egOutline.opacity(0.45)), lineWidth: 1.4)

    // Optional storefront sign — a colour band across the lit face just under the roofline.
    if let sign = b.sign {
      let a = lerp(n, r, 0.16).offsetBy(dy: -top * 0.86)
      let c = lerp(n, r, 0.84).offsetBy(dy: -top * 0.86)
      var band = Path()
      band.move(to: a)
      band.addLine(to: c)
      band.addLine(to: c.offsetBy(dy: top * 0.16))
      band.addLine(to: a.offsetBy(dy: top * 0.16))
      band.closeSubpath()
      context.fill(band, with: .color(sign))
      context.stroke(band, with: .color(Color.egOutline.opacity(0.8)), lineWidth: 1.2)
    }
  }

  /// A green escape route from centre to an exit — a curved, dash-flowing line with an arrowhead and an
  /// EXIT plate at the door.
  private func drawRoute(
    _ context: inout GraphicsContext, to exit: CGPoint, origin: CGPoint, tile: CGFloat, t: Double
  ) {
    let start = iso(0, 0.6, origin: origin, tile: tile)
    let end = iso(Double(exit.x), Double(exit.y), origin: origin, tile: tile)
    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - tile * 0.5)

    var route = Path()
    route.move(to: start)
    route.addQuadCurve(to: end, control: mid)
    context.stroke(
      route,
      with: .color(Color.egDataGreen),
      style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 7], dashPhase: -t * 26)
    )

    // Arrowhead near the door, aimed along the tangent (control→end).
    let dir = direction(from: mid, to: end)
    drawArrowhead(&context, at: lerp(mid, end, 0.86), pointing: dir)

    // EXIT plate at the door.
    drawExitPlate(&context, at: end)
  }

  /// The crowd — small pixel figures streaming each route from the plaza out to its door, on a phase-shifted
  /// loop so the flow never pops. They ride the outer stretch of the curve, leaving the marshal the centre.
  private func drawCrowd(
    _ context: inout GraphicsContext, origin: CGPoint, tile: CGFloat, t: Double
  ) {
    let perRoute = 3
    for (i, exit) in Self.exits.enumerated() {
      let start = iso(0, 0.6, origin: origin, tile: tile)
      let end = iso(Double(exit.x), Double(exit.y), origin: origin, tile: tile)
      let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - tile * 0.5)
      for k in 0..<perRoute {
        let phase = Double(k) / Double(perRoute)
        let s = fract(t * 0.06 + phase + Double(i) * 0.13)
        // Travel the outer 68% of the route, so the crowd hugs the doors and the marshal owns the centre.
        let ss = 0.32 + s * 0.68
        let p = bezier(start, mid, end, ss)
        let edge = min(s / 0.15, (1 - s) / 0.15, 1)
        let tint: Color = (k % 3 == 0) ? .egAgentUneasy : .egAgentCalm
        drawWalker(
          &context, at: p, tile: tile, tint: tint, alpha: max(0, edge) * 0.95,
          scale: lerp(0.82, 1.08, ss))
      }
    }
  }

  /// One tiny pixel person — a charcoal-outlined body and head, tinted by mood. Its feet sit at `p`.
  private func drawWalker(
    _ context: inout GraphicsContext, at p: CGPoint, tile: CGFloat, tint: Color, alpha: Double,
    scale: Double
  ) {
    let s = tile * 0.17 * CGFloat(scale)
    let bodyRect = CGRect(x: p.x - s * 0.45, y: p.y - s * 1.55, width: s * 0.9, height: s * 1.15)
    let body = Path(roundedRect: bodyRect, cornerRadius: s * 0.28)
    context.fill(body, with: .color(tint.opacity(alpha)))
    context.stroke(body, with: .color(Color.egOutline.opacity(alpha)), lineWidth: 1.2)

    let headD = s * 0.62
    let headRect = CGRect(
      x: p.x - headD / 2, y: bodyRect.minY - headD * 0.72, width: headD, height: headD)
    context.fill(Path(ellipseIn: headRect), with: .color(tint.opacity(alpha)))
    context.stroke(
      Path(ellipseIn: headRect), with: .color(Color.egOutline.opacity(alpha)), lineWidth: 1.2)
  }

  private func drawArrowhead(
    _ context: inout GraphicsContext, at point: CGPoint, pointing dir: CGVector
  ) {
    let len: CGFloat = 9
    let perp = CGVector(dx: -dir.dy, dy: dir.dx)
    let tip = CGPoint(x: point.x + dir.dx * len, y: point.y + dir.dy * len)
    let a = CGPoint(x: point.x + perp.dx * len * 0.6, y: point.y + perp.dy * len * 0.6)
    let b = CGPoint(x: point.x - perp.dx * len * 0.6, y: point.y - perp.dy * len * 0.6)
    var head = Path()
    head.move(to: tip)
    head.addLine(to: a)
    head.addLine(to: b)
    head.closeSubpath()
    context.fill(head, with: .color(Color.egDataGreen))
  }

  private func drawExitPlate(_ context: inout GraphicsContext, at point: CGPoint) {
    let w: CGFloat = 38
    let h: CGFloat = 16
    let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
    context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.egDataGreenDeep))
    context.stroke(
      Path(roundedRect: rect, cornerRadius: 3), with: .color(Color.egOutline), lineWidth: 1)
    context.draw(
      Text("EXIT").font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundColor(
        .egSurfaceRaised),
      at: point
    )
  }

  /// A small assembly-point billboard reading RALLY — the mascot's namesake muster sign.
  private func drawRallySign(_ context: inout GraphicsContext, at base: CGPoint, tile: CGFloat) {
    let boardW: CGFloat = 62
    let boardH: CGFloat = 26
    let board = CGRect(
      x: base.x - boardW / 2, y: base.y - tile * 1.4 - boardH, width: boardW, height: boardH)
    // Post.
    var post = Path()
    post.move(to: CGPoint(x: base.x, y: base.y))
    post.addLine(to: CGPoint(x: base.x, y: board.maxY))
    context.stroke(post, with: .color(Color.egOutline), lineWidth: 3)
    // Board.
    context.fill(Path(roundedRect: board, cornerRadius: 5), with: .color(Color.egSurfaceRaised))
    context.stroke(
      Path(roundedRect: board, cornerRadius: 5), with: .color(Color.egOutline), lineWidth: 2)
    context.draw(
      Text("RALLY").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(
        .egDataGreenDeep),
      at: CGPoint(x: board.midX, y: board.midY)
    )
  }

  /// Chunky pixel smoke — a rising, drifting stack of soft squares off a burning roof, fading as it climbs.
  private func drawSmoke(
    _ context: inout GraphicsContext, base: CGPoint, tile: CGFloat, t: Double, seed: Int
  ) {
    for i in 0..<7 {
      let cycle = fract(t * 0.09 + Double(i) * 0.14 + Double(seed) * 0.31)
      let rise = CGFloat(cycle) * tile * 3.0
      let drift = CGFloat(sin(t * 0.5 + Double(i) + Double(seed))) * tile * 0.3
      let side = tile * (0.20 + CGFloat(cycle) * 0.42)
      let alpha = (1 - cycle) * 0.30
      let rect = CGRect(
        x: base.x + drift - side / 2, y: base.y - rise - side / 2, width: side, height: side)
      context.fill(
        Path(roundedRect: rect, cornerRadius: side * 0.22),
        with: .color(Color.egHazardSmoke.opacity(Double(alpha))))
    }
  }

  // MARK: Isometric maths

  /// Project a grid point (gx east, gy south, origin at the marshal) to a 2:1 isometric screen point.
  private func iso(_ gx: Double, _ gy: Double, origin: CGPoint, tile: CGFloat) -> CGPoint {
    CGPoint(
      x: origin.x + CGFloat(gx - gy) * tile * 0.5,
      y: origin.y + CGFloat(gx + gy) * tile * 0.25
    )
  }

  private func direction(from a: CGPoint, to b: CGPoint) -> CGVector {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let m = max(0.0001, hypot(dx, dy))
    return CGVector(dx: dx / m, dy: dy / m)
  }
}

// MARK: - Free helpers

private func fract(_ x: Double) -> Double { x - floor(x) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
  CGPoint(x: a.x + (b.x - a.x) * CGFloat(t), y: a.y + (b.y - a.y) * CGFloat(t))
}

/// Point on a quadratic Bézier (start, control, end) at parameter `s ∈ [0, 1]`.
private func bezier(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ s: Double) -> CGPoint {
  let u = 1 - s
  return CGPoint(
    x: u * u * p0.x + 2 * u * s * c.x + s * s * p1.x,
    y: u * u * p0.y + 2 * u * s * c.y + s * s * p1.y
  )
}

extension CGPoint {
  fileprivate func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
    CGPoint(x: x + dx, y: y + dy)
  }
}

#Preview {
  LandingView(onStart: {})
}
