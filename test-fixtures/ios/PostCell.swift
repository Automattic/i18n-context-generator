import UIKit

class PostCell: UITableViewCell {

    // MARK: - UI Elements

    private let contentLabel = UILabel()
    private let likeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let commentsLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    // MARK: - Properties

    var post: Post? {
        didSet {
            updateUI()
        }
    }

    var onLike: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        likeButton.setTitle(NSLocalizedString("post.like", comment: "Like button on post"), for: .normal)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)

        shareButton.setTitle(NSLocalizedString("post.share", comment: "Share button on post"), for: .normal)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        deleteButton.setTitle(NSLocalizedString("common.delete", comment: "Delete button"), for: .normal)
        deleteButton.setTitleColor(.systemRed, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        // Layout setup...
    }

    private func updateUI() {
        guard let post = post else { return }

        contentLabel.text = post.content

        // Format comments count
        let commentsFormat = NSLocalizedString("post.comments", comment: "Comments count label showing number of comments")
        commentsLabel.text = String(format: commentsFormat, post.commentsCount)
    }

    // MARK: - Actions

    @objc private func likeTapped() {
        onLike?()
    }

    @objc private func shareTapped() {
        onShare?()
    }

    @objc private func deleteTapped() {
        showDeleteConfirmation()
    }

    private func showDeleteConfirmation() {
        guard let viewController = findViewController() else { return }

        let alert = UIAlertController(
            title: NSLocalizedString("common.delete", comment: "Delete confirmation title"),
            message: NSLocalizedString("post.delete.confirm", comment: "Delete post confirmation message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("common.cancel", comment: "Cancel button"),
            style: .cancel
        ))

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("common.delete", comment: "Delete action button"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.onDelete?()
            }
        ))

        viewController.present(alert, animated: true)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let vc = nextResponder as? UIViewController {
                return vc
            }
            responder = nextResponder
        }
        return nil
    }
}

struct Post {
    let id: String
    let content: String
    let commentsCount: Int
    let isLiked: Bool
}
