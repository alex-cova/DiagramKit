//  Vendored from SplitView (MIT) — Copyright (c) 2023 Steven G. Harris.
//  See LICENSE in this directory. Ported for Hextech: see README.md.

import SwiftUI

/// A ViewModifier to split Content with `secondary` in the SplitLayout direction held by `layout`.
///
/// Other customization (e.g., `fraction`, `hide`, `styling`, `constraints`, `splitter`) is done using
/// those separate modifiers on the Split instance returned from this modifier.
struct SplitModifier<S: View>: ViewModifier {
    let layout: LayoutHolder
    let secondary: () -> S

    func body(content: Content) -> some View {
        Split(primary: { content }, secondary: secondary)
            .layout(layout)
    }

    init(_ layout: LayoutHolder, @ViewBuilder secondary: @escaping (() -> S)) {
        self.layout = layout
        self.secondary = secondary
    }
}

/// A ViewModifier to split Content horizontally with `secondary`.
struct HSplitModifier<S: View>: ViewModifier {
    let secondary: () -> S

    func body(content: Content) -> some View {
        HSplit(left: { content }, right: secondary)
    }

    init(@ViewBuilder secondary: @escaping (() -> S)) {
        self.secondary = secondary
    }
}

/// A ViewModifier to split Content vertically with `secondary`.
struct VSplitModifier<S: View>: ViewModifier {
    let secondary: () -> S

    func body(content: Content) -> some View {
        VSplit(top: { content }, bottom: secondary)
    }

    init(@ViewBuilder secondary: @escaping (() -> S)) {
        self.secondary = secondary
    }
}

extension View {

    /// Return an instance of Split in the SplitLayout direction held by `layout`, with a Splitter separating this `primary` View and `secondary`.
    func split(_ layout: LayoutHolder, @ViewBuilder secondary: @escaping (() -> some View)) -> some View {
        modifier(SplitModifier(layout, secondary: secondary))
    }

    /// Return an instance of Split in `layout` direction, with a Splitter separating this `primary` View and `secondary`.
    func split(_ layout: SplitLayout, @ViewBuilder secondary: @escaping (() -> some View)) -> some View {
        split(LayoutHolder(layout), secondary: secondary)
    }

    /// Return an instance of HSplit with a Splitter separating this `primary` View and `secondary`.
    func hSplit(@ViewBuilder secondary: @escaping (() -> some View)) -> some View {
        modifier(HSplitModifier(secondary: secondary))
    }

    /// Return an instance of VSplit with a Splitter separating this `primary` View and `secondary`.
    func vSplit(@ViewBuilder secondary: @escaping (() -> some View)) -> some View {
        modifier(VSplitModifier(secondary: secondary))
    }
}
