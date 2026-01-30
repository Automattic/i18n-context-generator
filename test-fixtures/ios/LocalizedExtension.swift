import Foundation

/// Examples of the .localized extension pattern
/// This is a common pattern where apps define a String extension
/// to simplify localization calls.

// The extension definition (for reference - this is what enables the pattern)
extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }

    func localized(comment: String) -> String {
        NSLocalizedString(self, comment: comment)
    }
}

class LocalizedExtensionExamples {

    func basicUsage() {
        // Simple .localized usage
        let title = "extension.title".localized
        let subtitle = "extension.subtitle".localized

        // .localized with format arguments
        let greeting = "extension.greeting.format".localized(with: "John")
        let count = "extension.items.count".localized(with: 5)

        // .localized with comment
        let hint = "extension.accessibility.hint".localized(comment: "Hint for button")

        print(title, subtitle, greeting, count, hint)
    }

    func inlineUsage() {
        // Inline in function calls
        showAlert(title: "extension.alert.title".localized)
        showAlert(message: "extension.alert.message".localized)

        // In string interpolation (edge case)
        let combined = "Prefix: \("extension.interpolated".localized)"
        print(combined)
    }

    func propertyUsage() {
        // As computed property
        var buttonLabel: String {
            "extension.button.label".localized
        }

        print(buttonLabel)
    }

    func chainedUsage() {
        // Chained with other String methods
        let uppercased = "extension.uppercase.text".localized.uppercased()
        let trimmed = "extension.trimmed.text".localized.trimmingCharacters(in: .whitespaces)

        print(uppercased, trimmed)
    }

    private func showAlert(title: String = "", message: String = "") {}
}

// Example in SwiftUI context
import SwiftUI

struct LocalizedExtensionView: View {
    var body: some View {
        VStack {
            Text("extension.swiftui.title".localized)
            Text("extension.swiftui.body".localized)
        }
    }
}
