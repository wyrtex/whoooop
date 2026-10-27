import Foundation

struct CoachInsight: Identifiable, Hashable {
    enum Tone { case positive, neutral, warning }

    var title: String
    var body: String
    var symbol: String
    var tone: Tone
    var id: String { title }
}

/// Персональный «коуч»: правила поверх рассчитанных метрик.
enum CoachEngine {
    static func insights(for day: DayMetrics, history: [DayMetrics], profile: UserProfile, now: Date = Date()) -> [CoachInsight] {
        var result: [CoachInsight] = []
        let target = StrainEngine.target(forRecovery: day.recovery)

        if let recovery = day.recovery {
            let range = String(format: "%.0f–%.0f", target.lowerBound, target.upperBound)
            switch RecoveryBand(recovery) {
            case .green:
                result.append(CoachInsight(
                    title: "Организм готов к нагрузке",
                    body: "Восстановление \(Int(recovery))%. Хороший день для интенсивной тренировки — целевая нагрузка \(range).",
                    symbol: "bolt.heart.fill", tone: .positive))
            case .yellow:
                result.append(CoachInsight(
                    title: "Умеренный день",
                    body: "Восстановление \(Int(recovery))%. Тренируйтесь, но без рекордов: целевая нагрузка \(range).",
                    symbol: "gauge.with.dots.needle.50percent", tone: .neutral))
            case .red:
                result.append(CoachInsight(
                    title: "Нужен отдых",
                    body: "Восстановление \(Int(recovery))%. Сделайте акцент на восстановлении: прогулка, растяжка, ранний отбой. Нагрузка до \(range).",
                    symbol: "bed.double.fill", tone: .warning))
            }
        }

        if let hrv = day.vitals.hrv, let mean = day.baselines.hrvMean, mean > 0 {
            let delta = (hrv / mean - 1) * 100
            if delta <= -15 {
                result.append(CoachInsight(
                    title: "ВСР ниже нормы",
                    body: String(format: "Вариабельность пульса на %.0f%% ниже вашей нормы. Это признак накопленной усталости, стресса или начинающейся болезни.", -delta),
                    symbol: "waveform.path.ecg", tone: .warning))
            } else if delta >= 15 {
                result.append(CoachInsight(
                    title: "ВСР выше нормы",
                    body: String(format: "Вариабельность пульса на %.0f%% выше нормы — нервная система хорошо восстановилась.", delta),
                    symbol: "waveform.path.ecg", tone: .positive))
            }
        }

        if let rhr = day.vitals.restingHR, let b = day.baselines.restingHR, rhr - b.mean >= 5 {
            result.append(CoachInsight(
                title: "Пульс покоя повышен",
                body: String(format: "Пульс покоя %.0f уд/мин — на %.0f выше обычного. Алкоголь, поздний ужин, жара или болезнь часто дают такой эффект.", rhr, rhr - b.mean),
                symbol: "heart.fill", tone: .warning))
        }

        if let resp = day.vitals.respiratoryRate, let b = day.baselines.respiratoryRate, abs(resp - b.mean) >= 1 {
            result.append(CoachInsight(
                title: "Дыхание отличается от нормы",
                body: String(format: "Частота дыхания во сне %.1f вд/мин при норме %.1f. Стоит последить за самочувствием.", resp, b.mean),
                symbol: "lungs.fill", tone: .warning))
        }

        if let temp = day.vitals.wristTemp, let b = day.baselines.wristTemp, abs(temp - b.mean) >= 0.5 {
            result.append(CoachInsight(
                title: "Температура кожи изменилась",
                body: String(format: "Отклонение %+.1f °C от нормы. Иногда это ранний признак болезни или фаза цикла.", temp - b.mean),
                symbol: "thermometer.medium", tone: .warning))
        }

        if let need = day.sleepNeed, let sleep = day.sleep {
            let deficit = need.total - sleep.asleep
            if deficit > 45 * 60 {
                result.append(CoachInsight(
                    title: "Недосып",
                    body: "Вы недоспали \(Fmt.durationLong(deficit)). Сегодня лягте пораньше — долг сна учтён в завтрашней потребности.",
                    symbol: "moon.zzz.fill", tone: .warning))
            }
        }

        if let consistency = day.sleepConsistency, consistency < 60 {
            result.append(CoachInsight(
                title: "Нерегулярный режим",
                body: String(format: "Регулярность сна %.0f%%. Ложитесь и вставайте в одно и то же время ±30 минут — это ускоряет восстановление.", consistency),
                symbol: "clock.badge.exclamationmark", tone: .neutral))
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(day.day), calendar.component(.hour, from: now) >= 17 {
            if day.strain < target.lowerBound {
                result.append(CoachInsight(
                    title: "Нагрузка ниже цели",
                    body: String(format: "Сейчас %.1f из %.0f–%.0f. Добавьте 20–30 минут активности в зоне 2–3.", day.strain, target.lowerBound, target.upperBound),
                    symbol: "figure.run", tone: .neutral))
            } else if day.strain > target.upperBound + 1 {
                result.append(CoachInsight(
                    title: "Нагрузка выше цели",
                    body: "Вы превысили рекомендованную нагрузку. Сон сегодня особенно важен.",
                    symbol: "exclamationmark.triangle.fill", tone: .warning))
            }
        }

        if result.isEmpty {
            result.append(CoachInsight(
                title: "Собираем данные",
                body: "Носите Apple Watch днём и ночью. Через 3–4 дня появится личная норма и точные оценки.",
                symbol: "applewatch", tone: .neutral))
        }
        return result
    }
}
