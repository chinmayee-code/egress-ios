import Foundation
import Observation

// MARK: - FeedbackSettings

/// The user's feedback preferences (§3.6 / §5.5.4): the master sound switch and the two
/// "reduce intensity" toggles. Persisted to `UserDefaults` so a choice survives relaunch, and
/// `@Observable` so the Settings sheet, the audio engine and the haptic engine all react the
/// instant it flips.
///
/// Reduce **Motion** is deliberately absent here — it is a *system* setting read through
/// `@Environment(\.accessibilityReduceMotion)`, never duplicated as an app toggle (§5.6). Audio,
/// haptics and motion are three orthogonal channels, each with its own control surface.
@MainActor
@Observable
final class FeedbackSettings {
    /// Master mute. Off ⇒ every cue is silent; haptics and visuals are untouched (audio is never the
    /// sole channel for a safety event, §5.5 rule 6, so muting it loses nothing critical).
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled.rawValue) }
    }

    /// Caps stings at −6 dB and softens the soundstage (§3.6) — a calmer mix, not silence.
    var reduceAudioIntensity: Bool {
        didSet { defaults.set(reduceAudioIntensity, forKey: Key.reduceAudioIntensity.rawValue) }
    }

    /// Halves every haptic intensity and collapses `haptic.crush` to a single transient (§5.5.4).
    var reduceHapticIntensity: Bool {
        didSet { defaults.set(reduceHapticIntensity, forKey: Key.reduceHapticIntensity.rawValue) }
    }

    /// Overlays a per-band texture (sparse dots → diagonal hatch → cross-hatch) on the density canvas so
    /// the crowding bands are distinguishable by *pattern*, not colour alone (§5.6, colour-vision pass).
    /// Defaults ON — colour must never be the sole channel for a safety signal.
    var colorBlindPatterns: Bool {
        didSet { defaults.set(colorBlindPatterns, forKey: Key.colorBlindPatterns.rawValue) }
    }

    /// First-run coachmark flags — one per core screen. Each flips true when its tour is finished or
    /// skipped, so a tour shows exactly once until the user replays it. Default false (unseen).
    var seenSpacesTour: Bool {
        didSet { defaults.set(seenSpacesTour, forKey: Key.seenSpacesTour.rawValue) }
    }

    var seenEditorTour: Bool {
        didSet { defaults.set(seenEditorTour, forKey: Key.seenEditorTour.rawValue) }
    }

    var seenSimulateTour: Bool {
        didSet { defaults.set(seenSimulateTour, forKey: Key.seenSimulateTour.rawValue) }
    }

    /// Re-arm every tour so the coachmarks play again on the next visit to each screen (Settings → Replay).
    func replayTours() {
        seenSpacesTour = false
        seenEditorTour = false
        seenSimulateTour = false
    }

    /// Sound and colour-blind patterns default ON (both part of the intended, accessible experience);
    /// the two "reduce" toggles default OFF. `didSet` never fires for assignments made inside `init`, so
    /// this seeds the store lazily on first write rather than stamping defaults on launch.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Key.soundEnabled.rawValue) as? Bool ?? true
        reduceAudioIntensity = defaults.bool(forKey: Key.reduceAudioIntensity.rawValue)
        reduceHapticIntensity = defaults.bool(forKey: Key.reduceHapticIntensity.rawValue)
        colorBlindPatterns = defaults.object(forKey: Key.colorBlindPatterns.rawValue) as? Bool ?? true
        seenSpacesTour = defaults.bool(forKey: Key.seenSpacesTour.rawValue)
        seenEditorTour = defaults.bool(forKey: Key.seenEditorTour.rawValue)
        seenSimulateTour = defaults.bool(forKey: Key.seenSimulateTour.rawValue)
    }

    private let defaults: UserDefaults
    private enum Key: String {
        case soundEnabled, reduceAudioIntensity, reduceHapticIntensity, colorBlindPatterns
        case seenSpacesTour, seenEditorTour, seenSimulateTour
    }
}
