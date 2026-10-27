import SwiftUI

struct WeighInSheet: View {
    @EnvironmentObject private var loss: LossStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focused: Bool

    private var value: Double? {
        guard let kg = NutritionAI.number(text), kg >= 25, kg <= 350 else { return nil }
        return kg
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0,0", text: $text)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .focused($focused)
                        Text("кг").font(.title2).foregroundStyle(Theme.secondaryText)
                    }
                    DatePicker("Время", selection: $date, in: ...Date())
                } footer: {
                    Text("Взвешивайтесь в одно и то же время — например, вечером перед сном. Вес сохранится в «Здоровье» и в профиле.")
                }
                if let latest = loss.latestWeight, let value {
                    Section {
                        StatRow(title: "Изменение с прошлого раза", value: String(format: "%+.1f кг", value - latest.kg))
                    }
                }
            }
            .navigationTitle("Взвешивание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let value else { return }
                        Task { await loss.addWeight(value, date: date) }
                        dismiss()
                    }
                    .disabled(value == nil)
                }
            }
            .onAppear {
                if let latest = loss.latestWeight {
                    text = String(format: "%.1f", latest.kg).replacingOccurrences(of: ".", with: ",")
                }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

struct WeightHistoryView: View {
    @EnvironmentObject private var loss: LossStore

    var body: some View {
        let entries = Array(loss.sortedWeights.reversed())
        List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(format: "%.1f кг", entry.kg)).font(.headline)
                        Text("\(Fmt.dayTitle(entry.date)), \(Fmt.time(entry.date)) · \(sourceTitle(entry.source))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if index + 1 < entries.count {
                        let delta = entry.kg - entries[index + 1].kg
                        Text(String(format: "%+.1f", delta))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(delta <= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                    }
                }
            }
            .onDelete { offsets in
                let toDelete = offsets.map { entries[$0] }
                Task {
                    for entry in toDelete { await loss.deleteWeight(entry) }
                }
            }
            if entries.isEmpty {
                Text("Взвешиваний пока нет").foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("История веса")
    }

    private func sourceTitle(_ source: WeightEntry.Source) -> String {
        switch source {
        case .app: return "Pulsar"
        case .health: return "Здоровье"
        case .profile: return "профиль"
        }
    }
}
