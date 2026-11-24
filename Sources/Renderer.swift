import AppKit
import CoreText

/// Draws a Canvas into a CGContext, grouping glyphs by (colour, alpha) so a frame
/// costs a few hundred CoreText calls instead of tens of thousands.
final class AsciiRenderer {
    let metrics: FontMetrics
    var mono: Monochrome = .off {
        didSet {
            if mono != oldValue { monoCache.removeAll(keepingCapacity: true) }
        }
    }
    private var monoCache: [UInt32: UInt32] = [:]

    private var glyphCache = [CGGlyph](repeating: 0, count: 65536)
    private var glyphCached = [Bool](repeating: false, count: 65536)

    private var runIndex: [UInt32: Int] = [:]
    private var runGlyphs: [[CGGlyph]] = []
    private var runPoints: [[CGPoint]] = []
    private var runColors: [RGB] = []
    private var runAlphas: [UInt8] = []
    private var runCount = 0

    init(metrics: FontMetrics) {
        self.metrics = metrics
        for code in 32...126 {
            _ = glyph(for: UInt16(code))
        }
    }

    func glyph(for code: UInt16) -> CGGlyph {
        let index = Int(code)
        if glyphCached[index] { return glyphCache[index] }
        var ch = code
        var g: CGGlyph = 0
        if CTFontGetGlyphsForCharacters(metrics.font, &ch, &g, 1) {
            glyphCache[index] = g
        } else {
            glyphCache[index] = 0
        }
        glyphCached[index] = true
        return glyphCache[index]
    }

    private func displayColor(_ packed: UInt32) -> UInt32 {
        if mono == .off { return packed }
        if let cached = monoCache[packed] { return cached }
        let out = mono.apply(to: RGB(hex: packed)).packed
        monoCache[packed] = out
        return out
    }

    private func resetRuns() {
        for i in 0..<runGlyphs.count {
            runGlyphs[i].removeAll(keepingCapacity: true)
            runPoints[i].removeAll(keepingCapacity: true)
        }
        runIndex.removeAll(keepingCapacity: true)
        runCount = 0
    }

    func draw(canvas: Canvas, in ctx: CGContext, size: CGSize,
              background: RGB, globalAlpha: Double = 1,
              dirtyRect: CGRect? = nil) {
        let ga = max(0, min(1, globalAlpha))

        var clipRect = CGRect(origin: .zero, size: size)
        if let dirtyRect {
            clipRect = dirtyRect.intersection(clipRect)
            if clipRect.isNull || clipRect.isEmpty { return }
        }

        ctx.saveGState()
        ctx.clip(to: clipRect)
        ctx.setFillColor(mono.apply(to: background).cgColor)
        ctx.fill(clipRect)
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.textMatrix = .identity

        resetRuns()

        let cols = canvas.cols
        let rows = canvas.rows
        guard cols > 0, rows > 0, size.width > 0, size.height > 0 else {
            ctx.restoreGState()
            return
        }

        let cw = metrics.cellWidth
        let ch = metrics.cellHeight
        let baselineOffset = metrics.descent + max(0, (ch - metrics.ascent - metrics.descent) * 0.5)
        let height = size.height

        let firstRow = max(0, Int(floor((height - clipRect.maxY) / ch)))
        let lastRow = min(rows - 1, Int(ceil((height - clipRect.minY) / ch)) - 1)
        let firstCol = max(0, Int(floor(clipRect.minX / cw)))
        let lastCol = min(cols - 1, Int(ceil(clipRect.maxX / cw)) - 1)
        guard firstRow <= lastRow, firstCol <= lastCol else {
            ctx.restoreGState()
            return
        }

        canvas.alphas.withUnsafeBufferPointer { alphaBuf in
            canvas.glyphs.withUnsafeBufferPointer { glyphBuf in
                canvas.colors.withUnsafeBufferPointer { colorBuf in
                    for r in firstRow...lastRow {
                        let y = height - CGFloat(r + 1) * ch + baselineOffset
                        let rowBase = r * cols
                        for c in firstCol...lastCol {
                            let i = rowBase + c
                            let a = alphaBuf[i]
                            if a == 0 { continue }
                            let g = glyph(for: glyphBuf[i])
                            if g == 0 { continue }
                            let rgb = displayColor(colorBuf[i])
                            let r5 = Int((rgb >> 19) & 0x1F)
                            let g5 = Int((rgb >> 11) & 0x1F)
                            let b5 = Int((rgb >> 3) & 0x1F)
                            let aLevel = Int((Int(a) * 15 + 128) / 255)
                            if aLevel == 0 { continue }
                            let key = UInt32((r5 << 15) | (g5 << 10) | (b5 << 5) | aLevel)
                            let point = CGPoint(x: CGFloat(c) * cw, y: y)

                            if let slot = runIndex[key] {
                                runGlyphs[slot].append(g)
                                runPoints[slot].append(point)
                            } else {
                                let slot = runCount
                                runIndex[key] = slot
                                if slot == runGlyphs.count {
                                    runGlyphs.append([g])
                                    runPoints.append([point])
                                    runColors.append(RGB(r: UInt8(r5 << 3 | r5 >> 2),
                                                         g: UInt8(g5 << 3 | g5 >> 2),
                                                         b: UInt8(b5 << 3 | b5 >> 2)))
                                    runAlphas.append(UInt8(aLevel))
                                } else {
                                    runGlyphs[slot].append(g)
                                    runPoints[slot].append(point)
                                    runColors[slot] = RGB(r: UInt8(r5 << 3 | r5 >> 2),
                                                          g: UInt8(g5 << 3 | g5 >> 2),
                                                          b: UInt8(b5 << 3 | b5 >> 2))
                                    runAlphas[slot] = UInt8(aLevel)
                                }
                                runCount += 1
                            }
                        }
                    }
                }
            }
        }

        for slot in 0..<runCount {
            let color = runColors[slot]
            let alpha = Double(runAlphas[slot]) / 15.0 * ga
            if alpha <= 0 { continue }
            ctx.setFillColor(CGColor(colorSpace: RGB.sRGB,
                                     components: [CGFloat(color.r) / 255,
                                                  CGFloat(color.g) / 255,
                                                  CGFloat(color.b) / 255,
                                                  CGFloat(alpha)])!)
            runGlyphs[slot].withUnsafeBufferPointer { gp in
                guard let gBase = gp.baseAddress else { return }
                runPoints[slot].withUnsafeBufferPointer { pp in
                    guard let pBase = pp.baseAddress else { return }
                    CTFontDrawGlyphs(metrics.font, gBase, pBase, gp.count, ctx)
                }
            }
        }

        ctx.restoreGState()
    }
}
