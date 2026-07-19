import SwiftUI

@main
struct HRVCVApp: App {
    @StateObject private var vm = HRVViewModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(vm)
        } label: {
            menuLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// The text/icon shown in the menu bar itself.
    @ViewBuilder
    var menuLabel: some View {
        if let result = vm.result {
            MenuBarLabel(result: result)
        } else {
            Image(systemName: "heart.text.square")
        }
    }
}

// MARK: - Menu Bar Label
// One glanceable thing: a tiny position arc + the value. No trend arrow — "up"
// for CV is ambiguous (that's the whole point of the app), so it stays out of
// the bar and the popover tells the story. Monochrome (the bar strips color).
struct MenuBarLabel: View {
    let result: HRVCVResult
    private var fill: CGFloat { CGFloat(min(max(result.cv / 30, 0), 1)) }

    var body: some View {
        // Identity ("CV") + metric ("22%") — no direction arrow, because the bar
        // can't show the verdict (colour is stripped) and "up" for CV is ambiguous.
        // Swap the "CV" Text for SpreadGlyph/MiniArc to try a glyph instead.
        HStack(spacing: 3) {
            Text("CV")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.7)
            Text("\(Int(result.cv.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }
}

// Stability glyph: a centered mark whose width = your spread (CV). Narrow = tight
// (stable), wide = variable. Faint ticks mark the ≤15% target width; when your
// mark grows past them, you're elevated. CV *is* spread, so this glyph is the metric.
struct SpreadGlyph: View {
    let normalized: CGFloat
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, cy = h / 2
            let maxHalf = w / 2 - 1
            let half = max(1.2, maxHalf * min(normalized, 1))
            let bracket = maxHalf * CGFloat(15.0 / 30.0)
            ZStack {
                Capsule().fill(Color.primary.opacity(0.22))
                    .frame(width: w, height: 1).position(x: w / 2, y: cy)
                ForEach([-1.0, 1.0], id: \.self) { s in
                    Rectangle().fill(Color.primary.opacity(0.4))
                        .frame(width: 1, height: h)
                        .position(x: w / 2 + CGFloat(s) * bracket, y: cy)
                }
                Capsule().fill(Color.primary)
                    .frame(width: half * 2, height: 3.5).position(x: w / 2, y: cy)
            }
        }
    }
}

// Tiny position gauge for the menu bar: a faint track with a solid fill to value.
struct MiniArc: View {
    let fill: CGFloat
    var body: some View {
        ZStack {
            MiniArcShape().stroke(Color.primary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            MiniArcShape().trim(from: 0, to: fill)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

struct MiniArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let r = min(rect.width / 2, rect.height) - 1
            let cx = rect.width / 2, cy = rect.height
            let steps = 40
            for i in 0...steps {
                let deg = 180.0 + Double(i) / Double(steps) * 180.0
                let rad = deg * .pi / 180
                let pt = CGPoint(x: cx + CGFloat(cos(rad)) * r, y: cy + CGFloat(sin(rad)) * r)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}
