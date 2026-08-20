import SwiftUI

// MARK: - FeedbackServices

/// The composition root for the feedback channels: one settings store shared by the audio and haptic
/// engines, injected once at the app root and read anywhere via `@Environment(FeedbackServices.self)`.
/// Keeping the three together means a view fires a cue (`feedback.sound.play(.klaxon)`) without wiring
/// up three separate dependencies.
@MainActor
@Observable
final class FeedbackServices {
    let settings: FeedbackSettings
    let haptics: Haptics
    let sound: SoundPlayer

    init() {
        let settings = FeedbackSettings()
        self.settings = settings
        haptics = Haptics(settings: settings)
        sound = SoundPlayer(settings: settings)
    }

    /// Honour the §5.4 engine-restart discipline: stop both engines on the way to the background so a
    /// phone call or app switch can't leave a stuck session; they restart lazily on the next cue.
    func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            sound.stop()
            haptics.stop()
        case .active:
            // The engine was torn down on the way to the background; fade the music bed back if one was on.
            sound.resumeMusicIfNeeded()
        default:
            break
        }
    }
}
