import AppKit

// MARK: - Color Helpers

func cpuColor(_ cpu: Double) -> NSColor {
    switch cpu {
    case 0..<20:
        return .systemGreen
    case 20..<40:
        return .systemYellow
    case 40..<85:
        return .systemOrange
    default:
        return .systemRed
    }
}

func ramPressureColor(_ pressure: Double) -> NSColor {
    switch pressure {
    case 0..<65:
        return .systemGreen
    case 65..<80:
        return .systemYellow
    case 80..<90:
        return .systemOrange
    default:
        return .systemRed
    }
}

func diskFreeColor(freePercent: Double) -> NSColor {
    switch freePercent {
    case 0..<30:
        return .systemGreen
    case 30..<60:
        return .systemYellow
    case 60..<80:
        return .systemOrange
    default:
        return .systemRed
    }
}
