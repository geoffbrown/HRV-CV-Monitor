import SwiftUI
import Combine
import HRVCVCore
#if os(macOS)
import AppKit
import ServiceManagement
#else
import UIKit
#endif

// MARK: - View Model
@MainActor
final class HRVViewModel: ObservableObject {
    @Published var result      : HRVCVResult?
    @Published var isLoading   = false
    @Published var isAuthed    = false
    @Published var error       : String?
    @Published var lastUpdated : Date?

    private let service = WHOOPService.shared
    private var timer   : Timer?

    init() {
        #if os(macOS)
        service.presentationAnchorProvider = { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
        #else
        service.presentationAnchorProvider = {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first ?? UIWindow()
        }
        #endif

        if MockData.isEnabled {
            result      = HRVCalculator.calculate(from: MockData.records(), sleep: MockData.sleepRecords())
            isAuthed    = true
            lastUpdated = Date()
            return
        }

        isAuthed = service.isAuthenticated
        if isAuthed { Task { await load() } }
        scheduleRefresh()

        #if os(macOS)
        // Refresh after the Mac wakes — the hourly timer doesn't fire during sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.loadIfStale() }
        }
        #endif
    }

    func signIn() async {
        isLoading = true
        error = nil
        do {
            try await service.startAuth()
            isAuthed = true
            await load()
        } catch is CancellationError {
            // Sign-in window was closed; leave the user on the sign-in screen.
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func load() async {
        guard isAuthed, !MockData.isEnabled else { return }
        isLoading = true
        error = nil
        do {
            let records = try await service.fetchRecovery(limit: 25)
            // Sleep is a secondary signal, not required data: a scope that
            // isn't granted yet (pre-existing sign-in) or a transient failure
            // just means the sleep consistency row stays hidden, not an error.
            let sleep = (try? await service.fetchSleep(limit: 25)) ?? []
            result      = HRVCalculator.calculate(from: records, sleep: sleep)
            lastUpdated = Date()
            if result == nil { error = "Need 7+ nights of WHOOP data." }
        } catch {
            self.error = error.localizedDescription
            if case WHOOPError.unauthorized = error { isAuthed = false }
        }
        isLoading = false
    }

    /// Reloads only if the data is older than 15 minutes (cheap to call often).
    func loadIfStale() async {
        guard isAuthed, !isLoading else { return }
        if let t = lastUpdated, Date().timeIntervalSince(t) < 900 { return }
        await load()
    }

    func signOut() {
        service.signOut()
        isAuthed = false
        result   = nil
        error    = nil
    }

    private func scheduleRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { await self?.load() }
        }
    }
}

// MARK: - Arc Gauge
// A neutral ruler with a verdict-colored reading. The track is deliberately NOT
// colour-coded: HRV-CV has no intrinsic good/bad (that ambiguity is the app's
// whole point), so the scale states only the fact. The "8" and "15" numerals sit
// in the boundary breaks of the arc itself, like dial graduations, so the
// segments are labeled without leaving the gauge. One hue total: the fill, knob
// ring, and center text all carry the verdict color — the interpretation.
struct CVGauge: View {
    let cv: Double
    let accent: Color   // verdict color (the interpretation)
    let label: String   // verdict label, e.g. "LEVELING UP"
    private let maxCV: Double = 30   // right end of the scale

    private var normalized: Double { min(max(cv / maxCV, 0), 1.0) }

    var body: some View {
        GeometryReader { geo in
            let w  = geo.size.width
            let h  = geo.size.height
            let cx = w / 2
            let r  = min(w * 0.40, h - 12)
            let cy = r + 8
            let lw : CGFloat = 9
            let b1 = 8.0 / maxCV                 // Elite / On-Track boundary
            let b2 = 15.0 / maxCV                // On-Track / Elevated boundary
            let stroke = StrokeStyle(lineWidth: lw, lineCap: .round)

            // Half-break sized so the rounded caps (which extend lw/2 past each
            // trim point) leave a ~3pt sliver of panel between segments.
            let g = Double((lw + 3) / (2 * .pi * r))

            ZStack {
                // Neutral track: three sub-arcs with rounded ends. The small
                // breaks at 8 and 15 are the tick marks, and every segment end
                // gets the same round cap as the ends of the arc itself.
                Group {
                    seg(0,      b1 - g, cx, cy, r).stroke(Color.primary.opacity(0.1), style: stroke)
                    seg(b1 + g, b2 - g, cx, cy, r).stroke(Color.primary.opacity(0.1), style: stroke)
                    seg(b2 + g, 1,      cx, cy, r).stroke(Color.primary.opacity(0.1), style: stroke)
                }

                // Fill to the value in neutral ink — the sweep answers only
                // "how far along the ruler". A judgment hue here would make a
                // mostly-full arc read as "a lot of good/bad", which is exactly
                // the misreading this gauge exists to avoid. The verdict colour
                // lives only in the reading: knob ring, number, label. The fill
                // breaks where the track breaks, caps matching.
                let fillInk = Color.primary.opacity(0.32)
                Group {
                    if normalized > 0 {
                        seg(0, min(b1 - g, normalized), cx, cy, r).stroke(fillInk, style: stroke)
                    }
                    if normalized > b1 + g {
                        seg(b1 + g, min(b2 - g, normalized), cx, cy, r).stroke(fillInk, style: stroke)
                    }
                    if normalized > b2 + g {
                        seg(b2 + g, min(1, normalized), cx, cy, r).stroke(fillInk, style: stroke)
                    }
                }

                // Threshold numerals tucked just inside the ring, under the seams.
                innerNumeral("8",  at: b1, cx: cx, cy: cy, r: r - lw / 2 - 9)
                innerNumeral("15", at: b2, cx: cx, cy: cy, r: r - lw / 2 - 9)

                // Knob at the value: a solid dot in the verdict hue with a
                // panel-colored ring to lift it off the fill — the one colored
                // point on the instrument, marking the reading.
                let pt = arcPoint(n: normalized, cx: cx, cy: cy, r: r)
                Circle()
                    .fill(accent)
                    .overlay(Circle().stroke(popoverBackground, lineWidth: 2.5))
                    .frame(width: 14, height: 14)
                    .position(pt)

                // Metric + value + verdict, centered in the bowl
                VStack(spacing: 2) {
                    Text("HRV-CV")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f%%", cv))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(accent)
                }
                .position(x: cx, y: cy - r * 0.40)
            }
        }
        .frame(height: 124)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        let zone = cv <= 8 ? "Elite, 8 percent or less"
                 : cv <= 15 ? "On Track, 8 to 15 percent"
                 : "Elevated, over 15 percent"
        return "HRV CV \(String(format: "%.1f", cv)) percent, \(label). In the \(zone) range."
    }

    // A small threshold numeral just inside the ring, beneath its seam.
    private func innerNumeral(_ text: String, at n: Double,
                              cx: CGFloat, cy: CGFloat, r: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .position(arcPoint(n: n, cx: cx, cy: cy, r: r))
    }


    // Upper semicircle as a Shape so the fill can be trimmed to the value.
    struct ArcShape: Shape {
        let cx, cy, r: CGFloat
        func path(in rect: CGRect) -> Path {
            Path { p in
                let steps = 96
                for i in 0...steps {
                    let deg = 180.0 + Double(i) / Double(steps) * 180.0
                    let rad = deg * .pi / 180.0
                    let pt = CGPoint(x: cx + CGFloat(cos(rad)) * r,
                                     y: cy + CGFloat(sin(rad)) * r)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
        }
    }

    // Maps normalized 0→1 to a CGPoint on the arc: n=0 left, n=0.5 top, n=1 right.
    private func arcPoint(n: Double, cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPoint {
        let deg = 180.0 + n * 180.0
        let rad = deg * Double.pi / 180.0
        return CGPoint(x: cx + CGFloat(cos(rad)) * r,
                       y: cy + CGFloat(sin(rad)) * r)
    }

    // A stroked sub-arc of the gauge from `from` to `to` (fractions 0...1 along the arc).
    private func seg(_ from: Double, _ to: Double,
                     _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> some Shape {
        ArcShape(cx: cx, cy: cy, r: r)
            .trim(from: CGFloat(max(0, from)), to: CGFloat(min(1, to)))
    }
}

// MARK: - HRV Band Chart
// The "evidence": nightly HRV (dots) travelling through its typical range (the
// band = terrain). A ghosted line marks last week's baseline so the shift shows.
struct HRVBandChart: View {
    let series: [HRVSeriesPoint]
    let oldBaseline: Double?
    let tint: Color
    @Binding var hoverIndex: Int?

    private var domain: (lo: Double, hi: Double) {
        var vals: [Double] = []
        for p in series { vals += [p.hrv, p.mean - p.sd, p.mean + p.sd] }
        if let o = oldBaseline { vals.append(o) }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = max((hi - lo) * 0.12, 1)
        return (lo - pad, hi + pad)
    }
    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        series.count > 1 ? CGFloat(i) / CGFloat(series.count - 1) * w : w / 2
    }
    private func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        let d = domain
        return (1 - CGFloat((v - d.lo) / max(d.hi - d.lo, 0.0001))) * h
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                // Typical range — the terrain
                bandPath(w, h).fill(tint.opacity(0.16))
                envelope(w, h, upper: true).stroke(tint.opacity(0.30), lineWidth: 1)
                envelope(w, h, upper: false).stroke(tint.opacity(0.30), lineWidth: 1)

                // Last week's baseline, ghosted, so the step-up is undeniable
                if let o = oldBaseline {
                    let oy = y(o, h)
                    Path { p in p.move(to: CGPoint(x: 0, y: oy)); p.addLine(to: CGPoint(x: w, y: oy)) }
                        .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    Text("last week")
                        .scaledFont(size: 8, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .position(x: 28, y: oy - 6)
                }

                // Nightly HRV — the travellers
                hrvPath(w, h).stroke(tint.opacity(0.85),
                                     style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                ForEach(series.indices, id: \.self) { i in
                    Circle().fill(tint).frame(width: 4, height: 4)
                        .position(x: x(i, w), y: y(series[i].hrv, h))
                }

                if let i = hoverIndex, series.indices.contains(i) {
                    let px = x(i, w), py = y(series[i].hrv, h)
                    // Neutral scrub guide + a selection marker (halo, not a judgment)
                    Rectangle().fill(Color.secondary.opacity(0.30)).frame(width: 1)
                        .frame(maxHeight: .infinity).position(x: px, y: h / 2)
                    Circle().stroke(tint.opacity(0.4), lineWidth: 1)
                        .frame(width: 13, height: 13).position(x: px, y: py)
                    Circle().fill(tint)
                        .overlay(Circle().stroke(popoverBackground, lineWidth: 1.5))
                        .frame(width: 7, height: 7).position(x: px, y: py)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoverIndex = nearestIndex(loc.x, w)
                case .ended:           hoverIndex = nil
                }
            }
        }
    }

    private func nearestIndex(_ px: CGFloat, _ w: CGFloat) -> Int {
        guard series.count > 1 else { return 0 }
        let step = w / CGFloat(series.count - 1)
        return min(max(Int((px / step).rounded()), 0), series.count - 1)
    }

    private func hrvPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            for (i, pt) in series.enumerated() {
                let c = CGPoint(x: x(i, w), y: y(pt.hrv, h))
                if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
            }
        }
    }
    private func envelope(_ w: CGFloat, _ h: CGFloat, upper: Bool) -> Path {
        Path { p in
            for (i, pt) in series.enumerated() {
                let v = upper ? pt.mean + pt.sd : pt.mean - pt.sd
                let c = CGPoint(x: x(i, w), y: y(v, h))
                if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
            }
        }
    }
    private func bandPath(_ w: CGFloat, _ h: CGFloat) -> Path {
        Path { p in
            guard !series.isEmpty else { return }
            for (i, pt) in series.enumerated() {
                let c = CGPoint(x: x(i, w), y: y(pt.mean + pt.sd, h))
                if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
            }
            for i in stride(from: series.count - 1, through: 0, by: -1) {
                p.addLine(to: CGPoint(x: x(i, w), y: y(series[i].mean - series[i].sd, h)))
            }
            p.closeSubpath()
        }
    }
}

// MARK: - Root Menu View
struct ContentView: View {
    @EnvironmentObject var vm: HRVViewModel

    var body: some View {
        Group {
            if !vm.isAuthed {
                SignInView()
            } else if vm.isLoading && vm.result == nil {
                LoadingView()
            } else if let result = vm.result {
                DashboardView(result: result)
            } else {
                ErrorView()
            }
        }
        #if os(macOS)
        .frame(width: 310)
        #else
        .frame(maxWidth: 310)
        #endif
        .padding(16)
        .background(popoverBackground)
        // Text scales with the user's Dynamic Type setting (iOS), but the panel
        // is dense with fixed frames, so clamp to the standard range: the full
        // accessibility sizes (2-3x) would need a layout reflow this doesn't
        // have yet. Meaningful growth without clipping.
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .onAppear { Task { await vm.loadIfStale() } }
    }
}

// MARK: - Sign In
struct SignInView: View {
    @EnvironmentObject var vm: HRVViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .scaledFont(size: 40)
                .foregroundStyle(.pink)
            Text("HRV-CV Monitor")
                .font(.headline)
            Text("How consistent your recovery has been: your 7-day HRV variation, from WHOOP.\nLower is better. Under 15% is steady, under 8% is elite.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: { Task { await vm.signIn() } }) {
                Label("Connect WHOOP", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.pink)
            .disabled(vm.isLoading)
            if vm.isLoading { ProgressView().scaleEffect(0.8) }
            if let err = vm.error {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            #if os(macOS)
            Divider().padding(.top, 4)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
            #endif
        }
        .padding(4)
    }
}

// MARK: - Loading
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Fetching WHOOP data…").font(.caption).foregroundStyle(.secondary)
        }
        .frame(height: 100)
    }
}

// MARK: - Error
struct ErrorView: View {
    @EnvironmentObject var vm: HRVViewModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(vm.error ?? "No data available.").font(.caption).multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }.controlSize(.small)
        }
        .frame(height: 100)
    }
}

// MARK: - Dashboard
struct DashboardView: View {
    let result: HRVCVResult
    @EnvironmentObject var vm: HRVViewModel
    @State private var trendHover: Int?
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiateWithoutColor
    @Environment(\.openURL) private var openURL
    // HRVCV_A11Y=1 forces the no-color rendering (the env key is read-only, so
    // snapshots can't inject it; this dev flag previews what the setting shows).
    private var differentiateWithoutColor: Bool {
        systemDifferentiateWithoutColor
            || ProcessInfo.processInfo.environment["HRVCV_A11Y"] == "1"
    }

    var body: some View {
        // While scrubbing the chart you're time-travelling — dim today's verdict
        // so the history reads as primary.
        let scrubbing = trendHover != nil
        // Whitespace, not rules, separates sections — one consistent air scale.
        return VStack(alignment: .leading, spacing: 16) {
            // Chart unit: the gauge, its trajectory, and the scale, grouped tightly.
            // Only the dimmed pieces animate — never the chart (avoids scrub jitter).
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    CVGauge(cv: result.cv,
                            accent: verdictColor(result.verdict),
                            label: result.verdictLabel)
                        .help("Your 7-night HRV consistency (\(result.window)). Lower is better: ≤8% elite, ≤15% on track.")
                    zoneLegend
                }
                .opacity(scrubbing ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.15), value: scrubbing)
                trendChart
            }
            statusCard
                .opacity(scrubbing ? 0.4 : 1)
                .animation(.easeInOut(duration: 0.15), value: scrubbing)
            statsRow
            dayTable
            Divider().opacity(0.3)
            footerRow
        }
    }

    // MARK: Hero — the gauge and its HRV-CV trajectory as one unit (no card box).
    // The line flows straight out of the gauge; the row below doubles as a live
    // readout while scrubbing.
    // MARK: Evidence chart — nightly HRV inside its expected range, open (no box),
    // grouped with the gauge as one chart unit. Answers "why is CV what it is."
    @ViewBuilder
    var trendChart: some View {
        if result.hrvSeries.count >= 2 {
            let s = result.hrvSeries
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if let i = trendHover, s.indices.contains(i) {
                        hrvReadout(s[i])
                    } else {
                        HStack(spacing: 4) {
                            Text("HRV")
                                .scaledFont(size: 11, weight: .bold)
                                .foregroundStyle(.secondary)
                            Text("typical range")
                                .scaledFont(size: 9)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        baselineSummary
                    }
                }
                .frame(height: 14)   // fixed so the default↔scrub swap can't reflow
                HRVBandChart(series: s,
                             oldBaseline: result.previousMean,
                             tint: verdictColor(result.verdict),
                             hoverIndex: $trendHover)
                    .frame(height: 76)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chartA11yLabel(s))
                HStack {
                    Text(s.first?.label ?? "")
                    Spacer()
                    Text(s.last?.label ?? "")
                }
                .scaledFont(size: 9)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // Spoken summary of the evidence chart for VoiceOver.
    func chartA11yLabel(_ s: [HRVSeriesPoint]) -> String {
        var text = "Nightly HRV chart, \(s.count) nights, \(s.first?.label ?? "") to \(s.last?.label ?? "")."
        if let d = result.baselineDeltaMs, abs(d) >= 1 {
            text += String(format: " Baseline %@ %.0f milliseconds versus last week.",
                           d > 0 ? "up" : "down", abs(d))
        }
        return text
    }

    // Live readout for a hovered night: date, HRV, and that night's recovery.
    // The ms value is tinted by THAT NIGHT's recovery band (matching the table
    // bars), not the week's verdict — per-night color = recovery, week-level
    // color = verdict.
    func hrvReadout(_ p: HRVSeriesPoint) -> some View {
        HStack(spacing: 6) {
            Text(p.label).foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", p.hrv)).foregroundStyle(recoveryColor(p.recovery))
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                Circle().fill(recoveryColor(p.recovery)).frame(width: 6, height: 6)
                Text("\(p.recovery)% recovery").foregroundStyle(.secondary)
            }
        }
        .scaledFont(size: 10, weight: .semibold, design: .rounded)
    }

    // WHOOP recovery zones: green ≥67, yellow 34–66, red <34.
    func recoveryColor(_ pct: Int) -> Color {
        pct >= 67 ? tierGreen : pct >= 34 ? tierAmber : tierRed
    }

    // Baseline change vs last week, in ms (HRV up = good = green).
    @ViewBuilder
    var baselineSummary: some View {
        if let d = result.baselineDeltaMs, abs(d) >= 1 {
            let up = d > 0
            HStack(spacing: 3) {
                Image(systemName: up ? "arrow.up" : "arrow.down").scaledFont(size: 8, weight: .bold)
                Text(String(format: "Baseline %@ %.0f ms", up ? "up" : "down", abs(d)))
            }
            .scaledFont(size: 10, weight: .semibold)
            .foregroundStyle(up ? tierGreen : tierRed)
        }
    }

    // MARK: Verdict callout — the one contained card, gently tinted by the verdict.
    var statusCard: some View {
        let accent = verdictColor(result.verdict)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 3)
            // The (i) sits only in the headline row, not its own full-height
            // column, so the detail sentence and SIGNALS run the full width.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(result.statusHeadline)
                        .scaledFont(size: 12, weight: .semibold)
                        .foregroundStyle(accent)
                    Spacer(minLength: 6)
                    Button(action: openLearnMore) {
                        Image(systemName: "info.circle")
                            .scaledFont(size: 12)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("What is HRV-CV?")
                    .accessibilityLabel("Learn more about HRV-CV")
                }
                Text(result.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                signalsList
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }

    // MARK: Status callout: headline + detail in a quietly tinted card,
    // with an (i) that explains what HRV-CV is.
    // Reasoning: the signals behind the verdict, expressed as logic (qualitative
    // reasons), not telemetry — the raw numbers already live elsewhere in the UI.
    @ViewBuilder
    var signalsList: some View {
        if result.baselineDeltaMs != nil {
            Divider().opacity(0.35).padding(.top, 3)
            HStack(spacing: 4) {
                Text("SIGNALS")
                    .scaledFont(size: 9, weight: .semibold)
                    .tracking(0.6)
                Text("· VS. PRIOR 7 NIGHTS")
                    .scaledFont(size: 9, weight: .medium)
                    .tracking(0.6)
                    .opacity(0.7)
            }
            .foregroundStyle(.tertiary)
            .padding(.top, 3)
            VStack(spacing: 3) {
                baselineSignalRow
                swingSignalRow
                recoverySignalRow
                sleepConsistencySignalRow
            }
            .padding(.top, 2)
        }
    }

    // The app's read on one signal. Rendered as a colored dot by default, as a
    // distinct glyph when the system asks to differentiate without color, and
    // spoken as words by VoiceOver — never color alone.
    enum SignalJudgment {
        case good, neutral, watch, concern

        // Neutral is deliberately the quietest thing in the row (dimmer than
        // the value text): a colored glyph means "the app has an opinion",
        // a faint one means "just context". Gray never means bad — bad is coral.
        var tint: Color {
            switch self {
            case .good:    return tierGreen
            case .neutral: return Color.primary.opacity(0.35)
            case .watch:   return tierAmber
            case .concern: return tierRed
            }
        }
        var symbol: String {
            switch self {
            case .good:    return "checkmark"
            case .neutral: return "minus"
            case .watch:   return "exclamationmark"
            case .concern: return "exclamationmark.triangle.fill"
            }
        }
        var spoken: String {
            switch self {
            case .good:    return "A good sign."
            case .neutral: return ""
            case .watch:   return "Worth watching."
            case .concern: return "Concerning."
            }
        }
    }

    // Your average HRV level, week over week. "HRV baseline", not "Baseline":
    // a WHOOP user thinks in HRV ms, so name the thing being averaged.
    var baselineSignalRow: some View {
        let bd = result.baselineDeltaMs ?? 0
        let judgment: SignalJudgment, word: String, sym: String
        if bd > 3        { judgment = .good;    word = "Rising";  sym = "arrow.up" }
        else if bd < -3  { judgment = .concern; word = "Falling"; sym = "arrow.down" }
        else             { judgment = .neutral; word = "Steady";  sym = "arrow.right" }
        return signalRow(judgment: judgment, symbol: sym, label: "HRV baseline", value: word)
            .help(result.previousMean.map {
                String(format: "Average nightly HRV: %.1f ms over the last 7 nights, %.1f ms the 7 nights before that.",
                       result.mean, $0)
            } ?? "")
    }

    // The night-to-night spread of HRV (what HRV-CV measures), as a direction.
    // Never "Variability": to a WHOOP user that word IS HRV. The word states the
    // fact; the tint says whether it's concerning in context. A widening swing
    // is only colored when CV is elevated, and even then the baseline decides:
    // rising = expected (leveling up), flat = caution, falling = warning.
    var swingSignalRow: some View {
        let delta = result.trendDelta ?? 0
        let widening = delta > 0.5, settling = delta < -0.5
        let word = widening ? "Widened" : settling ? "Settled" : "Steady"
        let sym  = widening ? "arrow.up" : settling ? "arrow.down" : "arrow.right"
        let judgment: SignalJudgment
        if settling                      { judgment = .good }
        else if !widening                { judgment = .neutral }
        else if result.tier != .reducing { judgment = .neutral }
        else {
            switch result.baselineDirection {
            case .some(1):  judgment = .neutral
            case .some(-1): judgment = .concern
            default:        judgment = .watch
            }
        }
        return signalRow(judgment: judgment, symbol: sym, label: "Night-to-night swing", value: word)
            .help(result.previousCV.map {
                String(format: "HRV-CV: %.1f%% over the last 7 nights, %.1f%% the 7 nights before that.", result.cv, $0)
            } ?? "")
    }

    // Context, not an input to the verdict: does WHOOP's own recovery score
    // agree with the HRV story?
    var recoverySignalRow: some View {
        let r = result.avgRecovery
        let judgment: SignalJudgment = r >= 67 ? .good : r >= 34 ? .watch : .concern
        let word = r >= 67 ? "Strong" : r >= 34 ? "Moderate" : "Low"
        return signalRow(judgment: judgment, label: "Recovery", value: word)
            .help("Average WHOOP recovery across the 7 nights: \(r)%.")
    }

    // Context, not an input to the verdict: has sleep timing itself gotten
    // more or less regular? A plausible "why" behind a widening HRV swing.
    // Hidden entirely until read:sleep is granted (existing sign-ins won't
    // have it until they reconnect) and sleep data lands in this window.
    @ViewBuilder
    var sleepConsistencySignalRow: some View {
        if let consistency = result.avgSleepConsistency {
            sleepRow(consistency: consistency)
        }
    }

    // Split out of the @ViewBuilder above: the imperative switch that picks
    // the word/glyph/judgment can't live inside a ViewBuilder (the builder
    // would try to read the assignment switch as a view), so it goes in a
    // plain function with an explicit return.
    private func sleepRow(consistency: Int) -> some View {
        let judgment: SignalJudgment, word: String, sym: String
        switch result.sleepConsistencyDirection {
        case .some(1):  judgment = .good;    word = "Rising";  sym = "arrow.up"
        case .some(-1): judgment = .watch;   word = "Falling"; sym = "arrow.down"
        default:        judgment = .neutral; word = "Steady";  sym = "arrow.right"
        }
        return signalRow(judgment: judgment, symbol: sym, label: "Sleep consistency", value: word)
            .help(result.previousSleepConsistency.map {
                "WHOOP sleep consistency: \(consistency)% over the last 7 nights, \($0)% the 7 nights before that."
            } ?? "WHOOP sleep consistency: \(consistency)% over the last 7 nights.")
    }

    // One row of the reasoning: a glyph + a factual word. Two clean channels:
    // the arrow (and the word, which restates it) is the FACT — which way that
    // quantity moved; the tint is the JUDGMENT — green good, amber watch, coral
    // concern, gray informational. Recovery is a level, not a direction, so it
    // gets a dot. When the system asks to differentiate without color, the
    // glyph becomes the judgment itself (check / minus / ! / warning); VoiceOver
    // speaks fact + judgment in words.
    func signalRow(judgment: SignalJudgment, symbol: String? = nil,
                   label: String, value: String) -> some View {
        HStack(spacing: 7) {
            Group {
                if differentiateWithoutColor {
                    Image(systemName: judgment.symbol)
                        .scaledFont(size: 8, weight: .bold)
                } else if let symbol {
                    Image(systemName: symbol)
                        .scaledFont(size: 8, weight: .bold)
                } else {
                    Circle().frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(judgment.tint)
            .frame(width: 10)
            Text(label).foregroundStyle(.tertiary)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .scaledFont(size: 9.5, weight: .medium, design: .rounded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(judgment.spoken)")
    }

    // Verdict color = severity: green when things are good (elite, on track, or a
    // rising baseline explaining the swing), amber for elevated-but-stable, coral
    // only for the true warning (destabilizing).
    func verdictColor(_ v: HRVCVResult.Verdict) -> Color {
        switch v {
        case .elite, .onTrack, .levelingUp: return tierGreen
        case .elevated:                     return tierAmber
        case .destabilizing:                return tierRed
        }
    }

    private func openLearnMore() {
        if let url = URL(string: "https://www.whoop.com/us/en/thelocker/hrv-cv-recovery-metric/") {
            openURL(url)
        }
    }

    // MARK: Tier scale — the gauge's key, directly beneath it. A neutral
    // reference ladder (never colored — color belongs to the verdict), read
    // like a segmented control: a quiet chip marks the tier you're in, so
    // "where you are on the ladder" is stated, not inferred from the knob.
    var zoneLegend: some View {
        HStack(spacing: 6) {
            tierMark("Elite",    "≤8",   tier: .elite)
            tierMark("On Track", "8–15", tier: .target)
            tierMark("Elevated", ">15",  tier: .reducing)
        }
        .frame(maxWidth: .infinity)
    }

    func tierMark(_ name: String, _ range: String, tier: HRVCVResult.Tier) -> some View {
        let active = result.tier == tier
        return HStack(spacing: 4) {
            Text(name)
                .scaledFont(size: 9, weight: active ? .bold : .medium)
                .foregroundStyle(active ? Color.primary : Color.secondary)
            Text(range)
                .scaledFont(size: 9, design: .monospaced)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background {
            if active {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
            }
        }
    }

    // MARK: Stats row
    var statsRow: some View {
        HStack {
            statCell(label: "AVG HRV", value: result.meanFormatted,
                     help: "Your average nightly HRV (rMSSD) over the window. The arrow is the direction vs last week — a rising baseline means you're levelling up, which is why a higher CV can still be good.",
                     trend: result.baselineDirection)
            Spacer()
            statCell(label: "SPREAD", value: result.sdFormatted,
                     help: "How much your nightly HRV varied (standard deviation). HRV-CV is this spread divided by the average.")
            Spacer()
            statCell(label: "RECOVERY", value: "\(result.avgRecovery)%",
                     help: "Average WHOOP recovery over the 7-night window.",
                     valueColor: recoveryColor(result.avgRecovery))
        }
    }

    func statCell(label: String, value: String, help: String,
                  trend: Int? = nil, valueColor: Color? = nil) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(value).scaledFont(size: 13, weight: .semibold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(valueColor ?? .primary)
                if let t = trend {
                    Image(systemName: t > 0 ? "arrow.up" : t < 0 ? "arrow.down" : "arrow.right")
                        .scaledFont(size: 8, weight: .bold)
                        .foregroundStyle(t > 0 ? tierGreen : t < 0 ? tierRed : .secondary)
                }
            }
            Text(label)
                .scaledFont(size: 9, weight: .semibold)
                .tracking(0.6)
                .foregroundStyle(.tertiary)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var text = "\(label): \(value)."
            if let t = trend, t != 0 { text += t > 0 ? " Up versus last week." : " Down versus last week." }
            return text
        }())
    }

    // MARK: Day table
    var dayTable: some View {
        VStack(spacing: 4) {
            // Column headers
            HStack(spacing: 8) {
                Text("DAY")
                    .frame(width: 48, alignment: .leading)
                Text("WHOOP RECOVERY")
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Mirror the data row's trailing columns (30 recovery% + 34 HRV
                // + ms unit) so "HRV" sits directly over the numbers, not the
                // "ms". The recovery-% column stays unlabeled; the ms slot is a
                // hidden placeholder that just reserves the unit's width.
                Spacer()
                    .frame(width: 30)
                Text("HRV")
                    .frame(width: 34, alignment: .trailing)
                Text("ms")
                    .scaledFont(size: 10)
                    .hidden()
            }
            .scaledFont(size: 9, weight: .semibold)
            .tracking(0.5)
            .foregroundStyle(.tertiary)

            ForEach(result.days.reversed()) { day in
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .leading)
                    recoveryBar(day.recovery)
                    Text("\(day.recovery)%")
                        .scaledFont(size: 10, weight: .medium, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text(String(format: "%.1f", day.hrv))
                        .scaledFont(size: 11, design: .monospaced)
                        .frame(width: 34, alignment: .trailing)
                    Text("ms")
                        .scaledFont(size: 10)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    func recoveryBar(_ pct: Int) -> some View {
        let color = recoveryColor(pct)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.opacity(0.85))
                    .frame(width: max(4, geo.size.width * CGFloat(pct) / 100))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)   // the row's % text carries the value
    }

    // MARK: Footer
    var footerRow: some View {
        HStack {
            if let updated = vm.lastUpdated {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: { Task { await vm.load() } }) {
                Image(systemName: "arrow.clockwise")
                    .scaledFont(size: 12)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
            .accessibilityLabel("Refresh")

            Menu {
                #if os(macOS)
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { on in
                        try? on ? SMAppService.mainApp.register()
                                : SMAppService.mainApp.unregister()
                    }))
                Divider()
                #endif
                Button("Sign out", action: vm.signOut)
                #if os(macOS)
                Divider()
                Button("Quit HRV-CV Monitor") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                #endif
            } label: {
                Image(systemName: "ellipsis")
                    .scaledFont(size: 12)
                    .foregroundStyle(.secondary)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .menuIndicator(.hidden)
            .frame(width: 20)
            .accessibilityLabel("More options")
        }
    }
}
