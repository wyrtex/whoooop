import Foundation

struct SourcedSleepSegment {
    var sourceID: String
    var isWatch: Bool
    var isInBed: Bool
    var segment: SleepSegment
}

struct RawWorkout {
    var id: UUID
    var activityRaw: UInt
    var name: String
    var symbol: String
    var start: Date
    var end: Date
    var energyKcal: Double?
    var distanceMeters: Double?
}

/// Сырые данные из HealthKit без зависимости от фреймворка — их можно тестировать отдельно.
struct RawHealthData {
    var heartRate: [HRSample] = []
    var restingHR: [Date: Double] = [:]
    var hrv: [ValueSample] = []
    var respiratoryRate: [ValueSample] = []
    var spo2: [ValueSample] = []
    var wristTemp: [ValueSample] = []
    var sleep: [SourcedSleepSegment] = []
    var workouts: [RawWorkout] = []
    var activeEnergy: [Date: Double] = [:]
    var basalEnergy: [Date: Double] = [:]
    var steps: [Date: Double] = [:]
    var vo2max: [ValueSample] = []
}

enum MetricsBuilder {
    static func build(
        raw: RawHealthData,
        profile: UserProfile,
        dayCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayMetrics] {
        let today = calendar.startOfDay(for: now)
        let dayStarts: [Date] = (0..<dayCount).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        let sleepByDay = assignSleep(raw.sleep, calendar: calendar)
        let heartRate = raw.heartRate.sorted { $0.date < $1.date }
        let vo2 = raw.vo2max.sorted { $0.end < $1.end }
        let maxHR = profile.maxHR

        var result: [DayMetrics] = []
        var vitalsHistory: [DailyVitals] = []
        var nights: [(day: Date, session: SleepSession)] = []

        for dayStart in dayStarts {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let dayEnd = min(nextDay, now)
            let sessions = sleepByDay[dayStart] ?? []
            let main = sessions.max { $0.asleep < $1.asleep }
            let naps = sessions.filter { $0 != main }.sorted { $0.start < $1.start }

            // Окно для ночных показателей: основной сон, иначе утро.
            let fallbackWindow = DateInterval(start: dayStart.addingTimeInterval(-6 * 3600), duration: 18 * 3600)
            let sleepWindow = main?.interval

            var vitals = DailyVitals()
            vitals.hrv = average(raw.hrv, primary: sleepWindow, fallback: fallbackWindow)
            vitals.respiratoryRate = average(raw.respiratoryRate, primary: sleepWindow, fallback: fallbackWindow)
            vitals.spo2 = average(raw.spo2, primary: sleepWindow, fallback: fallbackWindow).map { $0 * 100 }
            vitals.wristTemp = raw.wristTemp.last { sample in
                calendar.startOfDay(for: sample.end.addingTimeInterval(6 * 3600)) == dayStart
            }?.value
            vitals.restingHR = raw.restingHR[dayStart] ?? sleepingRestingHR(heartRate, window: sleepWindow)

            let baselines = RecoveryEngine.baselines(history: vitalsHistory)
            let restingHR = vitals.restingHR ?? baselines.restingHR?.mean ?? 62

            let dayHR = slice(heartRate, from: dayStart, to: dayEnd)
            let dayInterval = DateInterval(start: dayStart, end: max(dayStart, dayEnd))
            let load = StrainEngine.load(samples: dayHR, interval: dayInterval, restingHR: restingHR, maxHR: maxHR, sex: profile.sex)
            let strain = StrainEngine.strain(fromTrimp: load.trimp)

            let workouts: [WorkoutSummary] = raw.workouts
                .filter { calendar.isDate($0.start, inSameDayAs: dayStart) }
                .sorted { $0.start < $1.start }
                .map { workout in
                    let samples = slice(heartRate, from: workout.start, to: workout.end)
                    let wLoad = StrainEngine.load(
                        samples: samples,
                        interval: DateInterval(start: workout.start, end: max(workout.start, workout.end)),
                        restingHR: restingHR, maxHR: maxHR, sex: profile.sex, maxGap: 120)
                    return WorkoutSummary(
                        id: workout.id, activityRaw: workout.activityRaw, name: workout.name, symbol: workout.symbol,
                        start: workout.start, end: workout.end, energyKcal: workout.energyKcal,
                        distanceMeters: workout.distanceMeters, avgHR: wLoad.avgHR, maxHR: wLoad.maxHR,
                        strain: StrainEngine.strain(fromTrimp: wLoad.trimp), zoneSeconds: wLoad.zoneSeconds)
                }

            // Потребность во сне на прошедшую ночь.
            let previous = result.last
            let deficits: [TimeInterval] = result.suffix(3).reversed().map { day in
                let need = day.sleepNeed?.total ?? profile.sleepNeedHours * 3600
                return need - (day.sleep?.asleep ?? need)
            }
            let napCredit = previous?.naps.reduce(0) { $0 + $1.asleep } ?? 0
            let need = SleepEngine.need(
                baselineHours: profile.sleepNeedHours,
                previousStrain: previous?.strain,
                recentDeficits: deficits,
                napsAsleep: napCredit)
            let performance = main.map { SleepEngine.performance(asleep: $0.asleep, need: need.total) }

            if let main { nights.append((dayStart, main)) }
            let consistency = main == nil ? nil : SleepEngine.consistency(nights)

            let recovery = RecoveryEngine.score(vitals: vitals, baselines: baselines, sleepPerformance: performance, profile: profile)

            var excluded = workouts.map { DateInterval(start: $0.start, end: max($0.start, $0.end)) }
            excluded += sessions.map(\.interval)
            if let prevSleep = sleepByDay[nextDay] { excluded += prevSleep.map(\.interval) }
            let stress = StressEngine.timeline(
                samples: dayHR, dayStart: dayStart, dayEnd: dayEnd,
                restingHR: restingHR, maxHR: maxHR, excluding: excluded)

            let timeline = StrainEngine.timeline(
                samples: dayHR, dayStart: dayStart, end: dayEnd,
                restingHR: restingHR, maxHR: maxHR, sex: profile.sex)

            let metrics = DayMetrics(
                day: dayStart,
                vitals: vitals,
                baselines: baselines,
                sleep: main,
                naps: naps,
                sleepNeed: main == nil && previous == nil ? nil : need,
                sleepPerformance: performance,
                sleepConsistency: consistency,
                recovery: recovery,
                strain: strain,
                strainTimeline: timeline,
                zoneSeconds: load.zoneSeconds,
                workouts: workouts,
                activeEnergy: raw.activeEnergy[dayStart] ?? 0,
                basalEnergy: raw.basalEnergy[dayStart] ?? 0,
                steps: raw.steps[dayStart] ?? 0,
                vo2max: vo2.last { $0.end < dayEnd }?.value,
                stress: stress,
                heartRate: downsample(dayHR, every: 10 * 60),
                avgHR: load.avgHR)

            result.append(metrics)
            vitalsHistory.append(vitals)
        }
        return result
    }

    // MARK: - Сон

    /// Для каждого дня выбирает один источник: приоритет у Apple Watch, затем у источника с бо́льшим сном.
    static func assignSleep(_ segments: [SourcedSleepSegment], calendar: Calendar) -> [Date: [SleepSession]] {
        let bySource = Dictionary(grouping: segments, by: \.sourceID)
        var candidates: [Date: [(isWatch: Bool, sessions: [SleepSession])]] = [:]

        for (_, sourceSegments) in bySource {
            let isWatch = sourceSegments.contains { $0.isWatch }
            let asleep = sourceSegments.filter { !$0.isInBed }
            // Если источник пишет только «в кровати» (например, iPhone), считаем это сном без стадий.
            let usable = asleep.isEmpty ? sourceSegments.map { item -> SleepSegment in
                var segment = item.segment
                segment.stage = .light
                return segment
            } : asleep.map(\.segment)

            let sessions = SleepEngine.sessions(from: usable)
            let grouped = Dictionary(grouping: sessions) { SleepEngine.dayKey(for: $0, calendar: calendar) }
            for (day, daySessions) in grouped {
                candidates[day, default: []].append((isWatch, daySessions))
            }
        }

        var result: [Date: [SleepSession]] = [:]
        for (day, options) in candidates {
            let best = options.max { lhs, rhs in
                if lhs.isWatch != rhs.isWatch { return !lhs.isWatch }
                return totalAsleep(lhs.sessions) < totalAsleep(rhs.sessions)
            }
            result[day] = best?.sessions
        }
        return result
    }

    private static func totalAsleep(_ sessions: [SleepSession]) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.asleep }
    }

    // MARK: - Помощники

    static func average(_ samples: [ValueSample], primary: DateInterval?, fallback: DateInterval) -> Double? {
        if let primary {
            let values = samples.filter { primary.contains($0.start) }.map(\.value)
            if let mean = values.mean { return mean }
        }
        return samples.filter { fallback.contains($0.start) }.map(\.value).mean
    }

    /// Минимальное среднее за 5 минут во время сна — если Apple не посчитал пульс покоя.
    static func sleepingRestingHR(_ samples: [HRSample], window: DateInterval?) -> Double? {
        guard let window else { return nil }
        let values = slice(samples, from: window.start, to: window.end).map(\.bpm)
        guard values.count >= 5 else { return nil }
        var best = Double.greatestFiniteMagnitude
        for index in 0...(values.count - 5) {
            best = min(best, values[index..<(index + 5)].reduce(0, +) / 5)
        }
        return best
    }

    static func slice(_ samples: [HRSample], from start: Date, to end: Date) -> [HRSample] {
        guard start < end else { return [] }
        let lower = lowerBound(samples, start)
        let upper = lowerBound(samples, end)
        return lower < upper ? Array(samples[lower..<upper]) : []
    }

    private static func lowerBound(_ samples: [HRSample], _ date: Date) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    static func downsample(_ samples: [HRSample], every step: TimeInterval) -> [HRSample] {
        guard let first = samples.first else { return [] }
        var buckets: [Int: (Double, Int)] = [:]
        for sample in samples {
            let index = Int(sample.date.timeIntervalSince(first.date) / step)
            let current = buckets[index] ?? (0, 0)
            buckets[index] = (current.0 + sample.bpm, current.1 + 1)
        }
        return buckets.keys.sorted().map { index in
            let (sum, count) = buckets[index]!
            return HRSample(date: first.date.addingTimeInterval(Double(index) * step), bpm: sum / Double(count))
        }
    }
}
