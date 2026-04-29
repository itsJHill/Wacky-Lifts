import Foundation
import UIKit

struct Program: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var weeks: [ProgramWeek]
    var colorHex: String

    init(id: UUID = UUID(), name: String, weeks: [ProgramWeek] = [], colorHex: String = "#5856D6") {
        self.id = id
        self.name = name
        self.weeks = weeks
        self.colorHex = colorHex
    }

    var color: UIColor {
        UIColor(hex: colorHex) ?? .systemIndigo
    }

    static let presetColors: [(name: String, hex: String)] = [
        ("Indigo", "#5856D6"),
        ("Blue", "#007AFF"),
        ("Teal", "#5AC8FA"),
        ("Green", "#34C759"),
        ("Orange", "#FF9500"),
        ("Pink", "#FF2D55"),
        ("Purple", "#AF52DE"),
        ("Red", "#FF3B30"),
        ("Yellow", "#FFCC00"),
        ("Mint", "#00C7BE"),
    ]
}

extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

struct ProgramWeek: Hashable, Codable, Sendable {
    var weekNumber: Int
    var days: [ProgramDay]
    var notes: String

    init(weekNumber: Int, days: [ProgramDay] = [], notes: String = "") {
        self.weekNumber = weekNumber
        self.days = days
        self.notes = notes
    }
}

struct ProgramDay: Hashable, Codable, Sendable {
    let weekday: Weekday
    var workoutIds: [UUID]
}

struct ProgramCompletion: Hashable, Codable, Sendable {
    let programId: UUID
    let programName: String
    let startDate: Date
    let endDate: Date
    let totalWeeks: Int
}
