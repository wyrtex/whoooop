import Foundation

enum Fmt {
    static let locale = Locale(identifier: "ru_RU")

    /// 7:05
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// 1:02:03 или 02:03 — для секундомера тренировки.
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// 7 ч 05 мин
    static func durationLong(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded())
        if minutes < 60 { return "\(minutes) мин" }
        return String(format: "%d ч %02d мин", minutes / 60, minutes % 60)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EE, d MMMM"
        return formatter.string(from: date).capitalized(with: locale)
    }

    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func number(_ value: Double?, digits: Int = 0) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    static func strain(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func distance(_ meters: Double?) -> String? {
        guard let meters, meters > 0 else { return nil }
        return meters >= 1000 ? String(format: "%.2f км", meters / 1000) : String(format: "%.0f м", meters)
    }

    static func signed(_ value: Double, digits: Int = 0) -> String {
        String(format: "%+.\(digits)f", value)
    }
}
