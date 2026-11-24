import Foundation
import CoreGraphics

struct Options {
    var scene: SceneKind?
    var fps: Double = 24
    var fontSize: CGFloat = 13
    var cycle: Double = 75
    var showMenu = true

    var renderPath: String?
    var renderTime: Double = 6
    var cols: Int = 190
    var rows: Int?
    var scale: CGFloat = 2

    var quit = false
    var list = false
    var benchmark = false
    var help = false
}

let usageText = """
ASCII Wallpaper — live ASCII wallpapers for macOS.

Usage:
  asciiwallpaper [options]

Options:
  --scene <name>     scene: matrix | donut | plasma | fire | stars | hypercube
  --fps <number>     frames per second (default: 24)
  --font-size <pt>   character grid font size (default: 13)
  --cycle <seconds>  auto-cycle scenes, 0 disables it (default: 75)
  --no-menu          hide the menu bar icon
  --quit             stop the running wallpaper
  --list             list scenes
  --help             show this help

Debug and previews:
  --render <file.png>  save a scene frame to PNG
  --time <seconds>     seconds to simulate before the frame (default: 6)
  --cols <number>      grid width for --render (default: 190)
  --rows <number>      grid height (default: 16:9)
  --scale <number>     PNG scale (default: 2, Retina)
  --benchmark          measure scene update and draw time

Examples:
  asciiwallpaper --scene fire
  asciiwallpaper --render preview.png --scene donut --time 4
  asciiwallpaper --benchmark
"""
