import SwiftUI
import Charts

struct SleepDetailView: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigScoreHeader(
                    title: "Сон",
                    value: Fmt.percent(day.sleepPerformance),
                    subtitle: headerSubtitle,
                    progress: (day.sleepPerformance ?? 0) / 100,
                    color: Theme.sleep)

                if let sleep = day.sleep {
                    Card {
                        SectionTitle(title: "Стадии сна", trailing: "\(Fmt.time(sleep.start)) – \(Fmt.time(sleep.end))")
                        if sleep.hasStages {
                            HypnogramChart(session: sleep)
                                .frame(height: 170)
                        }
                        StageBreakdown(session: sleep)
                    }

                    Card {
                        SectionTitle(title: "Показатели сна")
                        StatRow(title: "Время во сне", value: Fmt.durationLong(sleep.asleep), symbol: "moon.fill", color: Theme.sleep)
                        StatRow(title: "Время в кровати", value: Fmt.durationLong(sleep.inBed), symbol: "bed.double.fill", color: Theme.sleep)
                        StatRow(title: "Эффективность", value: Fmt.percent(sleep.efficiency * 100), symbol: "chart.bar.fill", color: Theme.strain)
                        StatRow(title: "Регулярность", value: Fmt.percent(day.sleepConsistency), symbol: "clock.fill", color: Theme.recoveryYellow)
                        StatRow(title: "Восстанавливающий сон", value: "\(Fmt.durationLong(sleep.restorative)) · \(Fmt.percent(sleep.restorativeShare * 100))", symbol: "sparkles", color: Theme.recoveryGreen)
                        StatRow(title: "Время засыпания", value: Fmt.durationLong(sleep.latency), symbol: "hourglass", color: Theme.secondaryText)
                        StatRow(title: "Пробуждения", value: "\(sleep.disturbances)", symbol: "eye.fill", color: Theme.secondaryText)
                        StatRow(title: "Частота дыхания", value: "\(Fmt.number(day.vitals.respiratoryRate, digits: 1)) вд/мин", symbol: "lungs.fill", color: Theme.strain)
                    }
                } else {
                    Card {
                        EmptyStateView(symbol: "moon.zzz", title: "Нет данных о сне", message: "Включите отслеживание сна на Apple Watch (Здоровье → Сон → Режим сна) и спите с часами.")
                    }
                }

                if let need = day.sleepNeed {
                    Card {
                        SectionTitle(title: "Потребность во сне", trailing: Fmt.durationLong(need.total))
                        StatRow(title: "Базовая", value: Fmt.durationLong(need.baseline), symbol: "person.fill", color: Theme.sleep)
                        StatRow(title: "За вчерашнюю нагрузку", value: "+" + Fmt.durationLong(need.strain), symbol: "flame.fill", color: Theme.strain)
                        StatRow(title: "Долг сна", value: "+" + Fmt.durationLong(need.debt), symbol: "exclamationmark.circle.fill", color: Theme.recoveryYellow)
                        StatRow(title: "Дневной сон", value: "−" + Fmt.durationLong(need.naps), symbol: "powersleep", color: Theme.recoveryGreen)
                    }
                }

                SleepPlannerCard(day: day)

                Card {
                    SectionTitle(title: "Сон за 14 дней")
                    SleepHistoryChart(days: store.history(upTo: day.day, count: 14))
                        .frame(height: 180)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(Fmt.dayTitle(day.day))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSubtitle: String {
        guard let sleep = day.sleep else { return "Нет данных о сне" }
        let need = day.sleepNeed.map { " из \(Fmt.duration($0.total))" } ?? ""
        return "\(Fmt.duration(sleep.asleep))\(need) часов сна"
    }
}

struct HypnogramChart: View {
    var session: SleepSession

    var body: some View {
        Chart {
            ForEach(session.segments, id: \.start) { segment in
                RectangleMark(
                    xStart: .value("Начало", segment.start),
                    xEnd: .value("Конец", segment.end),
                    y: .value("Стадия", segment.stage.shortTitle),
                    height: .ratio(0.7))
                .foregroundStyle(Theme.stageColor(segment.stage))
                .cornerRadius(2)
            }
        }
        .chartYScale(domain: SleepStage.allCases.map(\.shortTitle))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
    }
}

struct StageBreakdown: View {
    var session: SleepSession

    var body: some View {
        let total = max(session.inBed, 1)
        VStack(spacing: 10) {
            StackedBar(parts: SleepStage.allCases.map { BarPart(value: session.time(in: $0), color: Theme.stageColor($0)) })
            ForEach(SleepStage.allCases) { stage in
                let time = session.time(in: stage)
                HStack {
                    Circle().fill(Theme.stageColor(stage)).frame(width: 10, height: 10)
                    Text(stage.title).font(.subheadline)
                    Spacer()
                    Text(Fmt.durationLong(time)).font(.subheadline.monospacedDigit())
                    Text(Fmt.percent(time / total * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

struct SleepPlannerCard: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    var body: some View {
        Card {
            SectionTitle(title: "Планировщик сна")
            Text("Когда лечь, чтобы проснуться в \(String(format: "%02d:%02d", store.profile.wakeHour, store.profile.wakeMinute))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            ForEach(options) { option in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title).font(.subheadline.weight(.semibold))
                        Text("\(Int(option.fraction * 100))% потребности · \(Fmt.durationLong(option.sleepDuration))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(Fmt.time(option.bedtime))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.sleep)
                }
            }
        }
    }

    /// Прогноз на ближайшую ночь: базовая потребность + нагрузка дня + долг.
    private var options: [SleepEngine.PlanOption] {
        let calendar = Calendar.current
        let recent = store.history(upTo: day.day, count: 3).reversed()
        let deficits = recent.map { item -> TimeInterval in
            let need = item.sleepNeed?.total ?? store.profile.sleepNeedHours * 3600
            return need - (item.sleep?.asleep ?? need)
        }
        let need = SleepEngine.need(
            baselineHours: store.profile.sleepNeedHours,
            previousStrain: day.strain,
            recentDeficits: Array(deficits),
            napsAsleep: day.naps.reduce(0) { $0 + $1.asleep })
        let efficiency = day.sleep?.efficiency ?? 0.9
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day.day) ?? day.day
        let wake = calendar.date(bySettingHour: store.profile.wakeHour, minute: store.profile.wakeMinute, second: 0, of: nextDay) ?? nextDay
        return SleepEngine.plan(need: need.total, efficiency: efficiency, wake: wake)
    }
}

struct SleepHistoryChart: View {
    var days: [DayMetrics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("День", day.day, unit: .day), y: .value("Сон", (day.sleep?.asleep ?? 0) / 3600))
                    .foregroundStyle(Theme.sleep)
                    .cornerRadius(3)
                if let need = day.sleepNeed {
                    PointMark(x: .value("День", day.day, unit: .day), y: .value("Потребность", need.total / 3600))
                        .symbol(.circle)
                        .symbolSize(28)
                        .foregroundStyle(Color.white)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(Int(hours)) ч") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.narrow))
            }
        }
    }
}
