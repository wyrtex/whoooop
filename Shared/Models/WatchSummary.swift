import Foundation

/// Короткая сводка дня: её получают часы и читают виджеты.
struct WatchSummary: Codable, Equatable {
    var generatedAt: Date
    var day: Date
    var recovery: Double?
    var strain: Double
    var strainTargetLow: Double
    var strainTargetHigh: Double
    var sleepPerformance: Double?
    var sleepAsleep: TimeInterval?
    var sleepNeed: TimeInterval?
    var sleepStages: [Double]?
    var hrv: Double?
    var hrvBaseline: Double?
    var restingHR: Double?
    var restingHRBaseline: Double?
    var respiratoryRate: Double?
    var spo2: Double?
    var stress: Double?
    var calories: Double
    var steps: Double
    var insightTitle: String?
    var insightBody: String?
    var profile: UserProfile

    static func make(from day: DayMetrics, profile: UserProfile, history: [DayMetrics] = []) -> WatchSummary {
        let target = StrainEngine.target(forRecovery: day.recovery)
        let insight = CoachEngine.insights(for: day, history: history, profile: profile).first
        return WatchSummary(
            generatedAt: Date(),
            day: day.day,
            recovery: day.recovery,
            strain: day.strain,
            strainTargetLow: target.lowerBound,
            strainTargetHigh: target.upperBound,
            sleepPerformance: day.sleepPerformance,
            sleepAsleep: day.sleep?.asleep,
            sleepNeed: day.sleepNeed?.total,
            sleepStages: day.sleep.map { session in SleepStage.allCases.map { session.time(in: $0) } },
            hrv: day.vitals.hrv,
            hrvBaseline: day.baselines.hrvMean,
            restingHR: day.vitals.restingHR,
            restingHRBaseline: day.baselines.restingHR?.mean,
            respiratoryRate: day.vitals.respiratoryRate,
            spo2: day.vitals.spo2,
            stress: day.currentStress,
            calories: day.totalEnergy,
            steps: day.steps,
            insightTitle: insight?.title,
            insightBody: insight?.body,
            profile: profile)
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// Данные дня закончились — нагрузку и стресс показываем как устаревшие.
    var isStale: Bool { !isToday }

    static let sample = WatchSummary(
        generatedAt: Date(), day: Calendar.current.startOfDay(for: Date()),
        recovery: 72, strain: 11.4, strainTargetLow: 12.3, strainTargetHigh: 15.3,
        sleepPerformance: 88, sleepAsleep: 7.2 * 3600, sleepNeed: 8.1 * 3600,
        sleepStages: [0.4 * 3600, 1.7 * 3600, 3.9 * 3600, 1.6 * 3600],
        hrv: 58, hrvBaseline: 52, restingHR: 54, restingHRBaseline: 56,
        respiratoryRate: 14.6, spo2: 97.2, stress: 0.8, calories: 2350, steps: 8400,
        insightTitle: "Организм готов к нагрузке",
        insightBody: "Хороший день для интенсивной тренировки.",
        profile: UserProfile())
}
