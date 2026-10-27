import Foundation

enum SleepEngine {
    /// Разрыв между сегментами, после которого начинается новая сессия сна.
    static let sessionGap: TimeInterval = 45 * 60

    static func sessions(from segments: [SleepSegment]) -> [SleepSession] {
        let sorted = segments.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var result: [SleepSession] = []
        var current: [SleepSegment] = []
        var currentEnd = Date.distantPast

        for segment in sorted {
            if !current.isEmpty, segment.start.timeIntervalSince(currentEnd) > sessionGap {
                result.append(makeSession(current))
                current = []
            }
            current.append(segment)
            currentEnd = max(currentEnd, segment.end)
        }
        if !current.isEmpty { result.append(makeSession(current)) }
        return result.filter { $0.asleep >= 10 * 60 }
    }

    private static func makeSession(_ segments: [SleepSegment]) -> SleepSession {
        let start = segments.map(\.start).min() ?? Date()
        let end = segments.map(\.end).max() ?? start
        return SleepSession(start: start, end: end, segments: removeOverlaps(segments))
    }

    /// Если источники пересекаются, оставляем сегмент, начавшийся раньше.
    private static func removeOverlaps(_ segments: [SleepSegment]) -> [SleepSegment] {
        var result: [SleepSegment] = []
        for var segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, segment.start < last.end {
                segment.start = last.end
            }
            if segment.end > segment.start { result.append(segment) }
        }
        return result
    }

    /// Сон относится к дню, в который человек проснулся (с запасом до 18:00 → следующий день).
    static func dayKey(for session: SleepSession, calendar: Calendar) -> Date {
        calendar.startOfDay(for: session.end.addingTimeInterval(6 * 3600))
    }

    static func need(
        baselineHours: Double,
        previousStrain: Double?,
        recentDeficits: [TimeInterval],
        napsAsleep: TimeInterval
    ) -> SleepNeed {
        let baseline = baselineHours * 3600
        let strainExtra: TimeInterval
        if let strain = previousStrain, strain > 8 {
            strainExtra = min(45 * 60, (strain - 8) / 13 * 45 * 60)
        } else {
            strainExtra = 0
        }
        let weights = [0.5, 0.25, 0.15]
        var debt = 0.0
        for (index, deficit) in recentDeficits.prefix(weights.count).enumerated() {
            debt += max(0, deficit) * weights[index]
        }
        return SleepNeed(
            baseline: baseline,
            strain: strainExtra,
            debt: min(debt, 2 * 3600),
            naps: min(napsAsleep, 90 * 60)
        )
    }

    static func performance(asleep: TimeInterval, need: TimeInterval) -> Double {
        guard need > 0 else { return 0 }
        return clamp(asleep / need * 100, 0, 100)
    }

    /// Регулярность: насколько стабильно время засыпания и пробуждения (последние 4 ночи).
    static func consistency(_ nights: [(day: Date, session: SleepSession)]) -> Double? {
        let recent = nights.suffix(4)
        guard recent.count >= 2 else { return nil }
        var onsets: [Double] = []
        var wakes: [Double] = []
        for night in recent {
            let reference = night.day.addingTimeInterval(-6 * 3600)
            onsets.append(night.session.start.timeIntervalSince(reference) / 60)
            wakes.append(night.session.end.timeIntervalSince(reference) / 60)
        }
        let sd = ((onsets.standardDeviation ?? 0) + (wakes.standardDeviation ?? 0)) / 2
        return clamp(100 - sd * 0.8, 0, 100)
    }

    struct PlanOption: Identifiable {
        var title: String
        var fraction: Double
        var bedtime: Date
        var sleepDuration: TimeInterval
        var id: String { title }
    }

    static func plan(need: TimeInterval, efficiency: Double, wake: Date) -> [PlanOption] {
        let eff = clamp(efficiency, 0.75, 0.97)
        let options: [(String, Double)] = [("Пик", 1.0), ("Норма", 0.85), ("Минимум", 0.7)]
        return options.map { title, fraction in
            let sleep = need * fraction
            return PlanOption(title: title, fraction: fraction, bedtime: wake.addingTimeInterval(-(sleep / eff + 15 * 60)), sleepDuration: sleep)
        }
    }
}
