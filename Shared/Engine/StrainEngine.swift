import Foundation

func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
}

extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }

    var standardDeviation: Double? {
        guard count > 1, let m = mean else { return nil }
        let variance = map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(count - 1)
        return variance.squareRoot()
    }
}

/// Нагрузка (Strain) по шкале 0–21.
/// Основа — TRIMP Банистера по резерву ЧСС, который переводится в логарифмически насыщающуюся шкалу:
/// каждый следующий балл даётся всё тяжелее, как в оригинальной шкале.
enum StrainEngine {
    static let maxStrain: Double = 21
    static let scale: Double = 100
    /// Границы зон в долях от максимального пульса: 50/60/70/80/90 %.
    static let zoneThresholds: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    static let zoneCount = 6

    struct Load {
        var trimp: Double
        var zoneSeconds: [Double]
        var avgHR: Double?
        var maxHR: Double?
    }

    static func zone(bpm: Double, maxHR: Double) -> Int {
        let fraction = bpm / max(maxHR, 1)
        var result = 0
        for (index, threshold) in zoneThresholds.enumerated() where fraction >= threshold {
            result = index + 1
        }
        return result
    }

    /// TRIMP в минуту при данном пульсе. Ниже 30 % резерва ЧСС нагрузка не засчитывается.
    static func trimpRate(bpm: Double, restingHR: Double, maxHR: Double, sex: BiologicalSexOption) -> Double {
        let reserve = max(maxHR - restingHR, 20)
        let hrr = (bpm - restingHR) / reserve
        guard hrr >= 0.3 else { return 0 }
        let x = min(hrr, 1.1)
        let a = sex == .female ? 0.86 : 0.64
        let b = sex == .female ? 1.67 : 1.92
        return x * a * exp(b * x)
    }

    static func strain(fromTrimp trimp: Double) -> Double {
        maxStrain * (1 - exp(-max(0, trimp) / scale))
    }

    static func trimp(forStrain strain: Double) -> Double {
        let capped = clamp(strain, 0, maxStrain - 0.01)
        return -scale * log(1 - capped / maxStrain)
    }

    static func load(
        samples: [HRSample],
        interval: DateInterval,
        restingHR: Double,
        maxHR: Double,
        sex: BiologicalSexOption,
        maxGap: TimeInterval = 600
    ) -> Load {
        var trimp = 0.0
        var zones = Array(repeating: 0.0, count: zoneCount)
        var weighted = 0.0
        var totalTime = 0.0
        var peak: Double?

        for (index, sample) in samples.enumerated() {
            guard sample.date >= interval.start, sample.date < interval.end else { continue }
            let nextDate = index + 1 < samples.count ? samples[index + 1].date : sample.date.addingTimeInterval(60)
            var dt = clamp(nextDate.timeIntervalSince(sample.date), 0, maxGap)
            dt = min(dt, interval.end.timeIntervalSince(sample.date))
            guard dt > 0 else { continue }

            trimp += trimpRate(bpm: sample.bpm, restingHR: restingHR, maxHR: maxHR, sex: sex) * dt / 60
            zones[zone(bpm: sample.bpm, maxHR: maxHR)] += dt
            weighted += sample.bpm * dt
            totalTime += dt
            peak = max(peak ?? 0, sample.bpm)
        }

        return Load(
            trimp: trimp,
            zoneSeconds: zones,
            avgHR: totalTime > 0 ? weighted / totalTime : nil,
            maxHR: peak
        )
    }

    /// Накопленная нагрузка за день с шагом 30 минут.
    static func timeline(
        samples: [HRSample],
        dayStart: Date,
        end: Date,
        restingHR: Double,
        maxHR: Double,
        sex: BiologicalSexOption
    ) -> [StrainPoint] {
        var points: [StrainPoint] = [StrainPoint(date: dayStart, strain: 0)]
        var cursor = dayStart
        var trimp = 0.0
        var sampleIndex = 0
        let step: TimeInterval = 30 * 60

        while cursor < end {
            let next = min(cursor.addingTimeInterval(step), end)
            while sampleIndex < samples.count, samples[sampleIndex].date < next {
                let sample = samples[sampleIndex]
                if sample.date >= cursor {
                    let nextDate = sampleIndex + 1 < samples.count ? samples[sampleIndex + 1].date : sample.date.addingTimeInterval(60)
                    let dt = min(clamp(nextDate.timeIntervalSince(sample.date), 0, 600), end.timeIntervalSince(sample.date))
                    trimp += trimpRate(bpm: sample.bpm, restingHR: restingHR, maxHR: maxHR, sex: sex) * max(0, dt) / 60
                }
                sampleIndex += 1
            }
            points.append(StrainPoint(date: next, strain: strain(fromTrimp: trimp)))
            cursor = next
        }
        return points
    }

    /// Рекомендованный диапазон нагрузки в зависимости от восстановления.
    static func target(forRecovery recovery: Double?) -> ClosedRange<Double> {
        guard let recovery else { return 8...12 }
        let center = 4 + recovery / 100 * 13
        return max(0, center - 1.5)...min(maxStrain, center + 1.5)
    }

    static func zoneTitle(_ zone: Int) -> String {
        switch zone {
        case 0: return "Покой"
        case 1: return "Зона 1"
        case 2: return "Зона 2"
        case 3: return "Зона 3"
        case 4: return "Зона 4"
        default: return "Зона 5"
        }
    }

    static func zoneRange(_ zone: Int, maxHR: Double) -> String {
        let bounds = [0.0] + zoneThresholds + [1.0]
        let low = Int((bounds[zone] * maxHR).rounded())
        if zone == zoneCount - 1 { return "\(low)+" }
        let high = Int((bounds[zone + 1] * maxHR).rounded()) - 1
        return zone == 0 ? "<\(high + 1)" : "\(low)–\(high)"
    }

    static func level(_ strain: Double) -> String {
        switch strain {
        case ..<10: return "Лёгкая"
        case ..<14: return "Умеренная"
        case ..<18: return "Высокая"
        default: return "Максимальная"
        }
    }
}
