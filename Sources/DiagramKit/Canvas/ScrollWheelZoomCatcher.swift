import AppKit
import SwiftUI

/// Zero-cost AppKit sink that turns ⌘-scroll into a cursor-anchored zoom request. Attach with
/// `.background(ScrollWheelZoomCatcher { factor, point in … })` so it inherits the host view's
/// bounds. `factor > 1` zooms in, `< 1` zooms out; `point` is in the host's flipped (top-left)
/// local space, ready to hand to a viewport's `zoom(toward:)`.
///
/// Shared by the diagram canvas (`CanvasScrollMonitor`) and the Photo Editor canvas, which keep
/// different viewport value types — hence the raw factor/point callback rather than a `Binding`.
public struct ScrollWheelZoomCatcher: NSViewRepresentable {
    public var onZoom: (_ factor: CGFloat, _ point: CGPoint) -> Void

    public func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onZoom = onZoom
        context.coordinator.install(on: view)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onZoom = onZoom
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        .zero
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Flipped to match SwiftUI's coordinate space; never claims a hit test from the canvas above.
    public final class CatcherView: NSView {
        public var onZoom: ((CGFloat, CGPoint) -> Void)?
        public override var isFlipped: Bool { true }
        public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    public final class Coordinator {
        private var monitor: Any?
        private weak var view: CatcherView?

        public func install(on view: CatcherView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let host = self.view,
                      let window = host.window,
                      host.superview != nil,
                      event.windowNumber == window.windowNumber,
                      event.modifierFlags.contains(.command)
                else { return event }

                let local = host.convert(event.locationInWindow, from: nil)
                guard host.bounds.contains(local) else { return event }

                let delta = event.scrollingDeltaY
                guard delta != 0 else { return nil }
                let factor: CGFloat = delta > 0 ? 1.06 : 0.94
                DispatchQueue.main.async { host.onZoom?(factor, local) }
                return nil
            }
        }

        public func tearDown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
        public init() {}
    }
    public init(onZoom: @escaping (_ factor: CGFloat, _ point: CGPoint) -> Void) {
        self.onZoom = onZoom
    }
}
