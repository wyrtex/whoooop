import SwiftUI
import HealthKit

struct WatchRootView: View {
    @EnvironmentObject private var store: HealthDataStore
    @EnvironmentObject private var workout: WorkoutManager
    @EnvironmentObject private var sync: SyncBridge
    @EnvironmentObject private var heartRate: LiveHeartRateMonitor
    @Environment(\.scenePhase) private var scenePhase

    /// Свежая сводка с iPhone важнее локального расчёта: у телефона больше истории для норм.
    private var summary: WatchSummary? {
        if let remote = sync.summary, remote.isToday, Date().timeIntervalSince(remote.generatedAt) < 6 * 3600 {
            return remote
        }
        if let today = store.today, Calendar.current.isDateInToday(today.day) {
            return WatchSummary.make(from: today, profile: store.profile)
        }
        return sync.summary
    }

    var body: some View {
        Group {
            if workout.isActive {
                WorkoutSessionView()
            } else if let result = workout.summary {
                WorkoutSummaryView(summary: result)
            } else {
                NavigationStack {
                    TabView {
                        SummaryPage(summary: summary)
                        LivePage(summary: summary)
                        WorkoutStartPage(summary: summary)
                        SleepPage(summary: summary)
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
        }
        .task {
            sync.activate()
            try? await HealthKitService.shared.requestAuthorization()
            heartRate.start()
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .onChange(of: sync.summary) { _, remote in
            if let remote { store.applyRemoteProfile(remote.profile) }
        }
    }
}

struct SummaryPage: View {
    var summary: WatchSummary?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RingView(progress: (summary?.recovery ?? 0) / 100, color: Theme.recoveryColor(summary?.recovery), lineWidth: 9)
                VStack(spacing: 0) {
                    Text(Fmt.percent(summary?.recovery))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ВОССТ.")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 108, height: 108)

            HStack(spacing: 18) {
                ScoreDial(title: "СОН", value: Fmt.percent(summary?.sleepPerformance), progress: (summary?.sleepPerformance ?? 0) / 100, color: Theme.sleep, size: 48, lineWidth: 5)
                ScoreDial(title: "НАГРУЗКА", value: Fmt.strain(summary?.strain ?? 0), progress: (summary?.strain ?? 0) / StrainEngine.maxStrain, color: Theme.strain, size: 48, lineWidth: 5)
            }
        }
        .containerBackground(Theme.recoveryColor(summary?.recovery).opacity(0.25).gradient, for: .tabView)
        .navigationTitle("Pulsar")
    }
}

struct LivePage: View {
    @EnvironmentObject private var heartRate: LiveHeartRateMonitor
    @EnvironmentObject private var store: HealthDataStore
    var summary: WatchSummary?

    private var stress: Double? {
        guard let bpm = heartRate.bpm else { return summary?.stress }
        let resting = summary?.restingHR ?? store.today?.vitals.restingHR ?? 62
        return StressEngine.level(bpm: bpm, restingHR: resting, maxHR: store.profile.maxHR)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.heart)
                Text(Fmt.number(heartRate.bpm))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("уд/мин").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            if let date = heartRate.date {
                Text("замер в \(Fmt.time(date))")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }

            if let stress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Стресс \(Fmt.number(stress, digits: 1)) · \(StressEngine.title(stress))")
                        .font(.footnote)
                    Gauge(value: stress, in: 0...3) { EmptyView() }
                        .gaugeStyle(.accessoryLinear)
                        .tint(Gradient(colors: [Theme.recoveryGreen, Theme.recoveryYellow, Theme.stress]))
                }
            }

            if let summary {
                Text("Нагрузка \(Fmt.strain(summary.strain)) · цель \(Fmt.number(summary.strainTargetLow))–\(Fmt.number(summary.strainTargetHigh))")
                    .font(.footnote)
                    .foregroundStyle(Theme.strain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(Theme.heart.opacity(0.2).gradient, for: .tabView)
        .navigationTitle("Сейчас")
    }
}

struct WorkoutStartPage: View {
    @EnvironmentObject private var workout: WorkoutManager
    @EnvironmentObject private var store: HealthDataStore
    var summary: WatchSummary?

    var body: some View {
        List {
            ForEach(WorkoutCatalog.startable, id: \.rawValue) { type in
                let info = WorkoutCatalog.info(for: type)
                Button {
                    workout.restingHR = summary?.restingHR ?? store.today?.vitals.restingHR ?? 62
                    workout.maxHR = (summary?.profile ?? store.profile).maxHR
                    workout.sex = (summary?.profile ?? store.profile).sex
                    workout.dayStrainBefore = summary?.strain ?? 0
                    workout.start(activity: type)
                } label: {
                    Label(info.name, systemImage: info.symbol)
                }
            }
            if let error = workout.errorText {
                Text(error).font(.footnote).foregroundStyle(Theme.recoveryRed)
            }
        }
        .navigationTitle("Тренировка")
        .containerBackground(Theme.strain.opacity(0.2).gradient, for: .tabView)
    }
}

struct SleepPage: View {
    var summary: WatchSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let asleep = summary?.sleepAsleep {
                    Text(Fmt.duration(asleep))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    if let need = summary?.sleepNeed {
                        Text("из \(Fmt.duration(need)) необходимых")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text("Качество: \(Fmt.percent(summary?.sleepPerformance))")
                        .font(.footnote)
                        .foregroundStyle(Theme.sleep)
                    if let stages = summary?.sleepStages, stages.count == SleepStage.allCases.count {
                        ForEach(Array(SleepStage.allCases.enumerated()), id: \.offset) { index, stage in
                            HStack {
                                Circle().fill(Theme.stageColor(stage)).frame(width: 8, height: 8)
                                Text(stage.title).font(.caption2)
                                Spacer()
                                Text(Fmt.duration(stages[index])).font(.caption2.monospacedDigit())
                            }
                        }
                    }
                } else {
                    Text("Нет данных о сне")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let hrv = summary?.hrv {
                    Text("ВСР \(Fmt.number(hrv)) мс · пульс покоя \(Fmt.number(summary?.restingHR))")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Сон")
        .containerBackground(Theme.sleep.opacity(0.2).gradient, for: .tabView)
    }
}
