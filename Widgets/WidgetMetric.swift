import SwiftUI
import AppIntents

/// Показатель, который можно вывести в виджет.
enum WidgetMetric: String, AppEnum, CaseIterable {
    case recovery, strain, sleep, sleepHours, hrv, restingHR, respiratoryRate, spo2, stress, calories, steps

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Показатель"

    static var caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .recovery: "Восстановление",
        .strain: "Нагрузка",
        .sleep: "Качество сна",
        .sleepHours: "Часы сна",
        .hrv: "Вариабельность пульса",
        .restingHR: "Пульс покоя",
        .respiratoryRate: "Частота дыхания",
        .spo2: "Кислород в крови",
        .stress: "Стресс",
        .calories: "Калории",
        .steps: "Шаги",
    ]

    var title: String {
        switch self {
        case .recovery: return "Восстановление"
        case .strain: return "Нагрузка"
        case .sleep: return "Сон"
        case .sleepHours: return "Часы сна"
        case .hrv: return "ВСР"
        case .restingHR: return "Пульс покоя"
        case .respiratoryRate: return "Дыхание"
        case .spo2: return "SpO₂"
        case .stress: return "Стресс"
        case .calories: return "Калории"
        case .steps: return "Шаги"
        }
    }

    var shortTitle: String {
        switch self {
        case .recovery: return "ВОССТ"
        case .strain: return "НАГР"
        case .sleep: return "СОН"
        case .sleepHours: return "СОН"
        case .hrv: return "ВСР"
        case .restingHR: return "ПП"
        case .respiratoryRate: return "ДЫХ"
        case .spo2: return "SpO₂"
        case .stress: return "СТРЕСС"
        case .calories: return "ККАЛ"
        case .steps: return "ШАГИ"
        }
    }

    var symbol: String {
        switch self {
        case .recovery: return "bolt.heart.fill"
        case .strain: return "flame.fill"
        case .sleep, .sleepHours: return "moon.fill"
        case .hrv: return "waveform.path.ecg"
        case .restingHR: return "heart.fill"
        case .respiratoryRate: return "lungs.fill"
        case .spo2: return "drop.fill"
        case .stress: return "brain.head.profile"
        case .calories: return "flame"
        case .steps: return "figure.walk"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .sleep, .spo2: return "%"
        case .hrv: return "мс"
        case .restingHR: return "уд/мин"
        case .respiratoryRate: return "вд/мин"
        case .calories: return "ккал"
        default: return ""
        }
    }

    func rawValue(_ s: WatchSummary) -> Double? {
        switch self {
        case .recovery: return s.recovery
        case .strain: return s.strain
        case .sleep: return s.sleepPerformance
        case .sleepHours: return s.sleepAsleep
        case .hrv: return s.hrv
        case .restingHR: return s.restingHR
        case .respiratoryRate: return s.respiratoryRate
        case .spo2: return s.spo2
        case .stress: return s.stress
        case .calories: return s.calories > 0 ? s.calories : nil
        case .steps: return s.steps > 0 ? s.steps : nil
        }
    }

    /// Значение без единиц — для колец и компактных мест.
    func value(_ s: WatchSummary?) -> String {
        guard let s, let v = rawValue(s) else { return "—" }
        switch self {
        case .strain: return Fmt.strain(v)
        case .sleepHours: return Fmt.duration(v)
        case .respiratoryRate, .stress: return Fmt.number(v, digits: 1)
        case .steps: return v >= 1000 ? String(format: "%.1fk", v / 1000) : Fmt.number(v)
        default: return Fmt.number(v)
        }
    }

    /// Значение с единицами для подписей.
    func valueWithUnit(_ s: WatchSummary?) -> String {
        let text = value(s)
        guard text != "—" else { return text }
        switch self {
        case .recovery, .sleep, .spo2: return text + "%"
        case .hrv, .restingHR, .calories: return text + " " + unit
        default: return text
        }
    }

    func progress(_ s: WatchSummary?) -> Double {
        guard let s, let v = rawValue(s) else { return 0 }
        let p: Double
        switch self {
        case .recovery, .sleep: p = v / 100
        case .strain: p = v / StrainEngine.maxStrain
        case .sleepHours: p = v / max(s.sleepNeed ?? 8 * 3600, 1)
        case .hrv: p = v / 120
        case .restingHR: p = (v - 30) / 70
        case .respiratoryRate: p = (v - 8) / 16
        case .spo2: p = (v - 85) / 15
        case .stress: p = v / 3
        case .calories: p = v / 3500
        case .steps: p = v / 10000
        }
        return clamp(p, 0, 1)
    }

    func color(_ s: WatchSummary?) -> Color {
        switch self {
        case .recovery: return Theme.recoveryColor(s?.recovery)
        case .strain: return Theme.strain
        case .sleep, .sleepHours: return Theme.sleep
        case .hrv: return Theme.recoveryGreen
        case .restingHR: return Theme.heart
        case .respiratoryRate: return Theme.strain
        case .spo2: return Theme.recoveryRed
        case .stress: return Theme.stressColor(s?.stress ?? 0)
        case .calories: return Theme.stress
        case .steps: return Theme.recoveryYellow
        }
    }

    /// Пояснение под значением.
    func detail(_ s: WatchSummary?) -> String {
        guard let s else { return "Откройте Pulsar" }
        switch self {
        case .recovery:
            return s.recovery.map { RecoveryBand($0).title } ?? "Нет данных за ночь"
        case .strain:
            return "Цель \(Fmt.number(s.strainTargetLow))–\(Fmt.number(s.strainTargetHigh))"
        case .sleep:
            guard let asleep = s.sleepAsleep else { return "Нет данных о сне" }
            return "\(Fmt.duration(asleep)) из \(Fmt.duration(s.sleepNeed ?? asleep))"
        case .sleepHours:
            return s.sleepNeed.map { "Нужно \(Fmt.duration($0))" } ?? "Потребность"
        case .hrv:
            return s.hrvBaseline.map { "Норма \(Fmt.number($0)) мс" } ?? "За ночь"
        case .restingHR:
            return s.restingHRBaseline.map { "Норма \(Fmt.number($0))" } ?? "За ночь"
        case .stress:
            return s.stress.map { StressEngine.title($0) } ?? "Нет данных"
        default:
            return title
        }
    }
}
