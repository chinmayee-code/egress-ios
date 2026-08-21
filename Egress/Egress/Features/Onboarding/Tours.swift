import SwiftUI

// MARK: - Tour catalog

/// The scripted coachmark tours for the core three screens. Copy is in the mascot's warm, plain voice —
/// each line names the control and what it does, nothing more. Kept as data so the overlay stays dumb and
/// the steps are trivial to reorder or retune.
enum Tours {
    /// Spaces: settings → a preset card → the ＋ create action.
    static let spaces = Tour(steps: [
        TourStep(
            anchor: nil,
            title: "Welcome",
            message: "Hi! I'm your safety inspector. Let me show you around in a few taps."
        ),
        TourStep(
            anchor: .spacesPreset,
            title: "Presets",
            message: "Start from a furnished room — tap a card to open it. The two icons on each card mean:",
            legend: [
                TourLegendItem(icon: StatGlyph.capacity, tint: .egVerdictPass, text: "Capacity — how many people are in the room"),
                TourLegendItem(icon: StatGlyph.difficulty, tint: .egAccentTerracotta, text: "Difficulty — how hard it is to clear, 1 to 3"),
            ]
        ),
        TourStep(
            anchor: .spacesCreate,
            title: "Create",
            message: "Or tap ＋ to build your own space from a blank floor."
        ),
        TourStep(
            anchor: .spacesSettings,
            title: "Settings",
            message: "Sound, haptics and accessibility live here — and you can replay these tips anytime."
        ),
    ])

    /// Editor: the tool tray → configuration → run.
    static let editor = Tour(steps: [
        TourStep(
            anchor: .editorTools,
            title: "Tools",
            message: "Build walls and exits, drop props, and add fire or water — all from this tray."
        ),
        TourStep(
            anchor: .editorConfig,
            title: "Configure",
            message: "Set the crowd size, room details and hazards in the full settings here."
        ),
        TourStep(
            anchor: .editorRun,
            title: "Run",
            message: "When your room's ready, hit play to run the evacuation and see how it holds up."
        ),
    ])

    /// Simulate: the HUD → transport → zoom.
    static let simulate = Tour(steps: [
        TourStep(
            anchor: .simHUD,
            title: "Live readout",
            message: "Watch the crowd, the clock, and the crowding band as everyone tries to get out."
        ),
        TourStep(
            anchor: .simTransport,
            title: "Playback",
            message: "Play, pause, step frame-by-frame, or scrub back to study a jam."
        ),
        TourStep(
            anchor: .simZoom,
            title: "Zoom",
            message: "Zoom in on a bottleneck or fit the whole floor — then read your verdict at the end."
        ),
    ])
}
