import AppKit

class MenuStatRowView: NSView {

    // MARK: - Views
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")

    // MARK: - Hover
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    // MARK: - Configuration
    private let rowWidth: CGFloat = 310
    private let padding: CGFloat = 8
    private let iconSize: CGFloat = 16
    private let labelWidth: CGFloat = 75
    private var isBold: Bool = false

    // MARK: - Size
    override var intrinsicContentSize: NSSize {
        NSSize(width: rowWidth, height: 28)
    }

    // MARK: - Init
    init(labelText: String, valueText: String, isBold: Bool = false) {
        let frame = NSRect(x: 0, y: 0, width: rowWidth, height: 28)
        super.init(frame: frame)
        
        self.isBold = isBold

        wantsLayer = true

        // Calculate valueX position
        let valueX = padding + labelWidth + 4
        
        // Label - positioned on the left with padding
        label.stringValue = labelText
        if isBold {
            label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        } else {
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        }
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: padding, y: 6, width: labelWidth, height: 16)
        addSubview(label)

        // Value - positioned after the label
        value.stringValue = valueText
        if isBold {
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        } else {
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        }
        value.textColor = .labelColor
        value.alignment = .right
        value.lineBreakMode = .byTruncatingTail
        
        // Initial value width (without icon)
        let valueWidthNoIcon = rowWidth - valueX - padding
        value.frame = NSRect(x: valueX, y: 6, width: valueWidthNoIcon, height: 16)
        addSubview(value)

        // Icon - positioned at the very end (right side with padding)
        iconView.frame = NSRect(x: rowWidth - iconSize - padding, y: 6, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Tracking
    override func updateTrackingAreas() {
        if let area = trackingArea {
            removeTrackingArea(area)
        }

        trackingArea = NSTrackingArea(
            rect: bounds.insetBy(dx: 2, dy: 2),
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

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 0), 
                                         xRadius: 10, yRadius: 10)
        
        if isHovered {
            let highlightColor = NSColor(white: 0.9, alpha: 0.10)  // Light grey-white
            highlightColor.setFill()
            backgroundPath.fill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.2).setFill()
            backgroundPath.fill()
        }
    }

    // MARK: - Public API
    func update(valueText: String) {
        value.stringValue = valueText
    }

    func setIcon(_ image: NSImage?) {
        iconView.image = image
        iconView.isHidden = (image == nil)
        
        // Calculate positions
        let valueX = padding + labelWidth + 4
        let valueWidthNoIcon = rowWidth - valueX - padding
        let valueWidthWithIcon = rowWidth - valueX - iconSize - 4 - padding
        
        if image == nil {
            value.frame = NSRect(x: valueX, y: 6, width: valueWidthNoIcon, height: 16)
            iconView.frame = NSRect(x: rowWidth - iconSize - padding, y: 6, width: iconSize, height: iconSize)
        } else {
            value.frame = NSRect(x: valueX, y: 6, width: valueWidthWithIcon, height: 16)
            iconView.frame = NSRect(x: rowWidth - iconSize - padding, y: 6, width: iconSize, height: iconSize)
        }
    }

    func setValueColor(_ color: NSColor) {
        value.textColor = color
    }

    func setLabelColor(_ color: NSColor) {
        label.textColor = color
    }

    func setRowColor(_ color: NSColor) {
        label.textColor = color
        value.textColor = color
    }
    
    func setBold(_ bold: Bool) {
        self.isBold = bold
        if bold {
            label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        } else {
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        }
    }
}