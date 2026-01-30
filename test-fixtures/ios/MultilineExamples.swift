import UIKit

/// Examples of multi-line localization patterns that the searcher must detect.
/// These patterns are common when using longer keys or when code formatters
/// break lines at specific column widths.
class MultilineExamples {

    func setupAccessibility() {
        // Multi-line NSLocalizedString - key on separate line
        let label = NSLocalizedString(
            "multiline.accessibility.label",
            comment: "Accessibility label for main content area"
        )

        // Multi-line with key on third line (after whitespace)
        let hint = NSLocalizedString(
            "multiline.accessibility.hint",
            comment: "Accessibility hint explaining the action"
        )

        // Multi-line String(localized:) - modern Swift
        let title = String(
            localized: "multiline.navigation.title",
            comment: "Navigation bar title"
        )

        // Multi-line with bundle parameter
        let bundleString = NSLocalizedString(
            "multiline.bundle.example",
            bundle: .main,
            comment: "String loaded from main bundle"
        )

        print(label, hint, title, bundleString)
    }

    func configureCell(_ cell: UITableViewCell) {
        // Real-world pattern: assignment with multi-line localization
        cell.textLabel?.text = NSLocalizedString(
            "multiline.cell.title",
            comment: "Cell title text"
        )

        cell.detailTextLabel?.text = NSLocalizedString(
            "multiline.cell.subtitle",
            comment: "Cell subtitle text"
        )

        cell.accessibilityLabel = NSLocalizedString(
            "multiline.cell.a11y",
            comment: "Full accessibility label for cell"
        )
    }

    func showAlert() {
        // Multi-line in UIAlertController
        let alert = UIAlertController(
            title: NSLocalizedString(
                "multiline.alert.title",
                comment: "Alert title"
            ),
            message: NSLocalizedString(
                "multiline.alert.message",
                comment: "Alert message body"
            ),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: NSLocalizedString(
                "multiline.alert.confirm",
                comment: "Confirm button"
            ),
            style: .default
        ))
    }

    // Edge case: deeply nested multi-line
    func nestedExample() {
        someFunction(
            parameter: anotherFunction(
                value: NSLocalizedString(
                    "multiline.nested.deep",
                    comment: "Deeply nested localized string"
                )
            )
        )
    }

    private func someFunction(parameter: String) {}
    private func anotherFunction(value: String) -> String { value }
}
