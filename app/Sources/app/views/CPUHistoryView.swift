import AppKit

class CPUHistoryView: NSView {

    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    // MARK: - Constants
    private let padding: CGFloat = 6
    private let maxVal: Double = 100

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 60)
    }

    // MARK: - CPU Color Helper
    private func cpuColor(_ value: Double) -> NSColor {
        switch value {
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

override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard values.count > 1 else { return }

    let usableWidth = bounds.width - padding * 2
    let usableHeight = bounds.height - padding * 2
    let stepX = usableWidth / CGFloat(values.count - 1)
    
    for i in 1..<values.count {
        let prevValue = min(max(values[i - 1], 0), 100)
        let currValue = min(max(values[i], 0), 100)

        let x1 = padding + CGFloat(i - 1) * stepX
        let x2 = padding + CGFloat(i) * stepX

        let y1 = padding + CGFloat(prevValue / 100) * usableHeight
        let y2 = padding + CGFloat(currValue / 100) * usableHeight
        
        let segmentColor = cpuColor(currValue)

        // Draw Fill
        let fillPath = NSBezierPath()
        fillPath.move(to: CGPoint(x: x1, y: padding))
        fillPath.line(to: CGPoint(x: x1, y: y1))
        fillPath.line(to: CGPoint(x: x2, y: y2))
        fillPath.line(to: CGPoint(x: x2, y: padding))
        fillPath.close()
        
        segmentColor.withAlphaComponent(0.22).setFill()
        fillPath.fill()

        // Draw Line
        let linePath = NSBezierPath()
        linePath.move(to: CGPoint(x: x1, y: y1))
        linePath.line(to: CGPoint(x: x2, y: y2))
        linePath.lineWidth = 2
        linePath.lineCapStyle = .round
        
        segmentColor.setStroke()
        linePath.stroke()
    }
}
}
