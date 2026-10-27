import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let day = store.today {
                        HealthMonitorCard(day: day)
                        BiologicalAgeCard()
                        NavigationLink {
                            StressView(day: day)
                        } label: {
                            Card {
                                HStack {
                                    Image(systemName: "brain.head.profile")
                                        .font(.title2)
                                        .foregroundStyle(Theme.stress)
                                    VStack(alignment: .leading) {
                                        Text("Монитор стресса").font(.headline)
                                        Text(day.currentStress.map { "Сейчас \(Fmt.number($0, digits: 1)) · \(StressEngine.title($0))" } ?? "Нет данных")
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        FitnessCard(day: day)
                    } else {
                        EmptyStateView(symbol: "heart.text.square", title: "Нет данных", message: "Подключите Apple Health в профиле.")
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Здоровье")
        }
    }
}

/// «Health Monitor»: показатели относительно личного диапазона нормы.
struct HealthMonitorCard: View {
    var day: DayMetrics

    private struct Item: Identifiable {
        var title: String
        var symbol: String
        var value: String
        var range: String
        var inRange: Bool?
        var id: String { title }
    }

    private var items: [Item] {
        let v = day.vitals
        let b = day.baselines
        func check(_ value: Double?, _ baseline: Baseline?, width: Double = 2) -> Bool? {
            guard let value, let baseline else { return nil }
            return abs(value - baseline.mean) <= width * baseline.sd
        }
        func range(_ baseline: Baseline?, digits: Int, width: Double = 2) -> String {
            guard let baseline else { return "норма формируется" }
            return "\(Fmt.number(baseline.mean - width * baseline.sd, digits: digits))–\(Fmt.number(baseline.mean + width * baseline.sd, digits: digits))"
        }
        let hrvRange: String = b.hrvLn.map { "\(Fmt.number(exp($0.mean - 2 * $0.sd)))–\(Fmt.number(exp($0.mean + 2 * $0.sd)))" } ?? "норма формируется"
        return [
            Item(title: "ВСР", symbol: "waveform.path.ecg", value: "\(Fmt.number(v.hrv)) мс", range: hrvRange, inRange: check(v.hrv.map { log(max($0, 1)) }, b.hrvLn)),
            Item(title: "Пульс покоя", symbol: "heart.fill", value: "\(Fmt.number(v.restingHR)) уд/мин", range: range(b.restingHR, digits: 0), inRange: check(v.restingHR, b.restingHR)),
            Item(title: "Частота дыхания", symbol: "lungs.fill", value: "\(Fmt.number(v.respiratoryRate, digits: 1)) вд/мин", range: range(b.respiratoryRate, digits: 1), inRange: check(v.respiratoryRate, b.respiratoryRate)),
            Item(title: "Кислород в крови", symbol: "drop.fill", value: "\(Fmt.number(v.spo2, digits: 1))%", range: range(b.spo2, digits: 1), inRange: check(v.spo2, b.spo2)),
            Item(title: "Температура кожи", symbol: "thermometer.medium", value: v.wristTemp.map { String(format: "%.2f °C", $0) } ?? "—", range: range(b.wristTemp, digits: 1), inRange: check(v.wristTemp, b.wristTemp)),
        ]
    }

    var body: some View {
        let list = items
        let measured = list.compactMap(\.inRange)
        let ok = measured.filter { $0 }.count
        Card {
            SectionTitle(title: "Монитор здоровья", trailing: Fmt.dayTitle(day.day))
            HStack(alignment: .firstTextBaseline) {
                Text("\(ok)/\(measured.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(ok == measured.count ? Theme.recoveryGreen : Theme.recoveryYellow)
                Text("показателей в пределах нормы")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(list) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(color(item.inRange))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold))
                        Text("Норма: \(item.range)").font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(item.value).font(.subheadline.monospacedDigit())
                    Image(systemName: item.inRange == false ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(color(item.inRange))
                }
            }
        }
    }

    private func color(_ inRange: Bool?) -> Color {
        switch inRange {
        case .some(true): return Theme.recoveryGreen
        case .some(false): return Theme.recoveryYellow
        case .none: return Theme.neutral
        }
    }
}

struct BiologicalAgeCard: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        Card {
            SectionTitle(title: "Биологический возраст")
            if let result = HealthspanEngine.compute(days: store.days, profile: store.profile) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.number(result.biological, digits: 1))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(result.biological <= result.chronological ? Theme.recoveryGreen : Theme.recoveryYellow)
                    VStack(alignment: .leading) {
                        Text("лет").foregroundStyle(Theme.secondaryText)
                        Text("паспортный: \(Int(result.chronological))")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer()
                    if let trend = result.trend {
                        VStack(alignment: .trailing) {
                            Text(Fmt.signed(trend, digits: 1))
                                .font(.headline)
                                .foregroundStyle(trend <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                            Text("за месяц")
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }
                ForEach(result.factors) { factor in
                    HStack(spacing: 12) {
                        Image(systemName: factor.symbol)
                            .foregroundStyle(factor.years <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(factor.name).font(.subheadline.weight(.semibold))
                            Text(factor.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text("\(Fmt.signed(factor.years, digits: 1)) г.")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(factor.years <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                    }
                }
                Text("Оценка по 30 дням. Это не медицинский показатель — ориентир, на что влияют ваши привычки.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            } else {
                Text("Недостаточно данных для оценки")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

struct FitnessCard: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    var body: some View {
        let week = store.days.suffix(7)
        let cardio = week.reduce(0) { $0 + $1.zoneSeconds.dropFirst(2).reduce(0, +) } / 60
        let workouts = week.reduce(0) { $0 + $1.workouts.count }
        Card {
            SectionTitle(title: "Форма")
            StatRow(title: "МПК (VO₂max)", value: day.vo2max.map { String(format: "%.1f мл/кг/мин", $0) } ?? "—", symbol: "lungs.fill", color: Theme.recoveryGreen)
            StatRow(title: "Кардио за 7 дней", value: "\(Int(cardio)) мин из 150", symbol: "heart.circle.fill", color: Theme.heart)
            StatRow(title: "Тренировок за 7 дней", value: "\(workouts)", symbol: "figure.run", color: Theme.strain)
            StatRow(title: "Максимальный пульс", value: "\(Int(store.profile.maxHR)) уд/мин", symbol: "bolt.heart.fill", color: Theme.stress)
        }
    }
}
