#if os(macOS)
import SwiftUI
import AppKit

// MARK: - Snapshot Hook
// Dev-only: HRVCV_SNAPSHOT=/path.png renders the popover to a PNG and exits
// (add HRVCV_LIGHT=1 for light mode). Combine with HRVCV_MOCK=1 for a
// deterministic, headless render — no WHOOP auth, no clicking the menu bar.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["HRVCV_SNAPSHOT"] else { return }
        let light = ProcessInfo.processInfo.environment["HRVCV_LIGHT"] == "1"
        let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
        NSApplication.shared.appearance = appearance

        let vm = HRVViewModel()
        let renderer = ImageRenderer(content: ContentView()
            .environmentObject(vm)
            .environment(\.colorScheme, light ? .light : .dark))
        renderer.scale = 2
        // Resolve dynamic NSColors (adaptiveTier) against the requested appearance.
        var cg: CGImage?
        appearance.performAsCurrentDrawingAppearance { cg = renderer.cgImage }
        if let cg {
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: path))
        }

        // Also emit the menu bar label (ink on transparent) next to the popover.
        if let result = vm.result {
            let img = MenuBarLabel.render(cv: Int(result.cv.rounded()))
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff) {
                let menuPath = path.replacingOccurrences(of: ".png", with: "-menubar.png")
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: menuPath))
            }
        }
        exit(0)
    }
}
#endif
