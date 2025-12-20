import AppKit

class MenuStatRowView: NSView {

    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")

    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init(labelText: String, valueText: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 24))

        wantsLayer = true

        label.stringValue = labelText
        value.stringValue = valueText

        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        label.textColor = .secondaryLabelColor
        value.textColor = .white

        label.frame = NSRect(x: 8, y: 4, width: 120, height: 16)
        value.frame = NSRect(x: 130, y: 4, width: 100, height: 16)

        addSubview(label)
        addSubview(value)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func updateTrackingAreas() {
        if let area = trackingArea {
            removeTrackingArea(area)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            let highlightColor: NSColor

            if #available(macOS 10.14, *) {
                highlightColor = NSColor.controlAccentColor.withAlphaComponent(0.18)
            } else {
                highlightColor = NSColor.selectedMenuItemColor.withAlphaComponent(0.18)
            }

            highlightColor.setFill()
            dirtyRect.fill()
        }
    }


    func update(valueText: String) {
        value.stringValue = valueText
    }

    func setValueColor(_ color: NSColor) {
        value.textColor = color
    }
}
