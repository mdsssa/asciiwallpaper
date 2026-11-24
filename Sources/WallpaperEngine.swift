import AppKit
import QuartzCore

final class WallpaperView: NSView {
    weak var engine: WallpaperEngine?
    var fade: Double = 1

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine?.render(into: ctx, size: bounds.size)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// One wallpaper window per display: it lives at the desktop level, below Finder
/// icons and above the system wallpaper.
final class WallpaperEngine {
    let screen: NSScreen
    let metrics: FontMetrics
    let renderer: AsciiRenderer
    let canvas = Canvas()
    let window: NSWindow
    let view: WallpaperView

    private(set) var kind: SceneKind
    private var scene: Scene
    private var pending: SceneKind?
    private var fade: Double = 1
    private(set) var drawCount = 0

    init(screen: NSScreen, metrics: FontMetrics, renderer: AsciiRenderer, kind: SceneKind) {
        self.screen = screen
        self.metrics = metrics
        self.renderer = renderer
        self.kind = kind
        self.scene = kind.make()

        let frame = screen.frame
        self.window = NSWindow(contentRect: frame,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
        self.view = WallpaperView(frame: CGRect(origin: .zero, size: frame.size))

        configureWindow()
        view.engine = self
        window.contentView = view
        layout()
        window.orderFrontRegardless()
    }

    private func configureWindow() {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.title = "ASCII Wallpaper"
        window.acceptsMouseMovedEvents = false
        window.displaysWhenScreenProfileChanges = true
    }

    func layout() {
        let frame = screen.frame
        window.setFrame(frame, display: true)
        view.frame = CGRect(origin: .zero, size: frame.size)

        let cols = max(20, Int(frame.width / metrics.cellWidth))
        let rows = max(6, Int(frame.height / metrics.cellHeight))
        if cols != canvas.cols || rows != canvas.rows {
            canvas.resize(cols: cols, rows: rows)
            scene.resize(cols: cols, rows: rows, cellAspect: metrics.cellAspect)
        }
        window.orderFrontRegardless()
    }

    func requestScene(_ newKind: SceneKind) {
        guard newKind != kind else { return }
        pending = newKind
    }

    func update(time: Double, dt: Double) {
        if let target = pending {
            fade -= dt / 0.45
            if fade <= 0 {
                fade = 0
                scene = target.make()
                scene.resize(cols: canvas.cols, rows: canvas.rows, cellAspect: metrics.cellAspect)
                kind = target
                pending = nil
            }
        } else if fade < 1 {
            fade = min(1, fade + dt / 0.45)
        }

        canvas.clear()
        scene.update(time: time, dt: dt, canvas: canvas)
        view.fade = fade
        view.needsDisplay = true
    }

    func render(into ctx: CGContext, size: CGSize) {
        drawCount += 1
        renderer.draw(canvas: canvas, in: ctx, size: size,
                      background: scene.background, globalAlpha: view.fade)
    }

    func teardown() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}
