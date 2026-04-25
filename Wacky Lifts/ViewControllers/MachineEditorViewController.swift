@preconcurrency import UIKit

protocol MachineEditorViewControllerDelegate: AnyObject {
    func machineEditorDidSave(_ controller: MachineEditorViewController)
}

final class MachineEditorViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case name
        case behavior
        case quickFill
        case weights
    }

    weak var delegate: MachineEditorViewControllerDelegate?

    private let store = MachineStore.shared
    private let existingMachine: WeightMachine?

    private var draftName: String
    private var draftWeights: [Double]
    private var draftProgressionKind: WeightProgressionKind

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Quick fill fields
    private var quickIncrement: String = "5"
    private var quickSecondIncrement: String = ""
    private var quickMax: String = "200"

    private var includesUnassisted: Bool {
        draftProgressionKind == .lowerIsBetter
    }

    private var visibleWeightRowCount: Int {
        draftWeights.count + (includesUnassisted ? 1 : 0)
    }

    init(machine: WeightMachine? = nil) {
        self.existingMachine = machine
        self.draftName = machine?.name ?? ""
        self.draftWeights = machine?.weights ?? []
        self.draftProgressionKind = machine?.progressionKind ?? .higherIsBetter
        super.init(nibName: nil, bundle: nil)
        self.title = machine != nil ? "Edit Machine" : "New Machine"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        configureNavBar()
        configureTableView()
    }

    private func configureNavBar() {
        let cancelButton = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        cancelButton.accessibilityLabel = "Cancel"
        navigationItem.leftBarButtonItem = cancelButton

        let saveButton = UIBarButtonItem(
            title: "Save",
            style: .prominent,
            target: self,
            action: #selector(saveTapped)
        )
        saveButton.accessibilityLabel = "Save"
        navigationItem.rightBarButtonItem = saveButton
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.keyboardDismissMode = .onDrag

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func saveTapped() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showAlert(message: "Please enter a machine name.")
            return
        }
        guard !draftWeights.isEmpty else {
            showAlert(message: "Please add at least one weight position.")
            return
        }

        let sortedWeights = draftWeights.filter { $0 > 0 }.sorted()

        if let existing = existingMachine {
            store.update(
                id: existing.id,
                name: trimmedName,
                weights: sortedWeights,
                progressionKind: draftProgressionKind
            )
        } else {
            store.add(name: trimmedName, weights: sortedWeights, progressionKind: draftProgressionKind)
        }

        delegate?.machineEditorDidSave(self)
        navigationController?.popViewController(animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "Missing Info", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func generateTapped() {
        view.endEditing(true)

        guard let increment = Double(quickIncrement.trimmingCharacters(in: .whitespacesAndNewlines)),
              increment > 0,
              let max = Double(quickMax.trimmingCharacters(in: .whitespacesAndNewlines)),
              max > 0 else {
            showAlert(message: "Enter a valid increment and max weight.")
            return
        }

        let secondText = quickSecondIncrement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondText.isEmpty, let secondary = Double(secondText), secondary > 0 {
            draftWeights = WeightMachine.generateAlternating(primary: increment, secondary: secondary, max: max)
        } else {
            draftWeights = WeightMachine.generateUniform(increment: increment, max: max)
        }

        tableView.reloadSections(IndexSet(integer: Section.weights.rawValue), with: .automatic)
    }

    private func promptAddWeight() {
        let alert = UIAlertController(title: "Add Weight", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Weight value"
            field.keyboardType = .decimalPad
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Double(text),
                  value > 0 else { return }
            self.draftWeights.append(value)
            self.draftWeights.sort()
            self.tableView.reloadSections(IndexSet(integer: Section.weights.rawValue), with: .automatic)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MachineEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .name: return 1
        case .behavior: return 1
        case .quickFill: return 4  // increment, 2nd increment, max, generate button
        case .weights: return visibleWeightRowCount + 1  // weights + "Add Weight" row
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .name: return "Name"
        case .behavior: return "Weight Behavior"
        case .quickFill: return "Quick Fill"
        case .weights:
            return includesUnassisted
                ? "Weight Positions (Unassisted + \(draftWeights.count))"
                : "Weight Positions (\(draftWeights.count))"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .behavior:
            return draftProgressionKind.description
        case .quickFill:
            return draftProgressionKind == .lowerIsBetter
                ? "Enter positive assistance values. Unassisted is included automatically."
                : "Enter an increment and max to auto-generate positions. Add a second increment for alternating machines (e.g., cable stacks with 2/3 patterns)."
        case .weights:
            return draftWeights.isEmpty ? nil : "Swipe to delete individual positions, or use Quick Fill to regenerate."
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        cell.backgroundConfiguration?.backgroundColor = .secondarySystemBackground
        cell.accessoryType = .none
        cell.selectionStyle = .none

        // Remove any existing content view subviews we added
        cell.contentView.subviews.forEach { if $0.tag == 999 { $0.removeFromSuperview() } }

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .name:
            let field = createTextField(
                placeholder: "Machine name",
                text: draftName,
                tag: 10
            )
            field.autocapitalizationType = .words
            field.addTarget(self, action: #selector(nameFieldChanged(_:)), for: .editingChanged)
            embedTextField(field, in: cell)

        case .behavior:
            var content = UIListContentConfiguration.valueCell()
            content.text = "Behavior"
            content.secondaryText = draftProgressionKind.shortTitle
            content.image = UIImage(systemName: draftProgressionKind == .lowerIsBetter ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
            content.imageProperties.tintColor = draftProgressionKind == .lowerIsBetter ? .systemPurple : .systemBlue
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default

        case .quickFill:
            switch indexPath.row {
            case 0:
                let field = createTextField(
                    placeholder: "Increment (e.g., 5)",
                    text: quickIncrement,
                    tag: 20
                )
                field.keyboardType = .decimalPad
                field.addTarget(self, action: #selector(incrementFieldChanged(_:)), for: .editingChanged)
                embedTextField(field, in: cell)
            case 1:
                let field = createTextField(
                    placeholder: "2nd increment (optional, for alternating)",
                    text: quickSecondIncrement,
                    tag: 21
                )
                field.keyboardType = .decimalPad
                field.addTarget(self, action: #selector(secondIncrementFieldChanged(_:)), for: .editingChanged)
                embedTextField(field, in: cell)
            case 2:
                let field = createTextField(
                    placeholder: "Max weight (e.g., 200)",
                    text: quickMax,
                    tag: 22
                )
                field.keyboardType = .decimalPad
                field.addTarget(self, action: #selector(maxFieldChanged(_:)), for: .editingChanged)
                embedTextField(field, in: cell)
            case 3:
                var content = UIListContentConfiguration.cell()
                content.text = "Generate"
                content.textProperties.color = .systemBlue
                content.textProperties.alignment = .center
                content.textProperties.font = .preferredFont(forTextStyle: .headline)
                cell.contentConfiguration = content
                cell.selectionStyle = .default
            default:
                break
            }

        case .weights:
            if includesUnassisted && indexPath.row == 0 {
                var content = UIListContentConfiguration.cell()
                content.text = "Unassisted"
                content.secondaryText = "Included automatically"
                content.image = UIImage(systemName: "figure.strengthtraining.traditional")
                content.imageProperties.tintColor = .systemPurple
                cell.contentConfiguration = content
            } else if indexPath.row < visibleWeightRowCount {
                let weightIndex = indexPath.row - (includesUnassisted ? 1 : 0)
                let weight = draftWeights[weightIndex]
                var content = UIListContentConfiguration.cell()
                let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", weight) : String(format: "%.1f", weight)
                content.text = "\(formatted) lbs"
                content.textProperties.font = .monospacedDigitSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                    weight: .regular
                )
                cell.contentConfiguration = content
            } else {
                var content = UIListContentConfiguration.cell()
                content.text = "Add Weight"
                content.image = UIImage(systemName: "plus.circle.fill")
                content.imageProperties.tintColor = .systemBlue
                cell.contentConfiguration = content
                cell.selectionStyle = .default
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .behavior:
            showBehaviorPicker()
        case .quickFill:
            if indexPath.row == 3 {
                generateTapped()
            }
        case .weights:
            if indexPath.row >= visibleWeightRowCount {
                promptAddWeight()
            }
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        return section == .weights
            && indexPath.row >= (includesUnassisted ? 1 : 0)
            && indexPath.row < visibleWeightRowCount
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete,
              let section = Section(rawValue: indexPath.section),
              section == .weights,
              indexPath.row < visibleWeightRowCount else { return }
        let weightIndex = indexPath.row - (includesUnassisted ? 1 : 0)
        guard weightIndex >= 0, weightIndex < draftWeights.count else { return }
        draftWeights.remove(at: weightIndex)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        // Reload header to update count
        tableView.reloadSections(IndexSet(integer: Section.weights.rawValue), with: .none)
    }

    // MARK: - Text Field Helpers

    private func createTextField(placeholder: String, text: String, tag: Int) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.tag = tag
        field.font = .preferredFont(forTextStyle: .body)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func embedTextField(_ field: UITextField, in cell: UITableViewCell) {
        cell.contentConfiguration = nil
        let wrapper = UIView()
        wrapper.tag = 999
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(field)
        cell.contentView.addSubview(wrapper)

        NSLayoutConstraint.activate([
            wrapper.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor),
            wrapper.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),

            field.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 11),
            field.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -11),
        ])
    }

    // MARK: - Field Actions

    @objc private func nameFieldChanged(_ sender: UITextField) {
        draftName = sender.text ?? ""
    }

    private func showBehaviorPicker() {
        let alert = UIAlertController(title: "Weight Behavior", message: nil, preferredStyle: .actionSheet)
        for kind in WeightProgressionKind.allCases {
            let title = kind == draftProgressionKind ? "\(kind.title) ✓" : kind.title
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.draftProgressionKind = kind
                self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    @objc private func incrementFieldChanged(_ sender: UITextField) {
        quickIncrement = sender.text ?? ""
    }

    @objc private func secondIncrementFieldChanged(_ sender: UITextField) {
        quickSecondIncrement = sender.text ?? ""
    }

    @objc private func maxFieldChanged(_ sender: UITextField) {
        quickMax = sender.text ?? ""
    }
}
