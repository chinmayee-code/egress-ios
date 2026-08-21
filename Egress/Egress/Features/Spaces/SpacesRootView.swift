import EgressEngine
import SwiftData
import SwiftUI

// MARK: - SpacesRootView

/// The Spaces library (§3.6): a gallery of furnished presets to start from, then the saved-run
/// history — every resolved simulation persisted as a `RunRecord`, newest-first with its score and
/// verdict. A custom cream header carries the wordmark and the Settings gear; the ＋ (in the floating
/// tab bar) and each preset card both open the parametric editor. Presented without a nav bar — the big
/// header *is* the chrome — and it reserves room for the floating tab bar via the parent's safe-area inset.
struct SpacesRootView: View {
    /// Opens the editor seeded with a preset (a full-screen cover owned by `AppRoot`).
    let onOpenPreset: (VenuePreset) -> Void

    /// Only the last ten runs — the history stays a glanceable strip, not an ever-growing ledger.
    @Query private var runs: [RunRecord]
    /// The settings sheet, raised from the gear in the header.
    @State private var showSettings = false
    /// Flips true on first appearance to stagger the preset cards in.
    @State private var appeared = false
    /// Which preset the carousel is centred on — drives the page-dot indicator and paging snap.
    @State private var currentPreset: VenuePreset.ID?
    /// The run whose full report is open (presented as a full-screen cover); nil when none.
    @State private var selectedRun: RunRecord?
    /// Decorative entrances (card + row stagger) collapse to a plain fade under Reduce Motion (§5.6).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Deletes a run from history via the row's context menu.
    @Environment(\.modelContext) private var modelContext
    /// For the soft haptic when a run is deleted; optional so previews without the services still render.
    @Environment(FeedbackServices.self) private var feedback: FeedbackServices?

    init(onOpenPreset: @escaping (VenuePreset) -> Void) {
        self.onOpenPreset = onOpenPreset
        var descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 10 // cap the recent-runs list at the ten most recent
        _runs = Query(descriptor)
        _currentPreset = State(initialValue: VenuePreset.catalog.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The header is the screen's chrome — pin it above the scroll so it always clears the status
            // bar / Dynamic Island, and the scrolling gallery never slides up underneath it into the top
            // safe area (a plain ScrollView lets its content scroll under the status bar).
            header
                .padding(.horizontal, EgressSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: EgressSpacing.xl) {
                    if !runs.isEmpty { summaryStrip }

                    presetSection

                    runsSection
                }
                .padding(.horizontal, EgressSpacing.lg)
                .padding(.top, EgressSpacing.md)
                .padding(.bottom, EgressSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color.egGround)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .fullScreenCover(item: $selectedRun) { run in
            RunReportView(run: run)
        }
        .onAppear { appeared = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                Text("SPACES")
                    .font(.system(size: 36, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Color.egTextPrimary)
                Text("Library of environments.")
                    .egBody(.subheadline)
                    .foregroundStyle(Color.egTextSecondary)
            }

            Spacer(minLength: EgressSpacing.md)

            Button { showSettings = true } label: {
                VStack(spacing: EgressSpacing.xxs) {
                    Image(app: .settings)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.egTextPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.egSurfaceRaised))
                        .overlay(Circle().strokeBorder(Color.egOutline, lineWidth: 2))
                    Text("Settings").egMicroLabel()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .tourAnchor(.spacesSettings)
        }
        .padding(.top, EgressSpacing.sm)
    }

    // MARK: Summary

    /// Best safety score across the loaded runs — the number to beat.
    private var bestScore: Int? { runs.map(\.score).max() }
    /// The most recent run's verdict (runs are date-descending), for the "last" chip.
    private var lastLevel: VerdictLevel? { runs.first.flatMap { VerdictLevel(rawValue: $0.verdictRaw) } }

    /// A one-line orientation strip above the gallery: how many runs are on file, the best score so
    /// far, and how the latest run landed — each a tiny labelled stat, the last tinted by verdict.
    private var summaryStrip: some View {
        HStack(spacing: EgressSpacing.sm) {
            summaryChip(label: "Runs",
                        value: runs.count >= 10 ? "10+" : "\(runs.count)",
                        icon: "stat_runs",
                        tint: Color.egTextPrimary)
            summaryChip(label: "Best",
                        value: bestScore.map(String.init) ?? "—",
                        icon: "stat_best",
                        tint: Color.egTextPrimary)
            summaryChip(label: "Last",
                        value: lastLevel?.label ?? runs.first?.verdictRaw.uppercased() ?? "—",
                        icon: "stat_last",
                        tint: lastLevel?.tint ?? Color.egVerdictPass)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(runs.count) recent runs. Best score \(bestScore.map(String.init) ?? "none"). Last verdict \(lastLevel?.label ?? "none").")
    }

    /// A dark "arcade HUD" stat tile — the chunky pixel-corner box from the Spaces design: a warm near-black
    /// fill inside a gold pixel border, with a small-caps gold label pinned top-left, the pixel-art icon
    /// centred as the hero, and the bold value along the bottom. Reuses `PixelCornerRect` so the stepped
    /// corners match the recent-runs container and the tab bar.
    private func summaryChip(label: String, value: String, icon: String, tint: Color) -> some View {
        let shape = PixelCornerRect(radius: EgressRadius.md, pixel: 4)
        return VStack(spacing: EgressSpacing.sm) {
            // Label, icon and value all centred, in the app's 5×7 bitmap font (matches the score pills).
            PixelText(text: label, pixel: 1.6, color: Color.egTextTertiary)

            Image(icon)
                .resizable()
                .interpolation(.none) // keep the pixel edges crisp when scaled
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 40) // a fixed box so the wide runner and tall heart read at a matched size

            PixelText(text: value, pixel: 2.3, color: tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, EgressSpacing.md)
        .padding(.horizontal, EgressSpacing.md)
        .background(shape.fill(Color.egSurfaceRaised)) // same cream fill as the preset cards
        // Match the preset card's chrome: a black pixel border with a soft gray inset line inside it.
        .overlay(shape.strokeBorder(Color.egOutline, lineWidth: 2.5))
        .overlay(shape.inset(by: 3).strokeBorder(Color.egTextTertiary.opacity(0.55), lineWidth: 1.5))
    }

    // MARK: Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.md) {
            sectionHeader("Start from a preset")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: EgressSpacing.md) {
                    ForEach(Array(VenuePreset.catalog.enumerated()), id: \.element.id) { index, preset in
                        Button { onOpenPreset(preset) } label: {
                            PresetCard(preset: preset)
                        }
                        .buttonStyle(PressableCardStyle())
                        .tourAnchor(.spacesPreset, if: index == 0)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .offset(x: appeared || reduceMotion ? 0 : 24)
                        .animation(reduceMotion ? nil : Motion.card.delay(Double(index) * 0.06), value: appeared)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, EgressSpacing.xs)
                .padding(.trailing, EgressSpacing.md) // let the last card breathe past the edge
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $currentPreset, anchor: .leading)
            // Let the carousel bleed to the screen edges while the rest of the page keeps its margin.
            .padding(.horizontal, -EgressSpacing.lg)
            .padding(.horizontal, EgressSpacing.lg)

            pageDots
        }
    }

    /// Page dots under the carousel: the current preset fills into a short bar, the rest stay hairline.
    private var pageDots: some View {
        HStack(spacing: EgressSpacing.sm) {
            ForEach(VenuePreset.catalog) { preset in
                let active = preset.id == currentPreset
                Capsule(style: .continuous)
                    .fill(active ? Color.egTextPrimary : Color.egSeparator)
                    .frame(width: active ? 18 : 7, height: 7)
                    .animation(reduceMotion ? nil : Motion.tap, value: currentPreset)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, EgressSpacing.xxs)
        .accessibilityHidden(true)
    }

    // MARK: Recent runs

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: EgressSpacing.md) {
            sectionHeader("Recent runs")

            if runs.isEmpty {
                emptyRunsState
            } else {
                // Cream container with the stat-tile's pixel-corner outline — but the soft cream stroke
                // only, no black — so the history reads as a bordered card, not a hard black box.
                let shape = PixelCornerRect(radius: EgressRadius.lg, pixel: 4)
                VStack(spacing: 0) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.egSeparator)
                                .frame(height: 1)
                                .padding(.horizontal, EgressSpacing.lg)
                        }
                        Button { selectedRun = run } label: { RunRow(run: run) }
                            .buttonStyle(PressableCardStyle())
                            .accessibilityHint("Opens the full run report")
                            .contextMenu {
                                Button(role: .destructive) { deleteRun(run) } label: {
                                    Label("Delete run", systemImage: "trash")
                                }
                            }
                            .opacity(appeared || reduceMotion ? 1 : 0)
                            .offset(y: appeared || reduceMotion ? 0 : 16)
                            .animation(reduceMotion ? nil : Motion.card.delay(Double(index) * 0.06), value: appeared)
                    }
                }
                .background(shape.fill(Color.egSurfaceRaised))
                .overlay(shape.strokeBorder(Color.egSeparator, lineWidth: 2))
            }
        }
    }

    /// Shown before the first run: the guide mascot invites the user to run an evacuation.
    private var emptyRunsState: some View {
        HStack(spacing: EgressSpacing.lg) {
            Image("guide_mascot")
                .resizable()
                .interpolation(.none) // keep the pixel edges crisp when scaled
                .aspectRatio(contentMode: .fit)
                .frame(height: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EgressSpacing.xs) {
                Text("No runs yet")
                    .font(.system(.headline, design: .serif, weight: .bold))
                    .foregroundStyle(Color.egTextPrimary)
                Text("Pick a preset or tap ＋, run an evacuation, and its result lands here.")
                    .egBody(.subheadline)
                    .foregroundStyle(Color.egTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EgressSpacing.lg)
        .background(RoundedRectangle.egSquircle(EgressRadius.lg).fill(Color.egSurfaceRaised))
    }

    /// Remove a run from history (row context menu). The `@Query` refreshes automatically, so the row
    /// animates out; a soft tap confirms the delete. Deletes the persisted record and saves.
    private func deleteRun(_ run: RunRecord) {
        feedback?.haptics.play(.toolTap)
        withAnimation(reduceMotion ? nil : Motion.card) {
            modelContext.delete(run)
        }
        try? modelContext.save()
    }

    /// A prominent title-case section label — the gallery's shelf headings.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .bold))
            .foregroundStyle(Color.egTextPrimary)
    }
}

// MARK: - PressableCardStyle

/// A springy press for the gallery cards — they dip and dim on touch, like pressing a physical button.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

// MARK: - RunRow

/// One saved run as a borderless row inside the shared pixel container (design: the recent-run list). The
/// venue and three labelled metrics — type, clearance time, occupancy — sit left; the pixel-font score and a
/// pixel PASS/WARN/FAIL pill sit right, tinted by verdict.
private struct RunRow: View {
    let run: RunRecord

    private var level: VerdictLevel? { VerdictLevel(rawValue: run.verdictRaw) }
    private var tint: Color { level?.tint ?? Color.egTextPrimary }

    /// "2h ago", "Yesterday" — a glanceable recency stamp, formatted once and reused.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeDate: String {
        // The formatter renders a just-saved run as "in 0 sec" (it rounds a ~0 interval up); a plain
        // "Just now" reads far better for anything under a minute old.
        if abs(run.date.timeIntervalSinceNow) < 60 { return "Just now" }
        return Self.relativeFormatter.localizedString(for: run.date, relativeTo: .now)
    }

    var body: some View {
        HStack(alignment: .center, spacing: EgressSpacing.md) {
            VStack(alignment: .leading, spacing: EgressSpacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.venueName)
                        .font(.system(.headline, design: .serif, weight: .bold))
                        .foregroundStyle(Color.egTextPrimary)
                    Text(relativeDate).egMicroLabel()
                }

                HStack(alignment: .top, spacing: EgressSpacing.md) {
                    stat("Type", (run.venueType?.displayName ?? run.venueTypeRaw).uppercased())
                    stat("Clear time", String(format: "%.0fS", run.clearanceTime))
                    stat("Count", "\(run.occupancy) PEOPLE")
                }
            }

            Spacer(minLength: EgressSpacing.sm)

            HStack(alignment: .center, spacing: EgressSpacing.sm) {
                VStack(alignment: .trailing, spacing: EgressSpacing.sm) {
                    PixelText(text: "\(run.score)", pixel: 3.0, color: tint)
                    verdictPill
                }
                // "Open report" arrow to the right of the score/verdict, vertically centred — signals the
                // whole row is tappable. Decorative for VoiceOver (the row announces its own label).
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.egTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(EgressSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Make the *whole* row a tap target — a Button's label only hit-tests where content actually is,
        // so without this the Spacer gap and the padding between the text and the chevron ignore taps.
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(run.venueName), \(level?.label ?? run.verdictRaw), score \(run.score). \(run.occupancy) people, cleared in \(Int(run.clearanceTime)) seconds. \(relativeDate).")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).egMicroLabel()
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .foregroundStyle(Color.egTextPrimary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var verdictPill: some View {
        PixelText(text: (level?.label ?? run.verdictRaw).uppercased(), pixel: 1.85, color: tint)
            .padding(.horizontal, EgressSpacing.sm)
            .padding(.vertical, 4)
            .overlay(
                PixelCornerRect(radius: 7, pixel: 2).strokeBorder(tint.opacity(0.75), lineWidth: 1.5)
            )
    }
}

#Preview {
    SpacesRootView(onOpenPreset: { _ in })
        .environment(\.dependencies, .preview())
}
