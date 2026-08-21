import SwiftUI

// MARK: - TourID

/// Every control a guided tour can point at, across the core three screens. A view marks itself a target
/// with `.tourAnchor(_:)`; the hosting `TourHost` resolves the id's on-screen bounds to place the spotlight
/// and arrow. Ids are screen-scoped by name only — each `TourHost` reads anchors from its own subtree, so
/// there is no cross-screen collision.
enum TourID: Hashable {
    // Spaces
    case spacesSettings, spacesPreset, spacesCreate
    // Editor
    case editorTools, editorConfig, editorRun
    // Simulate
    case simTransport, simZoom, simHUD
}

// MARK: - TourStep / Tour

/// One coachmark: the target to spotlight (nil = a centred intro with no arrow), plus the mascot's line.
struct TourStep: Identifiable {
    let id = UUID()
    /// The control to highlight, or nil for an untethered step.
    var anchor: TourID?
    /// Short uppercase eyebrow над the line (e.g. "RUN").
    var title: String
    /// What the mascot says about this control.
    var message: String
    /// Optional icon key below the line — teaches what an unlabeled pixel icon on screen means.
    var legend: [TourLegendItem] = []
}

/// One icon-and-caption row in a coachmark's legend, drawn with the same `PixelBitmap` art as the screen so
/// a first-time user learns exactly the glyph they're looking at (e.g. the preset cards' capacity icon).
struct TourLegendItem: Identifiable {
    let id = UUID()
    /// Pixel-art rows for `PixelBitmap` (see `StatGlyph`).
    var icon: [String]
    var tint: Color
    var text: String
}

/// An ordered set of coachmarks for one screen.
struct Tour {
    var steps: [TourStep]
}

// MARK: - Anchor plumbing

/// Collects every `.tourAnchor` bound in a subtree, keyed by id, for the host to resolve.
struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourID: Anchor<CGRect>], nextValue: () -> [TourID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Mark this view as a tour target under `id`. Its bounds ride up to the nearest `TourHost` via
    /// preferences — no coordinate maths at the call site, and it's inert until a tour is running.
    func tourAnchor(_ id: TourID) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Anchor only when `condition` holds — used to tag just the first item in a list (e.g. one preset card).
    @ViewBuilder
    func tourAnchor(_ id: TourID, if condition: Bool) -> some View {
        if condition { tourAnchor(id) } else { self }
    }
}
