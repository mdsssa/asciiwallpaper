import AppKit
import CoreText

/// Метрики моноширинного шрифта: размер «клетки» ASCII-сетки.
struct FontMetrics {
    let font: CTFont
    let fontName: String
    let pointSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let cellAspect: Double

    init(pointSize: CGFloat = 13) {
        let size = max(6, min(120, pointSize))
        let base = NSFont(name: "Menlo-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let ct = CTFontCreateWithName(base.fontName as CFString, size, nil)

        self.font = ct
        self.fontName = CTFontCopyPostScriptName(ct) as String
        self.pointSize = size

        let asc = CTFontGetAscent(ct)
        let desc = CTFontGetDescent(ct)
        let lead = CTFontGetLeading(ct)
        self.ascent = asc
        self.descent = desc
        self.cellHeight = max(1, ceil(asc + desc + lead))
        self.cellWidth = max(1, FontMetrics.advanceWidth(font: ct, character: "M"))
        self.cellAspect = Double(self.cellHeight / self.cellWidth)
    }

    static func advanceWidth(font: CTFont, character: Character) -> CGFloat {
        let utf16 = Array(String(character).utf16)
        guard !utf16.isEmpty else { return 0 }
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let ok = utf16.withUnsafeBufferPointer { chars -> Bool in
            glyphs.withUnsafeMutableBufferPointer { g -> Bool in
                CTFontGetGlyphsForCharacters(font, chars.baseAddress!, g.baseAddress!, chars.count)
            }
        }
        guard ok else { return 0 }
        var advance = CGSize.zero
        _ = glyphs.withUnsafeBufferPointer { g in
            CTFontGetAdvancesForGlyphs(font, .horizontal, g.baseAddress!, &advance, 1)
        }
        return advance.width
    }
}
