import Foundation

enum WeightProgressionKind: String, Codable, CaseIterable, Sendable {
    case higherIsBetter
    case lowerIsBetter

    var title: String {
        switch self {
        case .higherIsBetter: return "Higher weight is better"
        case .lowerIsBetter: return "Lower assistance is better"
        }
    }

    var shortTitle: String {
        switch self {
        case .higherIsBetter: return "Higher Weight"
        case .lowerIsBetter: return "Lower Assistance"
        }
    }

    var description: String {
        switch self {
        case .higherIsBetter:
            return "PRs improve as weight increases."
        case .lowerIsBetter:
            return "For assisted workouts. PRs improve as assistance decreases; Unassisted is best."
        }
    }
}

struct WeightMachine: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var weights: [Double]  // sorted ascending list of valid weight positions
    var order: Int
    var progressionKind: WeightProgressionKind

    // MARK: - Well-Known IDs

    static let standardPlatesId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let standardDumbbellsId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let standardCableMachineId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let bodyweightId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let unassistedValue = -1.0

    init(
        id: UUID,
        name: String,
        weights: [Double],
        order: Int,
        progressionKind: WeightProgressionKind = .higherIsBetter
    ) {
        self.id = id
        self.name = name
        self.weights = weights.filter { $0 > 0 }.sorted()
        self.order = order
        self.progressionKind = progressionKind
    }

    // MARK: - Weight Array Generators

    /// Generates a uniform weight array: 0, increment, 2*increment, ... up to max.
    static func generateUniform(increment: Double, max: Double) -> [Double] {
        guard increment > 0, max > 0 else { return [] }
        var result: [Double] = []
        var w = 0.0
        while w <= max + 0.001 {
            result.append(w)
            w += increment
        }
        return result
    }

    /// Generates an alternating weight array: primary, primary+secondary, 2*primary+secondary, ... up to max.
    static func generateAlternating(primary: Double, secondary: Double, max: Double) -> [Double] {
        guard primary > 0, secondary > 0, max > 0 else { return [] }
        var result: [Double] = []
        var w = 0.0
        var usePrimary = true
        while true {
            let step = usePrimary ? primary : secondary
            w += step
            if w > max + 0.001 { break }
            result.append(w)
            usePrimary.toggle()
        }
        return result
    }

    // MARK: - Defaults

    static let defaultMachines: [WeightMachine] = [
        WeightMachine(
            id: standardPlatesId,
            name: "Standard Plates",
            weights: generateUniform(increment: 5, max: 500),
            order: 0
        ),
        WeightMachine(
            id: standardDumbbellsId,
            name: "Standard Dumbbells",
            weights: generateUniform(increment: 5, max: 150),
            order: 1
        ),
        WeightMachine(
            id: standardCableMachineId,
            name: "Cable Machine",
            weights: generateAlternating(primary: 2, secondary: 3, max: 200),
            order: 2
        ),
        WeightMachine(
            id: bodyweightId,
            name: "Bodyweight",
            weights: [],
            order: 3
        ),
    ]

    var isBodyweight: Bool { id == Self.bodyweightId }
    var isAssisted: Bool { progressionKind == .lowerIsBetter }

    var selectableWeights: [Double] {
        isAssisted ? [Self.unassistedValue] + weights : weights
    }

    // MARK: - Display

    var displayDescription: String {
        if isBodyweight {
            return "No weight"
        }
        guard let first = weights.first, let last = weights.last, !weights.isEmpty else {
            return "No positions"
        }
        let f = first.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", first) : String(format: "%.1f", first)
        let l = last.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", last) : String(format: "%.1f", last)
        let range = "\(f)–\(l) lbs (\(weights.count) positions)"
        return isAssisted ? "\(range), Unassisted included" : range
    }

    func displayText(for weight: Double, unit: WeightUnit) -> String {
        if isAssisted && weight < 0 {
            return "Unassisted"
        }
        let formatted = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", weight)
            : String(format: "%.1f", weight)
        return "\(formatted) \(unit.symbol)"
    }

    func isValidLogWeight(_ weight: Double) -> Bool {
        isAssisted ? weight != 0 : weight > 0
    }

    // MARK: - Increment Logic

    /// Returns the next weight up from the given weight using the weights array.
    func incrementUp(from weight: Double) -> Double {
        guard !weights.isEmpty else { return weight }
        if isAssisted && weight < 0 {
            return weights.first ?? weight
        }
        // Find first element greater than current weight
        for w in weights {
            if w > weight + 0.001 {
                return w
            }
        }
        // Already at or above max — stay at max
        return weights.last ?? weight
    }

    /// Returns the next weight down from the given weight using the weights array.
    func incrementDown(from weight: Double) -> Double {
        guard !weights.isEmpty else { return weight }
        if isAssisted && weight <= (weights.first ?? 0) {
            return Self.unassistedValue
        }
        if isAssisted && weight < 0 {
            return Self.unassistedValue
        }
        // Find last element less than current weight
        var result = weights.first ?? 0
        for w in weights {
            if w < weight - 0.001 {
                result = w
            } else {
                break
            }
        }
        return weight > (weights.first ?? 0) ? result : (weights.first ?? 0)
    }
}

// MARK: - Codable (with migration from old primaryStep/secondaryStep format)

extension WeightMachine: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, weights, order, progressionKind
        // Legacy keys for decoding old format
        case primaryStep, secondaryStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Int.self, forKey: .order)
        progressionKind = try container.decodeIfPresent(WeightProgressionKind.self, forKey: .progressionKind) ?? .higherIsBetter

        if let w = try container.decodeIfPresent([Double].self, forKey: .weights) {
            weights = w.filter { $0 > 0 }.sorted()
        } else {
            // Migrate from old format
            let primaryStep = try container.decodeIfPresent(Double.self, forKey: .primaryStep) ?? 5
            let secondaryStep = try container.decodeIfPresent(Double.self, forKey: .secondaryStep)

            if primaryStep == 0 {
                // Bodyweight
                weights = []
            } else if let secondary = secondaryStep {
                weights = Self.generateAlternating(primary: primaryStep, secondary: secondary, max: 200)
            } else {
                weights = Self.generateUniform(increment: primaryStep, max: 500)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(weights, forKey: .weights)
        try container.encode(order, forKey: .order)
        try container.encode(progressionKind, forKey: .progressionKind)
    }
}
