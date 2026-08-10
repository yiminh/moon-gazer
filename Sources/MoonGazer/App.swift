import AppKit
import SwiftUI

final class DashboardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DashboardWindow!
    private let store = UsageStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let hosting = NSHostingView(rootView: DashboardView(store: store))
        window = DashboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = "Moon Gazer"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.055, green: 0.055, blue: 0.07, alpha: 1)
        window.isReleasedWhenClosed = false
        window.aspectRatio = NSSize(width: 960, height: 540)
        window.contentMinSize = NSSize(width: 640, height: 360)
        // Standard traffic lights + the green button enters real full-screen (its
        // own Space), so it sits beside the desktop and never fights the menu bar.
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        positionWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        store.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func screensChanged() { positionWindow() }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [store] in
            store.refreshUsage()
        }
    }

    /// Place the (normal, resizable) window on the small dedicated 960×540-pt
    /// display if present, else the smallest secondary screen, else centered on
    /// the main screen. The user can then hit the green button to full-screen it.
    private func positionWindow() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let screens = NSScreen.screens
        let dedicated = screens.first { $0.frame.size == NSSize(width: 960, height: 540) }
            ?? (screens.count > 1
                ? screens.dropFirst().min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                : nil)

        let target = dedicated ?? screens.first
        guard let target else { return }
        let visible = target.visibleFrame
        // Fit the 960×540 canvas within the screen, keeping aspect ratio.
        let scale = min(1, min(visible.width / 960, visible.height / 540))
        let size = NSSize(width: 960 * scale, height: 540 * scale)
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width, height: size.height)
        window.setFrame(frame, display: true)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Moon Gazer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        appMenu.addItem(refreshItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Moon Gazer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Moon Gazer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreen = NSMenuItem(title: "Enter Full Screen",
                                    action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(fullScreen)
        let paceItem = NSMenuItem(title: "Show Pace Marker", action: #selector(togglePace), keyEquivalent: "p")
        paceItem.target = self
        paceItem.state = store.showPace ? .on : .off
        self.paceMenuItem = paceItem
        viewMenu.addItem(paceItem)

        viewMenu.addItem(.separator())
        let barColorsItem = NSMenuItem(title: "Bar Colors", action: nil, keyEquivalent: "")
        let barColorsMenu = NSMenu(title: "Bar Colors")
        for mode in BarColorMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(setBarMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = store.barColorMode == mode ? .on : .off
            barColorsMenu.addItem(item)
            barColorItems.append(item)
        }
        barColorsItem.submenu = barColorsMenu
        viewMenu.addItem(barColorsItem)

        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }

    private var paceMenuItem: NSMenuItem?
    private var barColorItems: [NSMenuItem] = []

    @objc private func togglePace() {
        store.showPace.toggle()
        paceMenuItem?.state = store.showPace ? .on : .off
    }

    @objc private func setBarMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = BarColorMode(rawValue: raw) else { return }
        store.barColorMode = mode
        for item in barColorItems {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func refreshNow() { store.refreshUsage() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            runProbe()
            return
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }

    /// Headless data-layer check: fetch both providers, scan sessions, print, exit.
    static func runProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let claude = await ClaudeService().fetch()
            let codex = await CodexService().fetch()
            let omlx = await OMLXService().fetch()
            let sessions = SessionMonitor().scan()

            func describe(_ s: ProviderSnapshot) {
                print("== \(s.provider.rawValue) ==")
                print("  plan: \(s.plan ?? "-")  account: \(s.account ?? "-")")
                if let e = s.error { print("  error: \(e)") }
                for w in [s.primary, s.secondary].compactMap({ $0 }) + s.extraWindows {
                    let reset = w.resetsAt.map { " resets \(shortDuration($0.timeIntervalSinceNow))" } ?? ""
                    print(String(format: "  %-16@ %5.1f%%%@", w.label as NSString, w.usedPercent, reset))
                }
                if let x = s.extra { print("  \(x.text)") }
            }
            describe(claude)
            describe(codex)
            print("== OMLX ==")
            if !omlx.configured {
                print("  not configured (set MOONGAZER_OMLX_URL or ~/.config/moongazer/config.json)")
            } else if let error = omlx.error, omlx.fetchedAt == nil {
                print("  error: \(error)")
            } else {
                print("  host: \(omlx.host ?? "-")  GPU: \(omlx.gpuPercent.map { "\(Int($0))%" } ?? "-")  MEM: \(omlx.memPercent.map { "\(Int($0))%" } ?? "-") (\(omlx.memUsedGB ?? 0)/\(omlx.memTotalGB ?? 0) GB)")
                print("  model: \(omlx.model ?? "-")  PP: \(omlx.ppTps.map { "\(Int($0)) tok/s" } ?? "-")  TG: \(omlx.tgTps.map { "\(Int($0)) tok/s" } ?? "-")")
            }
            print("== TASKS ==")
            print("  claude: \(sessions.claude.map { "\($0.name)[\($0.state)]" }.joined(separator: ", "))")
            print("  codex:  \(sessions.codex.map { "\($0.name)[\($0.state)]" }.joined(separator: ", "))")
            semaphore.signal()
        }
        semaphore.wait()
    }
}
