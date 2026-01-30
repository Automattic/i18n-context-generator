import SwiftUI

/// Examples of SwiftUI-specific localization patterns
struct SwiftUIExamples: View {
    // LocalizedStringKey used in @State
    @State private var buttonTitle: LocalizedStringKey = "swiftui.state.button"

    // LocalizedStringKey in property
    let headerKey = LocalizedStringKey("swiftui.header.title")

    var body: some View {
        VStack {
            // Direct LocalizedStringKey initialization
            Text(LocalizedStringKey("swiftui.welcome.message"))

            // Text with LocalizedStringKey variable
            Text(headerKey)

            // Button with LocalizedStringKey
            Button(buttonTitle) {
                performAction()
            }

            // Text with tableName parameter
            Text("swiftui.custom.table", tableName: "CustomStrings")

            // Text with bundle
            Text("swiftui.bundle.string", bundle: .main)

            // Label with localized title and system image
            Label(LocalizedStringKey("swiftui.label.title"), systemImage: "star")

            // NavigationLink with localized destination title
            NavigationLink(LocalizedStringKey("swiftui.nav.destination")) {
                DetailView()
            }

            // TextField with localized placeholder
            TextField(LocalizedStringKey("swiftui.textfield.placeholder"), text: .constant(""))

            // Toggle with localized label
            Toggle(LocalizedStringKey("swiftui.toggle.label"), isOn: .constant(true))

            // Picker with localized title
            Picker(LocalizedStringKey("swiftui.picker.title"), selection: .constant(0)) {
                Text("Option 1").tag(0)
                Text("Option 2").tag(1)
            }
        }
    }

    private func performAction() {}
}

struct DetailView: View {
    var body: some View {
        Text(LocalizedStringKey("swiftui.detail.content"))
    }
}

// Example with environment-based localization
struct LocalizedContentView: View {
    @Environment(\.locale) var locale

    var body: some View {
        VStack {
            // Multi-line LocalizedStringKey
            Text(
                LocalizedStringKey("swiftui.multiline.key")
            )

            // String(localized:) for programmatic use
            Text(String(localized: "swiftui.programmatic.string"))
        }
    }
}
