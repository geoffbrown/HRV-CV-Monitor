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
struct MenuBarLabel: View {
    let result: HRVCVResult

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trendSymbol)
                .font(.system(size: 9, weight: .bold))
            Text("HRV-CV \(Int(result.cv.rounded()))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
        )
    }

    // Direction only: color is stripped by the menu bar, so the arrow shape
    // carries the trend. Lower CV is better: down = improving, up = worsening.
    private var trendSymbol: String {
        switch result.trend {
        case .improving: return "arrow.down.right"
        case .worsening: return "arrow.up.right"
        case .flat:      return "minus"
        }
    }
}
