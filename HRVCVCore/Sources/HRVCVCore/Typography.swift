import SwiftUI

// MARK: - Scalable Type
// A system font at a specific point size that scales with the user's Dynamic
// Type setting, instead of staying fixed. Keeps the app's finely-tuned sizes at
// the default setting while letting text grow for people who need it.
//
// Why not semantic text styles (.caption/.footnote/...)? They'd snap the app's
// fine-grained size scale (8/9/9.5/10/11/12/13) onto iOS's coarser fixed rungs,
// enlarging and flattening the tuned hierarchy. Scaling a custom size preserves
// the exact design at the default setting and only grows it on demand.
//
// macOS has no system Dynamic Type control, so this is effectively inert there
// (the size stays as given) — which is fine; the win is on iOS.
public extension View {
    func scaledFont(size: CGFloat,
                    weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo textStyle: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}

private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}
