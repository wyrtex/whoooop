import SwiftUI

struct LossSettingsView: View {
    @EnvironmentObject private var loss: LossStore
    @EnvironmentObject private var store: HealthDataStore
    @State private var userKeys: [String] = GeminiKeys.userKeys
    @State private var newKey = ""
    @State private var modelsText = GeminiSettings.models.joined(separator: "\n")
    @State private var usage = GeminiClient.usageToday()
    @State private var blocked = 0

    private var goalBinding: Binding<Double> {
        Binding(
            get: { loss.settings.goalWeight ?? max(40, (loss.latestWeight?.kg ?? store.profile.weightKg) - 5) },
            set: { loss.settings.goalWeight = ($0 * 10).rounded() / 10 })
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: loss.settings.reminderHour, minute: loss.settings.reminderMinute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                loss.settings.reminderHour = parts.hour ?? 21
                loss.settings.reminderMinute = parts.minute ?? 30
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Есть целевой вес", isOn: Binding(
                    get: { loss.settings.goalWeight != nil },
                    set: { loss.settings.goalWeight = $0 ? goalBinding.wrappedValue : nil }))
                if loss.settings.goalWeight != nil {
                    Stepper(String(format: "Цель: %.1f кг", goalBinding.wrappedValue), value: goalBinding, in: 35...250, step: 0.5)
                }
                Picker("Дефицит в день", selection: $loss.settings.dailyDeficit) {
                    Text("250 ккал (≈0,25 кг/нед)").tag(250.0)
                    Text("500 ккал (≈0,45 кг/нед)").tag(500.0)
                    Text("750 ккал (≈0,7 кг/нед)").tag(750.0)
                    Text("1000 ккал (≈0,9 кг/нед)").tag(1000.0)
                }
                StatRow(title: "Норма калорий в день", value: "\(Int(loss.dailyBudget)) ккал")
                StatRow(title: "Средний расход (Apple Watch)", value: "\(Int(loss.averageBurn)) ккал")
                StatRow(title: "Текущий вес (= профиль)", value: String(format: "%.1f кг", store.profile.weightKg))
            } header: {
                Text("Цель")
            } footer: {
                Text("Вес в профиле и во вкладке «Похудение» синхронизируются в обе стороны и сохраняются в «Здоровье».")
            }

            Section {
                Toggle("Напоминать взвеситься", isOn: $loss.settings.reminderEnabled)
                if loss.settings.reminderEnabled {
                    DatePicker("Время", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("Напоминание")
            }

            Section {
                ForEach(userKeys, id: \.self) { key in
                    HStack {
                        Image(systemName: "key.fill").foregroundStyle(Theme.recoveryYellow)
                        Text(GeminiKeys.masked(key)).font(.body.monospaced())
                    }
                }
                .onDelete { offsets in
                    userKeys.remove(atOffsets: offsets)
                    GeminiKeys.setUserKeys(userKeys)
                }
                HStack {
                    SecureField("Вставьте ключ AIza…", text: $newKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Добавить") {
                        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty, !userKeys.contains(key) else { return }
                        userKeys.append(key)
                        GeminiKeys.setUserKeys(userKeys)
                        newKey = ""
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !GeminiKeys.embedded.isEmpty {
                    StatRow(title: "Встроено при локальной сборке", value: "\(GeminiKeys.embedded.count)")
                }
                if let url = URL(string: "https://aistudio.google.com/apikey") {
                    Link("Получить бесплатный ключ в Google AI Studio", destination: url)
                }
            } header: {
                Text("Ключи Gemini")
            } footer: {
                Text("Ключи хранятся в Keychain на этом iPhone и никуда не отправляются, кроме Google. Используются по очереди: следующий — только когда у предыдущего закончился лимит.")
            }

            Section {
                TextEditor(text: $modelsText)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 110)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: modelsText) { _, value in
                        GeminiSettings.models = value.components(separatedBy: .newlines)
                    }
                Button("Вернуть список по умолчанию") {
                    modelsText = GeminiSettings.defaultModels.joined(separator: "\n")
                }
                StatRow(title: "Запросов сегодня", value: "\(usage.requests)")
                StatRow(title: "Токенов сегодня", value: "\(usage.tokens)")
                StatRow(title: "Заблокировано пар ключ/модель", value: "\(blocked)")
                Button("Сбросить блокировки") {
                    Task {
                        await GeminiClient.shared.resetCooldowns()
                        blocked = 0
                    }
                }
            } header: {
                Text("Модели (по порядку)")
            } footer: {
                Text("Если модель недоступна или выдаёт ошибку, берётся следующая. При исчерпании лимита ключа — следующий ключ. Одинаковая еда и план берутся из памяти без новых запросов.")
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Настройки похудения")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            usage = GeminiClient.usageToday()
            blocked = await GeminiClient.shared.activeCooldowns()
        }
    }
}
