import EgressEngine
import SwiftData
import SwiftUI

// MARK: - SimulateRootView

/// Simulate tab entry — owns the tab's own load lifecycle (§E.2): an explicit **empty** first-launch, a
/// route-solve **loading** warm-up, then the live `SimulateScreen`. The editor pushes
/// `SimulateScreen(venue:config:)` into its own stack instead and bypasses this — it always arrives with
/// a venue already in hand.
struct SimulateRootView: View {
    @State private var phase: LoadPhase = .empty

    private enum LoadPhase {
        case empty
        case loading(Double)
        case ready(VenueModel, SimulationConfig)
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .empty:
            CanvasHost { SimulateEmptyState(onLoadDemo: loadDemo) }
                .navigationTitle("Simulate")
                .navigationBarTitleDisplayMode(.inline)
        case let .loading(progress):
            CanvasHost { SimulateLoadingState(progress: progress) }
                .navigationTitle("Simulate")
                .navigationBarTitleDisplayMode(.inline)
        case let .ready(venue, config):
            SimulateScreen(venue: venue, config: config)
        }
    }

    /// Load the demo scenario through a genuine route-solve warm-up: constructing the engine builds the
    /// flow field and spawns the crowd (the real work), so the first rendered frame is never a frozen
    /// canvas. The determinate indicator is paced briefly so the state stays legible in the recording.
    private func loadDemo() {
        let (venue, config) = SampleVenue.moneyShotDemo()
        phase = .loading(0.15)
        Task { @MainActor in
            phase = .loading(0.5)
            _ = Simulation(venue: venue, config: config) // real flow-field solve + spawn
            try? await Task.sleep(for: .milliseconds(350))
            phase = .loading(1.0)
            try? await Task.sleep(for: .milliseconds(140))
            phase = .ready(venue, config)
        }
    }
}

// MARK: - SimulateScreen

/// Simulation host — owns the run and shows the live canvas, HUD, escalation banner and transport
/// controls, then the results sheet the moment the run resolves (§0.9 core journey). Reusable: the
/// Simulate tab shows the demo venue; the editor hands in a user-authored venue + crowd.
struct SimulateScreen: View {
    @Environment(\.modelContext)
    private var modelContext
    /// Optional so SwiftUI previews that don't inject the feedback root still render (they simply run silent).
    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?
    /// Data-motion stays; decorative motion (the banner spring) softens to a cross-fade (§5.6).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    /// Drives the return-from-background pause (§E.2) — a run is never advanced while the app is away.
    @Environment(\.scenePhase)
    private var scenePhase

    @State private var controller: SimulationController
    @State private var showSettings = false
    /// Set when a running sim is held on the way to the background; a return shows `PAUSED`, no auto-resume.
    @State private var pausedOnReturn = false
    /// Latest device thermal state — a `.serious`/`.critical` reading raises the step-down notice (§E.2).
    @State private var thermalState = ProcessInfo.processInfo.thermalState
    /// Last VoiceOver announcement time — escalation/verdict announcements stay ≥4 s apart (§5.6).
    @State private var lastAnnouncement: Date = .distantPast
    /// Tracks processed casualties so every dying agent gets their specific death sound once.
    @State private var processedCasualtyIDs: Set<Int> = []

    init(
        venue: VenueModel = SampleVenue.crowdedClub(),
        config: SimulationConfig = SimulationConfig(agentCount: 170, maxValidatedAgents: 300, seed: 42)
    ) {
        _controller = State(initialValue: SimulationController(venue: venue, config: config))
    }

    var body: some View {
        // The dark game-screen is framed in cream: only the canvas stays dark so agents, density and
        // hazards read; the HUD, banner and controls take the friendly cream shell (design hero).
        VStack(spacing: EgressSpacing.md) {
            CanvasHost {
                SimCanvasView(controller: controller, patternFills: feedback?.settings.colorBlindPatterns ?? true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        VStack(spacing: EgressSpacing.sm) {
                            SimHUDPill(
                                venueName: controller.venue.name,
                                agents: controller.configuredAgents,
                                elapsed: controller.snapshot.live.elapsed,
                                fps: controller.fps,
                                band: densityBand
                            )
                            .tourAnchor(.simHUD)
                            if let escalation = controller.escalation {
                                EscalationBanner(escalation: escalation)
                            }
                        }
                        .padding(.top, EgressSpacing.sm)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        SimDensityChip(density: controller.snapshot.live.worstDensity, band: densityBand)
                            .padding([.bottom, .trailing], EgressSpacing.md)
                    }
                    .overlay(alignment: .bottomLeading) {
                        SimZoomControls(controller: controller)
                            .padding(EgressSpacing.md)
                            .tourAnchor(.simZoom)
                    }
                    .overlay(alignment: .bottom) {
                        if let notice = performanceNotice {
                            PerformanceNotice(kind: notice).padding(EgressSpacing.sm)
                        }
                    }
                    .overlay {
                        if pausedOnReturn {
                            PausedOnReturnPanel(onResume: resumeAfterReturn)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.banner, value: controller.escalation)
            }
            .clipShape(RoundedRectangle.egSquircle(EgressRadius.lg))
            .overlay(
                RoundedRectangle.egSquircle(EgressRadius.lg)
                    .strokeBorder(Color.egOutline, lineWidth: 2)
            )

            if let escalation = controller.escalation {
                RallyLiveCard(escalation: escalation)
            }

            controls
                .tourAnchor(.simTransport)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.banner, value: controller.escalation)
        .padding(EgressSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.egGround)
        .navigationTitle(controller.venue.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // a run is full-screen — the back button returns to Spaces
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(app: .settings) }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            thermalState = ProcessInfo.processInfo.thermalState
        }
        .onChange(of: escalationKey) { _, _ in announceEscalation() }
        .onChange(of: controller.isRunning) { _, running in
            if running {
                feedback?.sound.startAmbience()
                updateAmbience()
            } else {
                feedback?.sound.stopAmbience()
            }
        }
        .onChange(of: controller.snapshot.time) { _, _ in
            updateAmbience()
            checkCasualties()
        }
        // A soft, low music bed plays for the whole time you're in a run (paused or not), entering at a
        // random point each time; the crowd/fire ambience above rides on top only while running.
        .onAppear { feedback?.sound.startBackgroundMusic(.simulation) }
        .onDisappear {
            feedback?.sound.stopAmbience()
            feedback?.sound.stopBackgroundMusic()
        }
        .onChange(of: controller.result?.id) { _, id in
            if id != nil {
                persistLatestRun()
                announceVerdict()
            }
        }
        .sheet(isPresented: resultPresented) {
            if let result = controller.result {
                ResultsSheet(
                    result: result,
                    onApply: { controller.applyFixAndRerun($0) },
                    onRunAgain: { controller.reset()
                        controller.play()
                    },
                    onDone: { controller.dismissResult() }
                )
            }
        }
        .tourHost(
            Tours.simulate,
            hasSeen: Binding(
                get: { feedback?.settings.seenSimulateTour ?? true },
                set: { feedback?.settings.seenSimulateTour = $0 }
            )
        )
    }

    /// Drives the results sheet off the controller's `result`; dismissing clears it.
    private var resultPresented: Binding<Bool> {
        Binding(
            get: { controller.result != nil },
            set: {
                if !$0 {
                    controller.dismissResult()
                }
            }
        )
    }

    private func persistLatestRun() {
        guard let result = controller.result else { return }
        // Fire isn't recoverable from geometry alone — read it from live hazard state (or infer from any
        // casualties, the only current hazard source) so the report's hazard flags are honest.
        let hasFire = !controller.snapshot.hazards.fire.isEmpty || result.metrics.casualties > 0
        let snapshot = RunReportSnapshot(result: result, venue: controller.venue, hasFire: hasFire)
        let record = RunRecord(
            id: result.id, // keyed to the RunResult so coach prose can be patched in once it resolves
            venueName: controller.venue.name,
            venueTypeRaw: controller.venue.type.rawValue,
            score: result.score.value,
            verdictRaw: result.verdict.level.rawValue,
            clearanceTime: result.metrics.clearance,
            occupancy: result.metrics.spawnedCount,
            seed: String(controller.seed),
            reportJSON: snapshot.jsonString
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    // MARK: States & recovery (§E.2)

    /// Hold a running sim when the app leaves the foreground and never auto-resume on return — the run is
    /// only advanced while it's being watched. Coming back raises the `PAUSED` panel.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .inactive, .background:
            if controller.isRunning {
                controller.pause()
                pausedOnReturn = true
            }
        default:
            break
        }
    }

    /// Explicit resume from the `PAUSED` panel — the only way a backgrounded run continues.
    private func resumeAfterReturn() {
        pausedOnReturn = false
        controller.play()
    }

    /// The single performance step-down notice to show, if any (§E.2 failure/recovery). A hot device takes
    /// precedence over the above-budget line; neither shows once the run has resolved.
    private var performanceNotice: PerformanceNotice.Kind? {
        guard controller.result == nil else { return nil }
        switch thermalState {
        case .serious: return .thermal("serious")
        case .critical: return .thermal("critical")
        default:
            return controller.isAboveBudget
                ? .aboveBudget(agents: controller.configuredAgents, budget: controller.validatedBudget)
                : nil
        }
    }

    // MARK: Feedback (§5.5) + VoiceOver announcements (§5.6)

    /// Identity that changes on each new live escalation, so `.onChange` fires once per crossing.
    private var escalationKey: String? {
        controller.escalation.map { "\($0.band)-\($0.time)" }
    }

    /// Start or pause. A fresh start *is* the emergency alarm — klaxon sound + custom haptic (§5.5).
    private func togglePlay() {
        if controller.isRunning {
            controller.pause()
        } else {
            if controller.snapshot.live.elapsed == 0 {
                processedCasualtyIDs.removeAll()
                feedback?.sound.play(.startSim)
                feedback?.haptics.play(.alarm)
            }
            controller.play()
        }
    }

    /// A new live band crossed: the warning or death cue, the band-specific haptic, and a throttled announcement.
    private func announceEscalation() {
        guard let escalation = controller.escalation else { return }
        if escalation.band != .casualty {
            feedback?.sound.play(.warning)
        }
        switch escalation.band {
        case .congestion: feedback?.haptics.play(.congestion)
        case .bottleneck: feedback?.haptics.play(.bottleneck)
        case .crush: feedback?.haptics.play(.crush)
        case .exitBlocked: feedback?.haptics.play(.exitBlocked)
        case .casualty: feedback?.haptics.play(.casualty)
        }
        announce(escalation.band.headline, throttled: true)
    }

    /// Check for any new casualty agent and play their gender-specific or default death sound.
    private func checkCasualties() {
        if controller.snapshot.time == 0 {
            processedCasualtyIDs.removeAll()
            return
        }
        for agent in controller.snapshot.agents where agent.status.isCasualty {
            // Each casualty sounds exactly once, the first frame they go down.
            guard processedCasualtyIDs.insert(agent.id).inserted else { continue }
            if agent.mobility == .adult {
                // Match the on-screen sprite's own gender so the voice fits the visible character.
                feedback?.sound.playDeath(AgentSprites.readsAsMale(id: agent.id) ? .deathMale : .deathFemale)
            } else {
                // Child / elderly / wheelchair / staff → the neutral impact (no gendered vocal).
                feedback?.sound.playDeath(.deathImpact)
            }
        }
    }

    /// The end-of-run verdict announcement — posted immediately so a VoiceOver user hears the outcome
    /// as the sheet appears. It always posts (§5.6 priority: a verdict pre-empts a lingering escalation).
    /// The verdict *sound* and *haptic* fire in `ResultsSheet`, synced to the end of the score-ring
    /// reveal, so the felt/heard payoff lands with the final number.
    private func announceVerdict() {
        guard let result = controller.result else { return }
        announce("\(result.verdict.level.label). Safety score \(result.score.value) out of 100.", throttled: false)
    }

    /// Post a VoiceOver announcement. Escalations are throttled to ≥4 s apart so a busy run doesn't
    /// chatter; the verdict overrides the throttle.
    private func announce(_ message: String, throttled: Bool) {
        let now = Date()
        if throttled, now.timeIntervalSince(lastAnnouncement) < 4 {
            return
        }
        lastAnnouncement = now
        AccessibilityNotification.Announcement(message).post()
    }

    /// The live crowding band, read off peak density — shared by the HUD status chip and the corner
    /// density chip so they never disagree.
    private var densityBand: SimDensityBand {
        SimDensityBand(density: controller.snapshot.live.worstDensity)
    }

    /// Drive the ambient beds from the live run: crowd murmur scales with peak density AND the remaining
    /// active crowd ratio (fading out smoothly as agents evacuate towards the end).
    private func updateAmbience() {
        guard controller.isRunning else { return }
        let live = controller.snapshot.live
        let totalAgents = live.activeCount + live.evacuatedCount + live.casualtyCount
        let activeFraction = totalAgents > 0 ? Double(live.activeCount) / Double(totalAgents) : 0
        let densityFactor = min(1.0, live.worstDensity / 6.0)

        // Crowd murmur scales dynamically with active crowd ratio, fading out to 0 at the end of run
        let crowd = (0.15 + 0.85 * densityFactor) * activeFraction
        let fire = min(1.0, Double(controller.snapshot.hazards.fire.count) / 40.0)
        feedback?.sound.setAmbience(crowd: crowd, fire: fire)
    }

    private var controls: some View {
        VStack(spacing: EgressSpacing.lg) {
            SimTimeline(
                progress: timelineProgress,
                elapsed: controller.displaySnapshot.live.elapsed,
                ticks: timelineTicks,
                tint: densityBand.tint,
                seekable: timelineSeekable,
                onScrub: { fraction in
                    let span = Double(max(1, controller.frameCount - 1))
                    controller.seek(toIndex: Int((fraction * span).rounded()))
                }
            )
            SimTransportBar(
                isRunning: controller.isRunning,
                isComplete: controller.isComplete,
                canStepBack: controller.frameCount > 1,
                isScrubbing: controller.isScrubbing,
                onRestart: { controller.reset() },
                onStepBack: { controller.stepBack() },
                onPlayPause: togglePlay,
                onStepForward: { controller.stepForward() },
                onRecenter: { controller.returnToLive() }
            )
        }
    }

    /// The timeline can be scrubbed only when the run is paused (or done) and there are frames to scrub.
    private var timelineSeekable: Bool {
        !controller.isRunning && controller.frameCount > 1
    }

    /// While running, the fill shows how much of the crowd is out; paused/finished, it shows the scrub
    /// position across the recorded frames.
    private var timelineProgress: Double {
        if timelineSeekable {
            return Double(controller.displayIndex) / Double(max(1, controller.frameCount - 1))
        }
        return controller.snapshot.live.fractionOut
    }

    /// Escalation ticks, placed as fractions of the recorded run — only meaningful once the tape can be
    /// scrubbed, so they're hidden during a live run to avoid implying a known end.
    private var timelineTicks: [Double] {
        guard timelineSeekable else { return [] }
        let maxTime = max(0.001, controller.recordedDuration)
        return controller.escalationTimes.map { min(1, $0 / maxTime) }
    }
}

#Preview {
    SimulateRootView()
}
