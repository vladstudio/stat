import Cocoa
import MacAppKit
import StatKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusItemView!
    private var systemStats: SystemStats!
    private var sampler: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        systemStats = SystemStats()
        LoginItem.enableOnFirstLaunch(key: "stat.loginItemEnabled")
        UserDefaults.standard.register(defaults:
            Dictionary(uniqueKeysWithValues: StatBlock.allCases.map { ($0.defaultsKey, true) })
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        statusView = StatusItemView(frame: NSRect(x: 0, y: 0, width: 150, height: 22))
        statusView.visibleBlocks = Set(StatBlock.allCases.filter {
            UserDefaults.standard.bool(forKey: $0.defaultsKey)
        })
        statusItem.button?.addSubview(statusView)
        statusItem.button?.frame = statusView.frame

        let menu = NSMenu()
        menu.delegate = self
        for block in StatBlock.allCases {
            let item = NSMenuItem(title: block.rawValue, action: #selector(toggleBlock(_:)), keyEquivalent: "")
            item.representedObject = block
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Start on Login", action: #selector(toggleLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About Stat", action: #selector(openAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Stat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu

        // Token must be retained or the observation is silently cancelled
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.systemStats.invalidateBaseline() }
            }
        }

        // Sample via the SystemStats actor: syscalls run off the main thread,
        // view updates hop back to main. First read establishes the baseline.
        sampler = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let stats = await self.systemStats.read()
                self.statusView.stats = stats
                self.statusItem.length = self.statusView.frame.width
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @objc private func toggleBlock(_ sender: NSMenuItem) {
        guard let block = sender.representedObject as? StatBlock else { return }
        if statusView.visibleBlocks.contains(block) {
            guard statusView.visibleBlocks.count > 1 else { return }
            statusView.visibleBlocks.remove(block)
        } else {
            statusView.visibleBlocks.insert(block)
        }
        UserDefaults.standard.set(statusView.visibleBlocks.contains(block), forKey: block.defaultsKey)
        statusItem.length = statusView.frame.width
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.toggle()
    }

    @objc private func checkUpdates(_ sender: NSMenuItem) {
        UpdateChecker.check(repo: "vladstudio/stat", appName: "Stat", manual: true)
    }

    @objc private func openAbout(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://apps.vlad.studio/stat")!)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(toggleLogin) {
                item.state = LoginItem.isEnabled ? .on : .off
            } else if item.action == #selector(toggleBlock(_:)),
                      let block = item.representedObject as? StatBlock {
                item.state = statusView.visibleBlocks.contains(block) ? .on : .off
            }
        }
    }
}
