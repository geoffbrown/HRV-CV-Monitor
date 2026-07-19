import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Tier Palette
// One hue per tier, used consistently across gauge, stats, and bars.
// Muted status colors (not alarms), adaptive to light/dark: a touch brighter
// and more saturated in dark mode so they read on a dark background.
public func adaptiveTier(light: (Double, Double, Double),
                         dark:  (Double, Double, Double)) -> Color {
    #if os(macOS)
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let c = isDark ? dark : light
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    })
    #else
    Color(uiColor: UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        let c = isDark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    })
    #endif
}

public let tierGreen = adaptiveTier(light: (0.30, 0.72, 0.48), dark: (0.40, 0.82, 0.56))
public let tierAmber = adaptiveTier(light: (0.90, 0.66, 0.24), dark: (0.96, 0.75, 0.38))
public let tierRed   = adaptiveTier(light: (0.84, 0.46, 0.40), dark: (0.94, 0.57, 0.52))  // muted coral

// Opaque popover/panel background, so the panel reads as a rich solid surface
// instead of a washed-out translucent material. Also used to "punch" the gauge
// knob and tick gaps so they match the panel exactly.
public let popoverBackground = adaptiveTier(light: (0.96, 0.96, 0.97), dark: (0.12, 0.12, 0.13))
