import AppKit

class NetworkHistoryView: NSView {

    var downValues: [Double] = []
    var upValues: [Double] = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !downValues.isEmpty else { return }

        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.clear(bounds)

        let barWidth: CGFloat = 3
        let spacing: CGFloat = 1
        let maxBars = Int(bounds.width / (barWidth + spacing))

        let downs = Array(downValues.suffix(maxBars))
        let ups   = Array(upValues.suffix(maxBars))

        let maxVal = max(downs.max() ?? 1, ups.max() ?? 1)

        var x: CGFloat = bounds.width - CGFloat(downs.count) * (barWidth + spacing)

        for i in 0..<downs.count {
            let downHeight = CGFloat(downs[i] / maxVal) * bounds.height
            let upHeight   = CGFloat(ups[i] / maxVal) * bounds.height

            NSColor.systemGreen.setFill()
            NSRect(x: x, y: 0, width: barWidth, height: downHeight).fill()

            NSColor.systemBlue.setFill()
            NSRect(
                x: x,
                y: bounds.height - upHeight,
                width: barWidth,
                height: upHeight
            ).fill()

            x += barWidth + spacing
        }
    }
}
