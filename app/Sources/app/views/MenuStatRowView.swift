import AppKit

final class MenuStatRowView: NSView {

    // MARK: - Constants (MAXIMUM SIZE)
    private static let maxRowWidth: CGFloat = 310
    private static let rowHeight: CGFloat = 28

    private let padding: CGFloat = 8
    private let iconSize: CGFloat = 16
    private let labelWidth: CGFloat = 75

    // MARK: - Constraints
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    // MARK: - Views
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")

    // MARK: - Hover
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    private var isBold: Bool = false

    // MARK: - Size
    override var intrinsicContentSize: NSSize {
        return NSSize(
            width: Self.maxRowWidth,
            height: Self.rowHeight
        )
    }
    
    override var fittingSize: NSSize {
        return NSSize(
            width: min(super.fittingSize.width, Self.maxRowWidth),
            height: Self.rowHeight
        )
    }

    // MARK: - Init
    init(labelText: String, valueText: String, isBold: Bool = false) {
        self.isBold = isBold
        super.init(frame: .zero)
        
        setupView()
        setupConstraints()
        setupSubviews(labelText: labelText, valueText: valueText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    // MARK: - Setup
    private func setupView() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        
        // Set content priorities
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }
    
    private func setupConstraints() {
        // Set maximum width constraint
        widthConstraint = widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxRowWidth)
        widthConstraint?.priority = .required
        widthConstraint?.isActive = true
        
        // Set exact height constraint
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.rowHeight)
        heightConstraint?.priority = .required
        heightConstraint?.isActive = true
        
        // Set minimum width (can't be less than needed for content)
        let minWidthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: 150) // Minimum reasonable width
        minWidthConstraint.priority = .defaultHigh
        minWidthConstraint.isActive = true
    }
    
    private func setupSubviews(labelText: String, valueText: String) {
        // Label
        label.stringValue = labelText
        label.font = NSFont.systemFont(
            ofSize: 13,
            weight: isBold ? .bold : .medium
        )
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        // Value
        value.stringValue = valueText
        value.font = NSFont.monospacedDigitSystemFont(
            ofSize: 13,
            weight: isBold ? .bold : .semibold
        )
        value.textColor = .labelColor
        value.alignment = .right
        value.lineBreakMode = .byTruncatingTail
        value.translatesAutoresizingMaskIntoConstraints = false
        addSubview(value)
        
        // Icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.isHidden = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        setupLayoutConstraints()
    }
    
    private func setupLayoutConstraints() {
        // Label constraints
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: labelWidth)
        ])
        
        // Icon constraints (when visible)
        NSLayoutConstraint.activate([
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize)
        ])
        
        // Value constraints - dynamic based on icon visibility
        let valueTrailingConstraint = value.trailingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -4)
        valueTrailingConstraint.priority = .defaultHigh
        
        let valueTrailingFallback = value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
        valueTrailingFallback.priority = .defaultLow
        
        NSLayoutConstraint.activate([
            value.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueTrailingConstraint,
            valueTrailingFallback
        ])
        
        // Force width to max when possible
        let preferredWidthConstraint = widthAnchor.constraint(equalToConstant: Self.maxRowWidth)
        preferredWidthConstraint.priority = .defaultHigh
        preferredWidthConstraint.isActive = true
    }

    // MARK: - Tracking
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

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: 10,
            yRadius: 10
        )

        if isHovered {
            NSColor(white: 0.9, alpha: 0.12).setFill()
        } else {
            NSColor.controlBackgroundColor
                .withAlphaComponent(0.18)
                .setFill()
        }

        path.fill()
    }

    // MARK: - Public API
    func update(valueText: String) {
        value.stringValue = valueText
    }

    func setIcon(_ image: NSImage?) {
        iconView.image = image
        iconView.isHidden = (image == nil)
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
        isBold = bold
        label.font = NSFont.systemFont(
            ofSize: 13,
            weight: bold ? .bold : .medium
        )
        value.font = NSFont.monospacedDigitSystemFont(
            ofSize: 13,
            weight: bold ? .bold : .semibold
        )
    }
    
    // MARK: - Size Management
    override func setFrameSize(_ newSize: NSSize) {
        // Ensure width doesn't exceed maximum
        let clampedWidth = min(newSize.width, Self.maxRowWidth)
        super.setFrameSize(NSSize(width: clampedWidth, height: Self.rowHeight))
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        // Update constraints if needed
        super.resize(withOldSuperviewSize: oldSize)
        
        // Re-apply max width constraint
        widthConstraint?.constant = Self.maxRowWidth
    }
}