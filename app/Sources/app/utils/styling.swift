import AppKit

// MARK: - Menu Styling Helpers
// Global UI utility functions used to style NSMenuItem titles.
// Kept as free (global) functions because they are stateless,
// reusable across files, and idiomatic in Swift.

func styledTitle(
    _ text: String,
    size: CGFloat = 15,
    weight: NSFont.Weight = .semibold,
    color: NSColor = .labelColor
) -> NSAttributedString {

    let font: NSFont

    if #available(macOS 10.15, *) {
        font = NSFont.monospacedSystemFont(
            ofSize: size,
            weight: weight
        )
    } else {
        font = NSFont.systemFont(
            ofSize: size,
            weight: weight
        )
    }

    return NSAttributedString(
        string: text,
        attributes: [
            .font: font,
            .foregroundColor: color
        ]
    )
}
