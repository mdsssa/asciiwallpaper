import AppKit
import QuartzCore

final class WallpaperView: NSView {
    weak var engine: WallpaperEngine?
    var fade: Double = 1

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine?.render(into: ctx, size: bounds.size, dirtyRect: dirtyRect)
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
    private(set) var frameCount = 0

    private var lastGlyphs: [UInt16] = []
    private var lastColors: [UInt32] = []
    private var lastAlphas: [UInt8] = []
    private var lastFade: Double = 1
    private var forceFullRedraw = true
    private var wasVisible = true
    private var lastOccludedFrame: Double = 0
    private(set) var lastDirtyFraction: Double = 1
    private(set) var lastDrawFraction: Double = 1

    private let tileCols = 16
    private let tileRows = 8
    private let occlusionEnabled =
        ProcessInfo.processInfo.environment["ASCIIWALLPAPER_DISABLE_OCCLUSION"] == nil

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
        lastGlyphs.removeAll(keepingCapacity: false)
        lastColors.removeAll(keepingCapacity: false)
        lastAlphas.removeAll(keepingCapacity: false)
        forceFullRedraw = true
        window.orderFrontRegardless()
    }

    func requestScene(_ newKind: SceneKind) {
        guard newKind != kind else { return }
        pending = newKind
    }

    /// Forces a full repaint, for example when the monochrome tint changes.
    func invalidate() {
        forceFullRedraw = true
        view.setNeedsDisplay(view.bounds)
    }

    func update(time: Double, dt: Double) {
        // If the window is completely covered by other windows, skip work.
        // A slow heartbeat keeps the surface correct even if occlusion is misreported.
        let hidden = occlusionEnabled && drawCount > 0 && !window.occlusionState.contains(.visible)
        if hidden && time - lastOccludedFrame < 2.0 {
            wasVisible = false
            return
        }
        if hidden {
            lastOccludedFrame = time
            forceFullRedraw = true
        } else if !wasVisible {
            wasVisible = true
            forceFullRedraw = true
        }

        if let target = pending {
            fade -= dt / 0.45
            if fade <= 0 {
                fade = 0
                scene = target.make()
                scene.resize(cols: canvas.cols, rows: canvas.rows, cellAspect: metrics.cellAspect)
                kind = target
                pending = nil
                forceFullRedraw = true
            }
        } else if fade < 1 {
            fade = min(1, fade + dt / 0.45)
        }

        if fade != lastFade {
            lastFade = fade
            forceFullRedraw = true
        }
        if fade < 1 {
            forceFullRedraw = true
        }

        canvas.clear()
        scene.update(time: time, dt: dt, canvas: canvas)
        view.fade = fade

        if forceFullRedraw {
            lastDirtyFraction = 1
            view.setNeedsDisplay(view.bounds)
        } else {
            let rects = dirtyRects()
            if !rects.isEmpty {
                for rect in rects {
                    view.setNeedsDisplay(rect)
                }
                let area = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
                lastDirtyFraction = Double(area / max(1, view.bounds.width * view.bounds.height))
            } else {
                lastDirtyFraction = 0
            }
        }

        lastGlyphs = canvas.glyphs
        lastColors = canvas.colors
        lastAlphas = canvas.alphas
        forceFullRedraw = false
        frameCount += 1
    }

    func render(into ctx: CGContext, size: CGSize, dirtyRect: CGRect) {
        drawCount += 1
        if view.bounds.width > 0 && view.bounds.height > 0 {
            lastDrawFraction = Double(dirtyRect.width * dirtyRect.height
                / (view.bounds.width * view.bounds.height))
        }
        renderer.draw(canvas: canvas, in: ctx, size: size,
                      background: scene.background, globalAlpha: view.fade,
                      dirtyRect: dirtyRect)
    }

    func teardown() {
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }

    // MARK: - Damage tracking

    /// Returns view-space rects for the tiles whose pixels changed since the last
    /// frame. Returns the full bounds when most of the screen changed.
    private func dirtyRects() -> [CGRect] {
        let cols = canvas.cols
        let rows = canvas.rows
        guard cols > 0, rows > 0,
              lastAlphas.count == canvas.alphas.count,
              lastGlyphs.count == canvas.glyphs.count,
              lastColors.count == canvas.colors.count else {
            return [view.bounds]
        }

        let tilesX = (cols + tileCols - 1) / tileCols
        let tilesY = (rows + tileRows - 1) / tileRows
        var dirty = [Bool](repeating: false, count: tilesX * tilesY)
        var dirtyCount = 0

        for ty in 0..<tilesY {
            let row0 = ty * tileRows
            let row1 = min(rows, row0 + tileRows)
            for tx in 0..<tilesX {
                let col0 = tx * tileCols
                let col1 = min(cols, col0 + tileCols)
                var changed = false
                rowsLoop: for r in row0..<row1 {
                    let base = r * cols
                    for c in col0..<col1 {
                        let i = base + c
                        let alpha = canvas.alphas[i]
                        if alpha != lastAlphas[i] {
                            changed = true
                            break rowsLoop
                        }
                        if alpha != 0 && (canvas.glyphs[i] != lastGlyphs[i]
                                            || canvas.colors[i] != lastColors[i]) {
                            changed = true
                            break rowsLoop
                        }
                    }
                }
                if changed {
                    dirty[ty * tilesX + tx] = true
                    dirtyCount += 1
                }
            }
        }

        if dirtyCount == 0 { return [] }
        if dirtyCount * 10 > tilesX * tilesY * 6 { return [view.bounds] }

        var rects: [CGRect] = []
        let cellW = metrics.cellWidth
        let cellH = metrics.cellHeight
        let height = view.bounds.height

        for ty in 0..<tilesY {
            var tx = 0
            while tx < tilesX {
                if !dirty[ty * tilesX + tx] {
                    tx += 1
                    continue
                }
                let start = tx
                while tx < tilesX && dirty[ty * tilesX + tx] {
                    tx += 1
                }
                let end = tx - 1

                let col0 = start * tileCols
                let col1 = min(cols, (end + 1) * tileCols)
                let row0 = ty * tileRows
                let row1 = min(rows, (ty + 1) * tileRows)
                let rect = CGRect(x: CGFloat(col0) * cellW,
                                  y: height - CGFloat(row1) * cellH,
                                  width: CGFloat(col1 - col0) * cellW,
                                  height: CGFloat(row1 - row0) * cellH)
                if rect.width > 0 && rect.height > 0 {
                    rects.append(rect)
                }
            }
        }
        return rects
    }
}
