import Foundation
import HealthKit
import WatchKit

/// Тренировка на часах: HKWorkoutSession + живой подсчёт нагрузки по пульсу.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    struct Summary {
        var activity: HKWorkoutActivityType
        var duration: TimeInterval
        var strain: Double
        var averageHR: Double
        var maxHR: Double
        var energy: Double
        var distance: Double
        var zoneSeconds: [Double]
    }

    @Published private(set) var isActive = false
    @Published private(set) var isRunning = false
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var averageHeartRate: Double = 0
    @Published private(set) var peakHeartRate: Double = 0
    @Published private(set) var activeEnergy: Double = 0
    @Published private(set) var distance: Double = 0
    @Published private(set) var strain: Double = 0
    @Published private(set) var zone: Int = 0
    @Published private(set) var zoneSeconds = Array(repeating: 0.0, count: StrainEngine.zoneCount)
    @Published private(set) var activity: HKWorkoutActivityType = .running
    @Published var summary: Summary?
    @Published var errorText: String?

    private let healthStore = HealthKitService.shared.store
    private var session: HKWorkoutSession?
    private(set) var builder: HKLiveWorkoutBuilder?
    private var trimp = 0.0
    private var lastSampleDate: Date?

    /// Параметры пульсовых зон приходят из профиля/данных дня.
    var restingHR: Double = 62
    var maxHR: Double = 190
    var sex: BiologicalSexOption = .male
    /// Нагрузка за день до начала тренировки — чтобы показать итоговую дневную нагрузку.
    var dayStrainBefore: Double = 0

    var dayStrain: Double {
        StrainEngine.strain(fromTrimp: StrainEngine.trimp(forStrain: dayStrainBefore) + trimp)
    }

    func elapsed(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    func start(activity: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = WorkoutCatalog.location(for: activity)
        start(configuration: configuration)
    }

    func start(configuration: HKWorkoutConfiguration) {
        guard session == nil else { return }
        reset()
        activity = configuration.activityType
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, error in
                if let error {
                    Task { @MainActor in self.errorText = error.localizedDescription }
                }
            }
            isActive = true
            isRunning = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    func togglePause() {
        guard let session else { return }
        if isRunning { session.pause() } else { session.resume() }
    }

    func end() {
        session?.end()
    }

    func dismissSummary() {
        summary = nil
    }

    private func reset() {
        heartRate = 0
        averageHeartRate = 0
        peakHeartRate = 0
        activeEnergy = 0
        distance = 0
        strain = 0
        zone = 0
        zoneSeconds = Array(repeating: 0, count: StrainEngine.zoneCount)
        trimp = 0
        lastSampleDate = nil
        summary = nil
        errorText = nil
    }

    private func handle(statistics: HKStatistics) {
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HealthKitService.bpm
            guard let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit) else { return }
            averageHeartRate = statistics.averageQuantity()?.doubleValue(for: unit) ?? bpm
            peakHeartRate = max(peakHeartRate, statistics.maximumQuantity()?.doubleValue(for: unit) ?? bpm)
            registerHeartRate(bpm, at: statistics.mostRecentQuantityDateInterval()?.end ?? Date())
        case HKQuantityType(.activeEnergyBurned):
            activeEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeEnergy
        case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
            distance = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? distance
        default:
            break
        }
    }

    private func registerHeartRate(_ bpm: Double, at date: Date) {
        if let last = lastSampleDate, isRunning {
            let dt = clamp(date.timeIntervalSince(last), 0, 30)
            trimp += StrainEngine.trimpRate(bpm: bpm, restingHR: restingHR, maxHR: maxHR, sex: sex) * dt / 60
            zoneSeconds[StrainEngine.zone(bpm: bpm, maxHR: maxHR)] += dt
        }
        lastSampleDate = date
        heartRate = bpm
        strain = StrainEngine.strain(fromTrimp: trimp)

        let newZone = StrainEngine.zone(bpm: bpm, maxHR: maxHR)
        if newZone != zone {
            if newZone >= 4 { WKInterfaceDevice.current().play(.directionUp) }
            zone = newZone
        }
    }

    private func finish(at date: Date) {
        guard let builder else { return }
        let duration = builder.elapsedTime(at: date)
        builder.endCollection(withEnd: date) { _, _ in
            builder.finishWorkout { _, _ in
                Task { @MainActor in
                    self.summary = Summary(
                        activity: self.activity,
                        duration: duration,
                        strain: self.strain,
                        averageHR: self.averageHeartRate,
                        maxHR: self.peakHeartRate,
                        energy: self.activeEnergy,
                        distance: self.distance,
                        zoneSeconds: self.zoneSeconds)
                    self.session = nil
                    self.builder = nil
                    self.isActive = false
                    self.isRunning = false
                }
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.isRunning = toState == .running
            if toState == .ended {
                self.finish(at: date)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorText = error.localizedDescription
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let statistics = collectedTypes.compactMap { type -> HKStatistics? in
            guard let quantityType = type as? HKQuantityType else { return nil }
            return workoutBuilder.statistics(for: quantityType)
        }
        Task { @MainActor in
            for item in statistics { self.handle(statistics: item) }
        }
    }
}
