import UIKit

final class LocalizationWrapperView: UIView {
    private lazy var saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localization.save, for: .normal)
        return button
    }()

    private lazy var noteTextField: UITextField = {
        let field = UITextField()
        field.placeholder = Localization.notePlaceholder
        return field
    }()
}

private extension LocalizationWrapperView {
    enum Localization {
        static let save = NSLocalizedString(
            "wrapper.save",
            comment: "Button title"
        )

        static let notePlaceholder = NSLocalizedString(
            "wrapper.note.placeholder",
            comment: ""
        )
    }
}
