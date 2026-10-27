import SwiftUI
import BackgroundTasks

/// Периодическое обновление в фоне, чтобы виджеты не устаревали.
@MainActor
enum BackgroundRefresh {
    static let identifier = "com.pulsar.app.refresh"
    static let store = HealthDataStore(historyDays: 60)

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func run() async {
        schedule()
        guard store.hasOnboarded else { return }
        await store.refresh()
    }
}

@main
struct PulsarApp: App {
    @StateObject private var store = BackgroundRefresh.store
    @StateObject private var journal = JournalStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SyncBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(journal)
                .preferredColorScheme(.dark)
                .tint(Theme.strain)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.hasOnboarded {
                Task { await store.refresh() }
            }
            if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await BackgroundRefresh.run()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        if store.hasOnboarded {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Обзор", systemImage: "circle.circle") }
            TrendsView()
                .tabItem { Label("Тренды", systemImage: "chart.xyaxis.line") }
            JournalView()
                .tabItem { Label("Дневник", systemImage: "book.closed.fill") }
            HealthView()
                .tabItem { Label("Здоровье", systemImage: "heart.text.square.fill") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
    }
}
