import EgressEngine
import SwiftUI

// MARK: - RunReportView

/// The full, static "report" for one saved run (design: tap a recent run → see everything). Reads the
/// `RunReportSnapshot` captured at save time and lays out — verdict-tinted — what happened (outcome +
/// reasons + RALLY's diagnosis), the configuration it was run on (room, exits, objects, hazards), the
/// end-of-run metrics, any before→after delta from an Apply, and the reproducible seed. A legacy record
/// with no snapshot still shows its header and a graceful "details unavailable" note.
struct RunReportView: View {
    let run: RunRecord

    @Environment(\.dismiss) private var dismiss

    /// A snapshot of the report rendered to an image for the system share sheet — produced once on
    /// appear via `ImageRenderer`, so the Share button is ready the moment the report is open.
    @State private var shareImage: Image?

    /// Decoded once per render — cheap, and keeps the body declarative.
    private var report: RunReportSnapshot? { run.report }
    private var level: VerdictLevel? { VerdictLevel(rawValue: run.verdictRaw) }
    private var tint: Color { level?.tint ?? Color.egTextPrimary }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: EgressSpacing.xl) {
                    header
                    if let report {
                        outcomeSection(report)
                        configurationSection(report)
                        metricsSection(report)
                        if report.baselineScore != nil { deltaSection(report) }
                    } else {
                        unavailableCard
                    }
                    footer
                }
                .padding(EgressSpacing.lg)
                .padding(.bottom, EgressSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.egGround)
        .onAppear(perform: renderShareCard)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: EgressSpacing.sm) {
            Text("Run report").egMicroLabel()
            Spacer()
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("\(run.venueName) — Egress run report", image: shareImage)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.egTextPrimary)
                        .padding(.horizontal, EgressSpacing.md)
                        .padding(.vertical, EgressSpacing.sm)
                        .background(Capsule().fill(Color.egSurfaceRaised))
                        .overlay(Capsule().strokeBorder(Color.egOutline.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("Share report")
            }
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.egTextPrimary)
                    .padding(.horizontal, EgressSpacing.md)
                    .padding(.vertical, EgressSpacing.sm)
                    .background(Capsule().fill(Color.egSurfaceRaised))
                    .overlay(Capsule().strokeBorder(Color.egOutline.opacity(0.15), lineWidth: 1))
            }
            .accessibilityLabel("Close report")
        }
        .padding(.horizontal, EgressSpacing.lg)
        .padding(.vertical, EgressSpacing.md)
        .background(Color.egGround)
    }

    // MARK: Share card

    /// Render the compact share card to an image for the system share sheet. Runs on the main actor via
    /// `ImageRenderer`; a nil result (renderer failure) simply leaves the Share button hidden.
    @MainActor private func renderShareCard() {
        guard shareImage == nil else { return }
        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }

    /// A self-contained, brand-framed summary of the run — venue, date, score ring, verdict and the three
    /// headline metrics — with the mandatory safety-framing disclaimer, so a shared image never reads as
    /// certified advice (§D). Fixed width and its own background so it renders cleanly off-screen.
    private var shareCard: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.md) {
            HStack {
                Text("EGRESS")
                    .font(.system(.subheadline, design: .monospaced, weight: .black))
                    .foregroundStyle(Color.egTextPrimary)
                Spacer()
                Text("RUN REPORT")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.egTextTertiary)
            }

            Text(run.venueName)
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(Color.egTextPrimary)
                .lineLimit(2)
            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                .egBody(.footnote)
                .foregroundStyle(Color.egTextSecondary)

            HStack(alignment: .center, spacing: EgressSpacing.lg) {
                ZStack {
                    Circle().stroke(Color.egSeparator, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(run.score) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(run.score)")
                        .font(EgressFont.accent(size: 30))
                        .foregroundStyle(Color.egTextPrimary)
                        .monospacedDigit()
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                    PixelText(text: (level?.label ?? run.verdictRaw).uppercased(), pixel: 2.4, color: tint)
                    if let report {
                        Text(outcomeLine(report))
                            .egBody(.footnote)
                            .foregroundStyle(Color.egTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, EgressSpacing.xs)

            if let report {
                HStack(spacing: EgressSpacing.xl) {
                    shareStat("People", "\(report.occupancy)")
                    shareStat("Clearance", report.didClear ? "\(Int(report.clearance.rounded())) s" : "—")
                    shareStat("Casualties", "\(report.casualties)")
                }
            }

            Text("Educational analysis, not certified engineering advice.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.egTextTertiary)
                .padding(.top, EgressSpacing.xs)
        }
        .padding(EgressSpacing.xl)
        .frame(width: 380, alignment: .leading)
        .background(Color.egGround)
    }

    private func shareStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).egMicroLabel()
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.egTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header — name, date, score ring, verdict

    private var header: some View {
        HStack(alignment: .top, spacing: EgressSpacing.md) {
            VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                Text(run.venueName)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(Color.egTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                    .egBody(.subheadline)
                    .foregroundStyle(Color.egTextSecondary)
                verdictPill
            }
            Spacer(minLength: EgressSpacing.sm)
            scoreRing
        }
    }

    private var verdictPill: some View {
        PixelText(text: (level?.label ?? run.verdictRaw).uppercased(), pixel: 2.2, color: tint)
            .padding(.horizontal, EgressSpacing.sm)
            .padding(.vertical, 5)
            .overlay(PixelCornerRect(radius: 8, pixel: 2).strokeBorder(tint.opacity(0.75), lineWidth: 1.5))
            .padding(.top, EgressSpacing.xxs)
    }

    private var scoreRing: some View {
        ZStack {
            Circle().stroke(Color.egSeparator, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(run.score) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(run.score)")
                .font(EgressFont.accent(size: 34))
                .foregroundStyle(Color.egTextPrimary)
                .monospacedDigit()
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Safety score \(run.score) out of 100")
    }

    // MARK: Outcome — what happened

    private func outcomeSection(_ report: RunReportSnapshot) -> some View {
        section("What happened") {
            VStack(alignment: .leading, spacing: EgressSpacing.md) {
                Label {
                    Text(outcomeLine(report))
                        .egBody(.callout)
                        .foregroundStyle(Color.egTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(app: level?.symbol ?? .warn).foregroundStyle(tint)
                }

                if report.reasons.isEmpty {
                    Text("No safety issues flagged for this run.")
                        .egBody(.footnote)
                        .foregroundStyle(Color.egTextSecondary)
                } else {
                    VStack(alignment: .leading, spacing: EgressSpacing.sm) {
                        ForEach(Array(report.reasons.enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .top, spacing: EgressSpacing.sm) {
                                Circle().fill(tint).frame(width: 7, height: 7).padding(.top, 6)
                                Text(reason)
                                    .egBody(.footnote)
                                    .foregroundStyle(Color.egTextPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let fix = report.suggestedFixSummary {
                    HStack(alignment: .top, spacing: EgressSpacing.sm) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(Color.egDataGreenDeep)
                            .accessibilityHidden(true)
                        Text("RALLY suggests: \(fix)")
                            .egBody(.footnote)
                            .foregroundStyle(Color.egTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                coachBlock(report)
            }
        }
    }

    /// The single-sentence outcome headline, honest about whether the crowd cleared.
    private func outcomeLine(_ report: RunReportSnapshot) -> String {
        if report.didClear {
            return "Cleared in \(Int(report.clearance.rounded())) s, target \(Int(report.clearanceTarget.rounded())) s."
        }
        let trapped = report.trapped
        return "Did not clear — \(trapped) still trying to escape at the \(Int(report.timeCap.rounded())) s cap."
    }

    /// RALLY's diagnosis, once the async advice was patched in; renders nothing if it hadn't resolved.
    @ViewBuilder private func coachBlock(_ report: RunReportSnapshot) -> some View {
        if let body = report.coachBody {
            VStack(alignment: .leading, spacing: EgressSpacing.sm) {
                HStack(spacing: EgressSpacing.sm) {
                    Image(systemName: "sparkles").foregroundStyle(tint).accessibilityHidden(true)
                    Text(report.coachHeadline ?? "RALLY").egMicroLabel()
                    Spacer(minLength: EgressSpacing.sm)
                    if let source = report.coachSource {
                        Text(source.uppercased())
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Color.egTextSecondary)
                            .padding(.horizontal, EgressSpacing.sm)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(Color.egSeparator, lineWidth: 1))
                    }
                }
                Text(coach: body)
                    .egBody(.footnote)
                    .foregroundStyle(Color.egTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let closing = report.coachClosing {
                    Text(coach: closing)
                        .egBody(.caption)
                        .foregroundStyle(Color.egTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(EgressSpacing.md)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle.egSquircle(EgressRadius.md).fill(Color.egGround))
            .overlay(RoundedRectangle.egSquircle(EgressRadius.md).strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: Configuration

    private func configurationSection(_ report: RunReportSnapshot) -> some View {
        section("Configuration") {
            VStack(alignment: .leading, spacing: EgressSpacing.lg) {
                statGrid([
                    ("Room size", String(format: "%.1f × %.1f m", report.roomWidth, report.roomHeight)),
                    ("People", "\(report.occupancy)"),
                    ("Gross area", "\(Int(report.grossArea.rounded())) m²"),
                    ("Usable area", "\(Int(report.netArea.rounded())) m²"),
                ])

                chipGroup("Exits (\(report.exits.count))",
                          chips: report.exits.map { String(format: "%.1f m · %@", $0.width, $0.side) },
                          empty: "No exits")

                chipGroup("Objects (\(report.obstacleCount))",
                          chips: report.obstacleBreakdown.map { "\($0.count) × \($0.kind.capitalized)" },
                          empty: "None")

                chipGroup("Hazards",
                          chips: hazardChips(report),
                          empty: "None")
            }
        }
    }

    private func hazardChips(_ report: RunReportSnapshot) -> [String] {
        var chips: [String] = []
        if report.hasFire { chips.append("Fire") }
        if report.hasWater { chips.append("Water") }
        return chips
    }

    // MARK: Metrics

    private func metricsSection(_ report: RunReportSnapshot) -> some View {
        section("Metrics") {
            statGrid([
                ("Clearance", "\(Int(report.clearance.rounded())) s"),
                ("Target", "\(Int(report.clearanceTarget.rounded())) s"),
                ("Peak density", String(format: "%.1f p/m²", report.peakDensity)),
                ("Casualties", "\(report.casualties)"),
                ("Trapped", "\(report.trapped)"),
                ("At-risk", "\(Int((report.atRiskFraction * 100).rounded()))%"),
            ])
        }
    }

    // MARK: Before → after (Apply runs)

    private func deltaSection(_ report: RunReportSnapshot) -> some View {
        section("Before → after the fix") {
            HStack(spacing: EgressSpacing.md) {
                if let improvement = report.improvement {
                    deltaChip(
                        title: "Score",
                        value: improvement > 0 ? "+\(improvement)" : "\(improvement)",
                        good: improvement >= 0
                    )
                }
                if let saved = report.casualtiesAverted, saved != 0 {
                    deltaChip(
                        title: "Casualties",
                        value: saved > 0 ? "−\(saved)" : "+\(-saved)",
                        good: saved > 0
                    )
                }
            }
        }
    }

    private func deltaChip(title: String, value: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).egMicroLabel()
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(good ? Color.egDataGreenDeep : Color.egVerdictFail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EgressSpacing.md)
        .background(RoundedRectangle.egSquircle(EgressRadius.md).fill(Color.egSurfaceRaised))
    }

    // MARK: Footer + legacy

    private var footer: some View {
        Text("Seed \(run.seed) · reproducible run")
            .egData(.caption2)
            .foregroundStyle(Color.egTextTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, EgressSpacing.sm)
    }

    private var unavailableCard: some View {
        Text("Detailed report isn't available for this run — it was saved before reports were added.")
            .egBody(.callout)
            .foregroundStyle(Color.egTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EgressSpacing.lg)
            .background(RoundedRectangle.egSquircle(EgressRadius.lg).fill(Color.egSurfaceRaised))
    }

    // MARK: Building blocks

    /// A titled report section: serif shelf heading over a raised cream card.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: EgressSpacing.md) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.egTextPrimary)
            content()
                .padding(EgressSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle.egSquircle(EgressRadius.lg).fill(Color.egSurfaceRaised))
        }
    }

    /// A two-column grid of labelled scalar facts.
    private func statGrid(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: EgressSpacing.lg) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.0).egMicroLabel()
                    Text(item.1)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.egTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A labelled row of small pill chips (exits, objects, hazards), or an "empty" line if there are none.
    private func chipGroup(_ title: String, chips: [String], empty: String) -> some View {
        VStack(alignment: .leading, spacing: EgressSpacing.sm) {
            Text(title).egMicroLabel()
            if chips.isEmpty {
                Text(empty).egBody(.footnote).foregroundStyle(Color.egTextSecondary)
            } else {
                FlowChips(chips: chips)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - FlowChips

/// A simple wrapping row of chips — each a rounded taupe pill. Uses SwiftUI's native wrapping `HStack`
/// behaviour via a flexible layout so long lists (many exits/objects) flow onto the next line.
private struct FlowChips: View {
    let chips: [String]

    var body: some View {
        FlowLayout(spacing: EgressSpacing.sm) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.egTextPrimary)
                    .padding(.horizontal, EgressSpacing.md)
                    .padding(.vertical, EgressSpacing.sm)
                    .background(Capsule().fill(Color.egSurfaceSunken))
                    .overlay(Capsule().strokeBorder(Color.egOutline.opacity(0.12), lineWidth: 1))
            }
        }
    }
}

// MARK: - FlowLayout

/// A minimal wrapping layout — lays children left-to-right, wrapping to a new line when the row is full.
/// Small and dependency-free; used for the report's chip groups.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
