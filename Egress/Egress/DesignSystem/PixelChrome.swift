import SwiftUI

// MARK: - PixelCornerRect

/// A rounded rectangle whose corners are quantised into square "pixels" — the chunky 8-bit border used on
/// the recent-runs container, the run pills and the tab bar (design: the Spaces screenshot). Each corner is
/// a staircase of `pixel`-sized steps approximating a quarter circle of `radius`, so the outline reads as
/// retro pixel-art rather than a smooth squircle. Conforms to `InsettableShape` so `.fill()` and
/// `.strokeBorder()` compose exactly like `RoundedRectangle` does in `egRaisedSurface`.
struct PixelCornerRect: InsettableShape {
    /// Corner radius before quantisation. Pass `height / 2` for a pixel-ended stadium (the tab bar pill).
    var radius: CGFloat
    /// Edge length of one corner step — bigger = chunkier, fewer steps.
    var pixel: CGFloat
    private var insetAmount: CGFloat = 0

    init(radius: CGFloat, pixel: CGFloat) {
        self.radius = radius
        self.pixel = pixel
    }

    func inset(by amount: CGFloat) -> PixelCornerRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(self.radius, min(r.width, r.height) / 2)
        let steps = max(1, Int((radius / max(1, pixel)).rounded()))
        let step = radius / CGFloat(steps)

        // How far a corner column is pushed in from the outer edge, `k` steps along the quarter circle.
        // drop(0) = 0 (flush with the edge), drop(steps) = radius (the straight edge resumes).
        func drop(_ k: Int) -> CGFloat {
            let along = CGFloat(k) * step
            return radius - sqrt(max(0, radius * radius - along * along))
        }

        var path = Path()
        let (minX, minY, maxX, maxY) = (r.minX, r.minY, r.maxX, r.maxY)

        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        // Top-right corner staircase — holds the top edge across each step, then drops to the arc.
        for k in 1 ... steps {
            let x = maxX - radius + CGFloat(k) * step
            path.addLine(to: CGPoint(x: x, y: minY + drop(k - 1)))
            path.addLine(to: CGPoint(x: x, y: minY + drop(k)))
        }
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        // Bottom-right corner.
        for k in 1 ... steps {
            let y = maxY - radius + CGFloat(k) * step
            path.addLine(to: CGPoint(x: maxX - drop(k - 1), y: y))
            path.addLine(to: CGPoint(x: maxX - drop(k), y: y))
        }
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        // Bottom-left corner.
        for k in 1 ... steps {
            let x = minX + radius - CGFloat(k) * step
            path.addLine(to: CGPoint(x: x, y: maxY - drop(k - 1)))
            path.addLine(to: CGPoint(x: x, y: maxY - drop(k)))
        }
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        // Top-left corner.
        for k in 1 ... steps {
            let y = minY + radius - CGFloat(k) * step
            path.addLine(to: CGPoint(x: minX + drop(k - 1), y: y))
            path.addLine(to: CGPoint(x: minX + drop(k), y: y))
        }
        path.closeSubpath()
        return path
    }
}

extension View {
    /// Raised card with the pixel-art outline — the `egRaisedSurface` sibling for chrome that wants the
    /// chunky 8-bit border (the recent-runs container). Solid cream fill inside a stepped charcoal edge.
    func egPixelSurface(radius: CGFloat = EgressRadius.lg, pixel: CGFloat = 5, lineWidth: CGFloat = 2.5) -> some View {
        let shape = PixelCornerRect(radius: radius, pixel: pixel)
        return background(shape.fill(Color.egSurfaceRaised))
            .overlay(shape.strokeBorder(Color.egOutline, lineWidth: lineWidth))
    }
}

// MARK: - PixelText

/// A short string drawn in the app's own 5×7 bitmap font — the retro "30" score and the FAIL / PASS / WARN
/// pill labels (design: the Spaces screenshot). Rendered as filled squares in a `Canvas`, so it's genuinely
/// pixel-art (no font file, all original) and tints with any colour. VoiceOver reads the surrounding row.
struct PixelText: View {
    let text: String
    /// Edge length of one font-pixel — the string is `PixelFont.height * pixel` tall.
    var pixel: CGFloat = 3
    var color: Color = .egTextPrimary
    /// Blank font-pixels between glyphs.
    var spacing: Int = 1

    var body: some View {
        let glyphs = text.uppercased().map(PixelFont.rows(for:))
        let columns = glyphs.count * PixelFont.width + max(0, glyphs.count - 1) * spacing
        let width = CGFloat(columns) * pixel
        let height = CGFloat(PixelFont.height) * pixel

        return Canvas { context, _ in
            var originColumn = 0
            for rows in glyphs {
                for (row, line) in rows.enumerated() {
                    for (column, mark) in line.enumerated() where mark == "#" {
                        let cell = CGRect(
                            x: CGFloat(originColumn + column) * pixel,
                            y: CGFloat(row) * pixel,
                            width: pixel, height: pixel
                        )
                        context.fill(Path(cell), with: .color(color))
                    }
                }
                originColumn += PixelFont.width + spacing
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - PixelBitmap

/// A small original pixel-art glyph — a grid of "#" (ink) / " " (paper) rows drawn as filled squares in a
/// `Canvas`, the icon sibling of `PixelText`. Used for the preset cards' capacity/difficulty icons and the
/// onboarding tour's matching legend, so both draw exactly the same art.
struct PixelBitmap: View {
    let rows: [String]
    /// Edge length of one pixel.
    var pixel: CGFloat = 2
    var color: Color = .egTextPrimary

    var body: some View {
        let height = rows.count
        let width = rows.map(\.count).max() ?? 0
        Canvas { context, _ in
            for (y, line) in rows.enumerated() {
                for (x, mark) in line.enumerated() where mark == "#" {
                    let cell = CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)
                    context.fill(Path(cell), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(width) * pixel, height: CGFloat(height) * pixel)
        .accessibilityHidden(true)
    }
}

// MARK: - StatGlyph

/// The shared capacity / difficulty stat icons behind `PixelBitmap`, so the preset cards and the first-run
/// tour draw the same pixel art. `capacity` is a little person; `difficulty` is three ascending bars.
enum StatGlyph {
    static let capacity = [
        " ### ",
        " ### ",
        "  #  ",
        " ### ",
        "#####",
        "# # #",
        "# # #",
    ]
    static let difficulty = [
        "    #",
        "    #",
        "  # #",
        "  # #",
        "# # #",
        "# # #",
        "# # #",
    ]
}

// MARK: - PixelFont

/// The tiny 5×7 bitmap font behind `PixelText` — just the glyphs the run rows need (digits for the score,
/// and the letters in PASS / WARN / FAIL). Unknown characters render blank. Each glyph is seven 5-wide rows
/// of "#" (ink) and " " (paper).
enum PixelFont {
    static let width = 5
    static let height = 7

    static func rows(for character: Character) -> [String] {
        glyphs[character] ?? blank
    }

    private static let blank = Array(repeating: "     ", count: height)

    private static let glyphs: [Character: [String]] = [
        "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
        "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
        "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
        "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
        "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
        "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
        "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
        "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
        "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
        "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
        "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
        "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
        "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
        "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
        "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ### "],
        "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
        "I": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "#####"],
        "J": ["  ###", "   # ", "   # ", "   # ", "#  # ", "#  # ", " ##  "],
        "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
        "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
        "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
        "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
        "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
        "N": ["#   #", "##  #", "# # #", "# # #", "#  ##", "#   #", "#   #"],
        "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
        "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
        "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
        "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
        "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
        "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
        "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
        "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
        "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
        "!": ["  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "     ", "  #  "],
        "+": ["     ", "  #  ", "  #  ", "#####", "  #  ", "  #  ", "     "],
    ]
}

#Preview {
    VStack(spacing: EgressSpacing.lg) {
        PixelText(text: "30", pixel: 5, color: .egVerdictFail)
        PixelText(text: "FAIL", pixel: 2.4, color: .egVerdictFail)
        PixelText(text: "PASS", pixel: 2.4, color: .egVerdictPass)
        Text("container").egPixelSurface().padding()
    }
    .padding(EgressSpacing.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.egGround)
    .preferredColorScheme(.light)
}
