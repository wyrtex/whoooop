import Foundation

/// Монитор стресса 0–3: насколько пульс в покое выше личного пульса покоя.
/// Тренировки и сон исключаются, чтобы не путать физическую нагрузку со стрессом.
enum StressEngine {
    static let bucket: TimeInterval = 15 * 60

    static func level(bpm: Double, restingHR: Double, maxHR: Double) -> Double {
        let range = max(15, 0.3 * (maxHR - restingHR))
        return clamp((bpm - restingHR - 3) / range * 3, 0, 3)
    }

    static func timeline(
        samples: [HRSample],
        dayStart: Date,
        dayEnd: Date,
        restingHR: Double,
        maxHR: Double,
        excluding: [DateInterval]
    ) -> [StressPoint] {
        var sums: [Int: (Double, Int)] = [:]
        for sample in samples where sample.date >= dayStart && sample.date < dayEnd {
            if excluding.contains(where: { $0.contains(sample.date) }) { continue }
            let index = Int(sample.date.timeIntervalSince(dayStart) / bucket)
            let current = sums[index] ?? (0, 0)
            sums[index] = (current.0 + sample.bpm, current.1 + 1)
        }
        return sums.keys.sorted().map { index in
            let (sum, count) = sums[index]!
            let date = dayStart.addingTimeInterval(Double(index) * bucket + bucket / 2)
            return StressPoint(date: date, level: level(bpm: sum / Double(count), restingHR: restingHR, maxHR: maxHR))
        }
    }

    static func title(_ level: Double) -> String {
        switch level {
        case ..<1: return "Низкий"
        case ..<2: return "Средний"
        default: return "Высокий"
        }
    }

    /// Доля времени в низком / среднем / высоком стрессе.
    static func distribution(_ points: [StressPoint]) -> [Double] {
        guard !points.isEmpty else { return [0, 0, 0] }
        var counts = [0.0, 0.0, 0.0]
        for point in points { counts[min(2, Int(point.level))] += 1 }
        return counts.map { $0 / Double(points.count) }
    }
}
