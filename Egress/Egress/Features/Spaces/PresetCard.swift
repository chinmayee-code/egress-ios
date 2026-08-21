import EgressEngine
import SwiftUI

// MARK: - PresetCard

/// A gallery card for one furnished preset, styled as a retro **game cartridge** (design: the cartridge
/// frame the user supplied — `cartridge_frame` in the asset catalog). The molded gray plastic shell is the
/// real PNG frame, with a transparent "screen" window: the live authored room plan is drawn behind it and
/// shows through, the preset name prints across the dark label strip, a CAPACITY · DIFFICULTY read-out sits
/// in the screen's bottom corner, and the venue's resident stands large in front, breaking out over the
/// screen border. Tapping loads exactly the room shown.
struct PresetCard: View {
    let preset: VenuePreset

    // The card is sized to the cropped frame PNG so nothing distorts (984 × 803 → w/h ≈ 1.225).
    private static let cardWidth: CGFloat = 260
    private static let frameAspect: CGFloat = 984.0 / 803.0

    // Regions measured from the frame PNG, as fractions of the cropped image (0…1).
    // The transparent screen window and the dark header well, respectively.
    private static let screen = (x0: 0.1128, y0: 0.3101, x1: 0.8862, y1: 0.8381)
    private static let header = (x0: 0.1118, y0: 0.0461, x1: 0.8872, y1: 0.2565)

    /// 1…3 — crowd pressure per exit, mapped to the difficulty squares (and the resident's mood).
    private var difficulty: Int {
        let perExit = Double(preset.crowd) / Double(max(1, preset.venue.exits.count))
        switch perExit {
        case ..<40: return 1
        case ..<80: return 2
        default: return 3
        }
    }

    /// The character who "lives" in this venue — one of the bundled pixel-art residents, picked from the
    /// preset's stable seed so a card keeps the same person across launches and never re-rolls on redraw.
    /// The pool is chosen to *match the difficulty* (design request): a calm, in-control resident on a LITE
    /// room, a neutral or mobility-aided one on STD, and a visibly alarmed one on PRO — the character's mood
    /// tracks the crowd pressure, so a one-square card never wears a panicked face.
    private var residentSprite: String {
        let pool = PresetCard.residents(for: difficulty)
        return pool[preset.id.pixelSeed % pool.count]
    }

    /// Resident sprites grouped by mood so a card's person reads its tier. Every id is a `sprite_N`
    /// character in `Assets.xcassets`; the item sprites (pills, hazard drops) are deliberately excluded.
    ///   • 1 — calm, waving, directing: relaxed and in control.
    ///   • 2 — neutral, older or mobility-aided: needs care, but isn't panicking.
    ///   • 3 — hands on head, arms flailing, frightened: the pressure shows.
    private static func residents(for difficulty: Int) -> [String] {
        let ids: [Int]
        switch difficulty {
        case 1: ids = [1, 3, 4, 5, 6, 7, 8, 9, 11, 13, 14, 20, 21, 22, 27, 28, 29, 30, 31] // calm / confident
        case 2: ids = [12, 15, 16, 17, 18, 19, 23, 25] // neutral / elderly / on the move
        default: ids = [2, 10, 24, 26] // alarmed / panicked
        }
        return ids.map { "sprite_\($0)" }
    }

    var body: some View {
        let cardHeight = PresetCard.cardWidth / PresetCard.frameAspect
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let s = PresetCard.screen, hd = PresetCard.header
            let sRect = CGRect(x: s.x0 * w, y: s.y0 * h, width: (s.x1 - s.x0) * w, height: (s.y1 - s.y0) * h)
            let hRect = CGRect(x: hd.x0 * w, y: hd.y0 * h, width: (hd.x1 - hd.x0) * w, height: (hd.y1 - hd.y0) * h)

            // 1) The live room plan, drawn behind the frame — shows through the transparent screen window.
            PresetThumbnail(venue: preset.venue)
                .frame(width: sRect.width, height: sRect.height)
                .position(x: sRect.midX, y: sRect.midY)

            // 2) The capacity / difficulty read-out — icon + value only — tucked into the screen's
            //    bottom-left tab (the frame's notch). Behind the frame, so any overflow is clipped.
            Color.clear
                .overlay(alignment: .bottomLeading) {
                    statReadout
                        .padding(.leading, sRect.minX + 5)
                        .padding(.bottom, (h - sRect.maxY) + 5)
                }

            // 3) The molded cartridge frame itself (gray shell, header well, stepped border, notches).
            Image("cartridge_frame")
                .resizable()
                .interpolation(.none)
                .frame(width: w, height: h)

            // 4) The preset name, centered across the dark label strip in the retro pixel font.
            PixelText(text: preset.title, pixel: 2.1, color: Color.egCanvasText)
                .position(x: hRect.midX, y: hRect.midY)

            // 5) The resident, standing large in front and breaking out over the screen's right border.
            Image(residentSprite)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(height: h * 0.62)
                .position(x: sRect.maxX - h * 0.06, y: sRect.maxY - h * 0.22)
        }
        .frame(width: PresetCard.cardWidth, height: cardHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(preset.title). \(preset.crowd) capacity, \(preset.venue.exits.count) exits, difficulty \(difficulty) of 3. \(preset.blurb)")
    }

    // MARK: Pieces

    /// The compact read-out in the bottom-left notch tab: capacity (green person icon + count) over
    /// difficulty (red bars icon + filled squares). Icons and values only — no text labels. A faint scrim
    /// keeps it legible over the room art.
    private var statReadout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                PixelBitmap(rows: StatGlyph.capacity, pixel: 1.4, color: Color.egVerdictPass)
                PixelText(text: "\(preset.crowd)", pixel: 1.6, color: Color.egCanvasText)
            }
            HStack(spacing: 4) {
                PixelBitmap(rows: StatGlyph.difficulty, pixel: 1.4, color: Color.egAccentTerracotta)
                difficultySquares
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.32)))
    }

    private var difficultySquares: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< 3, id: \.self) { i in
                Rectangle()
                    .fill(i < difficulty ? Color.egCanvasText : Color.clear)
                    .frame(width: 6, height: 6)
                    .overlay(Rectangle().strokeBorder(Color.egCanvasText.opacity(0.7), lineWidth: 1))
            }
        }
    }

}

// MARK: - PresetThumbnail

/// A small top-down plan of a venue — room outline, props, walls and exits — drawn on the dark canvas.
/// The grid is omitted (too busy at thumbnail scale); everything else matches the full canvas exactly.
struct PresetThumbnail: View {
    let venue: VenueModel

    var body: some View {
        Canvas { context, size in
            let projection = CanvasProjection(
                worldWidth: venue.geometry.worldWidth,
                worldHeight: venue.geometry.worldHeight,
                viewSize: size, inset: 8
            )
            let topLeft = projection.point(Vec2(0, 0))
            let bottomRight = projection.point(Vec2(venue.geometry.worldWidth, venue.geometry.worldHeight))
            let room = CGRect(
                x: topLeft.x, y: topLeft.y,
                width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y
            )
            context.stroke(
                Path(roundedRect: room, cornerRadius: 4),
                with: .color(.egSeparator), lineWidth: 1
            )
            VenueScenery.drawObstacles(venue.obstacles, projection: projection, into: &context)
            VenueScenery.drawWalls(venue.walls, projection: projection, into: &context)
            VenueScenery.drawExits(venue.exits, projection: projection, into: &context)
        }
        .background(Color.egCanvasBase)
        .environment(\.colorScheme, .dark)
    }
}
