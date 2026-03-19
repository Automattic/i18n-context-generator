import UIKit

final class UnrelatedLocalizationTitleView: UIView {
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localization.title
        return label
    }()
}

private extension UnrelatedLocalizationTitleView {
    enum Localization {
        static let title = NSLocalizedString(
            "unrelated.title",
            comment: "Unrelated view title"
        )
    }
}
