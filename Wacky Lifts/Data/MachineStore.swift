import Foundation

final class MachineStore {
    static let shared = MachineStore()

    static let machinesDidChangeNotification = Notification.Name("MachineStore.machinesDidChange")

    private let userDefaults = UserDefaults.standard
    private let machinesKey = "weight_machines"

    private(set) var machines: [WeightMachine] {
        didSet {
            save()
            notifyChange()
        }
    }

    var sortedMachines: [WeightMachine] {
        machines.sorted { $0.order < $1.order }
    }

    private init() {
        if let data = userDefaults.data(forKey: machinesKey),
           let saved = try? JSONDecoder().decode([WeightMachine].self, from: data) {
            machines = saved
            migrateDefaults()
        } else {
            // First launch - seed with defaults
            machines = WeightMachine.defaultMachines
            save()
        }
    }

    /// Adds any missing well-known default machines (e.g. Bodyweight) for existing users.
    private func migrateDefaults() {
        let existingIds = Set(machines.map(\.id))
        let missing = WeightMachine.defaultMachines.filter { !existingIds.contains($0.id) }
        guard !missing.isEmpty else { return }

        let maxOrder = machines.map(\.order).max() ?? -1
        for (offset, var machine) in missing.enumerated() {
            machine.order = maxOrder + 1 + offset
            machines.append(machine)
        }
    }

    // MARK: - CRUD

    func add(name: String, weights: [Double]) {
        let maxOrder = machines.map(\.order).max() ?? -1
        let machine = WeightMachine(
            id: UUID(),
            name: name,
            weights: weights,
            order: maxOrder + 1
        )
        machines.append(machine)
    }

    func update(id: UUID, name: String, weights: [Double]) {
        guard let index = machines.firstIndex(where: { $0.id == id }) else { return }
        var updated = machines[index]
        updated.name = name
        updated.weights = weights
        machines[index] = updated
    }

    func delete(id: UUID) {
        ReferenceCleaner.onMachineDeleted(id)
        machines.removeAll { $0.id == id }
        reindex()
    }

    func move(fromIndex: Int, toIndex: Int) {
        let sorted = sortedMachines
        guard fromIndex >= 0, fromIndex < sorted.count,
              toIndex >= 0, toIndex < sorted.count,
              fromIndex != toIndex else { return }

        var reordered = sorted
        let item = reordered.remove(at: fromIndex)
        reordered.insert(item, at: toIndex)

        for (index, machine) in reordered.enumerated() {
            if let machineIndex = machines.firstIndex(where: { $0.id == machine.id }) {
                machines[machineIndex].order = index
            }
        }
    }

    func machine(for id: UUID) -> WeightMachine? {
        machines.first { $0.id == id }
    }

    // MARK: - Private

    private func save() {
        if let data = try? JSONEncoder().encode(machines) {
            userDefaults.set(data, forKey: machinesKey)
        }
    }

    private func reindex() {
        let sorted = sortedMachines
        for (index, machine) in sorted.enumerated() {
            if let machineIndex = machines.firstIndex(where: { $0.id == machine.id }) {
                machines[machineIndex].order = index
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.machinesDidChangeNotification, object: self)
    }

    func resetAll() {
        machines = WeightMachine.defaultMachines
    }

    /// Re-read machines from UserDefaults. The `machines` didSet triggers
    /// save + notify automatically. Called by `DataBackupManager` after import.
    func reloadFromDisk() {
        if let data = userDefaults.data(forKey: machinesKey),
           let saved = try? JSONDecoder().decode([WeightMachine].self, from: data) {
            machines = saved
        } else {
            machines = WeightMachine.defaultMachines
        }
        migrateDefaults()
    }
}
