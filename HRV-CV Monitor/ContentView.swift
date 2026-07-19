import SwiftUI
import Combine
import AppKit

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
        isAuthed = service.isAuthenticated
        if isAuthed { Task { await load() } }
        scheduleRefresh()
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
        guard isAuthed else { return }
        isLoading = true
        error = nil
        do {
            let records = try await service.fetchRecovery(limit: 25)
            result      = HRVCalculator.calculate(from: records)
            lastUpdated = Date()
            if result == nil { error = "Need 7+ nights of WHOOP data." }
        } catch {
            self.error = error.localizedDescription
            if case WHOOPError.unauthorized = error { isAuthed = false }
        }
        isLoading = false
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

// MARK: - Tier Palette
// One hue per tier, used consistently across gauge, stats, and bars.
// Muted status colors (not alarms), adaptive to light/dark: a touch brighter
// and more saturated in dark mode so they read on a dark background.
private func adaptiveTier(light: (Double, Double, Double),
                          dark:  (Double, Double, Double)) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    })
}

let tierGreen = adaptiveTier(light: (0.30, 0.72, 0.48), dark: (0.40, 0.82, 0.56))
let tierAmber = adaptiveTier(light: (0.90, 0.66, 0.24), dark: (0.96, 0.75, 0.38))
let tierRed   = adaptiveTier(light: (0.84, 0.46, 0.40), dark: (0.94, 0.57, 0.52))  // muted coral

// Opaque popover background, so the panel reads as a rich solid surface instead
// of a washed-out translucent material. Also used to "punch" the gauge knob and
// tick gaps so they match the panel exactly.
let popoverBackground = adaptiveTier(light: (0.96, 0.96, 0.97), dark: (0.12, 0.12, 0.13))

// MARK: - Arc Gauge
struct CVGauge: View {
    let cv: Double
    private let maxCV: Double = 30   // 30% fills the arc fully

    private var normalized: Double { min(max(cv / maxCV, 0), 1.0) }

    private var color: Color {
        if cv <= 8  { return tierGreen }
        if cv <= 15 { return tierAmber }
        return tierRed
    }

    private var tierLabel: String {
        if cv <= 8  { return "ELITE" }
        if cv <= 15 { return "ON TRACK" }
        return "ELEVATED"
    }

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
            let g  = 0.02                        // half-gap at each boundary
            let stroke = StrokeStyle(lineWidth: lw, lineCap: .round)
            let track  = Color.primary.opacity(0.08)

            ZStack {
                // Neutral track, drawn as three tier segments with soft rounded gaps
                Group {
                    seg(0,      b1 - g, cx, cy, r).stroke(track, style: stroke)
                    seg(b1 + g, b2 - g, cx, cy, r).stroke(track, style: stroke)
                    seg(b2 + g, 1,      cx, cy, r).stroke(track, style: stroke)
                }

                // Single-hue fill up to the value, within the same segments
                Group {
                    if normalized > 0 {
                        seg(0, min(b1 - g, normalized), cx, cy, r).stroke(color, style: stroke)
                    }
                    if normalized > b1 + g {
                        seg(b1 + g, min(b2 - g, normalized), cx, cy, r).stroke(color, style: stroke)
                    }
                    if normalized > b2 + g {
                        seg(b2 + g, min(1, normalized), cx, cy, r).stroke(color, style: stroke)
                    }
                }

                // Knob at the value
                let pt = arcPoint(n: normalized, cx: cx, cy: cy, r: r)
                Circle()
                    .fill(popoverBackground)
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .frame(width: 13, height: 13)
                    .position(pt)

                // Metric + value + tier, centered in the bowl
                VStack(spacing: 2) {
                    Text("HRV-CV")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.tertiary)
                    Text(String(format: "%.1f%%", cv))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                    Text(tierLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                }
                .position(x: cx, y: cy - r * 0.40)
            }
        }
        .frame(height: 124)
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

// MARK: - Sparkline (interactive: reports the hovered index to its container)
struct Sparkline: View {
    let points: [TrendPoint]
    let lineColor: Color                  // line / area / resting dot (the verdict color)
    let tierColor: (Double) -> Color      // accent for the hovered point, by its tier
    let thresholds: [Double]              // tier boundaries drawn as faint guide lines
    @Binding var hoverIndex: Int?

    private var values: [Double] { points.map(\.cv) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pts = coords(in: size)
            ZStack(alignment: .topLeading) {
                // Faint tier boundary guides (e.g. 8% and 15%)
                ForEach(thresholds, id: \.self) { t in
                    let ty = y(t, size.height)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: ty))
                        p.addLine(to: CGPoint(x: size.width, y: ty))
                    }
                    .stroke(Color.secondary.opacity(0.16),
                            style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }

                areaPath(pts, height: size.height)
                    .fill(LinearGradient(colors: [lineColor.opacity(0.14), lineColor.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                linePath(pts)
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

                if let i = hoverIndex, pts.indices.contains(i) {
                    let p = pts[i]
                    let accent = tierColor(values[i])
                    Rectangle().fill(accent.opacity(0.40)).frame(width: 1)
                        .frame(maxHeight: .infinity).position(x: p.x, y: size.height / 2)
                    Circle().fill(accent).frame(width: 6, height: 6).position(p)
                } else if let last = pts.last {
                    Circle().fill(lineColor).frame(width: 4.5, height: 4.5).position(last)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc): hoverIndex = nearestIndex(to: loc.x, in: size)
                case .ended:           hoverIndex = nil
                }
            }
        }
    }

    // Vertical domain includes the data and the thresholds so the guides sit in range.
    private var domain: (lo: Double, hi: Double) {
        let all = values + thresholds
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.12, 0.5)
        return (lo - pad, hi + pad)
    }

    private func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        let d = domain
        return (1 - CGFloat((v - d.lo) / max(d.hi - d.lo, 0.0001))) * h
    }

    private func coords(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: y(v, size.height))
        }
    }

    private func nearestIndex(to x: CGFloat, in size: CGSize) -> Int {
        guard values.count > 1 else { return 0 }
        let stepX = size.width / CGFloat(values.count - 1)
        return min(max(Int((x / stepX).rounded()), 0), values.count - 1)
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: height))
            p.addLine(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: last.x, y: height))
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
        .frame(width: 310)
        .padding(16)
        .background(popoverBackground)
    }
}

// MARK: - Sign In
struct SignInView: View {
    @EnvironmentObject var vm: HRVViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 40))
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
            Divider().padding(.top, 4)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CVGauge(cv: result.cv)
            trendCard
            zoneLegend
            statusCard
            Divider().opacity(0.5)
            statsRow
            dayTable
            Divider().opacity(0.5)
            footerRow
        }
    }

    // MARK: Hero — the gauge and its HRV-CV trajectory as one unit (no card box).
    // The line flows straight out of the gauge; the row below doubles as a live
    // readout while scrubbing.
    // MARK: Trend card — contained to match the status card, with real presence
    // (taller chart, padding). Header doubles as a live readout while scrubbing.
    @ViewBuilder
    var trendCard: some View {
        if result.cvHistory.count >= 2 {
            let pts = result.cvHistory
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let i = trendHover, pts.indices.contains(i) {
                        trendReadout(pts[i])
                    } else {
                        Text("HRV-CV TREND")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        trendSummary
                    }
                }
                Sparkline(points: pts,
                          lineColor: verdictColor(result.verdict),
                          tierColor: { tierColor(forCV: $0) },
                          thresholds: [8, 15],
                          hoverIndex: $trendHover)
                    .frame(height: 50)
                HStack {
                    Text(pts.first?.label ?? "")
                    Spacer()
                    Text(pts.last?.label ?? "")
                }
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
    }

    // Live readout: the hovered point's date, HRV-CV (colored by that point's
    // tier), and average WHOOP recovery over its 7-night window.
    func trendReadout(_ pt: TrendPoint) -> some View {
        HStack(spacing: 6) {
            Text(pt.label).foregroundStyle(.secondary)
            Text(String(format: "HRV-CV %.1f%%", pt.cv))
                .foregroundStyle(tierColor(forCV: pt.cv))
            Spacer(minLength: 4)
            Text("\(pt.avgRecovery)% avg recovery").foregroundStyle(.tertiary)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
    }

    // Week-over-week summary shown in the trend-card header.
    @ViewBuilder
    var trendSummary: some View {
        if let delta = result.trendDelta {
            let worse = delta > 0.5, better = delta < -0.5
            let symbol = worse ? "arrow.up.right" : better ? "arrow.down.right" : "arrow.right"
            let tint: Color = worse ? tierRed : better ? tierGreen : .secondary
            let text = abs(delta) <= 0.5
                ? "Steady vs last week"
                : String(format: "%@ %.1f pts vs last week", worse ? "Up" : "Down", abs(delta))
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                Text(text)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
        }
    }

    // MARK: Status callout: headline + detail in a quietly tinted card,
    // with an (i) that explains what HRV-CV is.
    var statusCard: some View {
        let accent = verdictColor(result.verdict)
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.statusHeadline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text(result.statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button(action: openLearnMore) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("What is HRV-CV?")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }

    // Verdict color: green = doing well / levelling up, amber = fine, coral = watch out.
    func verdictColor(_ v: HRVCVResult.Verdict) -> Color {
        switch v {
        case .elite, .levelingUp:       return tierGreen
        case .onTrack:                  return tierAmber
        case .elevated, .destabilizing: return tierRed
        }
    }

    private func openLearnMore() {
        if let url = URL(string: "https://www.whoop.com/us/en/thelocker/hrv-cv-recovery-metric/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Tier scale: only the current tier lights up
    var zoneLegend: some View {
        HStack(spacing: 14) {
            tierMark("Elite", "≤8", tier: .elite)
            tierMark("On Track", "≤15", tier: .target)
            tierMark("Elevated", ">15", tier: .reducing)
        }
        .frame(maxWidth: .infinity)
    }

    func tierMark(_ name: String, _ range: String, tier: HRVCVResult.Tier) -> some View {
        let active = result.tier == tier
        return HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 9, weight: active ? .bold : .medium))
                .foregroundStyle(active ? tierColor(tier) : Color.secondary)
            Text(range)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    func tierColor(_ tier: HRVCVResult.Tier) -> Color {
        switch tier {
        case .elite:    return tierGreen
        case .target:   return tierAmber
        case .reducing: return tierRed
        }
    }

    // Tier color for a raw CV value (used by the sparkline hover).
    func tierColor(forCV cv: Double) -> Color {
        if cv <= 8  { return tierGreen }
        if cv <= 15 { return tierAmber }
        return tierRed
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
            statCell(label: "WINDOW", value: result.window,
                     help: "The 7 nights included in this HRV-CV calculation.")
        }
    }

    func statCell(label: String, value: String, help: String, trend: Int? = nil) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 2) {
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
                if let t = trend {
                    Image(systemName: t > 0 ? "arrow.up" : t < 0 ? "arrow.down" : "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(t > 0 ? tierGreen : t < 0 ? tierRed : .secondary)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
        }
        .help(help)
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
                Text("HRV")
                    .frame(width: 56, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .semibold))
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
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text(String(format: "%.1f", day.hrv))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 34, alignment: .trailing)
                    Text("ms")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    func recoveryBar(_ pct: Int) -> some View {
        let color: Color = pct >= 67 ? tierGreen : pct >= 34 ? tierAmber : tierRed
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.opacity(0.85))
                    .frame(width: max(4, geo.size.width * CGFloat(pct) / 100))
            }
        }
        .frame(height: 5)
    }

    // MARK: Footer
    var footerRow: some View {
        HStack {
            if let updated = vm.lastUpdated {
                Text("Updated \(updated, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { Task { await vm.load() } }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(vm.isLoading)

            Menu {
                Button("Sign out", action: vm.signOut)
                Divider()
                Button("Quit HRV-CV Monitor") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
    }
}
