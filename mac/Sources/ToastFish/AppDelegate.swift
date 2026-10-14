import AppKit
import ToastFishCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notifications: NotificationService?
    private var database: Database?
    private var settings: AppSettings?
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

        do {
            guard let bundledURL = Bundle.main.url(forResource: "inami", withExtension: "db") else {
                throw DatabaseError.sqlite("找不到 inami.db，请使用打包后的应用。")
            }
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("ToastFish", isDirectory: true)
            let url = try Database.prepareUserDatabase(bundledURL: bundledURL, appSupportDir: support)
            let database = try Database(url: url)
            settings = try AppSettings(database: database)
            self.database = database
        } catch {
            showDatabaseError(error)
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
                item.state = book.tableName == self.settings?.book ? .on : .off
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
        settings.addItem(toggleItem("自动播放", state: self.settings?.autoPlay == true ? .on : .off))
        settings.addItem(toggleItem("自动日志", state: self.settings?.autoLog == true ? .on : .off))
        settings.addItem(actionItem("重置进度", action: #selector(resetProgress(_:))))
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
        guard let tableName = sender.representedObject as? String,
              let database, let settings else { return }
        do {
            // Goin's current count is a cyclic counter, not derived from row status.
            if tableName != "Goin" {
                try database.updateTableCount(book: tableName)
            }
            let count = try database.selectCount(book: tableName)
            try database.updateBookName(tableName)
            settings.book = tableName
            for item in bookItems {
                item.state = (item.representedObject as? String) == settings.book ? .on : .off
            }
            notifications?.post(title: "ToastFish", body: "当前词库：\(sender.title)\n当前进度：\(count.current)/\(count.total)")
        } catch {
            showDatabaseError(error)
        }
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard sender.title == "自动播放" || sender.title == "自动日志" else {
            sender.state = sender.state == .on ? .off : .on
            return
        }
        guard let database, let settings else { return }
        let oldPlay = settings.autoPlay
        let oldLog = settings.autoLog
        if sender.title == "自动播放" { settings.autoPlay.toggle() }
        if sender.title == "自动日志" { settings.autoLog.toggle() }
        do {
            try settings.save(to: database)
        } catch {
            settings.autoPlay = oldPlay
            settings.autoLog = oldLog
            showDatabaseError(error)
            return
        }
        let enabled = sender.title == "自动播放" ? settings.autoPlay : settings.autoLog
        sender.state = enabled ? .on : .off
    }

    @objc private func resetProgress(_ sender: NSMenuItem) {
        guard let database, let settings,
              let book = Books.catalog.first(where: { $0.tableName == settings.book }) else { return }
        let alert = NSAlert()
        alert.messageText = "是否要重置“\(book.displayName)”的学习进度?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try database.resetTableCount(book: book.tableName)
            notifications?.post(title: "ToastFish", body: "重置\(book.displayName)完成！")
        } catch {
            showDatabaseError(error)
        }
    }

    private func showDatabaseError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "数据库操作失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
