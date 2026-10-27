import Foundation
import Combine
import UserNotifications

/// Данные вкладки «Похудение»: вес, питание, энергобаланс и план тренировок.
@MainActor
final class LossStore: ObservableObject {
    @Published private(set) var weights: [WeightEntry] = []
    @Published private(set) var foods: [FoodEntry] = []
    @Published private(set) var plan: TrainingPlan?
    @Published private(set) var planChecks: [String: [String]] = [:]
    @Published private(set) var isGeneratingPlan = false
    @Published var planError: String?
    @Published var settings: LossSettings {
        didSet {
            guard settings != oldValue else { return }
            Storage.saveFile(settings, name: Files.settings)
            if settings.reminderEnabled != oldValue.reminderEnabled
                || settings.reminderHour != oldValue.reminderHour
                || settings.reminderMinute != oldValue.reminderMinute {
                Task { await updateReminder() }
            }
        }
    }

    let health: HealthDataStore
    private var foodCache: [String: FoodAnalysis]
    private var hiddenHealthWeights: [Double]
    private var cancellables = Set<AnyCancellable>()

    private enum Files {
        static let weights = "loss.weights.json"
        static let foods = "loss.foods.json"
        static let plan = "loss.plan.json"
        static let checks = "loss.checks.json"
        static let settings = "loss.settings.json"
        static let cache = "loss.foodcache.json"
        static let hidden = "loss.hidden.json"
    }

    init(health: HealthDataStore) {
        self.health = health
        weights = Storage.loadFile([WeightEntry].self, name: Files.weights) ?? []
        foods = Storage.loadFile([FoodEntry].self, name: Files.foods) ?? []
        plan = Storage.loadFile(TrainingPlan.self, name: Files.plan)
        planChecks = Storage.loadFile([String: [String]].self, name: Files.checks) ?? [:]
        settings = Storage.loadFile(LossSettings.self, name: Files.settings) ?? LossSettings()
        foodCache = Storage.loadFile([String: FoodAnalysis].self, name: Files.cache) ?? [:]
        hiddenHealthWeights = Storage.loadFile([Double].self, name: Files.hidden) ?? []

        // Вес из профиля → журнал веса (обратное направление — в addWeight).
        health.$profile
            .map(\.weightKg)
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] kg in
                Task { @MainActor in await self?.profileWeightChanged(kg) }
            }
            .store(in: &cancellables)

        // Анализ, прерванный закрытием приложения, продолжаем.
        for entry in foods where entry.status == .pending {
            Task { await analyze(entry.id) }
        }
    }

    // MARK: - Вес

    var sortedWeights: [WeightEntry] { weights.sorted { $0.date < $1.date } }
    var latestWeight: WeightEntry? { sortedWeights.last }

    func weightChange(days: Int) -> Double? {
        guard let latest = latestWeight,
              let from = Calendar.current.date(byAdding: .day, value: -days, to: latest.date) else { return nil }
        guard let past = sortedWeights.last(where: { $0.date <= from }) ?? sortedWeights.first, past.id != latest.id else { return nil }
        return latest.kg - past.kg
    }

    func addWeight(_ kg: Double, date: Date) async {
        let entry = WeightEntry(date: date, kg: (kg * 10).rounded() / 10, source: .app)
        weights.append(entry)
        saveWeights()
        if entry.id == latestWeight?.id {
            health.profile.weightKg = entry.kg
        }
        try? await HealthKitService.shared.requestAuthorization()
        await HealthKitService.shared.saveWeight(entry.kg, date: entry.date)
    }

    func deleteWeight(_ entry: WeightEntry) async {
        weights.removeAll { $0.id == entry.id }
        saveWeights()
        if entry.source == .health {
            hiddenHealthWeights.append(entry.date.timeIntervalSince1970)
            Storage.saveFile(hiddenHealthWeights, name: Files.hidden)
        } else {
            await HealthKitService.shared.deleteWeight(at: entry.date)
        }
        if let latest = latestWeight { health.profile.weightKg = latest.kg }
    }

    /// Подтягивает взвешивания из «Здоровья» (умные весы, другие приложения).
    func importHealthWeights() async {
        let samples = await HealthKitService.shared.weightHistory(days: 365)
        var changed = false
        for sample in samples {
            let isHidden = hiddenHealthWeights.contains { abs($0 - sample.start.timeIntervalSince1970) < 2 }
            let exists = weights.contains { abs($0.date.timeIntervalSince(sample.start)) < 120 && abs($0.kg - sample.value) < 0.15 }
            if !isHidden && !exists {
                weights.append(WeightEntry(date: sample.start, kg: (sample.value * 10).rounded() / 10, source: .health))
                changed = true
            }
        }
        if changed {
            saveWeights()
            if let latest = latestWeight, abs(latest.kg - health.profile.weightKg) >= 0.05 {
                health.profile.weightKg = latest.kg
            }
        }
    }

    /// Вес изменили в профиле — обновляем сегодняшнее взвешивание.
    private func profileWeightChanged(_ kg: Double) async {
        if let latest = latestWeight, abs(latest.kg - kg) < 0.05 { return }
        let calendar = Calendar.current
        if let index = weights.firstIndex(where: { $0.source == .profile && calendar.isDateInToday($0.date) }) {
            let old = weights[index]
            weights[index].kg = kg
            weights[index].date = Date()
            await HealthKitService.shared.deleteWeight(at: old.date)
        } else {
            weights.append(WeightEntry(date: Date(), kg: kg, source: .profile))
        }
        saveWeights()
        if let entry = weights.last(where: { $0.source == .profile }) {
            await HealthKitService.shared.saveWeight(entry.kg, date: entry.date)
        }
    }

    private func saveWeights() {
        Storage.saveFile(weights, name: Files.weights)
    }

    // MARK: - Питание

    func foods(on day: Date) -> [FoodEntry] {
        foods.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    func entry(_ id: UUID) -> FoodEntry? {
        foods.first { $0.id == id }
    }

    /// Недавние блюда — повторное добавление без запроса к ИИ.
    var recentFoods: [FoodEntry] {
        var seen = Set<String>()
        return foods.sorted { $0.date > $1.date }
            .filter { $0.status == .done && seen.insert($0.title.lowercased()).inserted }
            .prefix(8)
            .map { $0 }
    }

    func addFood(text: String, mode: FoodEntry.Mode, date: Date, manual: Nutrients? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = FoodEntry(date: date, text: trimmed, mode: mode, status: .pending)
        if mode == .manual || manual != nil {
            entry.mode = .manual
            entry.status = .done
            entry.analysis = FoodAnalysis(
                title: trimmed.isEmpty ? "Еда" : trimmed, brand: nil, portion: nil, items: [],
                total: manual ?? .zero, per100g: nil, details: [], confidence: nil, notes: nil,
                sources: [], model: nil, isManual: true)
        } else if let cached = foodCache[cacheKey(trimmed, mode)] {
            entry.status = .done
            entry.analysis = cached
        }
        foods.append(entry)
        saveFoods()
        if entry.status == .pending {
            Task { await analyze(entry.id) }
        }
    }

    func repeatFood(_ source: FoodEntry, date: Date = Date()) {
        var copy = source
        copy.id = UUID()
        copy.date = date
        foods.append(copy)
        saveFoods()
    }

    func analyze(_ id: UUID, force: Bool = false) async {
        guard let index = foods.firstIndex(where: { $0.id == id }) else { return }
        let entry = foods[index]
        guard entry.mode != .manual else { return }
        let key = cacheKey(entry.text, entry.mode)
        if !force, let cached = foodCache[key] {
            update(id) { $0.analysis = cached; $0.status = .done; $0.error = nil }
            return
        }
        update(id) { $0.status = .pending; $0.error = nil }
        do {
            let analysis = try await NutritionAI.analyzeFood(entry.text, mode: entry.mode)
            foodCache[key] = analysis
            Storage.saveFile(foodCache, name: Files.cache)
            update(id) { $0.analysis = analysis; $0.status = .done; $0.error = nil }
        } catch {
            update(id) { $0.status = .failed; $0.error = error.localizedDescription }
        }
    }

    func update(_ id: UUID, _ change: (inout FoodEntry) -> Void) {
        guard let index = foods.firstIndex(where: { $0.id == id }) else { return }
        change(&foods[index])
        saveFoods()
    }

    func deleteFood(_ id: UUID) {
        foods.removeAll { $0.id == id }
        saveFoods()
    }

    private func cacheKey(_ text: String, _ mode: FoodEntry.Mode) -> String {
        let normalized = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return mode.rawValue + "|" + normalized
    }

    private func saveFoods() {
        Storage.saveFile(foods, name: Files.foods)
    }

    // MARK: - Энергобаланс

    /// Базовый обмен по Миффлину — Сан Жеору, если часы не записали basal energy.
    var bmr: Double {
        let p = health.profile
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return base + (p.sex == .male ? 5 : -161)
    }

    func energy(for day: Date) -> EnergyDay {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let metrics = health.metrics(for: start)
        let eaten = foods(on: start).reduce(0) { $0 + $1.kcal }
        let active = metrics?.activeEnergy ?? 0
        var basal = metrics?.basalEnergy ?? 0
        var estimated = false
        let fraction = calendar.isDateInToday(start) ? clamp(Date().timeIntervalSince(start) / 86400, 0, 1) : 1
        if basal < bmr * fraction * 0.5 {
            basal = bmr * fraction
            estimated = true
        }
        return EnergyDay(day: start, eaten: eaten, active: active, basal: basal, basalEstimated: estimated, hasFood: !foods(on: start).isEmpty)
    }

    func energyDays(_ count: Int) -> [EnergyDay] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: today).map { energy(for: $0) }
        }
    }

    /// Средний полный расход за последние 7 завершённых дней.
    var averageBurn: Double {
        let past = energyDays(8).dropLast().filter { $0.active > 0 }
        guard !past.isEmpty else { return bmr * 1.35 }
        return past.reduce(0) { $0 + $1.burned } / Double(past.count)
    }

    /// Сколько можно съесть за день, чтобы держать выбранный дефицит.
    var dailyBudget: Double { max(1200, averageBurn - settings.dailyDeficit) }

    /// Прогноз расхода к концу сегодняшнего дня.
    var projectedBurnToday: Double {
        let today = energy(for: Date())
        return today.active + max(today.basal, bmr)
    }

    /// Ориентировочная дата достижения цели при выбранном дефиците.
    var goalDate: Date? {
        guard let goal = settings.goalWeight, let latest = latestWeight, latest.kg > goal, settings.dailyDeficit > 0 else { return nil }
        let days = (latest.kg - goal) * 7700 / settings.dailyDeficit
        return Calendar.current.date(byAdding: .day, value: Int(days.rounded(.up)), to: Date())
    }

    // MARK: - План тренировок

    var hasAIKeys: Bool { !GeminiKeys.all.isEmpty }

    func generatePlan() async {
        guard !isGeneratingPlan else { return }
        planError = nil
        guard hasAIKeys else {
            setPlan(NutritionAI.basicPlan())
            return
        }
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }
        let recent = Array(health.days.suffix(14))
        let context = NutritionAI.PlanContext(
            profile: health.profile,
            goalWeight: settings.goalWeight,
            averageRecovery: recent.compactMap(\.recovery).mean,
            workoutsPerWeek: Int((Double(recent.reduce(0) { $0 + $1.workouts.count }) / 2).rounded()),
            averageSteps: recent.map(\.steps).filter { $0 > 0 }.mean,
            wishes: settings.planWishes)
        do {
            setPlan(try await NutritionAI.trainingPlan(context))
        } catch {
            planError = error.localizedDescription
            if plan == nil { setPlan(NutritionAI.basicPlan()) }
        }
    }

    func useBasicPlan() {
        setPlan(NutritionAI.basicPlan())
    }

    private func setPlan(_ newPlan: TrainingPlan) {
        plan = newPlan
        Storage.saveFile(newPlan, name: Files.plan)
    }

    func isDone(_ exercise: PlanExercise, on day: Date) -> Bool {
        planChecks[JournalStore.key(for: day)]?.contains(exercise.id.uuidString) ?? false
    }

    func toggle(_ exercise: PlanExercise, on day: Date) {
        let key = JournalStore.key(for: day)
        var done = planChecks[key] ?? []
        if let index = done.firstIndex(of: exercise.id.uuidString) {
            done.remove(at: index)
        } else {
            done.append(exercise.id.uuidString)
        }
        planChecks[key] = done
        Storage.saveFile(planChecks, name: Files.checks)
    }

    // MARK: - Напоминание о взвешивании

    private static let reminderID = "pulsar.weighin"

    func updateReminder() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
        guard settings.reminderEnabled else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            settings.reminderEnabled = false
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Время взвеситься"
        content.body = "Запишите вес и проверьте баланс калорий за день."
        content.sound = .default
        var components = DateComponents()
        components.hour = settings.reminderHour
        components.minute = settings.reminderMinute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
    }
}
