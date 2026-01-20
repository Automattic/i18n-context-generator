import UIKit

class ProfileViewController: UIViewController {

    // MARK: - UI Elements

    private lazy var profileImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 50
        return imageView
    }()

    private lazy var changePhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString("profile.photo.change", comment: "Button to change profile photo"), for: .normal)
        button.addTarget(self, action: #selector(changePhotoTapped), for: .touchUpInside)
        return button
    }()

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = NSLocalizedString("profile.name.placeholder", comment: "Placeholder for name input field")
        textField.borderStyle = .roundedRect
        return textField
    }()

    private lazy var saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString("common.save", comment: "Save button"), for: .normal)
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = NSLocalizedString("profile.edit", comment: "Edit profile screen title")
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.cancel", comment: "Cancel button"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    // MARK: - Actions

    @objc private func changePhotoTapped() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func saveTapped() {
        guard let name = nameTextField.text, !name.isEmpty else {
            return
        }

        // Show loading indicator
        let loadingMessage = NSLocalizedString("common.loading", comment: "Loading indicator text")
        showLoadingIndicator(message: loadingMessage)

        // Save profile
        saveProfile(name: name) { [weak self] result in
            self?.hideLoadingIndicator()

            switch result {
            case .success:
                self?.dismiss(animated: true)
            case .failure(let error):
                self?.showError(error)
            }
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func showError(_ error: Error) {
        let message: String

        if case NetworkError.noConnection = error {
            message = NSLocalizedString("error.network", comment: "Network error message")
        } else if case NetworkError.unauthorized = error {
            message = NSLocalizedString("error.unauthorized", comment: "Unauthorized error message")
        } else {
            message = NSLocalizedString("error.not_found", comment: "Generic error message")
        }

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.done", comment: "OK button"), style: .default))
        present(alert, animated: true)
    }

    private func showLoadingIndicator(message: String) {
        // Implementation
    }

    private func hideLoadingIndicator() {
        // Implementation
    }

    private func saveProfile(name: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Implementation
    }
}

extension ProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            profileImageView.image = image
        }
    }
}

enum NetworkError: Error {
    case noConnection
    case unauthorized
    case notFound
}
