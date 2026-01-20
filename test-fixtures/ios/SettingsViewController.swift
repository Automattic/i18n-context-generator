import UIKit

class SettingsViewController: UITableViewController {

    // MARK: - Properties

    private let sections = ["Account", "Preferences", "Actions"]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        title = NSLocalizedString("settings.title", comment: "Navigation bar title for settings screen")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.done", comment: "Done button"),
            style: .done,
            target: self,
            action: #selector(dismissSettings)
        )
    }

    // MARK: - TableView DataSource

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)

        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = NSLocalizedString("settings.notifications", comment: "Notifications settings row")
            cell.detailTextLabel?.text = NSLocalizedString("settings.notifications.description", comment: "Notifications description")
        case (0, 1):
            cell.textLabel?.text = NSLocalizedString("settings.privacy", comment: "Privacy settings row")
        case (2, 0):
            cell.textLabel?.text = NSLocalizedString("settings.logout", comment: "Logout button in settings")
            cell.textLabel?.textColor = .systemRed
        default:
            break
        }

        return cell
    }

    // MARK: - TableView Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 2 && indexPath.row == 0 {
            showLogoutConfirmation()
        }
    }

    // MARK: - Actions

    private func showLogoutConfirmation() {
        let alert = UIAlertController(
            title: NSLocalizedString("settings.logout", comment: "Logout alert title"),
            message: NSLocalizedString("settings.logout.confirm", comment: "Logout confirmation message"),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("common.cancel", comment: "Cancel button"),
            style: .cancel
        ))

        alert.addAction(UIAlertAction(
            title: NSLocalizedString("settings.logout", comment: "Logout action"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.performLogout()
            }
        ))

        present(alert, animated: true)
    }

    @objc private func dismissSettings() {
        dismiss(animated: true)
    }

    private func performLogout() {
        // Logout logic
    }
}
