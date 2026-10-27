import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: HealthDataStore
    @State private var isConnecting = false

    private struct Feature: Identifiable {
        var title: String
        var text: String
        var symbol: String
        var color: Color
        var id: String { title }
    }

    private let features: [Feature] = [
        Feature(title: "Восстановление", text: "Насколько организм готов к нагрузке — по ВСР, пульсу покоя, дыханию и сну.", symbol: "bolt.heart.fill", color: Theme.recoveryGreen),
        Feature(title: "Нагрузка", text: "Сердечно-сосудистая нагрузка за день и тренировки по шкале 0–21.", symbol: "flame.fill", color: Theme.strain),
        Feature(title: "Сон", text: "Стадии, потребность во сне, долг сна и рекомендованное время отбоя.", symbol: "moon.stars.fill", color: Theme.sleep),
        Feature(title: "Стресс и здоровье", text: "Монитор стресса, контроль показателей и биологический возраст.", symbol: "heart.text.square.fill", color: Theme.stress),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        RingView(progress: 0.82, color: Theme.recoveryGreen, lineWidth: 8)
                            .frame(width: 92, height: 92)
                        RingView(progress: 0.64, color: Theme.strain, lineWidth: 8)
                            .frame(width: 66, height: 66)
                        RingView(progress: 0.9, color: Theme.sleep, lineWidth: 8)
                            .frame(width: 40, height: 40)
                    }
                    Text("Pulsar")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                    Text("Персональный монитор восстановления, нагрузки и сна на основе данных Apple Watch.")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(features) { feature in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: feature.symbol)
                                .font(.title2)
                                .foregroundStyle(feature.color)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title).font(.headline)
                                Text(feature.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        isConnecting = true
                        Task {
                            await store.connectHealth()
                            isConnecting = false
                        }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView().tint(.black) }
                            Text("Подключить Apple Health")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.black)
                    }
                    .disabled(isConnecting)

                    Text("Данные не покидают устройство. Для точных оценок носите Apple Watch и днём, и ночью — личная норма формируется за 3–4 дня.")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .screenBackground()
    }
}
