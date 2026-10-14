import AppKit
import ToastFishCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notifications: NotificationService?
    private var selectedBook = "CET4_1"
    private var bookItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            let alert = NSAlert()
            alert.messageText = "程序已经在运行了"
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let service = NotificationService()
        notifications = service
        installStatusItem()
        service.requestAuthorization()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            item.button?.image = image
        } else {
            let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "ToastFish")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            item.button?.image = image
        }
        item.button?.toolTip = "ToastFish"
        item.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem("开始！", action: #selector(showStub(_:))))
        menu.addItem(actionItem("导入单词", action: #selector(showStub(_:))))
        for (title, language) in [("英语词汇", BookLanguage.english), ("日语词汇", .japanese)] {
            let submenu = addSubmenu(title, to: menu)
            for book in Books.catalog where book.language == language {
                let item = actionItem(book.displayName, action: #selector(selectBook(_:)))
                item.representedObject = book.tableName
                item.state = book.tableName == selectedBook ? .on : .off
                submenu.addItem(item)
                bookItems.append(item)
            }
        }
        let tests = addSubmenu("随机测试", to: menu)
        for title in ["随机单词测试", "随机五十音测试", "随机日语单词测试"] {
            tests.addItem(actionItem(title, action: #selector(showStub(_:))))
        }
        let settings = addSubmenu("参数设置", to: menu)
        for title in ["单词个数", "英标类型"] {
            settings.addItem(actionItem(title, action: #selector(showStub(_:))))
        }
        for title in ["自动播放", "自动日志"] {
            settings.addItem(toggleItem(title))
        }
        settings.addItem(actionItem("重置进度", action: #selector(showStub(_:))))
        let help = addSubmenu("使用说明", to: menu)
        help.addItem(actionItem("快捷方式", action: #selector(showShortcuts(_:))))
        help.addItem(actionItem("使用说明(必读)", action: #selector(openInstructions(_:))))
        help.addItem(actionItem("官方网站", action: #selector(openWebsite(_:))))
        help.addItem(actionItem("Star!!", action: #selector(openStar(_:))))
        menu.addItem(toggleItem("开机启动", state: .off))
        menu.addItem(actionItem("退出", action: #selector(quit(_:))))
        return menu
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, state: NSControl.StateValue = .on) -> NSMenuItem {
        let item = actionItem(title, action: #selector(toggle(_:)))
        item.state = state
        return item
    }

    private func addSubmenu(_ title: String, to menu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    @objc private func selectBook(_ sender: NSMenuItem) {
        guard let tableName = sender.representedObject as? String else { return }
        selectedBook = tableName
        for item in bookItems {
            item.state = (item.representedObject as? String) == selectedBook ? .on : .off
        }
        notifications?.post(title: "ToastFish", body: "当前词库：\(sender.title)")
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
    }

    @objc private func showStub(_ sender: NSMenuItem) {
        notifications?.post(title: "ToastFish", body: "功能开发中：\(sender.title)")
    }

    @objc private func showShortcuts(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "快捷方式"
        alert.informativeText = "⌥Q 开始内置单词学习\n⌥` 英语单词发音\n⌥1–⌥4 对应按钮1到4\n\n快捷键将在后续版本实现。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openInstructions(_ sender: NSMenuItem) {
        openResource("使用说明", extension: "html")
    }

    @objc private func openStar(_ sender: NSMenuItem) {
        openResource("Star", extension: "pdf")
    }

    private func openResource(_ name: String, extension fileExtension: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            notifications?.post(title: "ToastFish", body: "找不到资源：\(name).\(fileExtension)，请使用打包后的应用。")
            return
        }
        if !NSWorkspace.shared.open(url) {
            notifications?.post(title: "ToastFish", body: "无法打开：\(name).\(fileExtension)")
        }
    }

    @objc private func openWebsite(_ sender: NSMenuItem) {
        if let url = URL(string: "https://lab.magiconch.com/toast-fish/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
