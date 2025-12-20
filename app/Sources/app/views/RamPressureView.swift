import AppKit

class RamPressureView: NSView {

    var values: [Double] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard values.count > 1 else { return }

        let path = NSBezierPath()
        let width = bounds.width
        let height = bounds.height
        let stepX = width / CGFloat(values.count - 1)

        let maxVal: Double = 100

        for (i, value) in values.enumerated() {
            let x = CGFloat(i) * stepX
            let y = CGFloat(value / maxVal) * height

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.line(to: CGPoint(x: x, y: y))
            }
        }

        // Color based on current RAM %
        let current = values.last ?? 0
        let color: NSColor

        switch current {
        case 0..<60:
            color = .systemGreen
        case 60..<80:
            color = .systemYellow
        default:
            color = .systemRed
        }

        color.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
