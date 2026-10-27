import Foundation

/// Восстановление 0–100 %. Сравнивает сегодняшние показатели с личной 30-дневной нормой
/// (z-оценки), главный вклад — ВСР, затем пульс покоя, дыхание, SpO₂, температура и сон.
enum RecoveryEngine {
    static let baselineWindow = 30

    enum Metric: String, CaseIterable, Identifiable {
        case hrv, restingHR, respiratoryRate, spo2, wristTemp, sleep

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hrv: return "Вариабельность пульса"
            case .restingHR: return "Пульс покоя"
            case .respiratoryRate: return "Частота дыхания"
            case .spo2: return "Кислород в крови"
            case .wristTemp: return "Температура кожи"
            case .sleep: return "Качество сна"
            }
        }

        var symbol: String {
            switch self {
            case .hrv: return "waveform.path.ecg"
            case .restingHR: return "heart.fill"
            case .respiratoryRate: return "lungs.fill"
            case .spo2: return "drop.fill"
            case .wristTemp: return "thermometer.medium"
            case .sleep: return "bed.double.fill"
            }
        }
    }

    struct Contribution: Identifiable {
        var metric: Metric
        /// Положительное значение — помогает восстановлению.
        var z: Double
        var weight: Double
        var id: String { metric.id }
    }

    static func baseline(_ values: [Double], minSD: Double, minCount: Int = 3) -> Baseline? {
        guard values.count >= minCount, let m = values.mean else { return nil }
        let sd = max(values.standardDeviation ?? minSD, minSD)
        return Baseline(mean: m, sd: sd, count: values.count)
    }

    static func baselines(history: [DailyVitals]) -> Baselines {
        let recent = Array(history.suffix(baselineWindow))
        return Baselines(
            hrvLn: baseline(recent.compactMap(\.hrv).filter { $0 > 0 }.map { log($0) }, minSD: 0.08),
            restingHR: baseline(recent.compactMap(\.restingHR), minSD: 1.5),
            respiratoryRate: baseline(recent.compactMap(\.respiratoryRate), minSD: 0.4),
            spo2: baseline(recent.compactMap(\.spo2), minSD: 0.8),
            wristTemp: baseline(recent.compactMap(\.wristTemp), minSD: 0.15)
        )
    }

    /// Популяционная норма SDNN для старта, пока нет личной нормы.
    static func populationHRV(age: Int) -> Double {
        max(20, 65 - 0.7 * Double(age - 20))
    }

    static func contributions(
        vitals: DailyVitals,
        baselines: Baselines,
        sleepPerformance: Double?,
        profile: UserProfile
    ) -> [Contribution] {
        var result: [Contribution] = []

        if let hrv = vitals.hrv, hrv > 0 {
            let b = baselines.hrvLn ?? Baseline(mean: log(populationHRV(age: profile.age)), sd: 0.35, count: 0)
            result.append(Contribution(metric: .hrv, z: clamp((log(hrv) - b.mean) / b.sd, -3, 3), weight: 0.55))
        }
        if let rhr = vitals.restingHR {
            let b = baselines.restingHR ?? Baseline(mean: 62, sd: 6, count: 0)
            result.append(Contribution(metric: .restingHR, z: clamp(-(rhr - b.mean) / b.sd, -3, 3), weight: 0.25))
        }
        if let resp = vitals.respiratoryRate, let b = baselines.respiratoryRate {
            // Отклонение в любую сторону — плохо. Типичное |z| ≈ 0.8, поэтому центрируем.
            result.append(Contribution(metric: .respiratoryRate, z: clamp(0.8 - abs(resp - b.mean) / b.sd, -3, 1), weight: 0.07))
        }
        if let spo2 = vitals.spo2, let b = baselines.spo2 {
            result.append(Contribution(metric: .spo2, z: clamp((spo2 - b.mean) / b.sd, -3, 1), weight: 0.05))
        }
        if let temp = vitals.wristTemp, let b = baselines.wristTemp {
            result.append(Contribution(metric: .wristTemp, z: clamp(0.8 - abs(temp - b.mean) / b.sd, -3, 1), weight: 0.08))
        }
        if let perf = sleepPerformance {
            result.append(Contribution(metric: .sleep, z: clamp((perf - 85) / 15, -3, 1), weight: 0.25))
        }
        return result
    }

    static func score(
        vitals: DailyVitals,
        baselines: Baselines,
        sleepPerformance: Double?,
        profile: UserProfile
    ) -> Double? {
        let parts = contributions(vitals: vitals, baselines: baselines, sleepPerformance: sleepPerformance, profile: profile)
        let physiological = parts.filter { $0.metric != .sleep }
        guard physiological.contains(where: { $0.metric == .hrv || $0.metric == .restingHR }) else { return nil }

        let weightSum = physiological.reduce(0) { $0 + $1.weight }
        var s = physiological.reduce(0) { $0 + $1.z * $1.weight } / weightSum
        if let sleep = parts.first(where: { $0.metric == .sleep }) {
            s += sleep.z * sleep.weight
        }
        let recovery = 100 / (1 + exp(-(1.5 * s + 0.3)))
        return clamp(recovery, 1, 99)
    }
}
