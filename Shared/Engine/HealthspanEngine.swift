import Foundation

/// Биологический возраст: хронологический возраст плюс поправки за привычки и физиологию
/// (МПК, пульс покоя, ВСР, сон, регулярность, шаги, кардио-минуты).
enum HealthspanEngine {
    struct Factor: Identifiable, Hashable {
        var name: String
        var symbol: String
        var detail: String
        /// Положительное значение старит, отрицательное — молодит.
        var years: Double
        var id: String { name }
    }

    struct Result {
        var chronological: Double
        var biological: Double
        var factors: [Factor]
        /// Изменение биовозраста относительно предыдущих 30 дней.
        var trend: Double?
    }

    static func compute(days: [DayMetrics], profile: UserProfile) -> Result? {
        guard !days.isEmpty else { return nil }
        let recent = Array(days.suffix(30))
        guard let current = evaluate(recent, profile: profile) else { return nil }

        var trend: Double?
        if days.count >= 45, let older = evaluate(Array(days.dropLast(30).suffix(30)), profile: profile) {
            trend = sum(current) - sum(older)
        }
        let age = Double(profile.age)
        return Result(chronological: age, biological: max(14, age + sum(current)), factors: current, trend: trend)
    }

    private static func sum(_ factors: [Factor]) -> Double {
        factors.reduce(0) { $0 + $1.years }
    }

    private static func evaluate(_ days: [DayMetrics], profile: UserProfile) -> [Factor]? {
        let age = Double(profile.age)
        var factors: [Factor] = []

        if let vo2 = days.compactMap(\.vo2max).last {
            let norm = profile.sex == .male ? 47 - 0.35 * (age - 20) : 40 - 0.3 * (age - 20)
            let years = clamp((norm - vo2) * 0.35, -6, 6)
            factors.append(Factor(name: "МПК (VO₂max)", symbol: "lungs.fill", detail: String(format: "%.1f мл/кг/мин, норма %.0f", vo2, norm), years: years))
        }
        if let rhr = days.compactMap(\.vitals.restingHR).mean {
            let years = clamp((rhr - 62) * 0.15, -3, 3)
            factors.append(Factor(name: "Пульс покоя", symbol: "heart.fill", detail: String(format: "%.0f уд/мин в среднем", rhr), years: years))
        }
        if let hrv = days.compactMap(\.vitals.hrv).mean, hrv > 0 {
            let norm = RecoveryEngine.populationHRV(age: profile.age)
            let years = clamp((log(norm) - log(hrv)) * 4, -3, 3)
            factors.append(Factor(name: "Вариабельность пульса", symbol: "waveform.path.ecg", detail: String(format: "%.0f мс, норма для возраста %.0f", hrv, norm), years: years))
        }
        let sleepHours = days.compactMap { $0.sleep.map { $0.asleep / 3600 } }
        if let hours = sleepHours.mean {
            let years = clamp(abs(hours - 7.5) * 1.0 - 0.3, -0.5, 2.5)
            factors.append(Factor(name: "Продолжительность сна", symbol: "bed.double.fill", detail: String(format: "%.1f ч за ночь", hours), years: years))
        }
        if let consistency = days.compactMap(\.sleepConsistency).mean {
            let years = clamp((75 - consistency) / 10 * 0.5, -1.5, 1.5)
            factors.append(Factor(name: "Регулярность сна", symbol: "clock.fill", detail: String(format: "%.0f %%", consistency), years: years))
        }
        let steps = days.map(\.steps).filter { $0 > 0 }
        if let avgSteps = steps.mean {
            let years = clamp((8000 - avgSteps) / 2000 * 0.4, -2, 2)
            factors.append(Factor(name: "Шаги", symbol: "figure.walk", detail: String(format: "%.0f в день", avgSteps), years: years))
        }
        let weeks = max(1, Double(days.count) / 7)
        let cardioMinutes = days.reduce(0) { $0 + $1.zoneSeconds.dropFirst(2).reduce(0, +) } / 60 / weeks
        if days.contains(where: { !$0.heartRate.isEmpty }) {
            let years = clamp((150 - cardioMinutes) / 50 * 0.4, -2, 2)
            factors.append(Factor(name: "Кардио (зоны 2–5)", symbol: "flame.fill", detail: String(format: "%.0f мин в неделю", cardioMinutes), years: years))
        }
        return factors.isEmpty ? nil : factors
    }
}
