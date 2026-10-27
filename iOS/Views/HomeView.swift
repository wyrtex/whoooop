import SwiftUI
import HealthKit

struct HomeView: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DayNavigator()
                    if let day = store.selected {
                        DialsRow(day: day)
                        CoachCard(day: day)
                        StrainTargetCard(day: day)
                        ActivitiesCard(day: day)
                        StressSummaryCard(day: day)
                        KeyMetricsCard(day: day)
                        StartWatchWorkoutCard()
                    } else if store.isLoading {
                        ProgressView("Загружаем данные из Apple Health…")
                            .padding(.top, 80)
                    } else {
                        EmptyStateView(
                            symbol: "applewatch",
                            title: "Пока нет данных",
                            message: "Убедитесь, что Apple Watch синхронизированы с iPhone и в Здоровье разрешён доступ для Pulsar.")
                        Button("Обновить") { Task { await store.refresh() } }
                    }
                }
                .padding(16)
            }
            .refreshable { await store.refresh() }
            .screenBackground()
            .navigationTitle("Pulsar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

struct DayNavigator: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        HStack {
            Button { store.shiftSelection(by: -1) } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            .disabled(!store.canSelectPrevious)
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.dayTitle(store.selectedDay))
                    .font(.headline)
                if let updated = store.lastUpdated {
                    Text("Обновлено в \(Fmt.time(updated))")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer()
            Button { store.shiftSelection(by: 1) } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(!store.canSelectNext)
        }
        .foregroundStyle(.white)
    }
}

struct DialsRow: View {
    var day: DayMetrics

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            NavigationLink {
                SleepDetailView(day: day)
            } label: {
                ScoreDial(title: "СОН", value: Fmt.percent(day.sleepPerformance), progress: (day.sleepPerformance ?? 0) / 100, color: Theme.sleep)
                    .frame(maxWidth: .infinity)
            }
            NavigationLink {
                RecoveryDetailView(day: day)
            } label: {
                ScoreDial(title: "ВОССТАНОВЛ.", value: Fmt.percent(day.recovery), progress: (day.recovery ?? 0) / 100, color: Theme.recoveryColor(day.recovery), size: 116, lineWidth: 11)
                    .frame(maxWidth: .infinity)
            }
            NavigationLink {
                StrainDetailView(day: day)
            } label: {
                ScoreDial(title: "НАГРУЗКА", value: Fmt.strain(day.strain), progress: day.strain / StrainEngine.maxStrain, color: Theme.strain)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
    }
}

struct CoachCard: View {
    @EnvironmentObject private var store: HealthDataStore
    var day: DayMetrics

    var body: some View {
        let insights = CoachEngine.insights(for: day, history: store.days, profile: store.profile)
        Card {
            SectionTitle(title: "Коуч")
            ForEach(insights.prefix(3)) { insight in
                InsightRow(insight: insight)
            }
        }
    }
}

struct StrainTargetCard: View {
    var day: DayMetrics

    var body: some View {
        let target = StrainEngine.target(forRecovery: day.recovery)
        Card {
            SectionTitle(title: "Цель по нагрузке", trailing: String(format: "%.0f–%.0f", target.lowerBound, target.upperBound))
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardRaised)
                    Capsule()
                        .fill(Theme.strain.opacity(0.35))
                        .frame(width: width * (target.upperBound - target.lowerBound) / 21)
                        .offset(x: width * target.lowerBound / 21)
                    Capsule()
                        .fill(Theme.strain)
                        .frame(width: max(8, width * day.strain / 21))
                }
            }
            .frame(height: 12)
            HStack {
                Text("Сейчас \(Fmt.strain(day.strain)) · \(StrainEngine.level(day.strain))")
                Spacer()
                Text(statusText(target))
                    .foregroundStyle(Theme.secondaryText)
            }
            .font(.footnote)
        }
    }

    private func statusText(_ target: ClosedRange<Double>) -> String {
        if day.strain < target.lowerBound { return "до цели \(Fmt.strain(target.lowerBound - day.strain))" }
        if day.strain <= target.upperBound { return "в целевой зоне" }
        return "выше цели"
    }
}

struct ActivitiesCard: View {
    var day: DayMetrics

    var body: some View {
        Card {
            SectionTitle(title: "Мой день", trailing: "\(day.workouts.count) актив.")
            if let sleep = day.sleep {
                NavigationLink {
                    SleepDetailView(day: day)
                } label: {
                    ActivityRow(symbol: "moon.fill", color: Theme.sleep, title: "Сон", subtitle: "\(Fmt.time(sleep.start)) – \(Fmt.time(sleep.end))", value: Fmt.duration(sleep.asleep))
                }
            }
            ForEach(day.naps, id: \.start) { nap in
                ActivityRow(symbol: "powersleep", color: Theme.sleep, title: "Дневной сон", subtitle: "\(Fmt.time(nap.start)) – \(Fmt.time(nap.end))", value: Fmt.duration(nap.asleep))
            }
            ForEach(day.workouts) { workout in
                NavigationLink {
                    WorkoutDetailView(workout: workout)
                } label: {
                    ActivityRow(symbol: workout.symbol, color: Theme.strain, title: workout.name, subtitle: "\(Fmt.time(workout.start)) – \(Fmt.time(workout.end))", value: Fmt.strain(workout.strain))
                }
            }
            if day.workouts.isEmpty && day.sleep == nil {
                Text("Сегодня ещё нет активностей")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ActivityRow: View {
    var symbol: String
    var color: Color
    var title: String
    var subtitle: String
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text(value)
                .font(.headline.monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.tertiaryText)
        }
        .contentShape(Rectangle())
    }
}

struct StressSummaryCard: View {
    var day: DayMetrics

    var body: some View {
        NavigationLink {
            StressView(day: day)
        } label: {
            Card {
                SectionTitle(title: "Монитор стресса")
                if let level = day.currentStress {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Fmt.number(level, digits: 1))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.stressColor(level))
                        Text("/ 3 · \(StressEngine.title(level))")
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiaryText)
                    }
                    StressChart(points: day.stress, compact: true)
                        .frame(height: 70)
                } else {
                    Text("Недостаточно данных о пульсе за день")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct KeyMetricsCard: View {
    var day: DayMetrics

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var temperatureText: String {
        guard let temp = day.vitals.wristTemp, let baseline = day.baselines.wristTemp else { return "—" }
        return Fmt.signed(temp - baseline.mean, digits: 1)
    }

    var body: some View {
        Card {
            SectionTitle(title: "Ключевые показатели")
            LazyVGrid(columns: columns, spacing: 10) {
                MetricTile(title: "ВСР", value: Fmt.number(day.vitals.hrv), unit: "мс", symbol: "waveform.path.ecg", color: Theme.recoveryGreen,
                           footnote: baselineDelta(value: day.vitals.hrv, mean: day.baselines.hrvMean, unit: "мс", relative: true))
                MetricTile(title: "Пульс покоя", value: Fmt.number(day.vitals.restingHR), unit: "уд/мин", symbol: "heart.fill", color: Theme.heart,
                           footnote: baselineDelta(value: day.vitals.restingHR, mean: day.baselines.restingHR?.mean, unit: "уд"))
                MetricTile(title: "Дыхание", value: Fmt.number(day.vitals.respiratoryRate, digits: 1), unit: "вд/мин", symbol: "lungs.fill", color: Theme.strain,
                           footnote: baselineDelta(value: day.vitals.respiratoryRate, mean: day.baselines.respiratoryRate?.mean, unit: "", digits: 1))
                MetricTile(title: "SpO₂", value: Fmt.number(day.vitals.spo2, digits: 1), unit: "%", symbol: "drop.fill", color: Theme.recoveryRed)
                MetricTile(title: "Темп. кожи", value: temperatureText, unit: "°C", symbol: "thermometer.medium", color: Theme.stress, footnote: "отклонение от нормы")
                MetricTile(title: "Калории", value: Fmt.number(day.totalEnergy), unit: "ккал", symbol: "flame.fill", color: Theme.stress, footnote: "активные \(Fmt.number(day.activeEnergy))")
                MetricTile(title: "Шаги", value: Fmt.number(day.steps), unit: "", symbol: "figure.walk", color: Theme.recoveryGreen)
                MetricTile(title: "Средний пульс", value: Fmt.number(day.avgHR), unit: "уд/мин", symbol: "heart.circle", color: Theme.heart)
            }
        }
    }
}

struct StartWatchWorkoutCard: View {
    @State private var errorText: String?
    @State private var started = false

    var body: some View {
        Card {
            SectionTitle(title: "Тренировка")
            Text("Запустите тренировку на Apple Watch — пульс, зоны и нагрузка будут видны в реальном времени.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Menu {
                ForEach(WorkoutCatalog.startable, id: \.rawValue) { type in
                    let info = WorkoutCatalog.info(for: type)
                    Button {
                        HealthKitService.shared.startWatchWorkout(type) { error in
                            if let error {
                                errorText = error.localizedDescription
                            } else {
                                started = true
                            }
                        }
                    } label: {
                        Label(info.name, systemImage: info.symbol)
                    }
                }
            } label: {
                Label("Начать на часах", systemImage: "applewatch.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.strain, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            if started {
                Text("Тренировка запущена на часах")
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryGreen)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryRed)
            }
        }
    }
}
