import AppKit

class CPUHistoryView: NSView {

    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    // MARK: - Constants
    private let graphWidth: CGFloat = 280
    private let graphHeight: CGFloat = 60
    private let padding: CGFloat = 6
    private let maxVal: Double = 100

    override var intrinsicContentSize: NSSize {
        NSSize(width: graphWidth, height: graphHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard values.count > 1 else { return }

        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        let usableWidth = bounds.width - padding * 2
        let usableHeight = bounds.height - padding * 2
        let stepX = usableWidth / CGFloat(values.count - 1)

        for (i, value) in values.enumerated() {
            let x = padding + CGFloat(i) * stepX
            let normalized = min(max(value / maxVal, 0), 1)
            let y = padding + CGFloat(normalized) * usableHeight

            let point = CGPoint(x: x, y: y)

            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        NSColor.systemGreen.setStroke()
        path.stroke()
    }
}
