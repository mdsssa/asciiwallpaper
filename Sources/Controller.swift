import AppKit
import QuartzCore

extension Notification.Name {
    static let asciiWallpaperScene = Notification.Name("ru.disa.asciiwallpaper.scene")
    static let asciiWallpaperMono = Notification.Name("ru.disa.asciiwallpaper.mono")
    static let asciiWallpaperQuit = Notification.Name("ru.disa.asciiwallpaper.quit")
}

final class WallpaperController: NSObject {
    private let options: Options
    private let metrics: FontMetrics
    private let renderer: AsciiRenderer

    private var engines: [WallpaperEngine] = []
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var time: Double = 0

    private var sceneKind: SceneKind
    private var mono: Monochrome
    private var autoCycle: Bool
    private let cycleSeconds: Double
    private var cycleElapsed: Double = 0

    private var userPaused = false
    private var systemPaused = false
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var statusAccumulator: Double = 0

    private var isPaused: Bool { userPaused || systemPaused }

    init(options: Options) {
        self.options = options
        let metrics = FontMetrics(pointSize: options.fontSize)
        self.metrics = metrics
        self.renderer = AsciiRenderer(metrics: metrics)
        self.sceneKind = options.scene ?? SceneKind.saved ?? .matrix
        self.mono = options.mono ?? Monochrome.saved
        self.autoCycle = options.cycle > 0
        self.cycleSeconds = options.cycle > 0 ? options.cycle : 75
        super.init()
        renderer.mono = mono
    }

    func start() {
        rebuildEngines()
        setupStatusItem()
        registerObservers()
        lastTick = CACurrentMediaTime()
        installTimer()
        print("ASCII Wallpaper: scene \"\(sceneKind.title)\", \(engines.count) display(s), \(Int(options.fps)) fps, mono: \(mono.rawValue)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for engine in engines {
            engine.teardown()
        }
        engines.removeAll()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        DistributedNotificationCenter.default().removeObserver(self)
        for entry in observers {
            entry.center.removeObserver(entry.token)
        }
        observers.removeAll()
    }

    // MARK: - Screens

    private func rebuildEngines() {
        for engine in engines {
            engine.teardown()
        }
        engines = NSScreen.screens.map { screen in
            WallpaperEngine(screen: screen, metrics: metrics, renderer: renderer, kind: sceneKind)
        }
    }

    // MARK: - Timer

    private func installTimer() {
        timer?.invalidate()
        let interval = 1.0 / max(1, options.fps)
        let t = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        t.tolerance = min(0.01, interval * 0.2)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        var dt = now - lastTick
        lastTick = now
        guard !isPaused else { return }
        if dt <= 0 || dt > 0.5 {
            dt = 1.0 / max(1, options.fps)
        }
        time += dt

        if autoCycle && cycleSeconds > 0 {
            cycleElapsed += dt
            if cycleElapsed >= cycleSeconds {
                cycleElapsed = 0
                advanceScene()
            }
        }

        for engine in engines {
            engine.update(time: time, dt: dt)
        }

        statusAccumulator += dt
        if statusAccumulator >= 1.0 {
            statusAccumulator = 0
            writeStatus()
        }
    }

    /// Diagnostics: when ASCIIWALLPAPER_STATUS is set, write the state once per second.
    private func writeStatus() {
        guard let path = ProcessInfo.processInfo.environment["ASCIIWALLPAPER_STATUS"] else { return }
        let screens = engines.map { "\($0.canvas.cols)x\($0.canvas.rows):\($0.drawCount)" }
            .joined(separator: ",")
        let json = "{\"time\":\(time),\"scene\":\"\(sceneKind.rawValue)\",\"mono\":\"\(mono.rawValue)\",\"paused\":\(isPaused),\"screens\":[\"\(screens)\"]}"
        try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Scenes

    func selectScene(_ kind: SceneKind) {
        guard kind != sceneKind else { return }
        sceneKind = kind
        SceneKind.saved = kind
        cycleElapsed = 0
        for engine in engines {
            engine.requestScene(kind)
        }
        rebuildMenu()
    }

    func advanceScene() {
        let all = SceneKind.allCases
        guard let index = all.firstIndex(of: sceneKind) else {
            selectScene(.matrix)
            return
        }
        selectScene(all[(index + 1) % all.count])
    }

    // MARK: - Menu

    private func setupStatusItem() {
        guard options.showMenu else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "textformat.alt",
                                   accessibilityDescription: "ASCII Wallpaper") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "A"
            }
            button.toolTip = "ASCII Wallpaper"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "ASCII Wallpaper", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        for kind in SceneKind.allCases {
            let menuItem = NSMenuItem(title: kind.title,
                                      action: #selector(selectSceneFromMenu(_:)),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = kind.rawValue
            menuItem.state = kind == sceneKind ? .on : .off
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())

        let next = NSMenuItem(title: "Next Scene", action: #selector(nextSceneAction), keyEquivalent: "n")
        next.target = self
        menu.addItem(next)

        let auto = NSMenuItem(title: "Auto-cycle", action: #selector(toggleAutoCycle), keyEquivalent: "")
        auto.target = self
        auto.state = autoCycle ? .on : .off
        menu.addItem(auto)

        let pause = NSMenuItem(title: userPaused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = userPaused ? .on : .off
        menu.addItem(pause)

        menu.addItem(NSMenuItem.separator())
        let monoItem = NSMenuItem(title: "Monochrome", action: nil, keyEquivalent: "")
        let monoMenu = NSMenu()
        for option in Monochrome.allCases {
            let item = NSMenuItem(title: option.title,
                                  action: #selector(selectMonoFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == mono ? .on : .off
            monoMenu.addItem(item)
        }
        monoItem.submenu = monoMenu
        menu.addItem(monoItem)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func selectSceneFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = SceneKind(rawValue: raw) else { return }
        selectScene(kind)
    }

    @objc private func nextSceneAction() {
        advanceScene()
    }

    @objc private func selectMonoFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = Monochrome(rawValue: raw) else { return }
        applyMono(option)
    }

    private func applyMono(_ option: Monochrome) {
        guard option != mono else { return }
        mono = option
        Monochrome.saved = option
        renderer.mono = option
        rebuildMenu()
    }

    @objc private func toggleAutoCycle() {
        autoCycle.toggle()
        cycleElapsed = 0
        rebuildMenu()
    }

    @objc private func togglePause() {
        userPaused.toggle()
        lastTick = CACurrentMediaTime()
        rebuildMenu()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func registerObservers() {
        let nc = NotificationCenter.default
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.rebuildEngines()
        }))

        let wc = NSWorkspace.shared.notificationCenter
        observers.append((wc, wc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.systemPaused = true
        }))
        observers.append((wc, wc.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.systemPaused = false
            self?.lastTick = CACurrentMediaTime()
        }))
        observers.append((wc, wc.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.systemPaused = true
        }))
        observers.append((wc, wc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            self?.systemPaused = false
            self?.lastTick = CACurrentMediaTime()
        }))

        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(remoteScene(_:)),
                       name: .asciiWallpaperScene, object: nil)
        dc.addObserver(self, selector: #selector(remoteMono(_:)),
                       name: .asciiWallpaperMono, object: nil)
        dc.addObserver(self, selector: #selector(remoteQuit(_:)),
                       name: .asciiWallpaperQuit, object: nil)
    }

    @objc private func remoteScene(_ note: Notification) {
        guard let raw = note.object as? String,
              let kind = SceneKind(rawValue: raw) else { return }
        selectScene(kind)
    }

    @objc private func remoteMono(_ note: Notification) {
        guard let raw = note.object as? String,
              let option = Monochrome(rawValue: raw) else { return }
        applyMono(option)
    }

    @objc private func remoteQuit(_ note: Notification) {
        NSApp.terminate(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: Options
    private var controller: WallpaperController?

    init(options: Options) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = WallpaperController(options: options)
        self.controller = controller
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
