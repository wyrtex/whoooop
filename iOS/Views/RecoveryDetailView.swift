import SwiftUI
import Charts

struct RecoveryDetailView: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    private var contributions: [RecoveryEngine.Contribution] {
        RecoveryEngine.contributions(vitals: day.vitals, baselines: day.baselines, sleepPerformance: day.sleepPerformance, profile: store.profile)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigScoreHeader(
                    title: "Восстановление",
                    value: Fmt.percent(day.recovery),
                    subtitle: subtitle,
                    progress: (day.recovery ?? 0) / 100,
                    color: Theme.recoveryColor(day.recovery))

                Card {
                    SectionTitle(title: "Рекомендация")
                    let target = StrainEngine.target(forRecovery: day.recovery)
                    StatRow(title: "Оптимальная нагрузка", value: String(format: "%.0f–%.0f", target.lowerBound, target.upperBound), symbol: "flame.fill", color: Theme.strain)
                    Text(recommendation)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }

                Card {
                    SectionTitle(title: "Из чего складывается")
                    ForEach(contributions) { item in
                        ContributionRow(item: item, day: day)
                    }
                    if contributions.isEmpty {
                        Text("Нет данных ВСР и пульса покоя за эту ночь.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Card {
                    SectionTitle(title: "Восстановление за 30 дней")
                    RecoveryHistoryChart(days: store.history(upTo: day.day, count: 30))
                        .frame(height: 180)
                }

                Card {
                    SectionTitle(title: "ВСР за 30 дней", trailing: day.baselines.hrvMean.map { "норма \(Int($0)) мс" })
                    VitalLineChart(days: store.history(upTo: day.day, count: 30), value: { $0.vitals.hrv }, color: Theme.recoveryGreen, baseline: day.baselines.hrvMean)
                        .frame(height: 160)
                }

                Card {
                    SectionTitle(title: "Пульс покоя за 30 дней", trailing: day.baselines.restingHR.map { "норма \(Int($0.mean)) уд/мин" })
                    VitalLineChart(days: store.history(upTo: day.day, count: 30), value: { $0.vitals.restingHR }, color: Theme.heart, baseline: day.baselines.restingHR?.mean)
                        .frame(height: 160)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(Fmt.dayTitle(day.day))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var subtitle: String {
        guard let band = day.recoveryBand else { return "Недостаточно данных за ночь" }
        return "\(band.title) восстановление"
    }

    private var recommendation: String {
        guard let band = day.recoveryBand else {
            return "Наденьте Apple Watch на ночь, чтобы получить оценку восстановления."
        }
        switch band {
        case .green: return "Организм хорошо адаптировался. Отличный день для интенсивной тренировки или соревнований."
        case .yellow: return "Организм восстанавливается. Поддерживающая тренировка подойдёт, но без максимальных усилий."
        case .red: return "Организму нужен отдых. Выберите лёгкую активность, больше спите и пейте воду."
        }
    }
}

private struct ContributionRow: View {
    var item: RecoveryEngine.Contribution
    var day: DayMetrics

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.metric.symbol)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.metric.title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: item.z >= 0.25 ? "arrow.up.circle.fill" : (item.z <= -0.25 ? "arrow.down.circle.fill" : "equal.circle.fill"))
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        if item.z >= 0.25 { return Theme.recoveryGreen }
        if item.z <= -0.25 { return Theme.recoveryRed }
        return Theme.recoveryYellow
    }

    private var detail: String {
        let v = day.vitals
        let b = day.baselines
        switch item.metric {
        case .hrv:
            return "\(Fmt.number(v.hrv)) мс · норма \(Fmt.number(b.hrvMean)) мс"
        case .restingHR:
            return "\(Fmt.number(v.restingHR)) уд/мин · норма \(Fmt.number(b.restingHR?.mean))"
        case .respiratoryRate:
            return "\(Fmt.number(v.respiratoryRate, digits: 1)) вд/мин · норма \(Fmt.number(b.respiratoryRate?.mean, digits: 1))"
        case .spo2:
            return "\(Fmt.number(v.spo2, digits: 1))% · норма \(Fmt.number(b.spo2?.mean, digits: 1))%"
        case .wristTemp:
            if let t = v.wristTemp, let m = b.wristTemp?.mean { return "\(Fmt.signed(t - m, digits: 1)) °C от нормы" }
            return "—"
        case .sleep:
            return "Сон \(Fmt.percent(day.sleepPerformance)) от потребности"
        }
    }
}

struct RecoveryHistoryChart: View {
    var days: [DayMetrics]

    var body: some View {
        Chart {
            ForEach(days.filter { $0.recovery != nil }) { day in
                BarMark(
                    x: .value("День", day.day, unit: .day),
                    y: .value("Восстановление", day.recovery ?? 0))
                .foregroundStyle(Theme.recoveryColor(day.recovery))
                .cornerRadius(3)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 33, 66, 100]) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}

struct VitalLineChart: View {
    var days: [DayMetrics]
    var value: (DayMetrics) -> Double?
    var color: Color
    var baseline: Double?

    private struct Point: Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    private var points: [Point] {
        days.compactMap { day in value(day).map { Point(date: day.day, value: $0) } }
    }

    var body: some View {
        Chart {
            if let baseline {
                RuleMark(y: .value("Норма", baseline))
                    .foregroundStyle(Theme.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(points) { point in
                LineMark(x: .value("День", point.date, unit: .day), y: .value("Значение", point.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("День", point.date, unit: .day), y: .value("Значение", point.value))
                    .foregroundStyle(color)
                    .symbolSize(18)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}
