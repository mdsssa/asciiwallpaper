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
ASCII Wallpaper — живые ASCII-обои для macOS.

Использование:
  asciiwallpaper [опции]

Опции:
  --scene <имя>      сцена: matrix | donut | plasma | fire | stars | hypercube
  --fps <число>      кадров в секунду (по умолчанию 24)
  --font-size <pt>   размер шрифта сетки (по умолчанию 13)
  --cycle <сек>      автосмена сцен, 0 — выключить (по умолчанию 75)
  --no-menu          не показывать иконку в строке меню
  --quit             остановить уже запущенные обои
  --list             список сцен
  --help             эта справка

Отладка и превью:
  --render <файл.png>  сохранить кадр сцены в PNG
  --time <сек>         сколько секунд симулировать перед кадром (по умолчанию 6)
  --cols <число>       ширина сетки для --render (по умолчанию 190)
  --rows <число>       высота сетки (по умолчанию — 16:9)
  --scale <число>      масштаб PNG (по умолчанию 2, Retina)
  --benchmark          замер скорости сцен

Примеры:
  asciiwallpaper --scene fire
  asciiwallpaper --render preview.png --scene donut --time 4
  asciiwallpaper --benchmark
"""
