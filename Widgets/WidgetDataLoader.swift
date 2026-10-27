import Foundation
import AppIntents
import WidgetKit

/// Виджет не зависит от приложения: сам читает HealthKit (данные Apple Watch уже лежат в «Здоровье»),
/// считает сводку тем же движком и хранит последний результат в своём контейнере.
/// Когда HealthKit недоступен (телефон заблокирован), показывается последняя известная сводка.
enum WidgetDataLoader {
    private static let cacheKey = "widget.snapshot.v1"
    /// Сколько дней истории нужно для личных норм восстановления.
    private static let historyDays = 30

    /// Последняя известная сводка: собственный кэш виджета или сводка приложения из App Group.
    static func cached() -> WatchSummary? {
        let own = UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WatchSummary.self, from: $0) }
        return [own, SharedSnapshot.load()].compactMap { $0 }.max { $0.generatedAt < $1.generatedAt }
    }

    /// Свежая сводка; если кэш моложе `maxAge`, HealthKit не трогаем.
    static func load(maxAge: TimeInterval = 60) async -> WatchSummary? {
        if let cached = cached(), Date().timeIntervalSince(cached.generatedAt) < maxAge {
            return cached
        }
        return await Coordinator.shared.refresh() ?? cached()
    }

    fileprivate static func compute() async -> WatchSummary? {
        let health = HealthKitService.shared
        guard health.isAvailable else { return nil }
        let raw = await health.fetchRaw(days: historyDays, heartRateDays: 2)
        // Пустой ответ — признак заблокированного устройства или отсутствия доступа.
        guard !raw.heartRate.isEmpty || !raw.sleep.isEmpty || !raw.hrv.isEmpty else { return nil }

        let profile = await resolveProfile()
        let days = MetricsBuilder.build(raw: raw, profile: profile, dayCount: historyDays)
        guard let today = days.last else { return nil }
        let summary = WatchSummary.make(from: today, profile: profile, history: days)
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        return summary
    }

    /// Профиль из приложения, если App Group работает, иначе из характеристик «Здоровья».
    private static func resolveProfile() async -> UserProfile {
        if let profile = cached()?.profile { return profile }
        var profile = UserProfile()
        let hints = await HealthKitService.shared.profileHints()
        if let age = hints.age, age > 10 { profile.age = age }
        if let sex = hints.sex { profile.sex = sex }
        if let weight = hints.weightKg { profile.weightKg = weight }
        if let height = hints.heightCm { profile.heightCm = height }
        return profile
    }

    /// Все виджеты перезагружаются одновременно — считаем один раз и делимся результатом.
    private actor Coordinator {
        static let shared = Coordinator()
        private var running: Task<WatchSummary?, Never>?

        func refresh() async -> WatchSummary? {
            if let running { return await running.value }
            let task = Task { await WidgetDataLoader.compute() }
            running = task
            let result = await task.value
            running = nil
            return result
        }
    }
}

/// Кнопка «Обновить» в виджете: пересчитывает данные, не открывая приложение.
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Обновить данные Pulsar"
    static var description = IntentDescription("Заново читает данные Apple Watch из «Здоровья» и обновляет виджеты.")
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        _ = await WidgetDataLoader.load(maxAge: 0)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
