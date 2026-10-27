import SwiftUI
import HealthKit
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        SyncBridge.shared.activate()
    }

    /// Вызывается, когда тренировку запускают с iPhone.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WorkoutManager.shared.start(configuration: workoutConfiguration)
        }
    }
}

@main
struct PulsarWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var store = HealthDataStore(historyDays: 21)
    @StateObject private var workout = WorkoutManager.shared
    @StateObject private var sync = SyncBridge.shared
    @StateObject private var heartRate = LiveHeartRateMonitor()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .environmentObject(workout)
                .environmentObject(sync)
                .environmentObject(heartRate)
        }
    }
}

/// Последний замер пульса вне тренировки (часы меряют его каждые несколько минут).
@MainActor
final class LiveHeartRateMonitor: ObservableObject {
    @Published private(set) var bpm: Double?
    @Published private(set) var date: Date?
    private var query: HKAnchoredObjectQuery?

    func start() {
        guard query == nil else { return }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-6 * 3600), end: nil, options: [])
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            guard let latest = (samples as? [HKQuantitySample])?.max(by: { $0.endDate < $1.endDate }) else { return }
            let value = latest.quantity.doubleValue(for: HealthKitService.bpm)
            let date = latest.endDate
            Task { @MainActor in
                guard let self else { return }
                if let current = self.date, current >= date { return }
                self.bpm = value
                self.date = date
            }
        }
        let query = HKAnchoredObjectQuery(
            type: HKQuantityType(.heartRate),
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler)
        query.updateHandler = handler
        HealthKitService.shared.store.execute(query)
        self.query = query
    }

    func stop() {
        if let query { HealthKitService.shared.store.stop(query) }
        query = nil
    }
}
