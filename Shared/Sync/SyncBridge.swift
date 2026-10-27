import Foundation
import WatchConnectivity

final class SyncBridge: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = SyncBridge()

    @Published private(set) var summary: WatchSummary?
    /// На iPhone: установлено ли приложение на часах (в сборке «только iPhone» — нет).
    @Published private(set) var isWatchAppInstalled = false
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
        #if os(watchOS)
        // Сводка с iPhone точнее локальной — сразу обновляем циферблат.
        SharedSnapshot.save(decoded)
        #endif
        DispatchQueue.main.async {
            self.summary = decoded
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateWatchState(session)
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

    private func updateWatchState(_ session: WCSession) {
        #if os(iOS)
        let installed = session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        DispatchQueue.main.async { self.isWatchAppInstalled = installed }
        #endif
    }

    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) {
        updateWatchState(session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
