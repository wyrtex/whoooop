import SwiftUI
import WidgetKit

struct ProfileView: View {
    @EnvironmentObject private var store: HealthDataStore

    private var maxHRAuto: Binding<Bool> {
        Binding(
            get: { store.profile.maxHROverride == nil },
            set: { store.profile.maxHROverride = $0 ? nil : Int(store.profile.estimatedMaxHR) })
    }

    private var maxHRValue: Binding<Int> {
        Binding(
            get: { store.profile.maxHROverride ?? Int(store.profile.estimatedMaxHR) },
            set: { store.profile.maxHROverride = $0 })
    }

    private var wakeTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: store.profile.wakeHour, minute: store.profile.wakeMinute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.profile.wakeHour = components.hour ?? 7
                store.profile.wakeMinute = components.minute ?? 0
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Профиль") {
                    TextField("Имя", text: $store.profile.name)
                    Stepper("Возраст: \(store.profile.age)", value: $store.profile.age, in: 14...100)
                    Picker("Пол", selection: $store.profile.sex) {
                        ForEach(BiologicalSexOption.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(String(format: "Вес: %.1f кг", store.profile.weightKg), value: $store.profile.weightKg, in: 30...250, step: 0.5)
                    Stepper(String(format: "Рост: %.0f см", store.profile.heightCm), value: $store.profile.heightCm, in: 120...230, step: 1)
                }

                Section {
                    Toggle("Автоматически", isOn: maxHRAuto)
                    if store.profile.maxHROverride != nil {
                        Stepper("Макс. пульс: \(maxHRValue.wrappedValue)", value: maxHRValue, in: 120...230)
                    } else {
                        StatRow(title: "Макс. пульс (формула)", value: "\(Int(store.profile.estimatedMaxHR)) уд/мин")
                    }
                } header: {
                    Text("Пульсовые зоны")
                } footer: {
                    Text("Максимальный пульс определяет зоны и расчёт нагрузки. Если знаете свой реальный максимум — укажите его.")
                }

                Section {
                    Stepper(String(format: "Базовая потребность: %.2f ч", store.profile.sleepNeedHours), value: $store.profile.sleepNeedHours, in: 6...10, step: 0.25)
                    DatePicker("Подъём", selection: wakeTime, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Сон")
                } footer: {
                    Text("К базовой потребности добавляются нагрузка прошедшего дня и долг сна.")
                }

                Section("Данные") {
                    Button {
                        Task { await store.connectHealth() }
                    } label: {
                        Label("Разрешения Apple Health", systemImage: "heart.text.square")
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Label("Обновить данные", systemImage: "arrow.clockwise")
                            Spacer()
                            if store.isLoading { ProgressView() }
                        }
                    }
                    Button {
                        Task {
                            await store.refresh()
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    } label: {
                        Label("Обновить виджеты", systemImage: "square.grid.2x2")
                    }
                    if let updated = store.lastUpdated {
                        StatRow(title: "Последнее обновление", value: "\(Fmt.shortDay(updated)), \(Fmt.time(updated))")
                    }
                    StatRow(title: "Дней в истории", value: "\(store.days.count)")
                    if let error = store.lastError {
                        Text(error).font(.footnote).foregroundStyle(Theme.recoveryRed)
                    }
                }

                Section {
                    Text("Pulsar рассчитывает восстановление, нагрузку и сон по данным Apple Watch из приложения «Здоровье». Все вычисления выполняются на устройстве. Приложение не является медицинским изделием.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    StatRow(title: "Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                } header: {
                    Text("О приложении")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Профиль")
        }
    }
}
