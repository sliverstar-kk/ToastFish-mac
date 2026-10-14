import AppKit
import ToastFishCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notifications: NotificationService?
    private var database: Database?
    private var settings: AppSettings?
    private var bookItems: [NSMenuItem] = []
    private var presenter: NotificationPresenter?
    private var studyTask: Task<Void, Never>?
    private var checkedAlertStyle = false

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
        presenter = NotificationPresenter(notifications: service)
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
        menu.addItem(actionItem("开始！", action: #selector(startStudy(_:))))
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
        settings.addItem(actionItem("单词个数", action: #selector(chooseWordNumber(_:))))
        settings.addItem(actionItem("英标类型", action: #selector(chooseEngType(_:))))
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

    // MARK: Study

    @objc private func startStudy(_ sender: NSMenuItem?) {
        guard let database, let settings, let presenter, let notifications else { return }
        guard notifications.isAvailable else {
            showAlert("请使用打包后的 ToastFish.app 运行", info: "通知只能在应用包中使用，请先运行 scripts/build_app.sh。")
            return
        }
        guard Books.catalog.first(where: { $0.tableName == settings.book })?.language == .english else {
            notifications.post(title: "ToastFish", body: "功能开发中：日语词汇背诵")
            return
        }
        let options = EnglishStudySession.Options(
            book: settings.book, number: settings.wordNumber,
            engType: settings.engType, autoPlay: settings.autoPlay
        )
        let previous = studyTask
        previous?.cancel()
        studyTask = Task { @MainActor [weak self] in
            // Let the old session save its finished cards before the new one picks words.
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            guard await self.checkNotificationPermission(), !Task.isCancelled else { return }
            let session = EnglishStudySession(database: database, presenter: presenter, options: options)
            do {
                let outcome = try await session.runSM2()
                if outcome == .cancelled, let error = notifications.lastPostError {
                    self.showAlert("通知发送失败，背诵已停止", info: error)
                }
            } catch {
                self.showDatabaseError(error)
            }
        }
    }

    /// Requests permission on first use; refuses to start when notifications are off, and
    /// once per launch points out that action buttons vanish with the banner style.
    private func checkNotificationPermission() async -> Bool {
        guard let notifications else { return false }
        switch await notifications.ensurePermission() {
        case .denied:
            askToOpenNotificationSettings("通知权限未开启",
                info: "ToastFish 通过通知推送单词。请在 系统设置 → 通知 → ToastFish 中允许通知，并把样式设为“提醒”。")
            return false
        case .allowed(let alertStyle):
            if !alertStyle && !checkedAlertStyle {
                checkedAlertStyle = true
                askToOpenNotificationSettings("建议把 ToastFish 的通知样式设为“提醒”",
                    info: "横幅样式的通知几秒后就会消失，按钮也随之隐藏。请在 系统设置 → 通知 → ToastFish 中选择“提醒”。")
            }
            return true
        }
    }

    private func askToOpenNotificationSettings(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "打开通知设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Settings

    @objc private func chooseWordNumber(_ sender: NSMenuItem) {
        guard let database, let settings else { return }
        let options = [5, 10, 15, 20]
        guard let index = choose("这次要背多少个？", options: options.map(String.init),
                                 selected: options.firstIndex(of: settings.wordNumber)) else { return }
        let old = settings.wordNumber
        settings.wordNumber = options[index]
        do {
            try database.updateNumber(settings.wordNumber)
            notifications?.post(title: "ToastFish", body: "已设置单词数量为：\(settings.wordNumber)")
        } catch {
            settings.wordNumber = old
            showDatabaseError(error)
        }
    }

    @objc private func chooseEngType(_ sender: NSMenuItem) {
        guard let database, let settings else { return }
        let names = ["美国", "英国"]
        guard let index = choose("请选择发音类型？", options: names, selected: settings.engType == 1 ? 0 : 1) else { return }
        let old = settings.engType
        settings.engType = index == 0 ? 1 : 2
        do {
            try settings.save(to: database)
            notifications?.post(title: "ToastFish", body: "已设置英语类型为：\(names[index])")
        } catch {
            settings.engType = old
            showDatabaseError(error)
        }
    }

    /// A small modal with a pop-up list, replacing the Windows toast selection box.
    private func choose(_ message: String, options: [String], selected: Int?) -> Int? {
        let alert = NSAlert()
        alert.messageText = message
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
        popup.addItems(withTitles: options)
        popup.selectItem(at: selected ?? 0)
        alert.accessoryView = popup
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? popup.indexOfSelectedItem : nil
    }

    private func showAlert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    /// Covers 退出, logout and shutdown: cancelling makes the session save the cards it already finished.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        notifications?.clearDelivered()
        guard let task = studyTask else { return .terminateNow }
        studyTask = nil
        task.cancel()
        Task { @MainActor in
            await task.value
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
