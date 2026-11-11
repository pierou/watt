import SwiftUI
import AppKit

/// Shared user-preference keys and scene identifiers.
enum WattSettings {
    static let pinnedPanel = "com.watt.pinnedPanel"
    static let windowIdentifier = "com.watt.panelWindow"
}

enum WattWindowID {
    static let panel = "watt-panel"
}

@main
struct WattApp: App {
    @StateObject private var powerMonitor = PowerMonitorService()
    @StateObject private var systemMetrics = SystemMetricsService()
    @AppStorage(WattSettings.pinnedPanel) private var pinnedPanel = false

    init() {
        // Closing windows during termination must not be read as the user unpinning.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            WattWindows.isClosingForQuit = true
        }
    }

    var body: some Scene {
        MenuBarExtra {
            if pinnedPanel {
                PinnedNoticeView()
            } else {
                ContentView(powerMonitor: powerMonitor, systemMetrics: systemMetrics)
                    .onAppear { PanelVisibilityTracker.shared.appear(powerMonitor, systemMetrics) }
                    .onDisappear { PanelVisibilityTracker.shared.disappear(powerMonitor, systemMetrics) }
            }
        } label: {
            MenuBarLabel(powerMonitor: powerMonitor)
        }
        .menuBarExtraStyle(.window)

        Window("Watt", id: WattWindowID.panel) {
            PanelWindowRoot(powerMonitor: powerMonitor, systemMetrics: systemMetrics)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

// MARK: - Menu bar label

/// The status item title, plus the one-off restore of a pinned panel from a previous run.
private struct MenuBarLabel: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @Environment(\.openWindow) private var openWindow
    @AppStorage(WattSettings.pinnedPanel) private var pinnedPanel = false
    @State private var didRestore = false

    var body: some View {
        Text(String(format: "%.2fW", abs(powerMonitor.currentPower)))
            .monospacedDigit()
            .task {
                guard !didRestore else { return }
                didRestore = true
                guard pinnedPanel else { return }
                WattWindows.focusPanel(openWindow)
            }
    }
}

// MARK: - Floating panel window

private struct PanelWindowRoot: View {
    @ObservedObject var powerMonitor: PowerMonitorService
    @ObservedObject var systemMetrics: SystemMetricsService
    @AppStorage(WattSettings.pinnedPanel) private var pinnedPanel = false

    var body: some View {
        ContentView(powerMonitor: powerMonitor, systemMetrics: systemMetrics)
            .background(WindowConfigurator())
            .onAppear { PanelVisibilityTracker.shared.appear(powerMonitor, systemMetrics) }
            .onDisappear { PanelVisibilityTracker.shared.disappear(powerMonitor, systemMetrics) }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard !WattWindows.isClosingForQuit,
                      let window = note.object as? NSWindow,
                      window.identifier?.rawValue == WattSettings.windowIdentifier else { return }
                pinnedPanel = false
            }
    }
}

/// Reaches the hosting `NSWindow` to make the panel float above ordinary windows,
/// stay visible while the app is in the background, and be draggable by its content.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(WattSettings.windowIdentifier)
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.title = "Watt"
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Menu bar content while pinned

/// Shown in the menu bar dropdown instead of a second copy of the panel:
/// the live panel already exists as a floating window.
struct PinnedNoticeView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(WattSettings.pinnedPanel) private var pinnedPanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Panel pinned")
                    .font(.system(size: 13, weight: .semibold))
            }

            Text("Watt is showing its panel in a floating window.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Focus window") { WattWindows.focusPanel(openWindow) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Unpin") {
                    pinnedPanel = false
                    WattWindows.closePanel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 288)
    }
}

enum WattWindows {
    /// True while the app is tearing down, so a window closing on quit is not mistaken
    /// for the user unpinning the panel.
    static var isClosingForQuit = false

    /// Brings the pinned panel on screen and makes it key.
    static func focusPanel(_ openWindow: OpenWindowAction) {
        openWindow(id: WattWindowID.panel)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if let window = panelWindow() {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    static func panelWindow() -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == WattSettings.windowIdentifier }
    }

    /// Closes the floating panel. `dismissWindow` needs macOS 14, this does not.
    static func closePanel() {
        panelWindow()?.close()
    }
}

// MARK: - Visibility bookkeeping

/// Counts how many panels (menu bar dropdown, floating window) are on screen, so sampling
/// keeps its fast interval while any one of them is visible.
final class PanelVisibilityTracker {
    static let shared = PanelVisibilityTracker()

    private var count = 0
    private weak var powerMonitor: PowerMonitorService?
    private weak var systemMetrics: SystemMetricsService?

    private init() {}

    func appear(_ powerMonitor: PowerMonitorService, _ systemMetrics: SystemMetricsService) {
        self.powerMonitor = powerMonitor
        self.systemMetrics = systemMetrics
        count += 1
        if count == 1 { setVisible(true) }
    }

    func disappear(_ powerMonitor: PowerMonitorService, _ systemMetrics: SystemMetricsService) {
        count = max(0, count - 1)
        if count == 0 { setVisible(false) }
    }

    private func setVisible(_ visible: Bool) {
        powerMonitor?.setAppVisible(visible)
        systemMetrics?.setAppVisible(visible)
    }
}
