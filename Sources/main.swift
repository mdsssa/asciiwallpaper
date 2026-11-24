import AppKit
import Foundation

private var lockFileDescriptor: Int32 = -1

private func acquireSingleInstanceLock() -> Bool {
    let path = NSTemporaryDirectory() + "asciiwallpaper-\(getuid()).lock"
    let fd = open(path, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return true }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 {
        lockFileDescriptor = fd
        return true
    }
    close(fd)
    return false
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("asciiwallpaper: " + message + "\n").data(using: .utf8)!)
    exit(2)
}

private func parseOptions(_ args: [String]) -> Options {
    var options = Options()
    var i = 0
    while i < args.count {
        let arg = args[i]
        func value() -> String {
            guard i + 1 < args.count else { fail("missing value for \(arg)") }
            i += 1
            return args[i]
        }
        switch arg {
        case "--scene":
            let name = value()
            guard let kind = SceneKind(rawValue: name) else {
                fail("unknown scene \"\(name)\". Available: \(SceneKind.allCases.map { $0.rawValue }.joined(separator: ", "))")
            }
            options.scene = kind
        case "--fps":
            let raw = value()
            guard let fps = Double(raw), fps >= 1, fps <= 120 else { fail("--fps must be a number between 1 and 120") }
            options.fps = fps
        case "--font-size":
            let raw = value()
            guard let size = Double(raw), size >= 6, size <= 120 else { fail("--font-size must be a number between 6 and 120") }
            options.fontSize = CGFloat(size)
        case "--cycle":
            let raw = value()
            guard let cycle = Double(raw), cycle >= 0 else { fail("--cycle must be >= 0") }
            options.cycle = cycle
        case "--no-menu":
            options.showMenu = false
        case "--render":
            options.renderPath = value()
        case "--time":
            let raw = value()
            guard let time = Double(raw), time >= 0, time <= 600 else { fail("--time must be a number between 0 and 600") }
            options.renderTime = time
        case "--cols":
            let raw = value()
            guard let cols = Int(raw), cols >= 20, cols <= 600 else { fail("--cols must be a number between 20 and 600") }
            options.cols = cols
        case "--rows":
            let raw = value()
            guard let rows = Int(raw), rows >= 6, rows <= 400 else { fail("--rows must be a number between 6 and 400") }
            options.rows = rows
        case "--scale":
            let raw = value()
            guard let scale = Double(raw), scale >= 0.5, scale <= 8 else { fail("--scale must be a number between 0.5 and 8") }
            options.scale = CGFloat(scale)
        case "--benchmark":
            options.benchmark = true
        case "--list":
            options.list = true
        case "--quit":
            options.quit = true
        case "--version":
            print("ASCII Wallpaper 1.0")
            exit(0)
        case "--help", "-h":
            options.help = true
        default:
            fail("unknown option \"\(arg)\". See --help")
        }
        i += 1
    }
    return options
}

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))

if options.help {
    print(usageText)
    exit(0)
}

if options.list {
    for kind in SceneKind.allCases {
        print("\(kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)) \(kind.title)")
    }
    exit(0)
}

if options.benchmark {
    let metrics = FontMetrics(pointSize: options.fontSize)
    let rows = options.rows ?? max(10, Int((Double(options.cols) * 0.5625
        * Double(metrics.cellWidth / metrics.cellHeight)).rounded()))
    PreviewTool.benchmark(fontSize: options.fontSize, cols: options.cols, rows: rows, frames: 60)
    exit(0)
}

if let path = options.renderPath {
    let metrics = FontMetrics(pointSize: options.fontSize)
    let rows = options.rows ?? max(10, Int((Double(options.cols) * 0.5625
        * Double(metrics.cellWidth / metrics.cellHeight)).rounded()))
    do {
        try PreviewTool.render(sceneKind: options.scene ?? .matrix,
                               seconds: options.renderTime,
                               cols: options.cols,
                               rows: rows,
                               fontSize: options.fontSize,
                               scale: options.scale,
                               path: path)
    } catch {
        fail("\(error)")
    }
    exit(0)
}

if options.quit {
    DistributedNotificationCenter.default().postNotificationName(.asciiWallpaperQuit,
                                                                 object: nil,
                                                                 userInfo: nil,
                                                                 deliverImmediately: true)
    usleep(250_000)
    exit(0)
}

if !acquireSingleInstanceLock() {
    if let kind = options.scene {
        DistributedNotificationCenter.default().postNotificationName(.asciiWallpaperScene,
                                                                     object: kind.rawValue,
                                                                     userInfo: nil,
                                                                     deliverImmediately: true)
    }
    print("ASCII Wallpaper is already running — command sent to the active instance")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(options: options)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
