import SwiftUI
import AppKit

/// Installs a local NSEvent keyDown monitor scoped to the view's window.
/// Return `nil` from the handler to consume the event, or the event to pass it
/// through. The monitor is added when the view attaches to a window and removed
/// when it detaches.
struct KeyEventCatcher: NSViewRepresentable {
    let handler: (NSEvent) -> NSEvent?

    func makeNSView(context: Context) -> KeyCatcherNSView {
        let view = KeyCatcherNSView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: KeyCatcherNSView, context: Context) {
        view.handler = handler
    }
}

final class KeyCatcherNSView: NSView {
    var handler: ((NSEvent) -> NSEvent?)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window else { return event }
            guard event.window === window else { return event }
            return self.handler?(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}
