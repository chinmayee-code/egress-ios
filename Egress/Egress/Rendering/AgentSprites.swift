import EgressEngine
import SwiftUI

// MARK: - AgentSprites

/// Chunky pixel-people for the live crowd (design §3 "Characters"). Each person is drawn the way the
/// reference art reads: a *naturalistic*, individually-coloured little human — skin tone, hair, top
/// and trousers all vary per agent — with emotion carried on channels that survive greyscale
/// (accessibility §5.6):
///
///  • **Type by silhouette** — adult (male / female builds), child (small), elderly (hunched + cane),
///    wheelchair (seated + wheel), staff (capped + plum vest). Never by tint alone.
///  • **Motion by pose** — everyone *walks*: an alternating-foot step cycle whose cadence rises with
///    speed, so a flowing crowd visibly flows and a fleeing one visibly runs. Panicked people throw
///    their arms up and scream (waving hands above the head) and jitter.
///  • **Arousal by aura** — calm is bare; uneasy gains a soft ring; panicked gains a hard double ring.
///    Staff sit *outside* the arousal ramp — the plum vest never reads as "dangerous".
///
/// Every appearance choice (sex, skin, hair, clothes) is a deterministic hash of the agent's `id`, and
/// the whole thing is a pure function of one snapshot + its elapsed time — so the same frame always
/// draws identically (the renderer's determinism contract) and nothing here can perturb the physics.
/// All of a colour's cells across the whole crowd accumulate into one shared `Path` and fill once, so
/// 300 fully-coloured people stay a few dozen fills per frame.
enum AgentSprites {
    // MARK: Per-person palettes (indexed by a hash of the agent id)

    /// Skin tones, light → deep.
    private static let skinTones: [Color] = [
        Color(hex: 0xF4C9A5), Color(hex: 0xE0AC79), Color(hex: 0xC68642),
        Color(hex: 0x8D5524), Color(hex: 0x5A3A22)
    ]
    /// Hair — black, browns, ginger, blond, grey, a dyed red.
    private static let hairColors: [Color] = [
        Color(hex: 0x1A1512), Color(hex: 0x3A2817), Color(hex: 0x6B3F1D), Color(hex: 0xA6672B),
        Color(hex: 0xD9B36A), Color(hex: 0xB8B8BC), Color(hex: 0x8A2E1E)
    ]
    /// Index into `hairColors` of the grey — forced onto elderly agents.
    private static let greyHairIndex = 5
    /// Tops — the loud clothing variety that makes the crowd read as a crowd.
    private static let topColors: [Color] = [
        Color(hex: 0xB84A3E), Color(hex: 0x2E6DB4), Color(hex: 0x2A8C5A), Color(hex: 0x7D4CA5),
        Color(hex: 0xD46FA0), Color(hex: 0xE0842E), Color(hex: 0x444B54), Color(hex: 0xC9A24B),
        Color(hex: 0x2E9AA0)
    ]
    /// Trousers / skirts — muted lower half.
    private static let bottomColors: [Color] = [
        Color(hex: 0x2C3E50), Color(hex: 0x4A3B2A), Color(hex: 0x34404A),
        Color(hex: 0x6E5A3A), Color(hex: 0x222225), Color(hex: 0x5A5F66)
    ]
    private static let shoeColor = Color(hex: 0x1A1613)
    private static let caneColor = Color(hex: 0x74532F)
    private static let staffCapColor = Color(hex: 0x5A3B4A)
    /// Eyes + mouth ink — a warm near-black that reads on every skin tone.
    private static let faceInkColor = Color(hex: 0x241E1A)

    /// Draw the whole active crowd. `time` is the run's elapsed seconds — it drives only the
    /// deterministic step cycle and panic jitter, so identical snapshots still render identically.
    static func drawCrowd(
        _ agents: [AgentRender],
        projection: CanvasProjection,
        time: Double,
        into context: inout GraphicsContext
    ) {
        // One unit ≈ the body radius in points; a sprite is a few units tall. A floor keeps the crowd
        // legible even when a big room is fitted to a small canvas.
        let unit = max(2.4, projection.length(SafetyStandards.bodyRadius))

        // Facial features read only when a sprite is big enough to carry them; below that they'd be
        // dark specks, so tiny sprites in a huge crowd keep their aura + badge and skip the face.
        let showFaces = unit >= 4

        // Colour buckets — one Path per palette entry, filled once at the end.
        var skin = [Path](repeating: Path(), count: skinTones.count)
        var hair = [Path](repeating: Path(), count: hairColors.count)
        var tops = [Path](repeating: Path(), count: topColors.count)
        var bottoms = [Path](repeating: Path(), count: bottomColors.count)
        var shoes = Path()
        var canes = Path()
        var staffVests = Path()
        var staffCaps = Path()
        var shadows = Path()
        var wheels = Path()
        var faceInk = Path()
        var auraUneasy = Path()
        var auraPanicked = Path()

        for agent in agents where agent.status.isActive {
            let isStaff = agent.mobility == .staff
            let female = !isStaff && sex(of: agent.id) == .female
            let sprite = Sprite.forMobility(agent.mobility, female: female)

            // A single pixel cell, sized so the sprite's footprint ≈ the body's real diameter — a packed
            // room reads as a packed room, not a wall of overlapping giants.
            let cell = unit * 0.33 * sprite.scale
            let spriteWidth = CGFloat(sprite.columns) * cell
            let spriteHeight = CGFloat(sprite.rows.count) * cell
            let centre = projection.point(agent.position)

            // Colour picks — stable per person.
            let skinIdx = pick(agent.id, salt: 0x51, mod: skinTones.count)
            let hairIdx = agent.mobility == .elderly
                ? greyHairIndex
                : pick(agent.id, salt: 0xA3, mod: hairColors.count)
            let topIdx = pick(agent.id, salt: 0x7F, mod: topColors.count)
            let botIdx = pick(agent.id, salt: 0xC1, mod: bottomColors.count)

            // Step cycle. Cadence climbs with speed (a runner's legs fly), panic winds it up further.
            let speed = Double(hypot(agent.velocity.x, agent.velocity.y))
            let panicked = agent.emotion == .panicked
            let moving = speed > 0.12
            let cadence = (2.4 + speed * 2.2) * (panicked ? 1.6 : 1.0)
            let stridePhase = time * cadence + Double(agent.id) * 0.8

            // Panic jitter (deterministic) plus a gentle up-down bob synced to the footfalls.
            let panicBob = panicked ? CGFloat(sin(time * 7.0 + Double(agent.id) * 1.3)) * cell * 0.5 : 0
            let walkBob = moving ? CGFloat(sin(stridePhase * 2)) * cell * 0.12 : 0

            let originX = centre.x - spriteWidth / 2
            let originY = centre.y - spriteHeight / 2 + panicBob + walkBob

            // Contact shadow — a squashed ellipse under the feet lifts the sprite off the dark floor.
            shadows.addEllipse(in: CGRect(
                x: centre.x - spriteWidth * 0.42,
                y: centre.y + spriteHeight * 0.42,
                width: spriteWidth * 0.84,
                height: cell * 1.1
            ))

            // Gait lean: tilt the sprite into its horizontal stride so the crowd visibly flows toward the
            // exits — the head shifts most, the feet stay planted. Purely cosmetic; physics owns velocity.
            let lean = max(-cell * 2.2, min(cell * 2.2, CGFloat(agent.velocity.x) * cell * 1.3))
            let lastRow = max(1, sprite.rows.count - 1)
            let shoeCols = sprite.shoeColumns

            // Walk the sprite's cells, routing each to its colour bucket.
            for (row, line) in sprite.rows.enumerated() {
                let shear = lean * CGFloat(lastRow - row) / CGFloat(lastRow)
                for (col, ch) in line.enumerated() {
                    guard ch != " " else { continue }
                    // Panic raises the arms: drop the side hands, we redraw them overhead below.
                    if panicked, ch == "S" {
                        continue
                    }

                    var y = originY + CGFloat(row) * cell
                    // Alternating footfall — lift each shoe out of phase with the other.
                    if ch == "B", moving, let legIdx = shoeCols.firstIndex(of: col) {
                        let lift = max(0, sin(stridePhase + Double(legIdx) * .pi)) * cell * 0.8
                        y -= CGFloat(lift)
                    }
                    let rect = CGRect(
                        x: originX + CGFloat(col) * cell + shear,
                        y: y,
                        width: cell + 0.4,
                        height: cell + 0.4
                    )
                    switch ch {
                    case "H": hair[hairIdx].addRect(rect)
                    case "F", "S": skin[skinIdx].addRect(rect)
                    case "T":
                        if isStaff {
                            staffVests.addRect(rect)
                        } else {
                            tops[topIdx].addRect(rect)
                        }
                    case "P": bottoms[botIdx].addRect(rect)
                    case "B": shoes.addRect(rect)
                    case "C": canes.addRect(rect)
                    case "K": staffCaps.addRect(rect)
                    default: break
                    }
                }
            }

            // Raised, waving hands — the "screaming, arms up" pose. Both fists overhead, shaking.
            if panicked {
                let wave = CGFloat(sin(stridePhase * 2.0)) * cell * 0.5
                for side in [CGFloat(-1), CGFloat(1)] {
                    let hx = centre.x + side * (spriteWidth * 0.42) - cell * 0.6
                    let hy = originY - cell * 1.4 + side * wave
                    skin[skinIdx].addRect(CGRect(x: hx, y: hy, width: cell * 1.3, height: cell * 1.7))
                }
            }

            // The face — eyes + a mouth that changes with the emotion (calm neutral, uneasy worried,
            // panicked screaming). Drawn in the face's own cells so it leans with the head.
            if showFaces, let box = sprite.faceBox {
                let faceMid = Double(box.minRow + box.maxRow) / 2
                let faceShear = lean * CGFloat(Double(lastRow) - faceMid) / CGFloat(lastRow)
                appendFace(
                    emotion: agent.emotion,
                    originX: originX + CGFloat(box.minCol) * cell + faceShear,
                    originY: originY + CGFloat(box.minRow) * cell,
                    width: CGFloat(box.maxCol - box.minCol + 1) * cell,
                    height: CGFloat(box.maxRow - box.minRow + 1) * cell,
                    cell: cell,
                    into: &faceInk
                )
            }

            // Wheelchair wheel — a ring straddling the seat, drawn once per chair.
            if agent.mobility == .wheelchair {
                let wheelSide = spriteWidth * 1.02
                wheels.addEllipse(in: CGRect(
                    x: centre.x - wheelSide / 2,
                    y: originY + spriteHeight * 0.42,
                    width: wheelSide,
                    height: wheelSide
                ))
            }

            // Arousal aura — a ring sized to the sprite, skipped for calm and for staff.
            if !isStaff, agent.emotion != .calm {
                let ringInset = -cell * 1.2
                let ringRect = CGRect(x: originX, y: originY, width: spriteWidth, height: spriteHeight)
                    .insetBy(dx: ringInset, dy: ringInset)
                if agent.emotion == .uneasy {
                    auraUneasy.addEllipse(in: ringRect)
                } else {
                    auraPanicked.addEllipse(in: ringRect)
                    auraPanicked.addEllipse(in: ringRect.insetBy(dx: cell * 0.7, dy: cell * 0.7))
                }
            }
        }

        // Paint back-to-front: shadow, auras, wheels, then bodies bottom-up (trousers → torso → skin →
        // hair) so a raised hand sits over the shirt and hair caps the face.
        context.fill(shadows, with: .color(.black.opacity(0.28)))
        context.stroke(auraUneasy, with: .color(.egAgentUneasy.opacity(0.5)), lineWidth: 1)
        context.stroke(auraPanicked, with: .color(.egAgentPanicked.opacity(0.7)), lineWidth: 1.4)
        context.stroke(wheels, with: .color(.egAgentCalm.opacity(0.85)), lineWidth: 1.6)

        for (i, path) in bottoms.enumerated() {
            context.fill(path, with: .color(bottomColors[i]))
        }
        context.fill(shoes, with: .color(shoeColor))
        context.fill(canes, with: .color(caneColor))
        context.fill(staffVests, with: .color(.egAgentStaff))
        for (i, path) in tops.enumerated() {
            context.fill(path, with: .color(topColors[i]))
        }
        for (i, path) in skin.enumerated() {
            context.fill(path, with: .color(skinTones[i]))
        }
        for (i, path) in hair.enumerated() {
            context.fill(path, with: .color(hairColors[i]))
        }
        context.fill(staffCaps, with: .color(staffCapColor))
        context.fill(faceInk, with: .color(faceInkColor)) // eyes + mouth on top of the face

        drawEmotes(agents, projection: projection, unit: unit, into: &context)
    }

    // MARK: Deterministic per-agent choices

    private enum Sex { case male, female }

    private static func sex(of id: Int) -> Sex {
        pick(id, salt: 0x0F, mod: 2) == 0 ? .male : .female
    }

    /// Whether agent `id` reads as male on screen — the single source of truth the sprite draws with
    /// (`sex(of:)`), reused by the death-sound picker so the dying voice matches the visible character.
    static func readsAsMale(id: Int) -> Bool {
        sex(of: id) == .male
    }

    /// A stable small index in `0..<mod`, hashed from the agent id + a per-attribute salt. Deterministic,
    /// no RNG — so the same person is always the same person, frame to frame and run to run.
    private static func pick(_ id: Int, salt: UInt64, mod: Int) -> Int {
        var h = UInt64(bitPattern: Int64(id)) &+ salt &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 30
        h &*= 0xBF58_476D_1CE4_E5B9
        h ^= h >> 27
        h &*= 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        return Int(h % UInt64(mod))
    }

    // MARK: Face

    /// Lay two eyes and a mouth inside the head's rect. The expression tracks arousal so it reads like a
    /// little emoji: **calm** — small eyes, a flat neutral mouth; **uneasy** — a small open "o" of worry;
    /// **panicked** — wide eyes and a big round screaming mouth (the arms are already up). Everything is
    /// placed as a fraction of the face box, so it scales with the sprite and shears with the head lean.
    private static func appendFace(
        emotion: EmotionalState,
        originX: CGFloat,
        originY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        cell: CGFloat,
        into ink: inout Path
    ) {
        // Per-expression sizing: eye size, how far apart the eyes sit, mouth size, and whether the mouth
        // is an open oval (worried / screaming) or a flat neutral dash.
        let eyeSize: CGFloat
        let eyeGap: CGFloat
        let mouthWidth: CGFloat
        let mouthHeight: CGFloat
        let mouthOpen: Bool
        switch emotion {
        case .calm:
            eyeSize = cell * 0.40
            eyeGap = width * 0.44
            mouthWidth = width * 0.40
            mouthHeight = cell * 0.26
            mouthOpen = false
        case .uneasy:
            eyeSize = cell * 0.44
            eyeGap = width * 0.44
            mouthWidth = width * 0.34
            mouthHeight = cell * 0.48
            mouthOpen = true
        case .panicked:
            eyeSize = cell * 0.56
            eyeGap = width * 0.52
            mouthWidth = width * 0.52
            mouthHeight = cell * 0.95
            mouthOpen = true
        }

        let cx = originX + width / 2
        let eyeY = originY + height * 0.28
        ink.addRect(CGRect(x: cx - eyeGap / 2 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize))
        ink.addRect(CGRect(x: cx + eyeGap / 2 - eyeSize / 2, y: eyeY, width: eyeSize, height: eyeSize))

        let mouthY = originY + height * (mouthOpen ? 0.60 : 0.72)
        let mouth = CGRect(x: cx - mouthWidth / 2, y: mouthY, width: mouthWidth, height: mouthHeight)
        if mouthOpen {
            ink.addEllipse(in: mouth)
        } else {
            ink.addRect(mouth)
        }
    }

    // MARK: Emote badges

    /// The emote layer (design §3): a shape-only glyph badge above the head of agents who are feeling
    /// something. Capped at 12 on screen — the most urgent (highest priority) win — and suppressed
    /// entirely when the sprites are too small for a badge to read, so a huge crowd never turns into a
    /// field of illegible specks.
    private static func drawEmotes(
        _ agents: [AgentRender],
        projection: CanvasProjection,
        unit: CGFloat,
        into context: inout GraphicsContext
    ) {
        guard unit >= 5 else { return } // too small to badge legibly

        let emoting = agents
            .filter { $0.status.isActive && $0.emote != nil }
            .sorted { ($0.emote?.priority ?? 0) > ($1.emote?.priority ?? 0) }
            .prefix(12)
        guard !emoting.isEmpty else { return }

        let badgeRadius = max(6, unit * 0.95)
        for agent in emoting {
            guard let emote = agent.emote else { continue }
            let centre = projection.point(agent.position)
            let badgeCentre = CGPoint(x: centre.x, y: centre.y - unit * 1.7 - badgeRadius)

            // Cream badge with a charcoal outline, then the charcoal glyph — shape-only, no colour cue.
            let rect = CGRect(
                x: badgeCentre.x - badgeRadius,
                y: badgeCentre.y - badgeRadius,
                width: badgeRadius * 2,
                height: badgeRadius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.egCanvasText))
            context.stroke(Path(ellipseIn: rect), with: .color(.egCanvasBase), lineWidth: 1)

            let glyph = Text(Image(systemName: symbolName(for: emote)))
                .font(.system(size: badgeRadius * 1.15, weight: .black))
                .foregroundColor(.egCanvasBase)
            context.draw(glyph, at: badgeCentre)
        }
    }

    /// Each emote's shape-only SF Symbol. Chosen to read in greyscale — the design's `!`, `?`, spiral,
    /// droplet, relief and chevrons.
    private static func symbolName(for emote: EmoteKind) -> String {
        switch emote {
        case .astonished: "exclamationmark"
        case .confused: "questionmark"
        case .frustrated: "tornado"
        case .distressed: "drop.fill"
        case .relieved: "wind"
        case .resolute: "chevron.up.2"
        }
    }
}

// MARK: - Single-sprite hero (cards + landing)

extension AgentSprites {
    /// Draw **one** pixel person for chrome — a preset card or the landing diorama — centred in `rect`
    /// and sized to fill its height. Colours come from `seed` through the exact same hashed palette the
    /// live crowd uses, so a card previews the real people a run spawns. `phase` (seconds) drives an idle
    /// bob or, when `walking`, a full step cycle in place; `mirrored` flips the figure to face left.
    /// This is the un-batched cousin of `drawCrowd` — fine for a handful of sprites, not a whole floor.
    static func drawHero(
        mobility: MobilityClass,
        emotion: EmotionalState = .calm,
        seed: Int,
        walking: Bool = false,
        mirrored: Bool = false,
        phase: Double,
        in rect: CGRect,
        into context: inout GraphicsContext
    ) {
        let isStaff = mobility == .staff
        let female = !isStaff && mobility == .adult && pick(seed, salt: 0x0F, mod: 2) == 0
        let sprite = Sprite.forMobility(mobility, female: female)

        let cell = rect.height / CGFloat(sprite.rows.count)
        let spriteWidth = CGFloat(sprite.columns) * cell
        let spriteHeight = rect.height

        // Same salts as `drawCrowd`, so the same seed is always the same person.
        let skinIdx = pick(seed, salt: 0x51, mod: skinTones.count)
        let hairIdx = mobility == .elderly ? greyHairIndex : pick(seed, salt: 0xA3, mod: hairColors.count)
        let topIdx = pick(seed, salt: 0x7F, mod: topColors.count)
        let botIdx = pick(seed, salt: 0xC1, mod: bottomColors.count)

        let panicked = emotion == .panicked
        let cadence = walking ? 6.5 : 2.2
        let stridePhase = phase * cadence + Double(seed) * 0.8
        let bob = CGFloat(sin(stridePhase * 2)) * cell * (walking ? 0.14 : 0.07)

        let originX = rect.midX - spriteWidth / 2
        let originY = rect.midY - spriteHeight / 2 + bob
        let lastCol = max(0, sprite.columns - 1)
        let shoeCols = sprite.shoeColumns

        var skinP = Path(), hairP = Path(), topP = Path(), botP = Path()
        var shoeP = Path(), caneP = Path(), capP = Path(), faceInk = Path()

        for (row, line) in sprite.rows.enumerated() {
            for (col, ch) in line.enumerated() {
                guard ch != " " else { continue }
                if panicked, ch == "S" {
                    continue
                } // side hands go overhead when screaming
                let drawCol = mirrored ? (lastCol - col) : col
                var y = originY + CGFloat(row) * cell
                if walking, ch == "B", let legIdx = shoeCols.firstIndex(of: col) {
                    let lift = max(0, sin(stridePhase + Double(legIdx) * .pi)) * cell * 0.7
                    y -= CGFloat(lift)
                }
                let r = CGRect(x: originX + CGFloat(drawCol) * cell, y: y, width: cell + 0.5, height: cell + 0.5)
                switch ch {
                case "H": hairP.addRect(r)
                case "F", "S": skinP.addRect(r)
                case "T": topP.addRect(r)
                case "P": botP.addRect(r)
                case "B": shoeP.addRect(r)
                case "C": caneP.addRect(r)
                case "K": capP.addRect(r)
                default: break
                }
            }
        }

        if panicked {
            let wave = CGFloat(sin(stridePhase * 2)) * cell * 0.5
            for side in [CGFloat(-1), CGFloat(1)] {
                let hx = rect.midX + side * (spriteWidth * 0.42) - cell * 0.6
                let hy = originY - cell * 1.4 + side * wave
                skinP.addRect(CGRect(x: hx, y: hy, width: cell * 1.3, height: cell * 1.7))
            }
        }

        if let box = sprite.faceBox {
            let minColDraw = mirrored ? (lastCol - box.maxCol) : box.minCol
            appendFace(
                emotion: emotion,
                originX: originX + CGFloat(minColDraw) * cell,
                originY: originY + CGFloat(box.minRow) * cell,
                width: CGFloat(box.maxCol - box.minCol + 1) * cell,
                height: CGFloat(box.maxRow - box.minRow + 1) * cell,
                cell: cell,
                into: &faceInk
            )
        }

        // Painter's order: shadow, wheel, then body bottom-up with the face last.
        let shadow = Path(ellipseIn: CGRect(
            x: rect.midX - spriteWidth * 0.42,
            y: originY + spriteHeight - cell * 0.35,
            width: spriteWidth * 0.84,
            height: cell * 1.1
        ))
        context.fill(shadow, with: .color(.black.opacity(0.22)))

        if mobility == .wheelchair {
            let side = spriteWidth * 1.02
            let wheel = Path(ellipseIn: CGRect(
                x: rect.midX - side / 2, y: originY + spriteHeight * 0.42, width: side, height: side
            ))
            context.stroke(wheel, with: .color(.egAgentCalm.opacity(0.9)), lineWidth: 1.8)
        }

        context.fill(botP, with: .color(bottomColors[botIdx]))
        context.fill(shoeP, with: .color(shoeColor))
        context.fill(caneP, with: .color(caneColor))
        context.fill(topP, with: .color(isStaff ? .egAgentStaff : topColors[topIdx]))
        context.fill(skinP, with: .color(skinTones[skinIdx]))
        context.fill(hairP, with: .color(hairColors[hairIdx]))
        context.fill(capP, with: .color(staffCapColor))
        context.fill(faceInk, with: .color(faceInkColor))
    }
}

// MARK: - Sprite

/// A chunky pixel silhouette drawn from a material map: each cell's character says which body part it
/// is, so one figure paints in several colours. `scale` sizes the whole figure against the adult
/// baseline. Silhouettes are deliberately different shapes so the types read apart with no colour cue.
///
/// Material legend: `H` hair · `F` face (skin) · `S` hand (skin) · `T` top · `P` trousers/skirt ·
/// `B` shoe · `C` cane · `K` staff cap · space = empty.
private struct Sprite {
    let rows: [String]
    let scale: CGFloat

    var columns: Int {
        rows.map(\.count).max() ?? 0
    }

    /// Columns carrying a shoe (`B`) — the feet the walk cycle lifts, out of phase with each other.
    var shoeColumns: [Int] {
        var cols = Set<Int>()
        for line in rows {
            for (col, ch) in line.enumerated() where ch == "B" {
                cols.insert(col)
            }
        }
        return cols.sorted()
    }

    /// The bounding box of the face cells (`F`), in grid coordinates — where the eyes and mouth go.
    /// `nil` if this silhouette has no exposed face.
    var faceBox: (minRow: Int, maxRow: Int, minCol: Int, maxCol: Int)? {
        var minRow = Int.max, maxRow = Int.min, minCol = Int.max, maxCol = Int.min
        for (row, line) in rows.enumerated() {
            for (col, ch) in line.enumerated() where ch == "F" {
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
                minCol = min(minCol, col)
                maxCol = max(maxCol, col)
            }
        }
        guard minRow <= maxRow else { return nil }
        return (minRow, maxRow, minCol, maxCol)
    }

    static func forMobility(_ mobility: MobilityClass, female: Bool) -> Sprite {
        switch mobility {
        case .adult: female ? adultFemale : adultMale
        case .child: child
        case .elderly: elderly
        case .wheelchair: wheelchair
        case .staff: staff
        }
    }

    /// Broad shoulders, arms at the sides, two stepping legs — the reference male build.
    static let adultMale = Sprite(rows: [
        " HHHH ",
        "HHHHHH",
        "HFFFFH",
        " FFFF ",
        " TTTT ",
        "TTTTTT",
        "STTTTS",
        " PPPP ",
        " P  P ",
        " B  B "
    ], scale: 1.0)

    /// Longer hair framing the face, narrower shoulders — reads female without relying on colour.
    static let adultFemale = Sprite(rows: [
        " HHHH ",
        "HHHHHH",
        "HFFFFH",
        "HFFFFH",
        " TTTT ",
        " TTTT ",
        "STTTTS",
        " PPPP ",
        " P  P ",
        " B  B "
    ], scale: 0.98)

    /// Same build, scaled right down — reads as "small person".
    static let child = Sprite(rows: [
        " HH ",
        "HFFH",
        " FF ",
        " TT ",
        "STTS",
        " PP ",
        " BB "
    ], scale: 0.72)

    /// Hunched, grey (forced), a cane down the right side.
    static let elderly = Sprite(rows: [
        " HHHH ",
        "HHHHHH",
        "HFFFH ",
        " FFF  ",
        " TTT C",
        "TTTTTC",
        "STTTS ",
        " PPPP ",
        " P  P ",
        " B  B "
    ], scale: 0.9)

    /// Seated block — no standing legs; the wheel ring is drawn around it separately.
    static let wheelchair = Sprite(rows: [
        " HHHH ",
        "HFFFFH",
        " FFFF ",
        " TTTT ",
        "TTTTTT",
        "STTTTS",
        " PPPP ",
        " PPPP "
    ], scale: 1.0)

    /// Flat cap over the brow (`K`) and a plum vest torso (`T` → staff colour) — the "marshal" cues.
    static let staff = Sprite(rows: [
        "KKKKKK",
        " KKKK ",
        " FFFF ",
        " FFFF ",
        " TTTT ",
        "TTTTTT",
        "STTTTS",
        " PPPP ",
        " P  P ",
        " B  B "
    ], scale: 1.0)
}
