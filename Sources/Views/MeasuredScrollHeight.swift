import SwiftUI

// MARK: - macOS 26 MenuBarExtra(.window) zero-height workaround
//
// Under macOS 26, a `ScrollView` sized with only `.frame(maxHeight:)` collapses to
// ZERO height inside `MenuBarExtra(.window)` when the enclosing layout has no
// concrete height — the panel renders blank (header + Quit visible, the content in
// between gone). The data layer is fine; it's purely a SwiftUI layout regression.
//
// Fix: measure the scroll *content's* natural height with a GeometryReader +
// PreferenceKey, then pin the ScrollView to a CONCRETE `.frame(height:)` clamped
// between a floor (so it never collapses before the first measurement) and a cap
// (so it grows to fit content, then scrolls for overflow). Do NOT revert any of
// these panels to a `maxHeight`-only frame — that reintroduces the blank-menu bug.
//
// Usage:
//   ScrollView {
//       VStack { ... }
//           .measureContentHeight()      // on the CONTENT, inside the ScrollView
//   }
//   .scrollContentHeight(cap: 320)       // on the ScrollView itself
//
// The two halves talk via the ContentHeightKey preference, so the reader always
// reflects the laid-out content rather than the (clamped) ScrollView frame.

/// Carries the scroll content's measured natural height up to the ScrollView.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Apply to the content *inside* a ScrollView so its natural height is published
    /// to an enclosing `.scrollContentHeight(cap:)`.
    func measureContentHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
    }

    /// Apply to a ScrollView whose content uses `.measureContentHeight()`. Frames the
    /// ScrollView to the measured content height clamped to `floor...cap`: it grows to
    /// fit content up to `cap`, then scrolls. Survives MenuBarExtra(.window) on macOS 26.
    ///
    /// - Parameters:
    ///   - cap: Maximum panel height. Content taller than this scrolls.
    ///   - floor: Minimum height, applied before the first measurement so the panel
    ///            never collapses to zero. Defaults to 44.
    func scrollContentHeight(cap: CGFloat, floor: CGFloat = 44) -> some View {
        modifier(ScrollContentHeight(cap: cap, floor: floor))
    }
}

private struct ScrollContentHeight: ViewModifier {
    let cap: CGFloat
    let floor: CGFloat
    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ContentHeightKey.self) { measured = $0 }
            .frame(height: min(max(measured, floor), cap))
    }
}
