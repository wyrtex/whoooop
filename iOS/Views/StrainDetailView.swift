import SwiftUI
import Charts

struct StrainDetailView: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    var body: some View {
        let target = StrainEngine.target(forRecovery: day.recovery)
        ScrollView {
            VStack(spacing: 16) {
                BigScoreHeader(
                    title: "Нагрузка",
                    value: Fmt.strain(day.strain),
                    subtitle: "\(StrainEngine.level(day.strain)) · цель \(Fmt.number(target.lowerBound))–\(Fmt.number(target.upperBound))",
                    progress: day.strain / StrainEngine.maxStrain,
                    color: Theme.strain)

                Card {
                    SectionTitle(title: "Нагрузка в течение дня")
                    StrainTimelineChart(points: day.strainTimeline, target: target)
                        .frame(height: 180)
                }

                Card {
                    SectionTitle(title: "Пульс")
                    HeartRateChart(samples: day.heartRate)
                        .frame(height: 160)
                    HStack {
                        StatRow(title: "Средний", value: "\(Fmt.number(day.avgHR)) уд/мин")
                    }
                }

                Card {
                    SectionTitle(title: "Время в пульсовых зонах")
                    ZoneBreakdown(zoneSeconds: day.zoneSeconds, maxHR: store.profile.maxHR)
                }

                Card {
                    SectionTitle(title: "Энергия и активность")
                    StatRow(title: "Всего калорий", value: "\(Fmt.number(day.totalEnergy)) ккал", symbol: "flame.fill", color: Theme.stress)
                    StatRow(title: "Активные калории", value: "\(Fmt.number(day.activeEnergy)) ккал", symbol: "bolt.fill", color: Theme.recoveryYellow)
                    StatRow(title: "Шаги", value: Fmt.number(day.steps), symbol: "figure.walk", color: Theme.recoveryGreen)
                }

                if !day.workouts.isEmpty {
                    Card {
                        SectionTitle(title: "Тренировки")
                        ForEach(day.workouts) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                ActivityRow(symbol: workout.symbol, color: Theme.strain, title: workout.name, subtitle: Fmt.durationLong(workout.duration), value: Fmt.strain(workout.strain))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Card {
                    SectionTitle(title: "Нагрузка за 30 дней")
                    StrainHistoryChart(days: store.history(upTo: day.day, count: 30))
                        .frame(height: 180)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(Fmt.dayTitle(day.day))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var store: HealthDataStore
    var workout: WorkoutSummary

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BigScoreHeader(
                    title: workout.name,
                    value: Fmt.strain(workout.strain),
                    subtitle: "\(Fmt.time(workout.start)) – \(Fmt.time(workout.end)) · \(Fmt.durationLong(workout.duration))",
                    progress: workout.strain / StrainEngine.maxStrain,
                    color: Theme.strain)

                Card {
                    SectionTitle(title: "Показатели")
                    StatRow(title: "Длительность", value: Fmt.durationLong(workout.duration), symbol: "timer", color: Theme.strain)
                    StatRow(title: "Средний пульс", value: "\(Fmt.number(workout.avgHR)) уд/мин", symbol: "heart.fill", color: Theme.heart)
                    StatRow(title: "Максимальный пульс", value: "\(Fmt.number(workout.maxHR)) уд/мин", symbol: "heart.circle.fill", color: Theme.heart)
                    StatRow(title: "Калории", value: "\(Fmt.number(workout.energyKcal)) ккал", symbol: "flame.fill", color: Theme.stress)
                    if let distance = Fmt.distance(workout.distanceMeters) {
                        StatRow(title: "Дистанция", value: distance, symbol: "point.topleft.down.to.point.bottomright.curvepath", color: Theme.recoveryGreen)
                    }
                }

                Card {
                    SectionTitle(title: "Пульсовые зоны")
                    ZoneBreakdown(zoneSeconds: workout.zoneSeconds, maxHR: store.profile.maxHR)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StrainTimelineChart: View {
    var points: [StrainPoint]
    var target: ClosedRange<Double>

    var body: some View {
        Chart {
            if let first = points.first?.date, let last = points.last?.date, first < last {
                RectangleMark(
                    xStart: .value("Начало", first),
                    xEnd: .value("Конец", last),
                    yStart: .value("Цель от", target.lowerBound),
                    yEnd: .value("Цель до", target.upperBound))
                .foregroundStyle(Theme.strain.opacity(0.12))
            }
            ForEach(points) { point in
                AreaMark(x: .value("Время", point.date), y: .value("Нагрузка", point.strain))
                    .foregroundStyle(LinearGradient(colors: [Theme.strain.opacity(0.5), Theme.strain.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Время", point.date), y: .value("Нагрузка", point.strain))
                    .foregroundStyle(Theme.strain)
            }
        }
        .chartYScale(domain: 0...21)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
}

struct HeartRateChart: View {
    var samples: [HRSample]

    var body: some View {
        Chart {
            ForEach(samples, id: \.date) { sample in
                LineMark(x: .value("Время", sample.date), y: .value("Пульс", sample.bpm))
                    .foregroundStyle(Theme.heart)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(Theme.separator)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
}

struct StrainHistoryChart: View {
    var days: [DayMetrics]

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("День", day.day, unit: .day), y: .value("Нагрузка", day.strain))
                    .foregroundStyle(Theme.strain)
                    .cornerRadius(3)
            }
        }
        .chartYScale(domain: 0...21)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}
