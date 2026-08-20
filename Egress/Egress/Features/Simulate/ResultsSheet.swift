import EgressEngine
import SwiftData
import SwiftUI

// MARK: - Verdict presentation

extension VerdictLevel {
    /// The verdict tint from the design token table (§5).
    var tint: Color {
        switch self {
        case .pass: .egVerdictPass
        case .warn: .egVerdictWarn
        case .fail: .egVerdictFail
        }
    }

    var symbol: AppSymbol {
        switch self {
        case .pass: .pass
        case .warn: .warn
        case .fail: .fail
        }
    }

    var label: String {
        switch self {
        case .pass: "PASS"
        case .warn: "WARN"
        case .fail: "FAIL"
        }
    }
}

// MARK: - ResultsSheet

/// The end-of-run payoff (§0.9): a Safety Score ring, the PASS/WARN/FAIL verdict, the reasons with real
/// units, and — when the run fell short — RALLY's grounded fix with an Apply & re-run button. Pure
/// presentation of a `RunResult`; every number here is engine-sourced.
struct ResultsSheet: View {
    let result: RunResult
    let onApply: (Fix) -> Void
    let onRunAgain: () -> Void
    let onDone: () -> Void

    @State private var ringProgress: CGFloat = 0
    /// RALLY's coaching for this run — fetched async (canned coach returns instantly; the on-device model
    /// streams). `nil` while it's being produced, which the card shows as a brief "thinking" state.
    @State private var advice: CoachAdvice?

    @Environment(FeedbackServices.self)
    private var feedback: FeedbackServices?
    /// Used to patch RALLY's prose into the saved run's report snapshot once the advice resolves.
    @Environment(\.modelContext)
    private var modelContext
    /// The score-ring sweep is decorative motion: under Reduce Motion the number cross-fades to its
    /// final value instead of sweeping, and the reveal ticks are skipped (§5.6).
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var level: VerdictLevel {
        result.verdict.level
    }

    var body: some View {
        ScrollView {
            VStack(spacing: EgressSpacing.xl) {
                scoreHeader
                verdictBadge
                reasons
                coachCard
                actions
            }
            .padding(EgressSpacing.xl)
        }
        .background(Color.egGround)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            feedback?.sound.play(.popup)
            if reduceMotion {
                ringProgress = CGFloat(result.score.value) / 100 // no sweep — settle on the final value
            } else {
                withAnimation(Motion.scoreRingReveal) {
                    ringProgress = CGFloat(result.score.value) / 100
                }
            }
        }
        .egButtonSound()
        .task(id: result.id) {
            advice = await CoachProvider.shared.advise(for: result, venue: result.venue)
            if let advice {
                feedback?.haptics.play(.rallyAppears) // §5.5: 1 soft tap per card
                patchReportCoach(advice) // fold RALLY's prose into the saved run's report
            }
        }
        .task(id: result.id) {
            await runScoreReveal()
        }
    }

    /// The score-ring reveal feedback (§5.4): up to 8 evenly-spaced light ticks as the ring fills, then
    /// the verdict's sound + haptic landing on the final number. Under Reduce Motion there is no sweep,
    /// so the payoff fires at once.
    private func runScoreReveal() async {
        if !reduceMotion {
            let step = Motion.scoreRingDuration / Double(Motion.scoreRevealTickCeiling)
            for _ in 0 ..< Motion.scoreRevealTickCeiling {
                try? await Task.sleep(for: .seconds(step))
                if Task.isCancelled {
                    return
                }
                feedback?.haptics.play(.scoreTick)
            }
        }
        switch level {
        case .pass: feedback?.sound.play(.verdictPass)
            feedback?.haptics.play(.verdictPass)
        case .warn: feedback?.sound.play(.warning)
            feedback?.haptics.play(.verdictWarn)
        case .fail: feedback?.sound.play(.verdictFail)
            feedback?.haptics.play(.verdictFail)
        }
    }

    /// Fold RALLY's resolved prose into the run's stored report. The record was saved keyed to
    /// `result.id`, so we fetch it back and patch the coach fields in place. Silent no-op if the record
    /// isn't found (e.g. a preview with no store) — the report just shows without a coach section.
    private func patchReportCoach(_ advice: CoachAdvice) {
        let runID = result.id
        let descriptor = FetchDescriptor<RunRecord>(predicate: #Predicate { $0.id == runID })
        guard let record = try? modelContext.fetch(descriptor).first,
              var snapshot = record.report else { return }
        snapshot.coachHeadline = advice.headline
        snapshot.coachBody = advice.body
        snapshot.coachClosing = advice.closing
        snapshot.coachSource = advice.source.label
        record.report = snapshot
        try? modelContext.save()
    }

    /// The spoken score band (§5.6) — a plain-language qualifier VoiceOver appends to the ring value.
    private var scoreBandName: String {
        switch level {
        case .pass: "safe"
        case .warn: "caution"
        case .fail: "critical"
        }
    }

    // MARK: Score ring

    private var scoreHeader: some View {
        VStack(spacing: EgressSpacing.sm) {
            Text("Safety Score").egMicroLabel()
            ZStack {
                Circle()
                    .stroke(Color.egSeparator, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(level.tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(result.score.value)")
                    .font(EgressFont.accent(size: 68))
                    .foregroundStyle(Color.egTextPrimary)
                    .monospacedDigit()
            }
            .frame(width: 176, height: 176)
            // §5.6: the ring is one element — the decorative sweep is not spoken; the value is.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Safety score")
            .accessibilityValue("\(result.score.value) out of 100, \(scoreBandName) band")

            if let improvement = result.improvement {
                improvementChip(improvement)
            }
            if let saved = result.casualtiesAverted, saved != 0 {
                casualtyChip(saved)
            }
        }
    }

    /// The casualties before → after an Apply. With a fire the Safety Score's casualty term saturates, so
    /// the score chip barely moves even as lives are saved — this states the real gain outright.
    private func casualtyChip(_ saved: Int) -> some View {
        let good = saved > 0
        return Label(
            good ? "\(saved) fewer casualties after the fix" : "\(-saved) more casualties after the fix",
            systemImage: good ? "cross.case.fill" : "exclamationmark.triangle.fill"
        )
        .egData(.footnote)
        .foregroundStyle(good ? Color.egDataGreen : Color.egVerdictFail)
        .padding(.horizontal, EgressSpacing.md)
        .padding(.vertical, EgressSpacing.sm)
        .egGlassSurface(cornerRadius: EgressRadius.xs)
        .accessibilityLabel(good ? "\(saved) fewer casualties after the fix" : "\(-saved) more casualties after the fix")
    }

    /// The before → after delta shown after an Apply & re-run.
    private func improvementChip(_ delta: Int) -> some View {
        let up = delta > 0
        return Label(
            up ? "+\(delta) after the fix" : (delta == 0 ? "no change" : "\(delta) after the fix"),
            systemImage: up ? "arrow.up.right" : (delta == 0 ? "equal" : "arrow.down.right")
        )
        .egData(.footnote)
        .foregroundStyle(up ? Color.egDataGreen : Color.egTextSecondary)
        .padding(.horizontal, EgressSpacing.md)
        .padding(.vertical, EgressSpacing.sm)
        .egGlassSurface(cornerRadius: EgressRadius.xs)
    }

    // MARK: Verdict badge

    private var verdictBadge: some View {
        HStack(spacing: EgressSpacing.sm) {
            Image(app: level.symbol)
            Text(level.label)
                .egDisplay(.title2)
        }
        .foregroundStyle(level.tint)
        .padding(.horizontal, EgressSpacing.lg)
        .padding(.vertical, EgressSpacing.sm)
        .overlay(
            Capsule().strokeBorder(level.tint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Reasons

    @ViewBuilder private var reasons: some View {
        if result.verdict.reasons.isEmpty {
            Text("No safety issues flagged for this run.")
                .egBody(.callout)
                .foregroundStyle(Color.egTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: EgressSpacing.md) {
                Text("Why").egMicroLabel()
                ForEach(Array(result.verdict.reasons.enumerated()), id: \.offset) { _, reason in
                    HStack(alignment: .top, spacing: EgressSpacing.sm) {
                        Circle()
                            .fill(reason.level.tint)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        Text(reason.text)
                            .egBody(.callout)
                            .foregroundStyle(Color.egTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(EgressSpacing.lg)
            .frame(maxWidth: .infinity)
            .egRaisedSurface()
            // Read as one grouped list — metric, threshold, value and units exactly as displayed (§5.6).
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Why")
        }
    }

    // MARK: RALLY coach card

    /// RALLY's voice on the run: a headline, a grounded diagnosis (or a PASS summary + joke), the
    /// Apply & re-run action when there's a fix, and a provenance badge that's honest about whether the
    /// on-device model or the canned fallback wrote it (§3.5.4).
    private var coachCard: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.md) {
            HStack(spacing: EgressSpacing.sm) {
                Image(systemName: "sparkles").foregroundStyle(level.tint)
                    .accessibilityHidden(true) // decorative — RALLY's state is in the headline text (§5.6)
                Text(advice?.headline ?? "RALLY").egMicroLabel()
                Spacer(minLength: EgressSpacing.sm)
                if let source = advice?.source {
                    sourceBadge(source)
                }
            }

            if let advice {
                Text(coach: advice.body)
                    .egBody(.callout)
                    .foregroundStyle(Color.egTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let closing = advice.closing {
                    Text(coach: closing)
                        .egBody(.footnote)
                        .foregroundStyle(Color.egTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let fix = advice.primaryFix {
                    Button {
                        onApply(fix)
                    } label: {
                        Label(fix.summary, systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.egDataGreen)
                    .accessibilityHint("Applies the fix and re-runs the simulation")

                    if let alt = advice.altSuggestion {
                        Text(alt).egMicroLabel().foregroundStyle(Color.egTextSecondary)
                    }
                }
            } else {
                HStack(spacing: EgressSpacing.sm) {
                    ProgressView()
                    Text("RALLY is thinking…").egMicroLabel()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(EgressSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle.egSquircle(EgressRadius.xl).fill(Color.egSurfaceRaised)
        )
        .overlay(
            RoundedRectangle.egSquircle(EgressRadius.xl).strokeBorder(level.tint.opacity(0.5), lineWidth: 1)
        )
        // Contain so VoiceOver reads headline → diagnosis → action in order, the Apply chip as a button (§5.6).
        .accessibilityElement(children: .contain)
    }

    /// The "On-device AI" / "RALLY" provenance chip — never dresses the canned fallback up as the model.
    private func sourceBadge(_ source: CoachSource) -> some View {
        Text(source.label.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .foregroundStyle(Color.egTextSecondary)
            .padding(.horizontal, EgressSpacing.sm)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.egSeparator, lineWidth: 1))
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: EgressSpacing.md) {
            Button(role: .cancel) { onDone() } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button { onRunAgain() } label: {
                Label("Run again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .tint(Color.egTextSecondary)
    }
}
