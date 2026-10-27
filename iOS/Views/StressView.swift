import SwiftUI
import Charts

struct StressView: View {
    var day: DayMetrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let level = day.currentStress ?? 0
                BigScoreHeader(
                    title: "Стресс",
                    value: day.currentStress.map { Fmt.number($0, digits: 1) } ?? "—",
                    subtitle: day.currentStress.map { "\(StressEngine.title($0)) уровень · шкала 0–3" } ?? "Нет данных",
                    progress: level / 3,
                    color: Theme.stressColor(level))

                Card {
                    SectionTitle(title: "В течение дня")
                    StressChart(points: day.stress, compact: false)
                        .frame(height: 200)
                }

                Card {
                    SectionTitle(title: "Распределение")
                    let share = StressEngine.distribution(day.stress)
                    StackedBar(parts: [
                        BarPart(value: share[0], color: Theme.recoveryGreen),
                        BarPart(value: share[1], color: Theme.recoveryYellow),
                        BarPart(value: share[2], color: Theme.stress),
                    ])
                    StatRow(title: "Низкий (0–1)", value: Fmt.percent(share[0] * 100), symbol: "circle.fill", color: Theme.recoveryGreen)
                    StatRow(title: "Средний (1–2)", value: Fmt.percent(share[1] * 100), symbol: "circle.fill", color: Theme.recoveryYellow)
                    StatRow(title: "Высокий (2–3)", value: Fmt.percent(share[2] * 100), symbol: "circle.fill", color: Theme.stress)
                }

                Card {
                    SectionTitle(title: "Как это работает")
                    Text("Монитор стресса сравнивает пульс в состоянии покоя с вашим личным пульсом покоя. Время сна и тренировок не учитывается. Если уровень долго держится выше 2, попробуйте дыхательную практику: вдох 4 секунды, выдох 6 секунд в течение 2–3 минут.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Монитор стресса")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StressChart: View {
    var points: [StressPoint]
    var compact: Bool

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Время", point.date, unit: .minute), y: .value("Стресс", max(point.level, 0.05)), width: .fixed(compact ? 2 : 4))
                    .foregroundStyle(Theme.stressColor(point.level))
            }
        }
        .chartYScale(domain: 0...3)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisValueLabel(format: .dateTime.hour())
            }
        }
    }
}
