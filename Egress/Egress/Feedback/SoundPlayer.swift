import AVFoundation
import Foundation
import QuartzCore

// MARK: - SoundPlayer

/// The §3.6 sound system: plays audio cues and looping ambience beds from bundled MP3 files
/// (with synthesized 8-bit fallback buffers) through one `AVAudioEngine`.
///
/// The session is `.ambient` + `.mixWithOthers`, so the **silent switch is respected** and the user's
/// own music is never interrupted. Audio carries no rubric weight of its own and is never the sole
/// channel for a safety event (§5.5 rule 6), so every failure path here is a silent no-op — the banner,
/// haptic and VoiceOver announcement already cover the event.
@MainActor
final class SoundPlayer {
    /// The cues the app plays across simulation and UI interactions.
    enum Cue {
        case klaxon
        case sting
        case verdictPass
        case verdictFail
        case popup
        case buttonTap
        case startSim
        case warning
        case deathMale
        case deathFemale
        case deathImpact
    }

    init(settings: FeedbackSettings) {
        self.settings = settings

        // Render synthesized fallback scores
        let klaxonFallback = Self.render(Self.klaxonScore)
        let stingFallback = Self.render(Self.stingScore)
        let passFallback = Self.render(Self.passScore)
        let failFallback = Self.render(Self.failScore)

        // Load bundled audio buffers (with fallback to synthesized scores)
        let startSimBuf = Self.loadBuffer(named: "start_sim") ?? klaxonFallback
        let warningBuf = Self.loadBuffer(named: "warning_alarm") ?? stingFallback
        let passBuf = Self.loadBuffer(named: "sim_success") ?? passFallback
        let failBuf = Self.loadBuffer(named: "sim_fail") ?? failFallback
        let popupBuf = Self.loadBuffer(named: "popup")
        let buttonTapBuf = Self.loadBuffer(named: "button_tap") ?? stingFallback
        let femaleDeathBuf = Self.loadBuffer(named: "death_female") ?? stingFallback
        let maleDeathBuf = Self.loadBuffer(named: "death_male") ?? stingFallback
        let impactDeathBuf = Self.loadBuffer(named: "death_impact") ?? stingFallback

        buffers = [
            .klaxon: startSimBuf,
            .startSim: startSimBuf,
            .sting: warningBuf,
            .warning: warningBuf,
            .verdictPass: passBuf,
            .verdictFail: failBuf,
            .popup: popupBuf ?? stingFallback,
            .buttonTap: buttonTapBuf,
            .deathMale: maleDeathBuf,
            .deathFemale: femaleDeathBuf,
            .deathImpact: impactDeathBuf
        ]

        // Create player node pool for polyphonic overlapping playback (8 nodes)
        playerNodes = (0 ..< 8).map { _ in AVAudioPlayerNode() }

        // Ambient beds — authentic crowd murmur MP3 or synthesized brown noise
        murmurBuffer = Self.loadBuffer(named: "crowd_murmur") ?? Self.renderMurmur()
        crackleBuffer = Self.renderCrackle()
    }

    /// Play a cue. Honours the master toggle and the −6 dB Reduce Audio Intensity cap; uses the player
    /// node pool so overlapping cues don't cut each other off or leak memory.
    func play(_ cue: Cue) {
        guard settings.soundEnabled, let buffer = buffers[cue] else { return }

        do {
            try startIfNeeded()
            // Format safety guard: player node connection requires matching sample rate & channel count
            guard buffer.format.sampleRate == Self.format.sampleRate &&
                buffer.format.channelCount == Self.format.channelCount else
            {
                return
            }

            // Pick an idle player node from the pool or recycle via round-robin
            let player = playerNodes.first(where: { !$0.isPlaying }) ?? playerNodes[nextPlayerIndex]
            nextPlayerIndex = (nextPlayerIndex + 1) % playerNodes.count

            let cap: Float = settings.reduceAudioIntensity ? 0.5 : 1.0

            // Soft matched volume (22% volume) for UI interaction cues (popup and button tap)
            let volume: Float = switch cue {
            case .popup, .buttonTap:
                0.22 * cap
            case .deathMale, .deathFemale, .deathImpact:
                0.6 * cap
            default:
                1.0 * cap
            }
            player.volume = volume

            if player.isPlaying {
                player.stop()
            }
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in }
            player.play()
        } catch {
            // Silent: the event's banner / haptic / announcement already carry it.
        }
    }

    // MARK: Death cues (burst-safe)

    /// Play a per-casualty death cue, but *space* rapid deaths so a mass-casualty frame reads as an
    /// audible staccato of individual people going down — not one muddy blast that thrashes the 8-node
    /// pool (which is exactly what made a burst sound like "one sound then nothing"). Deaths beyond
    /// `deathBurstCap` still queued are dropped: past the cap they'd only overlap inaudibly, and dropping
    /// them is what keeps a 150-agent crush from flooding the engine (the "no sound leaks" rule).
    func playDeath(_ cue: Cue) {
        guard settings.soundEnabled else { return }
        guard deathQueue.count < deathBurstCap else { return }
        deathQueue.append(cue)
        drainDeaths()
    }

    /// Emit the next queued death if enough time has passed since the last; otherwise wait out the gap.
    private func drainDeaths() {
        guard !deathDraining, !deathQueue.isEmpty else { return }
        let now = CACurrentMediaTime()
        let sinceLast = now - lastDeathAt
        if sinceLast >= deathMinGap {
            lastDeathAt = now
            play(deathQueue.removeFirst())
            if !deathQueue.isEmpty {
                scheduleDrain(after: deathMinGap)
            }
        } else {
            scheduleDrain(after: deathMinGap - sinceLast)
        }
    }

    /// One-shot main-actor timer to resume draining — `[weak self]`, so a teardown mid-burst can't leak.
    private func scheduleDrain(after delay: TimeInterval) {
        deathDraining = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.deathDraining = false
            self.drainDeaths()
        }
    }

    // MARK: Ambient beds (crowd murmur + fire crackle)

    /// Begin the looping ambience under a run. Both beds start silent; `setAmbience` fades them in to
    /// match the crowd. A no-op when sound is off, so the silent switch and master toggle still win.
    func startAmbience() {
        guard settings.soundEnabled else { return }
        do { try startIfNeeded() } catch { return }
        if !ambienceScheduled {
            if murmurBuffer.format.sampleRate == Self.format.sampleRate, murmurBuffer.format.channelCount == Self.format.channelCount {
                murmur.scheduleBuffer(murmurBuffer, at: nil, options: [.loops], completionCallbackType: .dataPlayedBack) { _ in }
            }
            if crackleBuffer.format.sampleRate == Self.format.sampleRate, crackleBuffer.format.channelCount == Self.format.channelCount {
                crackle.scheduleBuffer(crackleBuffer, at: nil, options: [.loops], completionCallbackType: .dataPlayedBack) { _ in }
            }
            ambienceScheduled = true
        }
        murmur.volume = 0
        crackle.volume = 0
        if !murmur.isPlaying {
            murmur.play()
        }
        if !crackle.isPlaying {
            crackle.play()
        }
        ambienceOn = true
    }

    /// Set the live ambience level. `crowd` and `fire` are 0…1 — the murmur swells with the crowd's
    /// arousal, the crackle with how much fire is on the floor. Held well below the one-shot cues so it
    /// never masks the alarm or a sting.
    func setAmbience(crowd: Double, fire: Double) {
        guard ambienceOn else { return }
        let cap: Float = settings.reduceAudioIntensity ? 0.5 : 1.0
        murmur.volume = Float(min(1, max(0, crowd))) * 0.22 * cap
        crackle.volume = Float(min(1, max(0, fire))) * 0.34 * cap
    }

    /// Stop the ambience (a pause, the end of a run, or leaving the screen). One-shot cues are unaffected.
    func stopAmbience() {
        murmur.stop()
        crackle.stop()
        ambienceOn = false
        ambienceScheduled = false
    }

    /// Tear the engine down on backgrounding (§5.4); it restarts lazily on the next `play`.
    func stop() {
        for node in playerNodes {
            node.stop()
        }
        deathQueue.removeAll()
        stopAmbience()
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        started = false
    }

    // MARK: Engine

    private let settings: FeedbackSettings
    private let engine = AVAudioEngine()
    /// Polyphonic pool of player nodes for overlapping sounds without leaks.
    private let playerNodes: [AVAudioPlayerNode]
    private var nextPlayerIndex = 0
    /// The two looping ambience voices, mixed in under the one-shot cues.
    private let murmur = AVAudioPlayerNode()
    private let crackle = AVAudioPlayerNode()
    private let session = AVAudioSession.sharedInstance()
    private let buffers: [Cue: AVAudioPCMBuffer]
    private let murmurBuffer: AVAudioPCMBuffer
    private let crackleBuffer: AVAudioPCMBuffer
    private var started = false
    private var ambienceOn = false
    private var ambienceScheduled = false

    /// Pending death cues awaiting their spacing slot, plus the rate-limit book-keeping.
    private var deathQueue: [Cue] = []
    private var deathDraining = false
    private var lastDeathAt: TimeInterval = 0
    /// Minimum gap between two death cues, and the most that may be queued in a burst.
    private let deathMinGap: TimeInterval = 0.12
    private let deathBurstCap = 10

    /// One mono 44.1 kHz float format shared by every buffer and the player→mixer connection.
    private static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private static let sampleRate: Double = 44100

    private func startIfNeeded() throws {
        guard !started else { return }
        try session.setCategory(.ambient, options: [.mixWithOthers]) // respect silent switch + others' audio
        try session.setActive(true)
        for node in playerNodes where engine.attachedNodes.contains(node) == false {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: Self.format)
        }
        for node in [murmur, crackle] where engine.attachedNodes.contains(node) == false {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: Self.format)
        }
        try engine.start()
        started = true
    }

    // MARK: - Audio File Loading

    private final class ConversionFlag: @unchecked Sendable {
        var supplied = false
    }

    /// Attempts to load an audio file from the app bundle or main bundle resources, converting it to `Self.format`.
    private static func loadBuffer(named name: String, ext: String = "mp3") -> AVAudioPCMBuffer? {
        let bundle = Bundle.main
        guard let url = bundle.url(forResource: name, withExtension: ext) ??
            bundle.url(forResource: name, withExtension: ext, subdirectory: "Sounds") ??
            bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/Sounds") else
        {
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let fileFormat = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else { return nil }
            try file.read(into: sourceBuffer)

            // If format already matches Self.format, return directly
            if fileFormat.sampleRate == format.sampleRate &&
                fileFormat.channelCount == format.channelCount &&
                fileFormat.commonFormat == format.commonFormat
            {
                return sourceBuffer
            }

            // Convert to Self.format (44.1 kHz, Mono float32)
            guard let converter = AVAudioConverter(from: fileFormat, to: format) else {
                return nil
            }

            let ratio = format.sampleRate / fileFormat.sampleRate
            let targetCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 100
            guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: targetCapacity) else {
                return nil
            }

            var error: NSError?
            let flag = ConversionFlag()
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if flag.supplied {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                flag.supplied = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            let status = converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)
            if status == .error || error != nil {
                return nil
            }

            return targetBuffer
        } catch {
            return nil
        }
    }

    // MARK: - Synthesis

    /// One note in a cue: pitch, length, timbre and gain.
    private struct Note { let hz: Double
        let seconds: Double
        let wave: Wave
        let gain: Float
    }

    private enum Wave { case square, triangle }

    /// 2-tone square alarm, 3 repetitions (A5 ↔ E5).
    private static let klaxonScore: [Note] = (0 ..< 3).flatMap { _ in
        [
            Note(hz: 880, seconds: 0.16, wave: .square, gain: 0.9),
            Note(hz: 659, seconds: 0.16, wave: .square, gain: 0.9)
        ]
    }

    /// 3-note descending square sting — the threshold / WARN cue.
    private static let stingScore: [Note] = [
        Note(hz: 784, seconds: 0.11, wave: .square, gain: 0.8),
        Note(hz: 659, seconds: 0.11, wave: .square, gain: 0.8),
        Note(hz: 523, seconds: 0.16, wave: .square, gain: 0.8)
    ]

    /// Ascending 5-note major arpeggio — the PASS fanfare (C E G C E).
    private static let passScore: [Note] = [
        Note(hz: 523, seconds: 0.10, wave: .square, gain: 0.75),
        Note(hz: 659, seconds: 0.10, wave: .square, gain: 0.75),
        Note(hz: 784, seconds: 0.10, wave: .square, gain: 0.75),
        Note(hz: 1046, seconds: 0.10, wave: .square, gain: 0.75),
        Note(hz: 1318, seconds: 0.20, wave: .square, gain: 0.8)
    ]

    /// Descending 4-note minor motif on soft triangle waves — low and sombre, never comedic.
    private static let failScore: [Note] = [
        Note(hz: 440, seconds: 0.16, wave: .triangle, gain: 0.7),
        Note(hz: 392, seconds: 0.16, wave: .triangle, gain: 0.7),
        Note(hz: 349, seconds: 0.16, wave: .triangle, gain: 0.7),
        Note(hz: 262, seconds: 0.30, wave: .triangle, gain: 0.7)
    ]

    /// Render a note sequence into one PCM buffer, with a short linear attack/release per note so the
    /// square edges don't click.
    private static func render(_ notes: [Note]) -> AVAudioPCMBuffer {
        let totalFrames = notes.reduce(0) { $0 + Int($1.seconds * sampleRate) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let samples = buffer.floatChannelData![0]

        var cursor = 0
        for note in notes {
            let frames = Int(note.seconds * sampleRate)
            let ramp = min(frames / 2, Int(0.005 * sampleRate)) // ≤5 ms fade in/out
            for i in 0 ..< frames {
                let phase = Double(i) / sampleRate * note.hz
                let raw: Float = note.wave == .square
                    ? (phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1)
                    : Float(4 * abs(phase.truncatingRemainder(dividingBy: 1) - 0.5) - 1) // triangle
                var envelope: Float = 1
                if i < ramp {
                    envelope = Float(i) / Float(ramp)
                } else if i > frames - ramp {
                    envelope = Float(frames - i) / Float(ramp)
                }
                samples[cursor + i] = raw * note.gain * envelope * 0.3 // 0.3 = headroom against clipping
            }
            cursor += frames
        }
        return buffer
    }

    // MARK: - Ambience synthesis

    private struct Noise {
        var state: UInt64
        mutating func bipolar() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 20001) / 10000.0 - 1.0
        }

        mutating func unit() -> Double {
            (bipolar() + 1) / 2
        }
    }

    private static func renderMurmur() -> AVAudioPCMBuffer {
        let seconds = 4.0
        let frames = Int(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]

        var rng = Noise(state: 0x9E37_79B9_7F4A_7C15)
        var brown = 0.0
        var low = 0.0
        var highPrevIn = 0.0
        var highPrevOut = 0.0
        var peak = 1e-6
        for i in 0 ..< frames {
            let white = rng.bipolar()
            brown = (brown + 0.02 * white) * 0.995
            low += 0.18 * (brown - low)
            let highOut = 0.92 * (highPrevOut + low - highPrevIn)
            highPrevIn = low
            highPrevOut = highOut
            let t = Double(i) / Double(frames)
            let sway = 0.6 + 0.4 * sin(2 * .pi * 3 * t)
            let value = highOut * sway
            samples[i] = Float(value)
            peak = max(peak, abs(value))
        }
        let gain = Float(0.6 / peak)
        for i in 0 ..< frames {
            samples[i] *= gain
        }
        return buffer
    }

    private static func renderCrackle() -> AVAudioPCMBuffer {
        let seconds = 4.0
        let frames = Int(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]

        var rng = Noise(state: 0xD1B5_4A32_D192_ED03)
        var brown = 0.0
        var low = 0.0
        for i in 0 ..< frames {
            brown = (brown + 0.02 * rng.bipolar()) * 0.995
            low += 0.05 * (brown - low)
            samples[i] = Float(low * 2.4)
        }
        let quietTail = Int(0.1 * sampleRate)
        for _ in 0 ..< 40 {
            let start = Int(rng.unit() * Double(frames - quietTail))
            let length = Int((0.005 + rng.unit() * 0.02) * sampleRate)
            let amp = 0.4 + rng.unit() * 0.5
            for k in 0 ..< length where start + k < frames {
                let envelope = exp(-Double(k) / Double(length) * 5)
                samples[start + k] += Float(rng.bipolar() * envelope * amp)
            }
        }
        var peak: Float = 1e-6
        for i in 0 ..< frames {
            peak = max(peak, abs(samples[i]))
        }
        let gain = 0.7 / peak
        for i in 0 ..< frames {
            samples[i] *= gain
        }
        return buffer
    }
}
