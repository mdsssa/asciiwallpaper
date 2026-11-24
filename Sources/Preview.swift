import Foundation
import CoreGraphics
import ImageIO

enum PreviewError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let m): return m
        }
    }
}

enum PreviewTool {
    /// Отрисовывает один кадр сцены в PNG (после симуляции `seconds` секунд).
    static func render(sceneKind: SceneKind,
                       seconds: Double,
                       cols: Int,
                       rows: Int,
                       fontSize: CGFloat,
                       scale: CGFloat,
                       path: String) throws {
        let metrics = FontMetrics(pointSize: fontSize)
        let renderer = AsciiRenderer(metrics: metrics)
        let canvas = Canvas()
        canvas.resize(cols: cols, rows: rows)

        let scene = sceneKind.make()
        scene.resize(cols: cols, rows: rows, cellAspect: metrics.cellAspect)

        let dt = 1.0 / 60.0
        var t = 0.0
        while t < seconds {
            canvas.clear()
            scene.update(time: t, dt: dt, canvas: canvas)
            t += dt
        }
        canvas.clear()
        scene.update(time: seconds, dt: dt, canvas: canvas)

        let pointSize = CGSize(width: CGFloat(cols) * metrics.cellWidth,
                               height: CGFloat(rows) * metrics.cellHeight)
        let pixelWidth = Int((pointSize.width * scale).rounded())
        let pixelHeight = Int((pointSize.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw PreviewError.message("пустой размер кадра")
        }
        guard let ctx = CGContext(data: nil,
                                  width: pixelWidth,
                                  height: pixelHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: RGB.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PreviewError.message("не удалось создать CGContext")
        }
        ctx.scaleBy(x: scale, y: scale)
        renderer.draw(canvas: canvas, in: ctx, size: pointSize, background: scene.background)

        guard let image = ctx.makeImage() else {
            throw PreviewError.message("не удалось получить CGImage")
        }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw PreviewError.message("не удалось создать PNG по пути \(path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw PreviewError.message("не удалось записать PNG \(path)")
        }
        print("PNG: \(path) (\(pixelWidth)x\(pixelHeight), сцена «\(sceneKind.title)», t=\(String(format: "%.1f", seconds))с)")
    }

    /// Замер скорости обновления сцены и отрисовки кадра.
    static func benchmark(fontSize: CGFloat, cols: Int, rows: Int, frames: Int) {
        let metrics = FontMetrics(pointSize: fontSize)
        let renderer = AsciiRenderer(metrics: metrics)
        let canvas = Canvas()
        canvas.resize(cols: cols, rows: rows)
        let pointSize = CGSize(width: CGFloat(cols) * metrics.cellWidth,
                               height: CGFloat(rows) * metrics.cellHeight)
        let scale: CGFloat = 2
        let pixelWidth = Int(pointSize.width * scale)
        let pixelHeight = Int(pointSize.height * scale)

        print("Сетка: \(cols)x\(rows) клеток @ \(metrics.pointSize)pt, кадр \(pixelWidth)x\(pixelHeight) px")
        print(String(format: "%-10@ %10@ %10@ %10@", "сцена" as NSString, "update" as NSString, "draw" as NSString, "итого" as NSString))
        print(String(repeating: "-", count: 46))

        for kind in SceneKind.allCases {
            let scene = kind.make()
            scene.resize(cols: cols, rows: rows, cellAspect: metrics.cellAspect)
            canvas.clear()
            scene.update(time: 0, dt: 1.0 / 60.0, canvas: canvas)

            guard let ctx = CGContext(data: nil,
                                      width: pixelWidth,
                                      height: pixelHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: RGB.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                print("не удалось создать CGContext")
                return
            }
            ctx.scaleBy(x: scale, y: scale)

            var updateTotal = 0.0
            var drawTotal = 0.0
            var worst = 0.0
            for f in 0..<frames {
                let t0 = CFAbsoluteTimeGetCurrent()
                canvas.clear()
                scene.update(time: Double(f) / 30.0, dt: 1.0 / 30.0, canvas: canvas)
                let t1 = CFAbsoluteTimeGetCurrent()
                renderer.draw(canvas: canvas, in: ctx, size: pointSize, background: scene.background)
                let t2 = CFAbsoluteTimeGetCurrent()
                updateTotal += t1 - t0
                drawTotal += t2 - t1
                worst = max(worst, t2 - t0)
            }
            let n = Double(max(1, frames))
            let updateMs = updateTotal / n * 1000
            let drawMs = drawTotal / n * 1000
            let totalMs = updateMs + drawMs
            print(String(format: "%-10@ %8.2f мс %8.2f мс %8.2f мс   (худший %.2f мс)",
                         kind.rawValue as NSString, updateMs, drawMs, totalMs, worst * 1000))
        }
    }
}
