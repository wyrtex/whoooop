import Foundation

enum BiologicalSexOption: String, Codable, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }
    var title: String { self == .male ? "Мужской" : "Женский" }
}

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var age: Int = 30
    var sex: BiologicalSexOption = .male
    var weightKg: Double = 75
    var heightCm: Double = 178
    var maxHROverride: Int? = nil
    var sleepNeedHours: Double = 7.75
    var wakeHour: Int = 7
    var wakeMinute: Int = 0

    /// Формула Танаки: 208 − 0.7 × возраст.
    var estimatedMaxHR: Double { 208 - 0.7 * Double(age) }
    var maxHR: Double { maxHROverride.map(Double.init) ?? estimatedMaxHR }
}

struct HRSample: Codable, Hashable {
    var date: Date
    var bpm: Double
}

struct ValueSample: Codable, Hashable {
    var start: Date
    var end: Date
    var value: Double
}

struct StressPoint: Codable, Hashable, Identifiable {
    var date: Date
    var level: Double
    var id: Date { date }
}

struct StrainPoint: Codable, Hashable, Identifiable {
    var date: Date
    var strain: Double
    var id: Date { date }
}

enum SleepStage: String, Codable, CaseIterable, Identifiable {
    case awake, rem, light, deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake: return "Бодрствование"
        case .rem: return "REM"
        case .light: return "Лёгкий"
        case .deep: return "Глубокий"
        }
    }

    var shortTitle: String {
        switch self {
        case .awake: return "Бодр."
        case .rem: return "REM"
        case .light: return "Лёгк."
        case .deep: return "Глуб."
        }
    }
}

struct SleepSegment: Codable, Hashable {
    var start: Date
    var end: Date
    var stage: SleepStage

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepSession: Codable, Hashable {
    var start: Date
    var end: Date
    var segments: [SleepSegment]

    var inBed: TimeInterval { end.timeIntervalSince(start) }

    func time(in stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var asleep: TimeInterval {
        segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
    }

    var awake: TimeInterval { max(0, inBed - asleep) }
    var efficiency: Double { inBed > 0 ? asleep / inBed : 0 }
    var restorative: TimeInterval { time(in: .deep) + time(in: .rem) }
    var restorativeShare: Double { asleep > 0 ? restorative / asleep : 0 }

    /// Количество пробуждений длиннее двух минут.
    var disturbances: Int {
        segments.filter { $0.stage == .awake && $0.duration >= 120 }.count
    }

    var latency: TimeInterval {
        guard let firstSleep = segments.first(where: { $0.stage != .awake }) else { return 0 }
        return max(0, firstSleep.start.timeIntervalSince(start))
    }

    var hasStages: Bool {
        segments.contains { $0.stage == .deep || $0.stage == .rem }
    }

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
}

struct SleepNeed: Codable, Hashable {
    var baseline: TimeInterval
    var strain: TimeInterval
    var debt: TimeInterval
    var naps: TimeInterval

    var total: TimeInterval { max(4 * 3600, baseline + strain + debt - naps) }
}

struct WorkoutSummary: Codable, Hashable, Identifiable {
    var id: UUID
    var activityRaw: UInt
    var name: String
    var symbol: String
    var start: Date
    var end: Date
    var energyKcal: Double?
    var distanceMeters: Double?
    var avgHR: Double?
    var maxHR: Double?
    var strain: Double
    var zoneSeconds: [Double]

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct DailyVitals: Codable, Hashable {
    /// ВСР (SDNN), мс.
    var hrv: Double?
    var restingHR: Double?
    var respiratoryRate: Double?
    /// Сатурация, %.
    var spo2: Double?
    /// Температура запястья во сне, °C.
    var wristTemp: Double?
}

struct Baseline: Codable, Hashable {
    var mean: Double
    var sd: Double
    var count: Int
}

struct Baselines: Codable, Hashable {
    /// Хранится в логарифмической шкале (ln мс).
    var hrvLn: Baseline?
    var restingHR: Baseline?
    var respiratoryRate: Baseline?
    var spo2: Baseline?
    var wristTemp: Baseline?

    var hrvMean: Double? { hrvLn.map { exp($0.mean) } }
}

enum RecoveryBand {
    case green, yellow, red

    init(_ score: Double) {
        if score >= 67 { self = .green } else if score >= 34 { self = .yellow } else { self = .red }
    }

    var title: String {
        switch self {
        case .green: return "Высокое"
        case .yellow: return "Среднее"
        case .red: return "Низкое"
        }
    }
}

struct DayMetrics: Codable, Hashable, Identifiable {
    var day: Date
    var vitals: DailyVitals
    var baselines: Baselines
    var sleep: SleepSession?
    var naps: [SleepSession]
    var sleepNeed: SleepNeed?
    var sleepPerformance: Double?
    var sleepConsistency: Double?
    var recovery: Double?
    var strain: Double
    var strainTimeline: [StrainPoint]
    var zoneSeconds: [Double]
    var workouts: [WorkoutSummary]
    var activeEnergy: Double
    var basalEnergy: Double
    var steps: Double
    var vo2max: Double?
    var stress: [StressPoint]
    var heartRate: [HRSample]
    var avgHR: Double?

    var id: Date { day }
    var totalEnergy: Double { activeEnergy + basalEnergy }
    var recoveryBand: RecoveryBand? { recovery.map(RecoveryBand.init) }
    var currentStress: Double? { stress.last?.level }
}
