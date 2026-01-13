import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var mainWindow: NSWindow?
    private var allowTerminate = false
    private var eventMonitor: Any?
    private var localEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState.shared

        panel = makePanel(rootView: StatusPopoverView(appState: appState))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "tt"
            button.target = self
            button.action = #selector(togglePopover)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: .ttShowMainWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hidePanelNotification),
            name: .ttHidePanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(requestQuit),
            name: .ttRequestQuit,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTerminate {
            return .terminateNow
        }
        mainWindow?.orderOut(nil)
        hidePanel()
        return .terminateCancel
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        togglePanel(anchoredTo: button)
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainWindowView(appState: AppState.shared))
            mainWindow = window
        }

        mainWindow?.center()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestQuit() {
        allowTerminate = true
        NSApp.terminate(nil)
    }

    @objc private func hidePanelNotification() {
        hidePanel()
    }

    private func makePanel<Content: View>(rootView: Content) -> NSPanel {
        let hosting = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting.view
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        return panel
    }

    private func togglePanel(anchoredTo button: NSStatusBarButton) {
        if panel?.isVisible == true {
            hidePanel()
            return
        }
        showPanel(anchoredTo: button)
    }

    private func showPanel(anchoredTo button: NSStatusBarButton) {
        guard let panel else { return }
        guard let screen = button.window?.screen else { return }

        let buttonFrame = button.window?.convertToScreen(button.frame) ?? .zero
        let panelSize = panel.frame.size
        let x = max(screen.frame.minX, min(buttonFrame.maxX - panelSize.width, screen.frame.maxX - panelSize.width))
        let y = buttonFrame.minY - panelSize.height
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)

        panel.orderFront(nil)
        startEventMonitor()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleGlobalClick()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleLocalClick(event)
            return event
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func handleGlobalClick() {
        guard let panel else { return }
        if panel.frame.contains(NSEvent.mouseLocation) {
            return
        }
        hidePanel()
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard let panel else { return }
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) {
            return
        }
        if panel.isVisible {
            hidePanel()
        }
    }
}
