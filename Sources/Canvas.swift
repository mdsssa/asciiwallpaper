import Foundation
import CoreGraphics

/// Цвет в sRGB, упакованный для быстрой отрисовки.
struct RGB: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.r = UInt8((hex >> 16) & 0xFF)
        self.g = UInt8((hex >> 8) & 0xFF)
        self.b = UInt8(hex & 0xFF)
    }

    var packed: UInt32 {
        (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
    }

    var cgColor: CGColor {
        CGColor(colorSpace: RGB.sRGB,
                components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, 1])!
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func lerp(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let k = max(0, min(1, t))
        return RGB(UInt8((Double(a.r) + (Double(b.r) - Double(a.r)) * k).rounded()),
                   UInt8((Double(a.g) + (Double(b.g) - Double(a.g)) * k).rounded()),
                   UInt8((Double(a.b) + (Double(b.b) - Double(a.b)) * k).rounded()))
    }

    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let hue = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let i = Int(hue)
        let f = hue - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        let rr: Double
        let gg: Double
        let bb: Double
        switch i % 6 {
        case 0: rr = v; gg = t; bb = p
        case 1: rr = q; gg = v; bb = p
        case 2: rr = p; gg = v; bb = t
        case 3: rr = p; gg = q; bb = v
        case 4: rr = t; gg = p; bb = v
        default: rr = v; gg = p; bb = q
        }
        return RGB(UInt8((max(0, min(1, rr)) * 255).rounded()),
                   UInt8((max(0, min(1, gg)) * 255).rounded()),
                   UInt8((max(0, min(1, bb)) * 255).rounded()))
    }
}

let ASCII_RAMP_SOFT: [UInt16] = Array(" .:-=+*#%@".utf16)
let ASCII_RAMP_DENSE: [UInt16] = Array(" .'`^\",:;Il!i~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$".utf16)

/// Символьная сетка кадра: для каждой клетки — глиф, цвет и прозрачность.
final class Canvas {
    private(set) var cols = 0
    private(set) var rows = 0
    private(set) var glyphs = [UInt16]()
    private(set) var colors = [UInt32]()
    private(set) var alphas = [UInt8]()

    var count: Int { cols * rows }

    func resize(cols: Int, rows: Int) {
        let c = max(1, cols)
        let r = max(1, rows)
        guard c != self.cols || r != self.rows else { return }
        self.cols = c
        self.rows = r
        let n = c * r
        glyphs = [UInt16](repeating: 32, count: n)
        colors = [UInt32](repeating: 0, count: n)
        alphas = [UInt8](repeating: 0, count: n)
    }

    @inline(__always)
    func clear() {
        alphas.withUnsafeMutableBufferPointer { buf in
            if let base = buf.baseAddress {
                memset(base, 0, buf.count)
            }
        }
    }

    @inline(__always)
    func put(_ index: Int, _ glyph: UInt16, _ color: RGB, _ alpha: Double) {
        let a: UInt8
        if alpha <= 0 { return }
        else if alpha >= 1 { a = 255 }
        else { a = UInt8(alpha * 255) }
        if a == 0 { return }
        alphas[index] = a
        colors[index] = color.packed
        glyphs[index] = glyph
    }

    /// Детерминированный шум 0...1 для дизеринга клетки.
    @inline(__always)
    func ditherValue(_ index: Int, _ value: Double, _ amount: Double) -> Double {
        let h = Double((index &* 2654435761 &+ 12345) & 0xFFFF) / 65535.0
        var v = value + (h - 0.5) * amount
        if v < 0 { v = 0 }
        if v > 1 { v = 1 }
        return v
    }

    /// Кладёт символ из рампы по значению 0...1.
    /// dither добавляет детерминированный шум, чтобы плавные градиенты
    /// не превращались в длинные горизонтальные полосы одинаковых символов.
    @inline(__always)
    func put(_ index: Int, _ value: Double, _ ramp: [UInt16], _ color: RGB,
             _ alpha: Double = 1, dither: Double = 0) {
        guard value > 0.001 else { return }
        var v = value >= 1 ? 1 : value
        if dither > 0 {
            let h = Double((index &* 2654435761 &+ 12345) & 0xFFFF) / 65535.0
            v += (h - 0.5) * dither
            if v < 0 { v = 0 }
            if v > 1 { v = 1 }
        }
        let i = Int(v * Double(ramp.count - 1) + 0.5)
        put(index, ramp[min(ramp.count - 1, max(0, i))], color, alpha)
    }
}
