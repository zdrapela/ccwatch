import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var dataProvider: SessionDataProvider!
    private var tickerController: TickerController!
    private var cornerMenuItems: [PanelCorner: NSMenuItem] = [:]
    private var moveMenuItem: NSMenuItem!
    private var opacitySlider: NSSlider!

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
