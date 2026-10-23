import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = OrbPanel()
    lazy var conversation = Conversation(orb: panel.renderer)
    var statusItem: NSStatusItem!
    var shortcutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.pixelIcon()

        let menu = NSMenu()

        // Vozes do Kokoro em português: pm_alex (masculina jovem), pm_santa (masculina madura), pf_dora (feminina).
        let voices = NSMenu()
        for v in ["pm_alex", "pm_santa", "pf_dora"] {
            let i = item(v, #selector(pickVoice))
            i.state = v == currentVoice ? .on : .off
            voices.addItem(i)
        }
        menu.addItem(submenu("Voz", voices))

        // Cofres do Obsidian, lidos da configuração do próprio Obsidian; padrão = o cofre aberto.
        let vaults = NSMenu()
        let known = Self.obsidianVaults()
        if UserDefaults.standard.object(forKey: "obsidianVault") == nil, let open = known.first(where: \.open) {
            UserDefaults.standard.set(open.path, forKey: "obsidianVault")
        }
        let chosen = UserDefaults.standard.string(forKey: "obsidianVault") ?? ""
        for v in known {
            let i = item((v.path as NSString).lastPathComponent, #selector(pickVault))
            i.representedObject = v.path
            i.state = v.path == chosen ? .on : .off
            vaults.addItem(i)
        }
        let none = item("Nenhum", #selector(pickVault))
        none.representedObject = ""
        none.state = chosen.isEmpty ? .on : .off
        vaults.addItem(none)
        menu.addItem(submenu("Cofre do Obsidian", vaults))
        menu.addItem(item("Atalho…", #selector(showShortcut)))
        let login = item("Abrir ao iniciar o Mac", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        panel.orderFrontRegardless()
        Task { try? await conversation.server.ensureRunning() }  // desliga sozinho após 10 min sem uso
    }

    func applicationWillTerminate(_ notification: Notification) {
        conversation.server.stopNow()
        conversation.brain.interrupt()
    }

    static func obsidianVaults() -> [(path: String, open: Bool)] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = json["vaults"] as? [String: [String: Any]] else { return [] }
        return vaults.values.compactMap { v in
            (v["path"] as? String).map { ($0, v["open"] as? Bool ?? false) }
        }.sorted { $0.path < $1.path }
    }

    @objc func pickVault(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String ?? "", forKey: "obsidianVault")  // "" = nenhum
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        conversation.brain.interrupt()  // o próximo pedido reabre o Claude com o cofre novo
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Ava: abrir ao iniciar falhou: %@", "\(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func showShortcut() {
        if shortcutWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView:
                Form { KeyboardShortcuts.Recorder("Falar com a Ava:", name: .talk) }.padding(20)))
            w.title = "Atalho da Ava"
            w.isReleasedWhenClosed = false
            shortcutWindow = w
        }
        NSApp.activate()
        shortcutWindow?.center()
        shortcutWindow?.makeKeyAndOrderFront(nil)
    }

    var currentVoice: String { UserDefaults.standard.string(forKey: "voice") ?? defaultVoice }

    @objc func pickVoice(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.title, forKey: "voice")
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
    }


    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = menu
        return i
    }

    /// O mascote do tema, pixelado, na cor principal da paleta.
    static func pixelIcon() -> NSImage {
        let theme = Config.shared.theme
        return NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let (r, g, b) = theme.palette[5]
            NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).setFill()
            for (row, line) in (theme.rows + [theme.legs[0]]).enumerated() {
                for (col, ch) in line.enumerated() where ch == "#" {  // olhos ficam vazados
                    NSRect(x: col, y: 4 + row * 2, width: 1, height: 2).fill()  // 1×2 pt: mesma proporção do terminal
                }
            }
            return true
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
