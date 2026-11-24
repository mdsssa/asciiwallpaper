import Foundation

/// Monochrome colouring for every scene. `.off` keeps the original palette;
/// the other cases map each colour's luminance onto a single tint.
enum Monochrome: String, CaseIterable {
    case off
    case white
    case amber
    case green
    case ice

    var title: String {
        switch self {
        case .off: return "Off"
        case .white: return "White"
        case .amber: return "Amber"
        case .green: return "Green"
        case .ice: return "Ice"
        }
    }

    var tint: RGB? {
        switch self {
        case .off: return nil
        case .white: return RGB(255, 255, 255)
        case .amber: return RGB(255, 186, 110)
        case .green: return RGB(120, 255, 165)
        case .ice: return RGB(150, 215, 255)
        }
    }

    /// Maps a colour to the tint at the colour's relative luminance.
    func apply(to color: RGB) -> RGB {
        guard let tint else { return color }
        let luminance = 0.2126 * Double(color.r)
            + 0.7152 * Double(color.g)
            + 0.0722 * Double(color.b)
        let k = pow(luminance / 255.0, 0.9)
        return RGB(UInt8((Double(tint.r) * k).rounded()),
                   UInt8((Double(tint.g) * k).rounded()),
                   UInt8((Double(tint.b) * k).rounded()))
    }

    static var saved: Monochrome {
        get {
            UserDefaults.standard.string(forKey: "mono")
                .flatMap(Monochrome.init(rawValue:)) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mono") }
    }
}
