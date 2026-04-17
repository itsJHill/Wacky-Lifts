@preconcurrency import UIKit
import UniformTypeIdentifiers

final class SettingsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let streakStore = StreakStore.shared
    private let themeManager = ThemeManager.shared
    private let weightLogStore = WeightLogStore.shared
    private let libraryStore = WorkoutLibraryStore.shared
    private let profileStore = UserProfileStore.shared
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let footerDefaultSuffix = "by jordan"
    private var footerResetWorkItem: DispatchWorkItem?

    /// Max number of characters allowed in the display name. Matches the
    /// worst-case length of "Test User 123456789" so even long combined
    /// greetings ("What's Good, Test User 123456789?") fit the header card
    /// at its shrink-to-fit minimum.
    fileprivate static let displayNameMaxLength = 19
    

    private enum Section: Int, CaseIterable, Hashable, Sendable {
        case profile
        case streaks
        case general
        case reset

        var title: String? {
            switch self {
            case .profile: return "Profile"
            case .streaks: return "Streaks"
            case .general: return "General"
            case .reset: return nil
            }
        }
    }

    nonisolated private enum Row: Hashable, Sendable {
        case userName
        case streakMode
        case weeklyWorkoutGoal
        case resetData
        case weightUnit
        case appTheme
        case dataManagement
        case machineSetup
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    private let footerLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .systemBackground
        configureTableView()
        configureDataSource()
        applySnapshot()
        observeChanges()
    }

    deinit {
        footerResetWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard tableView.tableFooterView === footerLabel else {
            tableView.tableFooterView = footerLabel
            return
        }

        var frame = footerLabel.frame
        if frame.width != tableView.bounds.width {
            frame.size.width = tableView.bounds.width
            footerLabel.frame = frame
            tableView.tableFooterView = footerLabel
        }
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.delegate = self
        updateFooterText(footerDefaultSuffix, animated: false)
        footerLabel.textAlignment = .center
        footerLabel.textColor = .secondaryLabel
        footerLabel.font = .preferredFont(forTextStyle: .footnote)
        footerLabel.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
        footerLabel.isUserInteractionEnabled = true
        footerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(footerTapped)))
        tableView.tableFooterView = footerLabel
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView) {
            [weak self] (tableView: UITableView, indexPath: IndexPath, row: Row) -> UITableViewCell in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            cell.selectionStyle = .none
            cell.accessoryView = nil
            cell.accessoryType = .none

            switch row {
            case .userName:
                var content = UIListContentConfiguration.valueCell()
                content.text = "Name"
                content.secondaryText = self.profileStore.displayName ?? "Not Set"
                content.image = UIImage(systemName: "person.fill")
                content.imageProperties.tintColor = .systemCyan
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .streakMode:
                var content = UIListContentConfiguration.valueCell()
                content.text = "Streak Mode"
                content.secondaryText = self.streakStore.streakMode.title
                content.image = UIImage(systemName: "flame.fill")
                content.imageProperties.tintColor = .systemOrange
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .weeklyWorkoutGoal:
                var content = UIListContentConfiguration.valueCell()
                content.text = "Weekly Goal"
                content.secondaryText = "\(self.streakStore.weeklyWorkoutGoal) workout\(self.streakStore.weeklyWorkoutGoal == 1 ? "" : "s")"
                content.image = UIImage(systemName: "target")
                content.imageProperties.tintColor = .systemBlue
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .resetData:
                var content = UIListContentConfiguration.cell()
                content.text = "Reset Data"
                content.textProperties.color = .systemRed
                content.image = UIImage(systemName: "arrow.counterclockwise")
                content.imageProperties.tintColor = .systemRed
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .weightUnit:
                var content = UIListContentConfiguration.valueCell()
                content.text = "Weight Unit"
                content.secondaryText = self.weightLogStore.preferredUnit.symbol
                content.image = UIImage(systemName: "scalemass.fill")
                content.imageProperties.tintColor = .systemGreen
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .appTheme:
                var content = UIListContentConfiguration.valueCell()
                content.text = "Appearance"
                content.secondaryText = self.themeManager.currentTheme.title
                content.image = UIImage(systemName: "circle.lefthalf.filled")
                content.imageProperties.tintColor = .systemIndigo
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .dataManagement:
                var content = UIListContentConfiguration.cell()
                content.text = "Data Management"
                content.image = UIImage(systemName: "externaldrive.fill")
                content.imageProperties.tintColor = .systemTeal
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            case .machineSetup:
                var content = UIListContentConfiguration.cell()
                content.text = "Machine Setup"
                content.image = UIImage(systemName: "gearshape.2.fill")
                content.imageProperties.tintColor = .systemPurple
                cell.contentConfiguration = content
                cell.accessoryType = .disclosureIndicator
                cell.selectionStyle = .default

            }

            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
            cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground

            return cell
        }
    }

    private func applySnapshot(animated: Bool = false) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections(Section.allCases)

        snapshot.appendItems([.userName], toSection: .profile)

        var streakItems: [Row] = [.streakMode]
        if streakStore.streakMode == .perWeek {
            streakItems.append(.weeklyWorkoutGoal)
        }

        snapshot.appendItems(streakItems, toSection: .streaks)
        snapshot.appendItems([.weightUnit, .appTheme, .machineSetup, .dataManagement], toSection: .general)
        snapshot.appendItems([.resetData], toSection: .reset)
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStreakChange),
            name: StreakStore.streakDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.themeDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWeightLogChange),
            name: WeightLogStore.logsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNameChange),
            name: UserProfileStore.nameDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleStreakChange() {
        applySnapshot(animated: true)
        // Also refresh the footer
        tableView.reloadData()
    }

    @objc private func handleThemeChange() {
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems([.appTheme])
        dataSource.apply(snapshot, animatingDifferences: false)
        // Refresh footer
        tableView.reloadData()
    }

    @objc private func handleWeightLogChange() {
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems([.weightUnit])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    @objc private func handleNameChange() {
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems([.userName])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func showDataManagementMenu(from sourceView: UIView?) {
        let sheet = UIAlertController(title: "Data Management", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Export History (CSV)", style: .default) { [weak self] _ in
            self?.exportHistory(from: sourceView)
        })
        sheet.addAction(UIAlertAction(title: "Export All Data", style: .default) { [weak self] _ in
            self?.exportAllData(from: sourceView)
        })
        sheet.addAction(UIAlertAction(title: "Import Data", style: .default) { [weak self] _ in
            self?.confirmImportData()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            if let sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }

        present(sheet, animated: true)
    }

    private func exportHistory(from sourceView: UIView?) {
        let logs = weightLogStore.allLogs()
        guard !logs.isEmpty else {
            let alert = UIAlertController(title: "No History", message: "No weight logs to export.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let csv = makeCSV(from: logs)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = "WackyLifts_History_\(formatter.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = UIAlertController(title: "Export Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            if let sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            }
        }
        present(activityVC, animated: true)
    }

    private func makeCSV(from logs: [ExerciseLog]) -> String {
        let unit = weightLogStore.preferredUnit.symbol
        let header = [
            "Date",
            "Workout",
            "Exercise",
            "Weight (\(unit))",
            "Progression (\(unit))",
        ].map(csvField).joined(separator: ",")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = [header]
        for log in logs {
            let workoutName = libraryStore.template(withId: log.workoutId)?.name ?? ""
            let dateString = formatter.string(from: log.date)
            let weightString = formatWeight(log.weight, isPersonalBest: log.isPersonalRecord)
            let progression = progressionString(for: log)
            let row = [dateString, workoutName, log.exerciseName, weightString, progression]
                .map(csvField)
                .joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    private func progressionString(for log: ExerciseLog) -> String {
        guard let setWeights = log.setWeights, !setWeights.isEmpty else { return "" }
        let maxWeight = setWeights.max() ?? 0
        let parts = setWeights.map { weight -> String in
            var value = formatWeight(weight)
            if log.isPersonalRecord && weight == maxWeight && weight > 0 {
                value += " (PB)"
            }
            return value
        }
        return parts.joined(separator: "->")
    }

    private func formatWeight(_ weight: Double, isPersonalBest: Bool = false) -> String {
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
        if isPersonalBest && weight > 0 {
            return "\(formatted) (PB)"
        }
        return formatted
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func showStreakModePicker() {
        let alert = UIAlertController(title: "Streak Mode", message: "Choose how your streak is calculated", preferredStyle: .actionSheet)

        for mode in StreakMode.allCases {
            let description = mode.description(weeklyGoal: streakStore.weeklyWorkoutGoal)
            let action = UIAlertAction(title: "\(mode.title)\n\(description)", style: .default) { [weak self] _ in
                self?.streakStore.streakMode = mode
            }
            if mode == streakStore.streakMode {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func showWeeklyGoalPicker() {
        let alert = UIAlertController(title: "Weekly Workout Goal", message: "How many workouts do you want to complete each week?", preferredStyle: .actionSheet)

        for goal in 1...7 {
            let title = goal == 1 ? "1 workout" : "\(goal) workouts"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.streakStore.weeklyWorkoutGoal = goal
            }
            if goal == streakStore.weeklyWorkoutGoal {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func showThemePicker() {
        let alert = UIAlertController(title: "Appearance", message: "Choose your preferred appearance", preferredStyle: .actionSheet)

        for theme in AppTheme.allCases {
            let action = UIAlertAction(title: "\(theme.title)", style: .default) { [weak self] _ in
                self?.themeManager.currentTheme = theme
            }
            if theme == themeManager.currentTheme {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func showNameEditor() {
        let alert = UIAlertController(title: "Name", message: "Set your display name for personalized greetings.", preferredStyle: .alert)
        alert.addTextField { [weak self] textField in
            textField.placeholder = "Enter your name"
            textField.text = self?.profileStore.displayName
            textField.autocapitalizationType = .words
            textField.returnKeyType = .done
            if let self {
                textField.addTarget(
                    self,
                    action: #selector(self.enforceDisplayNameLengthLimit(_:)),
                    for: .editingChanged
                )
            }
        }

        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let trimmed = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Defensive trim in case text bypassed editingChanged (e.g. set
            // programmatically). Keeps the stored name within the documented
            // limit even when the UI guard didn't fire.
            let limited = String(trimmed.prefix(Self.displayNameMaxLength))
            self.profileStore.displayName = limited.isEmpty ? nil : limited
        })

        if profileStore.displayName != nil {
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                self?.profileStore.displayName = nil
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc fileprivate func enforceDisplayNameLengthLimit(_ textField: UITextField) {
        guard let text = textField.text, text.count > Self.displayNameMaxLength else { return }
        // Preserve the user's cursor position as best we can after trimming.
        let trimmed = String(text.prefix(Self.displayNameMaxLength))
        textField.text = trimmed
        if let end = textField.position(from: textField.beginningOfDocument, offset: trimmed.count) {
            textField.selectedTextRange = textField.textRange(from: end, to: end)
        }
    }

    private func showMachineSetup() {
        let vc = MachineSetupViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func showResetData() {
        let vc = ResetDataViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func exportAllData(from sourceView: UIView?) {
        do {
            let data = try DataBackupManager.shared.exportBackup()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let fileName = "WackyLifts_Backup_\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                if let sourceView {
                    popover.sourceView = sourceView
                    popover.sourceRect = sourceView.bounds
                } else {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                }
            }
            present(activityVC, animated: true)
        } catch {
            let alert = UIAlertController(title: "Export Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func confirmImportData() {
        let alert = UIAlertController(
            title: "Import Data",
            message: "This will replace all current data with the backup. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Choose File", style: .destructive) { [weak self] _ in
            self?.presentDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func performImport(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            try DataBackupManager.shared.importBackup(from: data)

            let alert = UIAlertController(
                title: "Import Successful",
                message: "All data has been restored.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        } catch {
            let alert = UIAlertController(title: "Import Failed", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    private func showWeightUnitPicker() {
        let alert = UIAlertController(title: "Weight Unit", message: "Choose your preferred weight unit", preferredStyle: .actionSheet)

        for unit in WeightUnit.allCases {
            let action = UIAlertAction(title: unit.symbol, style: .default) { [weak self] _ in
                self?.weightLogStore.preferredUnit = unit
            }
            if unit == weightLogStore.preferredUnit {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func updateFooterText(_ suffix: String, animated: Bool) {
        let text = "v\(appVersion) · \(suffix)"
        footerLabel.font = .preferredFont(forTextStyle: .footnote)
        footerLabel.textColor = .secondaryLabel
        footerLabel.textAlignment = .center
        footerLabel.frame.size.height = 44
        guard animated else {
            footerLabel.text = text
            return
        }
        UIView.transition(with: footerLabel, duration: 0.25, options: .transitionCrossDissolve) {
            self.footerLabel.text = text
        }
        tableView.tableFooterView = footerLabel
    }

    @objc private func footerTapped() {
        footerResetWorkItem?.cancel()
        UIView.transition(with: footerLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.footerLabel.text = ":)"
        }

        // Fun haptic pattern while :) is showing
        let haptic = HapticManager.shared
        haptic.light()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { haptic.light() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { haptic.medium() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { haptic.light() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { haptic.light() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { haptic.medium() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { haptic.success() }

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateFooterText(self?.footerDefaultSuffix ?? "by jordan", animated: true)
        }
        footerResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }

        switch row {
        case .userName:
            showNameEditor()
        case .streakMode:
            showStreakModePicker()
        case .weeklyWorkoutGoal:
            showWeeklyGoalPicker()
        case .resetData:
            showResetData()
        case .weightUnit:
            showWeightUnitPicker()
        case .appTheme:
            showThemePicker()
        case .dataManagement:
            showDataManagementMenu(from: tableView.cellForRow(at: indexPath))
        case .machineSetup:
            showMachineSetup()
        }
    }

    private func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    private func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        switch sectionType {
        case .profile:
            return nil
        case .streaks:
            return streakStore.streakDescription
        case .general:
            return nil
        case .reset:
            return nil
        }
    }
}

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        performImport(from: url)
    }
}

extension UIListContentConfiguration {
    fileprivate func with(_ transform: (inout UIListContentConfiguration) -> Void)
        -> UIListContentConfiguration
    {
        var copy = self
        transform(&copy)
        return copy
    }
}
