import SwiftUI
import AppKit

@main
struct SyncCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.backgroundEngine)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let backgroundEngine = BackgroundSyncEngine()
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.icloud.fill", accessibilityDescription: "SyncCloud")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(togglePopover)
        }
        
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // Status header
        let statusTitle = NSMenuItem(title: "SyncCloud — Arka Plan", action: nil, keyEquivalent: "")
        statusTitle.isEnabled = false
        menu.addItem(statusTitle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Toggle background sync
        let toggleItem = NSMenuItem(
            title: backgroundEngine.isEnabled ? "✅ Arka Plan Aktif" : "⏸ Arka Plan Kapalı",
            action: #selector(toggleBackgroundSync),
            keyEquivalent: "b"
        )
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Interval submenu
        let intervalMenu = NSMenu()
        for interval in BackgroundSyncEngine.SyncInterval.allCases {
            let item = NSMenuItem(
                title: interval.label,
                action: #selector(changeInterval(_:)),
                keyEquivalent: ""
            )
            item.tag = interval.rawValue
            item.state = (backgroundEngine.syncInterval == interval) ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "⏱ Sıklık", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Sync now
        let syncNowItem = NSMenuItem(
            title: "🔄 Şimdi Kontrol Et",
            action: #selector(syncNow),
            keyEquivalent: "s"
        )
        menu.addItem(syncNowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Last sync info
        let lastSyncText: String
        if let lastDate = backgroundEngine.lastSyncDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            lastSyncText = "Son: \(formatter.string(from: lastDate)) — \(backgroundEngine.lastSyncCount) dosya"
        } else {
            lastSyncText = "Henüz senkronize edilmedi"
        }
        let lastSyncItem = NSMenuItem(title: lastSyncText, action: nil, keyEquivalent: "")
        lastSyncItem.isEnabled = false
        menu.addItem(lastSyncItem)
        
        // Status
        let statusLine = NSMenuItem(title: "📋 \(backgroundEngine.statusMessage)", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open main window
        let openItem = NSMenuItem(
            title: "📂 Ana Pencereyi Aç",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Uygulamayı Kapat",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func toggleBackgroundSync() {
        backgroundEngine.isEnabled.toggle()
        updateStatusIcon()
        updateMenu()
    }
    
    @objc private func changeInterval(_ sender: NSMenuItem) {
        if let interval = BackgroundSyncEngine.SyncInterval(rawValue: sender.tag) {
            backgroundEngine.syncInterval = interval
            updateMenu()
        }
    }
    
    @objc private func syncNow() {
        backgroundEngine.checkForNewPhotos()
        
        // Refresh menu after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.updateMenu()
        }
    }
    
    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func togglePopover() {
        updateMenu() // Refresh before showing
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateStatusIcon() {
        if let button = statusItem.button {
            let iconName = backgroundEngine.isEnabled
                ? "arrow.triangle.2.circlepath.icloud.fill"
                : "icloud.slash"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "SyncCloud")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }
}
