import AppKit

class RamPressureView: NSView {

    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    private let padding: CGFloat = 6
    private let maxVal: Double = 100

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 40)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard values.count > 1 else { return }

        let usableWidth = bounds.width - padding * 2
        let usableHeight = bounds.height - padding * 2
        let stepX = usableWidth / CGFloat(values.count - 1)

        for i in 1..<values.count {
            let prevValue = min(max(values[i - 1], 0), maxVal)
            let currValue = min(max(values[i], 0), maxVal)

            let x1 = padding + CGFloat(i - 1) * stepX
            let x2 = padding + CGFloat(i) * stepX

            let y1 = padding + CGFloat(prevValue / maxVal) * usableHeight
            let y2 = padding + CGFloat(currValue / maxVal) * usableHeight

            let color = ramPressureColor(currValue)

            // Fill
            let fillPath = NSBezierPath()
            fillPath.move(to: CGPoint(x: x1, y: padding))
            fillPath.line(to: CGPoint(x: x1, y: y1))
            fillPath.line(to: CGPoint(x: x2, y: y2))
            fillPath.line(to: CGPoint(x: x2, y: padding))
            fillPath.close()

            color.withAlphaComponent(0.25).setFill()
            fillPath.fill()

            // Line
            let linePath = NSBezierPath()
            linePath.move(to: CGPoint(x: x1, y: y1))
            linePath.line(to: CGPoint(x: x2, y: y2))
            linePath.lineWidth = 2
            linePath.lineCapStyle = .round

            color.setStroke()
            linePath.stroke()
        }
    }
}
