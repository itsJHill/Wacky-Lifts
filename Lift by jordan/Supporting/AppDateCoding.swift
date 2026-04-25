import Foundation

enum AppDateCoding {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private static let dateKeyFormatter: DateFormatter = {
        makeDateKeyFormatter()
    }()

    static func makeDateKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    static func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func date(fromKey key: String) -> Date? {
        dateKeyFormatter.date(from: key)
    }

    static func weekIdentifier(for date: Date) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    static func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfWeek(for date: Date) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    static func daysBetween(_ startDate: Date, and endDate: Date) -> Int {
        let start = startOfDay(for: startDate)
        let end = startOfDay(for: endDate)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func weeksBetween(_ startDate: Date, and endDate: Date) -> Int {
        guard let start = startOfWeek(for: startDate),
              let end = startOfWeek(for: endDate) else { return 0 }
        return calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? 0
    }
}
