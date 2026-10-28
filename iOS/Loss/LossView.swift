import SwiftUI
import Charts

struct LossView: View {
    @EnvironmentObject private var loss: LossStore
    @EnvironmentObject private var store: HealthDataStore
    @State private var showWeighIn = false
    @State private var showAddFood = false
    @State private var selectedFood: FoodEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BalanceCard()
                    WeightCard(onWeighIn: { showWeighIn = true })
                    FoodTodayCard(onAdd: { showAddFood = true }, onSelect: { selectedFood = $0 })
                    WeekBalanceCard()
                    TodayPlanCard()
                }
                .padding(16)
            }
            .refreshable {
                await store.refresh()
                await loss.importHealthWeights()
            }
            .screenBackground()
            .navigationTitle("Похудение")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        LossSettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showWeighIn) { WeighInSheet() }
            .sheet(isPresented: $showAddFood) { AddFoodSheet() }
            .sheet(item: $selectedFood) { entry in FoodDetailSheet(entryID: entry.id) }
            .task { await loss.importHealthWeights() }
        }
    }
}

// MARK: - Баланс за сегодня

struct BalanceCard: View {
    @EnvironmentObject private var loss: LossStore

    var body: some View {
        let today = loss.energy(for: Date())
        let budget = loss.dailyBudget
        let remaining = budget - today.eaten
        let projected = today.eaten - loss.projectedBurnToday
        Card {
            SectionTitle(title: "Баланс за сегодня", trailing: "цель −\(Int(loss.settings.dailyDeficit)) ккал")
            HStack(spacing: 18) {
                ZStack {
                    RingView(progress: today.eaten / max(budget, 1), color: today.eaten > budget ? Theme.recoveryRed : Theme.recoveryGreen, lineWidth: 12)
                    VStack(spacing: 0) {
                        Text("\(Int(abs(remaining)))")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(remaining >= 0 ? "осталось" : "перебор")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    EnergyRow(symbol: "fork.knife", color: Theme.stress, title: "Съедено", value: today.eaten)
                    EnergyRow(symbol: "flame.fill", color: Theme.recoveryRed, title: "Активные", value: today.active)
                    EnergyRow(symbol: "bed.double.fill", color: Theme.sleep, title: today.basalEstimated ? "Обмен*" : "Обмен", value: today.basal)
                    EnergyRow(symbol: "plusminus", color: today.balance <= 0 ? Theme.recoveryGreen : Theme.recoveryRed, title: "Баланс", value: today.balance, signed: true)
                }
            }
            Text("«Активные» — то же число, что красное кольцо в «Фитнесе». «Обмен» — базовые калории, которые организм тратит в покое (сон, дыхание, мозг); Apple Watch считает их отдельно и в «Фитнесе» не показывает. Сожжено всего: \(Int(today.burned)) ккал на сейчас.")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
            Text("К концу дня: \(Fmt.signed(projected)) ккал ≈ \(weightText(projected / 7700)). Норма на день — \(Int(budget)) ккал.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if today.basalEstimated {
                Text("* базовый обмен рассчитан по формуле — часы ещё не передали данные")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

private struct EnergyRow: View {
    var symbol: String
    var color: Color
    var title: String
    var value: Double
    var signed = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text((signed ? Fmt.signed(value) : Fmt.number(value)) + " ккал")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

func weightText(_ kg: Double) -> String {
    String(format: "%+.2f кг", kg)
}

// MARK: - Вес

struct WeightCard: View {
    @EnvironmentObject private var loss: LossStore
    var onWeighIn: () -> Void

    var body: some View {
        Card {
            SectionTitle(title: "Вес", trailing: loss.latestWeight.map { "\(Fmt.shortDay($0.date)), \(Fmt.time($0.date))" })
            HStack(alignment: .firstTextBaseline) {
                Text(loss.latestWeight.map { String(format: "%.1f", $0.kg) } ?? "—")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("кг").foregroundStyle(Theme.secondaryText)
                Spacer()
                if let change = loss.weightChange(days: 7) {
                    VStack(alignment: .trailing) {
                        Text(String(format: "%+.1f кг", change))
                            .font(.headline)
                            .foregroundStyle(change <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                        Text("за 7 дней").font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                }
            }
            if let goal = loss.settings.goalWeight, let latest = loss.latestWeight {
                GoalProgress(start: loss.statsWeights.first?.kg ?? latest.kg, current: latest.kg, goal: goal, date: loss.goalDate)
            }
            WeightChart()
                .frame(height: 160)
            HStack {
                Button(action: onWeighIn) {
                    Label("Взвеситься", systemImage: "scalemass.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.recoveryGreen, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                NavigationLink {
                    WeightHistoryView()
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 44, height: 40)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private struct GoalProgress: View {
    var start: Double
    var current: Double
    var goal: Double
    var date: Date?

    var body: some View {
        let total = max(start - goal, 0.1)
        let done = clamp((start - current) / total, 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: done)
                .tint(Theme.recoveryGreen)
            HStack {
                Text("Цель \(String(format: "%.1f", goal)) кг · осталось \(String(format: "%.1f", max(0, current - goal))) кг")
                Spacer()
                if let date {
                    Text("≈ \(Fmt.shortDay(date))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
    }
}

struct WeightChart: View {
    @EnvironmentObject private var loss: LossStore

    private struct Point: Identifiable {
        var date: Date
        var kg: Double
        var series: String
        var id: String { series + "\(date.timeIntervalSince1970)" }
    }

    /// Факт и прогноз по калориям: старт с первого взвешивания за 60 дней.
    private var points: [Point] {
        let from = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let actual = loss.statsWeights.filter { $0.date >= from }
        var result = actual.map { Point(date: $0.date, kg: $0.kg, series: "Факт") }
        if let first = actual.first {
            var predicted = first.kg
            var day = Calendar.current.startOfDay(for: first.date)
            let today = Calendar.current.startOfDay(for: Date())
            result.append(Point(date: first.date, kg: predicted, series: "По калориям"))
            while day < today {
                let energy = loss.energy(for: day)
                if energy.hasFood { predicted += energy.weightChange }
                day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? today
                result.append(Point(date: day, kg: predicted, series: "По калориям"))
            }
        }
        return result
    }

    var body: some View {
        let data = points
        if data.isEmpty {
            Text("Взвесьтесь, чтобы увидеть график")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Chart {
                ForEach(data) { point in
                    LineMark(x: .value("Дата", point.date), y: .value("Вес", point.kg))
                        .foregroundStyle(by: .value("Серия", point.series))
                        .lineStyle(StrokeStyle(lineWidth: point.series == "Факт" ? 2.5 : 1.5, dash: point.series == "Факт" ? [] : [4, 4]))
                        .interpolationMethod(.monotone)
                }
                if let goal = loss.settings.goalWeight {
                    RuleMark(y: .value("Цель", goal))
                        .foregroundStyle(Theme.recoveryGreen.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            .chartForegroundStyleScale(["Факт": Theme.recoveryGreen, "По калориям": Theme.stress])
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(position: .bottom)
        }
    }
}

// MARK: - Неделя

struct WeekBalanceCard: View {
    @EnvironmentObject private var loss: LossStore

    private struct Bar: Identifiable {
        var day: Date
        var kind: String
        var kcal: Double
        var id: String { kind + "\(day.timeIntervalSince1970)" }
    }

    var body: some View {
        let days = loss.energyDays(7)
        let logged = days.filter(\.hasFood)
        let totalChange = logged.reduce(0) { $0 + $1.weightChange }
        let bars = days.flatMap { day in
            [Bar(day: day.day, kind: "Съедено", kcal: day.eaten), Bar(day: day.day, kind: "Сожжено", kcal: day.burned)]
        }
        Card {
            SectionTitle(title: "Неделя", trailing: logged.isEmpty ? nil : "\(logged.count) дн. с записями")
            Chart(bars) { bar in
                BarMark(x: .value("День", bar.day, unit: .day), y: .value("ккал", bar.kcal))
                    .foregroundStyle(by: .value("Тип", bar.kind))
                    .position(by: .value("Тип", bar.kind))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale(["Съедено": Theme.stress, "Сожжено": Theme.strain])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: 170)
            if logged.isEmpty {
                Text("Записывайте еду — здесь появится расчёт изменения веса.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("По калориям за дни с записями: \(weightText(totalChange)) (\(Fmt.signed(logged.reduce(0) { $0 + $1.balance })) ккал)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(totalChange <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
            }
        }
    }
}
