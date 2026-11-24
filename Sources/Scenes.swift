import Foundation
import CoreGraphics

protocol Scene: AnyObject {
    var title: String { get }
    var background: RGB { get }
    func resize(cols: Int, rows: Int, cellAspect: Double)
    func update(time: Double, dt: Double, canvas: Canvas)
}

enum SceneKind: String, CaseIterable {
    case matrix
    case donut
    case plasma
    case fire
    case stars
    case hypercube

    var title: String {
        switch self {
        case .matrix: return "Матрица"
        case .donut: return "Пончик"
        case .plasma: return "Плазма"
        case .fire: return "Огонь"
        case .stars: return "Звёзды"
        case .hypercube: return "Гиперкуб"
        }
    }

    func make() -> Scene {
        switch self {
        case .matrix: return MatrixScene()
        case .donut: return DonutScene()
        case .plasma: return PlasmaScene()
        case .fire: return FireScene()
        case .stars: return StarsScene()
        case .hypercube: return HypercubeScene()
        }
    }

    static var saved: SceneKind? {
        get { UserDefaults.standard.string(forKey: "scene").flatMap(SceneKind.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: "scene") }
    }
}

// MARK: - Матрица

final class MatrixScene: Scene {
    let title = "Матрица"
    let background = RGB(hex: 0x030806)

    private var cols = 0
    private var rows = 0
    private var heat: [Float] = []
    private var glyphs: [UInt16] = []
    private var headY: [Float] = []
    private var speed: [Float] = []
    private var wait: [Float] = []
    private var gain: [Float] = []

    private let symbols: [UInt16] = Array(
        #"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz<>/\|=+-*:."#.utf16
    )
    private let bodyColor = RGB(hex: 0x33ff96)
    private let headColor = RGB(hex: 0xeafff4)

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
        let n = cols * rows
        heat = [Float](repeating: 0, count: n)
        glyphs = [UInt16](repeating: 32, count: n)
        headY = (0..<cols).map { _ in Float.random(in: -Float(rows) * 2 ... Float(rows)) }
        speed = (0..<cols).map { _ in Float.random(in: 10 ... 26) }
        wait = [Float](repeating: 0, count: cols)
        gain = (0..<cols).map { _ in Float.random(in: 0.6 ... 1.0) }
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 0, rows > 0 else { return }
        let fdt = Float(min(dt, 0.1))
        let decay = Float(exp(-dt * 4.0))
        for i in 0..<heat.count {
            heat[i] *= decay
        }

        for c in 0..<cols {
            if wait[c] > 0 {
                wait[c] -= fdt
                continue
            }
            headY[c] += speed[c] * fdt
            let row = Int(headY[c])
            if row >= 0 && row < rows {
                let i = row * cols + c
                heat[i] = 1
                glyphs[i] = symbols[Int.random(in: 0..<symbols.count)]
            }
            if headY[c] > Float(rows) + 3 {
                headY[c] = -Float.random(in: 0 ... 30)
                speed[c] = Float.random(in: 10 ... 26)
                wait[c] = Float.random(in: 0.5 ... 4.0)
            }
        }

        let flickers = max(1, heat.count / 500)
        for _ in 0..<flickers {
            let i = Int.random(in: 0..<heat.count)
            if heat[i] > 0.2 {
                glyphs[i] = symbols[Int.random(in: 0..<symbols.count)]
            }
        }

        for i in 0..<heat.count {
            let v = heat[i]
            if v > 0.045 {
                let c = i % cols
                let isHead = v > 0.62
                canvas.put(i, glyphs[i], isHead ? headColor : bodyColor,
                           min(1, Double(v) * 1.1 * Double(gain[c])))
            }
        }
    }
}

// MARK: - Пончик

final class DonutScene: Scene {
    let title = "Пончик"
    let background = RGB(hex: 0x04060d)

    private var cols = 0
    private var rows = 0
    private var aspect = 1.9
    private var zbuf: [Float] = []
    private var shade: [Int16] = []

    private let ramp = ASCII_RAMP_SOFT
    private let palette: [RGB] = (0 ... 14).map { i in
        let t = Double(i) / 14.0
        if t < 0.45 {
            return RGB.lerp(RGB(hex: 0x0b1f4a), RGB(hex: 0x2f8fe6), t / 0.45)
        }
        return RGB.lerp(RGB(hex: 0x2f8fe6), RGB(hex: 0xe8fbff), (t - 0.45) / 0.55)
    }

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
        self.aspect = max(1.0, cellAspect)
        zbuf = [Float](repeating: 0, count: cols * rows)
        shade = [Int16](repeating: -1, count: cols * rows)
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 0, rows > 0 else { return }
        for i in 0..<zbuf.count {
            zbuf[i] = -1
            shade[i] = -1
        }

        let A = 0.16 + 0.05 * sin(time * 0.30)
        let B = 0.30 * sin(time * 0.45)
        let C = time * 0.55
        let sinA = sin(A), cosA = cos(A)
        let sinB = sin(B), cosB = cos(B)
        let sinC = sin(C), cosC = cos(C)
        let cx = Double(cols) * 0.5
        let cy = Double(rows) * 0.5
        let radiusTarget = min(Double(cols) * 0.23, Double(rows) * aspect * 0.39)
        let S = radiusTarget / 3.05
        let twoPi = Double.pi * 2

        let lx = 0.34, ly = 0.56, lz = 0.76
        let R1 = 0.92, R2 = 2.12

        var theta = 0.0
        while theta < twoPi {
            let ct = cos(theta)
            let st = sin(theta)
            let ringRadius = R2 + R1 * ct
            var phi = 0.0
            while phi < twoPi {
                let cp = cos(phi)
                let sp = sin(phi)

                let px = ringRadius * cp
                let py = ringRadius * sp
                let pz = R1 * st

                let nx = ct * cp
                let ny = ct * sp
                let nz = st

                // поворот в плоскости экрана
                let rx = px * cosC - py * sinC
                let ry = px * sinC + py * cosC
                let rnx = nx * cosC - ny * sinC
                let rny = nx * sinC + ny * cosC

                // наклон вокруг X
                let ty = ry * cosA - pz * sinA
                let tz = ry * sinA + pz * cosA
                let tny = rny * cosA - nz * sinA
                let tnz = rny * sinA + nz * cosA

                // лёгкое покачивание вокруг Y
                let ux = rx * cosB + tz * sinB
                let uz = -rx * sinB + tz * cosB
                let unx = rnx * cosB + tnz * sinB
                let unz = -rnx * sinB + tnz * cosB

                let persp = 1.0 / (1.0 - uz * 0.06)
                let fx = cx + S * ux * persp
                let fy = cy - S * ty * persp / aspect
                let c = Int(fx)
                let r = Int(fy)
                if c >= 0 && c < cols && r >= 0 && r < rows {
                    let i = r * cols + c
                    let depth = Float(uz)
                    if depth > zbuf[i] {
                        zbuf[i] = depth
                        let diffuse = max(0, unx * lx + tny * ly + unz * lz)
                        let spec = pow(diffuse, 18.0) * 0.55
                        let value = 0.12 + 0.88 * diffuse + spec
                        shade[i] = Int16(max(0, min(14, Int(value * 14.0 + 0.5))))
                    }
                }
                phi += 0.016
            }
            theta += 0.05
        }

        for i in 0..<shade.count {
            let s = shade[i]
            if s < 2 { continue }
            let v = Double(s) / 14.0
            let ch = ramp[min(ramp.count - 1, Int(v * Double(ramp.count - 1) + 0.5))]
            canvas.put(i, ch, palette[Int(s)], 0.06 + 0.94 * pow(v, 1.25))
        }
    }
}

// MARK: - Плазма

final class PlasmaScene: Scene {
    let title = "Плазма"
    let background = RGB(hex: 0x060312)

    private var cols = 0
    private var rows = 0
    private let ramp = ASCII_RAMP_DENSE
    private let palette: [RGB] = (0..<14).map { i in
        RGB.hsv(0.49 + 0.47 * Double(i) / 13.0, 0.65, 1.0)
    }

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 0, rows > 0 else { return }
        let t = time
        let paletteMax = Double(palette.count - 1)

        for r in 0..<rows {
            let y = Double(r) / Double(rows) * 5.0
            for c in 0..<cols {
                let x = Double(c) / Double(cols) * 9.0
                var v = sin(x * 1.9 + t * 1.4)
                v += sin(y * 2.7 - t * 1.1)
                v += sin((x + y) * 1.3 + t * 0.9)
                let dx = x - 4.5
                let dy = y - 2.5
                v += sin((dx * dx + dy * dy).squareRoot() * 2.2 - t * 1.8)
                v = max(0, min(1, 0.5 + v / 3.2))
                let i = r * cols + c
                let vd = canvas.ditherValue(i, v, 0.05)
                let idx = min(palette.count - 1, Int(vd * paletteMax + 0.5))
                canvas.put(i, vd, ramp, palette[idx], 0.66 + 0.34 * v)
            }
        }
    }
}

// MARK: - Огонь

final class FireScene: Scene {
    let title = "Огонь"
    let background = RGB(hex: 0x050201)

    private var cols = 0
    private var rows = 0

    private var px: [Double] = []
    private var py: [Double] = []
    private var vx: [Double] = []
    private var vy: [Double] = []
    private var life: [Double] = []
    private var maxLife: [Double] = []
    private var seed: [Double] = []

    private let ramp = ASCII_RAMP_SOFT
    private let palette: [RGB] = (0..<14).map { i in
        let t = Double(i) / 13.0
        if t < 0.35 {
            return RGB.lerp(RGB(hex: 0x3a0500), RGB(hex: 0xd01c03), t / 0.35)
        } else if t < 0.72 {
            return RGB.lerp(RGB(hex: 0xd01c03), RGB(hex: 0xff9c1a), (t - 0.35) / 0.37)
        }
        return RGB.lerp(RGB(hex: 0xff9c1a), RGB(hex: 0xfff6d2), (t - 0.72) / 0.28)
    }

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
        let n = max(220, cols * rows / 18)
        px = (0..<n).map { _ in Double.random(in: 0.05 ... 0.95) }
        py = (0..<n).map { _ in Double.random(in: 0 ... 1) }
        vx = (0..<n).map { _ in Double.random(in: -0.03 ... 0.03) }
        vy = (0..<n).map { _ in Double.random(in: 0.16 ... 0.5) }
        maxLife = (0..<n).map { _ in Double.random(in: 1.1 ... 2.8) }
        life = (0..<n).map { _ in Double.random(in: 0 ... 1) }
        seed = (0..<n).map { _ in Double.random(in: 0 ... 100) }
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 1, rows > 2 else { return }
        let step = min(dt, 0.1)

        // тлеющие угли у нижней кромки
        let glowRows = min(5, rows)
        for k in 0..<glowRows {
            let r = rows - 1 - k
            let fall = 1.0 - Double(k) / Double(glowRows)
            let base = 0.5 * fall * fall
            for c in 0..<cols {
                let x = Double(c) / Double(cols)
                let core = 0.55 + 0.45 * exp(-pow((x - 0.5) / 0.22, 2.0))
                let flick = 0.75 + 0.25 * sin(x * 34 + time * 3.0 + Double(k))
                let i = r * cols + c
                let v = canvas.ditherValue(i, base * core * flick, 0.12)
                if v < 0.04 { continue }
                canvas.put(i, v, ramp, palette[5], min(1, 0.6 + 0.6 * v))
            }
        }

        let paletteMax = Double(palette.count - 1)
        for index in 0..<px.count {
            life[index] -= step
            py[index] += vy[index] * step
            px[index] += (vx[index] + sin(time * 1.4 + seed[index]) * 0.02) * step

            if life[index] <= 0 || py[index] > 1.02 || px[index] < 0.01 || px[index] > 0.99 {
                respawn(index)
            }

            let c = Int(px[index] * Double(cols))
            let r = Int((1.0 - py[index]) * Double(rows))
            if c < 0 || c >= cols || r < 0 || r >= rows { continue }

            let fade = max(0, min(1, life[index] / maxLife[index]))
            let heat = max(0, min(1, 1.0 - py[index]))
            let flicker = 0.8 + 0.2 * sin(time * 11 + seed[index] * 7)
            let bright = (0.4 + 0.7 * heat) * (0.45 + 0.55 * fade) * flicker
            let idx = min(palette.count - 1, Int(heat * paletteMax))
            let glyph: UInt16
            if bright > 0.72 { glyph = 35 }        // #
            else if bright > 0.5 { glyph = 42 }    // *
            else if bright > 0.28 { glyph = 43 }   // +
            else { glyph = 46 }                    // .
            let i = r * cols + c
            canvas.put(i, glyph, palette[idx], min(1, 0.4 + 0.7 * bright))

            // короткий след вниз
            if r + 1 < rows {
                canvas.put(i + cols, 46, palette[idx], min(1, 0.12 + 0.35 * bright))
            }
        }
    }

    private func respawn(_ index: Int) {
        let g = Double.random(in: -1 ... 1) + Double.random(in: -1 ... 1)
            + Double.random(in: -1 ... 1)
        px[index] = min(0.96, max(0.04, 0.5 + g * 0.12))
        py[index] = 0
        vx[index] = Double.random(in: -0.035 ... 0.035)
        vy[index] = Double.random(in: 0.16 ... 0.5)
        maxLife[index] = Double.random(in: 1.1 ... 2.8)
        life[index] = maxLife[index]
        seed[index] = Double.random(in: 0 ... 100)
    }
}

// MARK: - Звёзды

final class StarsScene: Scene {
    let title = "Звёзды"
    let background = RGB(hex: 0x01030a)

    private var cols = 0
    private var rows = 0
    private var aspect = 1.9
    private var xs: [Double] = []
    private var ys: [Double] = []
    private var zs: [Double] = []
    private var speeds: [Double] = []
    private var warm: [Bool] = []
    private var bright: [Double] = []

    private let glyphs: [UInt16] = Array("..+*".utf16)
    private let cool = RGB(hex: 0xd8f1ff)
    private let warmColor = RGB(hex: 0xffd9a0)

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
        self.aspect = max(1.0, cellAspect)
        let n = max(240, min(6000, cols * rows / 14))
        xs = (0..<n).map { _ in Double.random(in: -1 ... 1) }
        ys = (0..<n).map { _ in Double.random(in: -1 ... 1) }
        zs = (0..<n).map { _ in Double.random(in: 0.12 ... 2.4) }
        speeds = (0..<n).map { _ in Double.random(in: 0.8 ... 2.2) }
        warm = (0..<n).map { _ in Double.random(in: 0 ... 1) < 0.12 }
        bright = (0..<n).map { _ in Double.random(in: 0.55 ... 1.0) }
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 0, rows > 0, !xs.isEmpty else { return }
        let cx = Double(cols) * 0.5
        let cy = Double(rows) * 0.5
        let S = min(Double(cols) * 0.55, Double(rows) * aspect * 0.8)

        for i in 0..<xs.count {
            let prevZ = zs[i]
            zs[i] -= dt * speeds[i] * 0.75
            if zs[i] < 0.12 {
                zs[i] = 2.4
                xs[i] = Double.random(in: -1 ... 1)
                ys[i] = Double.random(in: -1 ... 1)
                continue
            }
            let z = zs[i]
            let depth = max(0, min(1, (2.5 - z) / 2.3))
            let glyph = glyphs[min(3, Int(depth * 4))]
            let color = warm[i] ? warmColor : cool
            let alpha = (0.35 + 0.65 * depth) * bright[i]

            let f = 1.0 / max(0.05, z)
            let px = cx + xs[i] * f * S
            let py = cy - ys[i] * f * S / aspect
            let c = Int(px)
            let r = Int(py)
            if c >= 0 && c < cols && r >= 0 && r < rows {
                canvas.put(r * cols + c, glyph, color, alpha)
            }

            let pf = 1.0 / max(0.05, prevZ)
            let tx = cx + xs[i] * pf * S
            let ty = cy - ys[i] * pf * S / aspect
            let tc = Int(tx)
            let tr = Int(ty)
            if tc >= 0 && tc < cols && tr >= 0 && tr < rows {
                canvas.put(tr * cols + tc, 46, color, alpha * 0.45)
            }
        }
    }
}

// MARK: - Гиперкуб

final class HypercubeScene: Scene {
    let title = "Гиперкуб"
    let background = RGB(hex: 0x03040a)

    private var cols = 0
    private var rows = 0
    private var aspect = 1.9
    private var zbuf: [Float] = []

    private let vertices: [(Double, Double, Double, Double)] = (0..<16).map { i in
        (i & 1 == 0 ? -1.0 : 1.0,
         i & 2 == 0 ? -1.0 : 1.0,
         i & 4 == 0 ? -1.0 : 1.0,
         i & 8 == 0 ? -1.0 : 1.0)
    }
    private let edges: [(Int, Int)] = {
        var result: [(Int, Int)] = []
        for i in 0..<16 {
            for bit in 0..<4 {
                let j = i ^ (1 << bit)
                if j > i { result.append((i, j)) }
            }
        }
        return result
    }()

    private let palette: [RGB] = (0..<12).map { i in
        RGB.lerp(RGB(hex: 0x5b7cff), RGB(hex: 0xffffff), Double(i) / 11.0)
    }

    func resize(cols: Int, rows: Int, cellAspect: Double) {
        self.cols = cols
        self.rows = rows
        self.aspect = max(1.0, cellAspect)
        zbuf = [Float](repeating: -1000, count: cols * rows)
    }

    func update(time: Double, dt: Double, canvas: Canvas) {
        guard cols > 0, rows > 1 else { return }
        for i in 0..<zbuf.count { zbuf[i] = -1000 }

        let a = time * 0.52
        let b = time * 0.31
        let c = time * 0.19
        let ca = cos(a), sa = sin(a)
        let cb = cos(b), sb = sin(b)
        let cc = cos(c), sc = sin(c)
        let cx = Double(cols) * 0.5
        let cy = Double(rows) * 0.5
        let S = min(Double(cols) * 0.62, Double(rows) * aspect * 0.75)

        var projected = [(Double, Double, Double)](repeating: (0, 0, 0), count: 16)
        for (index, v) in vertices.enumerated() {
            let x1 = v.0 * ca - v.1 * sa
            let y1 = v.0 * sa + v.1 * ca
            let z1 = v.2 * cb - v.3 * sb
            let w1 = v.2 * sb + v.3 * cb
            let x2 = x1 * cc - w1 * sc
            let w2 = x1 * sc + w1 * cc

            let k = 2.9 / (3.2 - w2)
            let X = x2 * k
            let Y = y1 * k
            let Z = z1 * k
            let cam = 5.0 - Z
            let scale = S / max(0.7, cam)
            projected[index] = (cx + X * scale, cy - Y * scale / aspect, Z)
        }

        var minZ = Double.greatestFiniteMagnitude
        var maxZ = -Double.greatestFiniteMagnitude
        for p in projected {
            minZ = min(minZ, p.2)
            maxZ = max(maxZ, p.2)
        }
        if maxZ - minZ < 0.001 { maxZ = minZ + 0.001 }

        for (i0, i1) in edges {
            let p0 = projected[i0]
            let p1 = projected[i1]
            drawLine(p0, p1, minZ: minZ, maxZ: maxZ, canvas: canvas)
        }

        for p in projected {
            let c0 = Int(p.0)
            let r0 = Int(p.1)
            if c0 >= 0 && c0 < cols && r0 >= 0 && r0 < rows {
                canvas.put(r0 * cols + c0, 79, RGB(hex: 0xe8ffff), 0.95)
            }
        }
    }

    private func drawLine(_ p0: (Double, Double, Double),
                          _ p1: (Double, Double, Double),
                          minZ: Double, maxZ: Double,
                          canvas: Canvas) {
        let dx = p1.0 - p0.0
        let dy = p1.1 - p0.1
        let steps = max(2, Int(max(abs(dx), abs(dy)) * 2.0))
        let adx = abs(dx)
        let ady = abs(dy)
        let glyph: UInt16
        if adx > ady * 2.2 {
            glyph = 45
        } else if ady > adx * 2.2 {
            glyph = 124
        } else if dx * dy > 0 {
            glyph = 92
        } else {
            glyph = 47
        }

        for step in 0...steps {
            let f = Double(step) / Double(steps)
            let x = p0.0 + dx * f
            let y = p0.1 + dy * f
            let z = p0.2 + (p1.2 - p0.2) * f
            let c = Int(x)
            let r = Int(y)
            if c < 0 || c >= cols || r < 0 || r >= rows { continue }
            let i = r * cols + c
            if Float(z) <= zbuf[i] { continue }
            zbuf[i] = Float(z)
            let depth = max(0, min(1, (z - minZ) / (maxZ - minZ)))
            let idx = min(palette.count - 1, Int(depth * Double(palette.count - 1)))
            canvas.put(i, glyph, palette[idx], 0.8 + 0.2 * depth)
        }
    }
}
