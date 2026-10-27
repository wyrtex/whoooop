import Foundation
import WatchConnectivity

/// Короткая сводка дня, которую iPhone отправляет на часы.
struct WatchSummary: Codable, Equatable {
    var generatedAt: Date
    var day: Date
    var recovery: Double?
    var strain: Double
    var strainTargetLow: Double
    var strainTargetHigh: Double
    var sleepPerformance: Double?
    var sleepAsleep: TimeInterval?
    var sleepNeed: TimeInterval?
    var sleepStages: [Double]?
    var hrv: Double?
    var restingHR: Double?
    var respiratoryRate: Double?
    var stress: Double?
    var calories: Double
    var profile: UserProfile

    static func make(from day: DayMetrics, profile: UserProfile) -> WatchSummary {
        let target = StrainEngine.target(forRecovery: day.recovery)
        return WatchSummary(
            generatedAt: Date(),
            day: day.day,
            recovery: day.recovery,
            strain: day.strain,
            strainTargetLow: target.lowerBound,
            strainTargetHigh: target.upperBound,
            sleepPerformance: day.sleepPerformance,
            sleepAsleep: day.sleep?.asleep,
            sleepNeed: day.sleepNeed?.total,
            sleepStages: day.sleep.map { session in SleepStage.allCases.map { session.time(in: $0) } },
            hrv: day.vitals.hrv,
            restingHR: day.vitals.restingHR,
            respiratoryRate: day.vitals.respiratoryRate,
            stress: day.currentStress,
            calories: day.totalEnergy,
            profile: profile)
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }
}

final class SyncBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SyncBridge()

    @Published private(set) var summary: WatchSummary?
    private var pending: WatchSummary?
    private static let storageKey = "watchSummary.v1"

    override init() {
        super.init()
        summary = Storage.load(WatchSummary.self, key: Self.storageKey)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
    }

    func send(_ summary: WatchSummary) {
        guard WCSession.isSupported() else { return }
        activate()
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = summary
            return
        }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        guard let data = try? JSONEncoder().encode(summary) else { return }
        try? session.updateApplicationContext(["summary": data])
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context["summary"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSummary.self, from: data) else { return }
        Storage.save(decoded, key: Self.storageKey)
        DispatchQueue.main.async {
            self.summary = decoded
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        if let pending {
            self.pending = nil
            DispatchQueue.main.async { self.send(pending) }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
