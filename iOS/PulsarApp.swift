import SwiftUI

@main
struct PulsarApp: App {
    @StateObject private var store = HealthDataStore(historyDays: 60)
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
