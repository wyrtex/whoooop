import SwiftUI
import HealthKit

struct WorkoutSessionView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        TabView {
            WorkoutControlsView()
            WorkoutMetricsView()
            WorkoutZonesView()
        }
        .tabViewStyle(.page)
    }
}

struct WorkoutMetricsView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.clock(workout.elapsed(at: context.date)))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.recoveryYellow)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Fmt.number(workout.heartRate))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.zoneColors[workout.zone])
                    Text(StrainEngine.zoneTitle(workout.zone))
                        .font(.caption2)
                        .foregroundStyle(Theme.zoneColors[workout.zone])
                }
                Text("Нагрузка \(Fmt.strain(workout.strain)) · день \(Fmt.strain(workout.dayStrain))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.strain)
                Text("\(Fmt.number(workout.activeEnergy)) ккал")
                    .font(.footnote)
                if let distance = Fmt.distance(workout.distance) {
                    Text(distance).font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WorkoutZonesView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Зоны пульса").font(.footnote.weight(.semibold))
            ForEach((0..<StrainEngine.zoneCount).reversed(), id: \.self) { zone in
                let total = max(workout.zoneSeconds.reduce(0, +), 1)
                HStack(spacing: 6) {
                    Text(zone == 0 ? "П" : "\(zone)")
                        .font(.caption2.weight(.bold))
                        .frame(width: 14)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(Theme.zoneColors[zone])
                                .frame(width: max(3, proxy.size.width * workout.zoneSeconds[zone] / total))
                        }
                    }
                    .frame(height: 8)
                    Text(Fmt.clock(workout.zoneSeconds[zone]))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }
}

struct WorkoutControlsView: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        VStack(spacing: 12) {
            let info = WorkoutCatalog.info(for: workout.activity)
            Label(info.name, systemImage: info.symbol)
                .font(.headline)
            HStack(spacing: 12) {
                VStack {
                    Button {
                        workout.end()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(Theme.recoveryRed)
                    .font(.title2)
                    Text("Завершить").font(.caption2)
                }
                VStack {
                    Button {
                        workout.togglePause()
                    } label: {
                        Image(systemName: workout.isRunning ? "pause" : "play")
                    }
                    .tint(Theme.recoveryYellow)
                    .font(.title2)
                    Text(workout.isRunning ? "Пауза" : "Продолжить").font(.caption2)
                }
            }
        }
    }
}

struct WorkoutSummaryView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @EnvironmentObject private var store: HealthDataStore
    var summary: WorkoutManager.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let info = WorkoutCatalog.info(for: summary.activity)
                Label(info.name, systemImage: info.symbol)
                    .font(.headline)
                HStack {
                    ScoreDial(title: "НАГРУЗКА", value: Fmt.strain(summary.strain), progress: summary.strain / StrainEngine.maxStrain, color: Theme.strain, size: 62, lineWidth: 6)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.durationLong(summary.duration)).font(.footnote.weight(.semibold))
                        Text("\(Fmt.number(summary.energy)) ккал").font(.footnote)
                        if let distance = Fmt.distance(summary.distance) {
                            Text(distance).font(.footnote)
                        }
                    }
                }
                row("Средний пульс", "\(Fmt.number(summary.averageHR)) уд/мин")
                row("Максимальный", "\(Fmt.number(summary.maxHR)) уд/мин")
                Button("Готово") {
                    workout.dismissSummary()
                    Task { await store.refresh() }
                }
                .tint(Theme.strain)
                .padding(.top, 6)
            }
        }
        .navigationTitle("Итог")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}
