import SwiftUI
import HRVCVCore

@main
struct HRVCVApp: App {
    @StateObject private var vm = HRVViewModel()

    init() {
        #if os(macOS)
        Snapshot.runIfRequested()   // dev hook, no-op unless HRVCV_SNAPSHOT is set
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra {
            ContentView()
                .environmentObject(vm)
        } label: {
            menuLabel
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView()
                .environmentObject(vm)
        }
        #endif
    }

    #if os(macOS)
    /// The text/icon shown in the menu bar itself.
    @ViewBuilder
    var menuLabel: some View {
        if let result = vm.result {
            MenuBarLabel(result: result)
        } else {
            Image(systemName: "heart.text.square")
        }
    }
    #endif
}

#if os(macOS)
// MARK: - Menu Bar Label
// "CV" plus the value in a pill, rendered as ONE template image. No trend
// arrow — "up" for CV is ambiguous (that's the whole point of the app), so it
// stays out of the bar and the popover tells the story.
//
// Why an image: the status bar splits multi-view labels unreliably (an HStack
// of Texts once dropped the number), and template rendering strips color
// anyway. A single NSImage with isTemplate sidesteps both — alpha is the ink,
// so the pill knockout survives and adapts to light/dark/tinted menu bars.
struct MenuBarLabel: View {
    let result: HRVCVResult

    var body: some View {
        Image(nsImage: MenuBarLabel.render(cv: Int(result.cv.rounded())))
    }

    @MainActor
    static func render(cv: Int) -> NSImage {
        let label = (Text("CV ").font(.system(size: 11, weight: .semibold, design: .rounded))
                     + Text("\(cv)%").font(.system(size: 11, weight: .bold, design: .rounded)))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .overlay(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .strokeBorder(lineWidth: 1.2))   // outlined badge, not a filled block
            .foregroundStyle(.black)   // template images only use alpha; black previews cleanly
            .fixedSize()

        let renderer = ImageRenderer(content: label)
        renderer.scale = 2
        guard let cg = renderer.cgImage else {
            // Fallback: an empty template image; the popover still works.
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        let image = NSImage(cgImage: cg,
                            size: NSSize(width: CGFloat(cg.width) / 2,
                                         height: CGFloat(cg.height) / 2))
        image.isTemplate = true
        return image
    }
}
#endif
