import Foundation
import SwiftUI

/// Главное хранилище: грузит данные из HealthKit, считает метрики и кэширует их на диск.
@MainActor
final class HealthDataStore: ObservableObject {
    @Published private(set) var days: [DayMetrics] = []
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published var lastError: String?
    @Published var profile: UserProfile {
        didSet {
            guard oldValue != profile else { return }
            Storage.save(profile, key: Storage.profileKey)
            Task { await rebuild() }
        }
    }
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: Storage.onboardedKey) }
    }

    let historyDays: Int
    private var lastRaw: RawHealthData?

    init(historyDays: Int = 60) {
        self.historyDays = historyDays
        self.profile = Storage.load(UserProfile.self, key: Storage.profileKey) ?? UserProfile()
        self.hasOnboarded = UserDefaults.standard.bool(forKey: Storage.onboardedKey)
        if let cached = Storage.loadFile([DayMetrics].self, name: Storage.cacheFile) {
            self.days = cached
            self.lastUpdated = cached.isEmpty ? nil : Storage.fileDate(name: Storage.cacheFile)
        }
    }

    // MARK: - Доступ

    var today: DayMetrics? { days.last }

    var selected: DayMetrics? { metrics(for: selectedDay) ?? today }

    func metrics(for day: Date) -> DayMetrics? {
        let key = Calendar.current.startOfDay(for: day)
        return days.last { $0.day == key }
    }

    func previous(of day: DayMetrics) -> DayMetrics? {
        guard let index = days.firstIndex(of: day), index > 0 else { return nil }
        return days[index - 1]
    }

    func history(upTo day: Date, count: Int) -> [DayMetrics] {
        Array(days.filter { $0.day <= day }.suffix(count))
    }

    var canSelectPrevious: Bool {
        guard let first = days.first else { return false }
        return selectedDay > first.day
    }

    var canSelectNext: Bool {
        selectedDay < Calendar.current.startOfDay(for: Date())
    }

    func shiftSelection(by value: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: value, to: selectedDay) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if date > today { return }
        if let first = days.first, date < first.day { return }
        selectedDay = date
    }

    // MARK: - Загрузка

    func connectHealth() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
        } catch {
            lastError = error.localizedDescription
        }
        let hints = await HealthKitService.shared.profileHints()
        var updated = profile
        if let age = hints.age, age > 10 { updated.age = age }
        if let sex = hints.sex { updated.sex = sex }
        if let weight = hints.weightKg { updated.weightKg = (weight * 10).rounded() / 10 }
        if let height = hints.heightCm { updated.heightCm = height.rounded() }
        hasOnboarded = true
        if updated != profile {
            profile = updated
        }
        await refresh()
    }

    func refresh() async {
        guard HealthKitService.shared.isAvailable else {
            lastError = "Apple Health недоступен на этом устройстве"
            return
        }
        guard !isLoading else { return }
        isLoading = true
        lastRaw = await HealthKitService.shared.fetchRaw(days: historyDays)
        await rebuild()
        isLoading = false
    }

    private func rebuild() async {
        guard let raw = lastRaw else { return }
        let profile = self.profile
        let count = historyDays
        let built = await Task.detached(priority: .userInitiated) {
            MetricsBuilder.build(raw: raw, profile: profile, dayCount: count)
        }.value
        days = built
        lastUpdated = Date()
        selectedDay = min(selectedDay, Calendar.current.startOfDay(for: Date()))
        Storage.saveFile(built, name: Storage.cacheFile)
        #if os(iOS)
        if let today = built.last {
            SyncBridge.shared.send(WatchSummary.make(from: today, profile: profile))
        }
        #endif
    }

    /// Используется часами, когда профиль пришёл с iPhone.
    func applyRemoteProfile(_ remote: UserProfile) {
        if remote != profile { profile = remote }
    }
}

enum Storage {
    static let profileKey = "profile.v1"
    static let onboardedKey = "hasOnboarded"
    static let cacheFile = "days.v1.json"

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func url(_ name: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    static func saveFile<T: Encodable>(_ value: T, name: String) {
        guard let url = url(name) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func loadFile<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func fileDate(name: String) -> Date? {
        guard let url = url(name) else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
