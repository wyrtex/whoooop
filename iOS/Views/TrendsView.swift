import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case recovery, strain, sleepPerformance, sleepHours, hrv, restingHR, respiratoryRate, spo2, steps, calories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: return "Восстановление"
        case .strain: return "Нагрузка"
        case .sleepPerformance: return "Качество сна"
        case .sleepHours: return "Часы сна"
        case .hrv: return "ВСР"
        case .restingHR: return "Пульс покоя"
        case .respiratoryRate: return "Дыхание"
        case .spo2: return "SpO₂"
        case .steps: return "Шаги"
        case .calories: return "Калории"
        }
    }

    var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .spo2: return "%"
        case .strain: return ""
        case .sleepHours: return "ч"
        case .hrv: return "мс"
        case .restingHR: return "уд/мин"
        case .respiratoryRate: return "вд/мин"
        case .steps: return ""
        case .calories: return "ккал"
        }
    }

    var digits: Int {
        switch self {
        case .strain, .sleepHours, .respiratoryRate, .spo2: return 1
        default: return 0
        }
    }

    var color: Color {
        switch self {
        case .recovery: return Theme.recoveryGreen
        case .strain: return Theme.strain
        case .sleepPerformance, .sleepHours: return Theme.sleep
        case .hrv: return Theme.recoveryGreen
        case .restingHR: return Theme.heart
        case .respiratoryRate: return Theme.strain
        case .spo2: return Theme.recoveryRed
        case .steps: return Theme.recoveryYellow
        case .calories: return Theme.stress
        }
    }

    /// Для пульса покоя «меньше — лучше».
    var lowerIsBetter: Bool { self == .restingHR }

    func value(_ day: DayMetrics) -> Double? {
        switch self {
        case .recovery: return day.recovery
        case .strain: return day.strain > 0 ? day.strain : nil
        case .sleepPerformance: return day.sleepPerformance
        case .sleepHours: return day.sleep.map { $0.asleep / 3600 }
        case .hrv: return day.vitals.hrv
        case .restingHR: return day.vitals.restingHR
        case .respiratoryRate: return day.vitals.respiratoryRate
        case .spo2: return day.vitals.spo2
        case .steps: return day.steps > 0 ? day.steps : nil
        case .calories: return day.totalEnergy > 0 ? day.totalEnergy : nil
        }
    }
}

struct TrendsView: View {
    @EnvironmentObject private var store: HealthDataStore
    @State private var metric: TrendMetric = .recovery
    @State private var range = 30

    private struct Point: Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    private var points: [Point] {
        store.days.suffix(range).compactMap { day in metric.value(day).map { Point(date: day.day, value: $0) } }
    }

    private var previousPoints: [Double] {
        store.days.dropLast(range).suffix(range).compactMap { metric.value($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TrendMetric.allCases) { item in
                                Button {
                                    metric = item
                                } label: {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(metric == item ? item.color : Theme.card, in: Capsule())
                                        .foregroundStyle(metric == item ? Color.black : Color.white)
                                }
                            }
                        }
                    }

                    Picker("Период", selection: $range) {
                        Text("7 дней").tag(7)
                        Text("30 дней").tag(30)
                        Text("60 дней").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Card {
                        SectionTitle(title: metric.title, trailing: metric.unit)
                        chart
                            .frame(height: 220)
                    }

                    statsCard
                    WeeklyReportCard()
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Тренды")
        }
    }

    @ViewBuilder
    private var chart: some View {
        let average = points.map(\.value).mean
        Chart {
            ForEach(points) { point in
                if metric == .strain || metric == .steps || metric == .calories || metric == .recovery || metric == .sleepHours {
                    BarMark(x: .value("День", point.date, unit: .day), y: .value(metric.title, point.value))
                        .foregroundStyle(metric == .recovery ? Theme.recoveryColor(point.value) : metric.color)
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("День", point.date, unit: .day), y: .value(metric.title, point.value))
                        .foregroundStyle(metric.color)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("День", point.date, unit: .day), y: .value(metric.title, point.value))
                        .foregroundStyle(metric.color)
                        .symbolSize(16)
                }
            }
            if let average {
                RuleMark(y: .value("Среднее", average))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: metric == .strain || metric == .recovery || metric == .steps || metric == .calories || metric == .sleepHours))
    }

    private var statsCard: some View {
        let values = points.map(\.value)
        let average = values.mean
        let previous = previousPoints.mean
        return Card {
            SectionTitle(title: "Статистика")
            StatRow(title: "Среднее", value: format(average))
            StatRow(title: "Минимум", value: format(values.min()))
            StatRow(title: "Максимум", value: format(values.max()))
            if let average, let previous, previous != 0 {
                let change = (average / previous - 1) * 100
                let good = metric.lowerIsBetter ? change < 0 : change > 0
                HStack {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("\(Fmt.signed(change))% к предыдущему периоду")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(abs(change) < 2 ? Theme.secondaryText : (good ? Theme.recoveryGreen : Theme.recoveryRed))
            }
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return Fmt.number(value, digits: metric.digits) + (metric.unit.isEmpty ? "" : " \(metric.unit)")
    }
}

/// Еженедельный отчёт — аналог «Performance Assessment».
struct WeeklyReportCard: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        let week = Array(store.days.suffix(7))
        let previous = Array(store.days.dropLast(7).suffix(7))
        Card {
            SectionTitle(title: "Отчёт за неделю")
            row("Восстановление", week.compactMap(\.recovery).mean, previous.compactMap(\.recovery).mean, unit: "%", digits: 0)
            row("Нагрузка", week.map(\.strain).mean, previous.map(\.strain).mean, unit: "", digits: 1)
            row("Сон", week.compactMap { $0.sleep?.asleep }.mean.map { $0 / 3600 }, previous.compactMap { $0.sleep?.asleep }.mean.map { $0 / 3600 }, unit: "ч", digits: 1)
            row("ВСР", week.compactMap(\.vitals.hrv).mean, previous.compactMap(\.vitals.hrv).mean, unit: "мс", digits: 0)
            row("Пульс покоя", week.compactMap(\.vitals.restingHR).mean, previous.compactMap(\.vitals.restingHR).mean, unit: "уд/мин", digits: 0)
            let greenDays = week.filter { ($0.recovery ?? 0) >= 67 }.count
            Text("Зелёных дней: \(greenDays) из \(week.count). Тренировок: \(week.reduce(0) { $0 + $1.workouts.count }).")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func row(_ title: String, _ current: Double?, _ previous: Double?, unit: String, digits: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(Fmt.number(current, digits: digits) + (unit.isEmpty ? "" : " \(unit)"))
                .fontWeight(.semibold)
            if let current, let previous {
                Text(Fmt.signed(current - previous, digits: digits))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.subheadline)
    }
}
