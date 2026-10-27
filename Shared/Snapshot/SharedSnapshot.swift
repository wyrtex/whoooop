import Foundation
import WidgetKit

/// Общий для приложения и виджетов снимок данных (App Group).
enum SharedSnapshot {
    private static let key = "snapshot.v1"
    private static let infoKey = "PulsarAppGroup"

    /// Группа берётся из Info.plist; запасной вариант — group.<bundle id основного приложения>.
    /// Это нужно, если при переподписи (Sideloadly/AltStore) идентификаторы поменялись.
    static var groupID: String? {
        var candidates: [String] = []
        if let fromInfo = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            candidates.append(fromInfo)
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            var base = bundleID
            for suffix in [".widgets", ".watchkitapp"] where base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
            }
            candidates.append("group." + base)
        }
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }

    private static var defaults: UserDefaults? {
        groupID.flatMap { UserDefaults(suiteName: $0) }
    }

    static func load() -> WatchSummary? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSummary.self, from: data)
    }

    /// Без App Group (например, при подписи через eSign) виджеты всё равно перезагрузятся
    /// и посчитают данные сами из HealthKit.
    static func save(_ summary: WatchSummary) {
        if let defaults, let data = try? JSONEncoder().encode(summary) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
