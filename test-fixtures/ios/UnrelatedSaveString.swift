import UIKit

final class UnrelatedSaveStringViewController: UIViewController {
    private func configureAction() {
        let title = NSLocalizedString(
            "save",
            comment: "Generic save action"
        )

        navigationItem.title = title
    }
}
