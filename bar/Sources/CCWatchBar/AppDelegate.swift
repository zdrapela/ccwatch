import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var dataProvider: SessionDataProvider!
    private var tickerController: TickerController!
    private var cornerMenuItems: [PanelCorner: NSMenuItem] = [:]
    private var moveMenuItem: NSMenuItem!
    private var opacitySlider: NSSlider!
    private var editorMenuItems: [String: NSMenuItem] = [:]

    private static let editorChoices: [(label: String, command: String)] = [
        ("VS Code", "code"),
        ("Cursor", "cursor"),
        ("Zed", "zed"),
        ("Terminal", "open -a Terminal"),
        ("Finder", "open"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupOverlayWindow()
        setupDataProvider()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "text.line.first.and.arrowtriangle.forward",
                accessibilityDescription: "Session Monitor"
            )
        }

        let menu = NSMenu()
        menu.delegate = self

        let toggleItem = NSMenuItem(
            title: "Toggle Visibility",
            action: #selector(toggleVisibility),
            keyEquivalent: "v"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let positionMenu = NSMenu()
        for corner in PanelCorner.presets {
            let item = NSMenuItem(title: corner.label, action: #selector(setCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = corner.rawValue
            positionMenu.addItem(item)
            cornerMenuItems[corner] = item
        }

        positionMenu.addItem(NSMenuItem.separator())

        moveMenuItem = NSMenuItem(title: "Custom Position…", action: #selector(startMoveMode), keyEquivalent: "")
        moveMenuItem.target = self
        positionMenu.addItem(moveMenuItem)
        cornerMenuItems[.custom] = moveMenuItem

        updateCornerCheckmarks()

        let positionSubmenu = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionSubmenu.submenu = positionMenu
        menu.addItem(positionSubmenu)

        // Opacity slider
        let opacityMenu = NSMenu()

        let sliderItem = NSMenuItem()
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        let label = NSTextField(labelWithString: "Opacity")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 6, width: 50, height: 18)
        sliderView.addSubview(label)

        opacitySlider = NSSlider(value: 1.0, minValue: 0.2, maxValue: 1.0, target: self, action: #selector(opacityChanged(_:)))
        opacitySlider.frame = NSRect(x: 62, y: 6, width: 124, height: 18)
        opacitySlider.isContinuous = true
        sliderView.addSubview(opacitySlider)

        sliderItem.view = sliderView
        opacityMenu.addItem(sliderItem)

        let opacitySubmenu = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacitySubmenu.submenu = opacityMenu
        menu.addItem(opacitySubmenu)

        // Editor chooser
        let editorMenu = NSMenu()
        for choice in Self.editorChoices {
            let item = NSMenuItem(title: choice.label, action: #selector(setEditor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.command
            editorMenu.addItem(item)
            editorMenuItems[choice.command] = item
        }

        editorMenu.addItem(NSMenuItem.separator())

        let customEditorItem = NSMenuItem(title: "Custom\u{2026}", action: #selector(setCustomEditor), keyEquivalent: "")
        customEditorItem.target = self
        editorMenu.addItem(customEditorItem)
        editorMenuItems["__custom__"] = customEditorItem

        updateEditorCheckmarks()

        let editorSubmenu = NSMenuItem(title: "Editor", action: nil, keyEquivalent: "")
        editorSubmenu.submenu = editorMenu
        menu.addItem(editorSubmenu)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Overlay Window

    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow()

        tickerController = TickerController()
        tickerController.attach(to: overlayWindow.panelContentView)
        tickerController.onLayoutChanged = { [weak self] height in
            self?.overlayWindow.resizeToHeight(height)
        }
        tickerController.onWorkspaceClicked = { [weak self] cwd in
            self?.openWorkspace(cwd)
        }

        overlayWindow.onPositionChanged = { [weak self] in
            self?.updateCornerCheckmarks()
        }

        // Restore saved opacity (default 1.0)
        let savedOpacity = UserDefaults.standard.object(forKey: "panelOpacity") != nil
            ? UserDefaults.standard.double(forKey: "panelOpacity")
            : 1.0
        overlayWindow.alphaValue = CGFloat(savedOpacity)

        let visible = UserDefaults.standard.object(forKey: "barVisible") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "barVisible")
        if visible {
            overlayWindow.orderFront(nil)
        }
    }

    // MARK: - Data Provider

    private func setupDataProvider() {
        dataProvider = SessionDataProvider()
        dataProvider.onChange = { [weak self] sessions in
            self?.tickerController.update(sessions: sessions)
        }
        dataProvider.start()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Exit move mode whenever the user opens the menu
        if overlayWindow.isInMoveMode {
            overlayWindow.exitMoveMode()
        }
        // Sync opacity slider with current window value
        opacitySlider?.doubleValue = Double(overlayWindow.alphaValue)
    }

    // MARK: - Menu Actions

    @objc private func toggleVisibility() {
        if overlayWindow.isVisible {
            overlayWindow.orderOut(nil)
            UserDefaults.standard.set(false, forKey: "barVisible")
        } else {
            overlayWindow.orderFront(nil)
            UserDefaults.standard.set(true, forKey: "barVisible")
        }
    }

    @objc private func setCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = PanelCorner(rawValue: raw)
        else { return }

        overlayWindow.setPresetCorner(corner)
        updateCornerCheckmarks()
    }

    @objc private func startMoveMode() {
        if !overlayWindow.isVisible {
            overlayWindow.orderFront(nil)
            UserDefaults.standard.set(true, forKey: "barVisible")
        }
        overlayWindow.enterMoveMode()
    }

    private func updateCornerCheckmarks() {
        let current = overlayWindow?.corner ?? .bottomRight
        for (corner, item) in cornerMenuItems {
            item.state = corner == current ? .on : .off
        }
        // Update the move item title based on state
        if current == .custom {
            moveMenuItem?.title = "Custom Position"
        } else {
            moveMenuItem?.title = "Custom Position…"
        }
    }

    @objc private func setEditor(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        UserDefaults.standard.set(command, forKey: "editorCommand")
        updateEditorCheckmarks()
    }

    @objc private func setCustomEditor() {
        let alert = NSAlert()
        alert.messageText = "Custom Editor Command"
        alert.informativeText = "Enter the shell command to open a workspace directory.\nUse $DIR as a placeholder for the directory path, or it will be appended as the last argument.\n\nExamples: code, cursor, vim, open -a iTerm"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = UserDefaults.standard.string(forKey: "editorCommand") ?? "code"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let command = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !command.isEmpty {
                UserDefaults.standard.set(command, forKey: "editorCommand")
                updateEditorCheckmarks()
            }
        }
    }

    private func updateEditorCheckmarks() {
        let current = UserDefaults.standard.string(forKey: "editorCommand") ?? "code"
        let isPreset = Self.editorChoices.contains { $0.command == current }

        for (command, item) in editorMenuItems {
            if command == "__custom__" {
                item.state = isPreset ? .off : .on
                item.title = isPreset ? "Custom\u{2026}" : "Custom: \(current)"
            } else {
                item.state = command == current ? .on : .off
            }
        }
    }

    func openWorkspace(_ cwd: String) {
        let editor = UserDefaults.standard.string(forKey: "editorCommand") ?? "code"

        // Build the shell command
        let shellCommand: String
        if editor.contains("$DIR") {
            shellCommand = editor.replacingOccurrences(of: "$DIR", with: "'\(cwd)'")
        } else {
            shellCommand = "\(editor) '\(cwd)'"
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", shellCommand]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            // Fallback: open in Finder
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
        }
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue)
        overlayWindow.alphaValue = value
        UserDefaults.standard.set(sender.doubleValue, forKey: "panelOpacity")
    }

    @objc private func quitApp() {
        dataProvider.stop()
        NSApp.terminate(nil)
    }
}
