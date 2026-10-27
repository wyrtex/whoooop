import SwiftUI

struct FoodTodayCard: View {
    @EnvironmentObject private var loss: LossStore
    var onAdd: () -> Void
    var onSelect: (FoodEntry) -> Void

    var body: some View {
        let entries = loss.foods(on: Date())
        let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
        Card {
            SectionTitle(title: "Питание сегодня", trailing: "\(Int(total.kcal)) ккал")
            if total.kcal > 0 {
                MacroBar(nutrients: total)
            }
            ForEach(entries) { entry in
                Button { onSelect(entry) } label: { FoodRow(entry: entry) }
                    .buttonStyle(.plain)
            }
            if entries.isEmpty {
                Text("Пока ничего не записано")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Button(action: onAdd) {
                    Label("Добавить еду", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.stress, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                NavigationLink {
                    FoodHistoryView()
                } label: {
                    Image(systemName: "calendar")
                        .frame(width: 44, height: 40)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            let recent = loss.recentFoods
            if !recent.isEmpty {
                Text("Повторить (без запроса к ИИ)")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recent) { item in
                            Button {
                                loss.repeatFood(item)
                            } label: {
                                Text("\(item.title) · \(Int(item.kcal))")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.cardRaised, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct FoodRow: View {
    var entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(Fmt.time(entry.date)).font(.caption.monospacedDigit())
                Text(entry.meal).font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if entry.status == .failed {
                    Text(entry.error ?? "Ошибка")
                        .font(.caption)
                        .foregroundStyle(Theme.recoveryRed)
                        .lineLimit(2)
                } else if entry.mode == .product, entry.status == .done {
                    Text("найдено в интернете")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer()
            switch entry.status {
            case .pending:
                ProgressView()
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.recoveryYellow)
            case .done:
                Text("\(Int(entry.kcal))")
                    .font(.headline.monospacedDigit())
            }
        }
        .contentShape(Rectangle())
    }
}

struct MacroBar: View {
    var nutrients: Nutrients

    var body: some View {
        VStack(spacing: 6) {
            StackedBar(parts: [
                BarPart(value: nutrients.protein * 4, color: Theme.recoveryGreen),
                BarPart(value: nutrients.fat * 9, color: Theme.recoveryYellow),
                BarPart(value: nutrients.carbs * 4, color: Theme.strain),
            ], height: 8)
            HStack {
                macro("Белки", nutrients.protein, Theme.recoveryGreen)
                Spacer()
                macro("Жиры", nutrients.fat, Theme.recoveryYellow)
                Spacer()
                macro("Углеводы", nutrients.carbs, Theme.strain)
            }
        }
    }

    private func macro(_ title: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(Int(grams.rounded())) г")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Добавление еды

struct AddFoodSheet: View {
    @EnvironmentObject private var loss: LossStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var mode: FoodEntry.Mode = .describe
    @State private var date = Date()
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""

    private var manualNutrients: Nutrients? {
        guard let value = NutritionAI.number(kcal), value > 0 else { return nil }
        return Nutrients(
            kcal: value,
            protein: NutritionAI.number(protein) ?? 0,
            fat: NutritionAI.number(fat) ?? 0,
            carbs: NutritionAI.number(carbs) ?? 0)
    }

    private var canSave: Bool {
        if mode == .manual { return manualNutrients != nil }
        return !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Способ", selection: $mode) {
                        ForEach(FoodEntry.Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text(hint)
                }

                if mode == .manual {
                    Section("Пищевая ценность") {
                        numberField("Калории, ккал", $kcal)
                        numberField("Белки, г", $protein)
                        numberField("Жиры, г", $fat)
                        numberField("Углеводы, г", $carbs)
                    }
                }

                Section {
                    DatePicker("Когда ели", selection: $date, in: ...Date())
                }

                if mode != .manual && !loss.hasAIKeys {
                    Section {
                        NavigationLink("Добавить ключ Gemini") { LossSettingsView() }
                    } footer: {
                        Text("Без ключа ИИ не сможет посчитать калории. Можно ввести их вручную.")
                    }
                }
            }
            .navigationTitle("Что вы съели?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        loss.addFood(text: text, mode: mode, date: date, manual: mode == .manual ? manualNutrients : nil)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var placeholder: String {
        switch mode {
        case .describe: return "Фасоль, брокколи и цветная капуста на 3/4 тарелки, большая куриная котлета"
        case .product: return "Йогурт Активиа клубника 2,4% 130 г"
        case .manual: return "Название (необязательно)"
        }
    }

    private var hint: String {
        switch mode {
        case .describe: return "Опишите блюдо и примерный размер порции — ИИ разложит его на компоненты и посчитает КБЖУ. Одинаковые описания берутся из кэша без нового запроса."
        case .product: return "Точное название с брендом и весом — ИИ найдёт продукт в интернете и покажет состав, КБЖУ на 100 г и на порцию."
        case .manual: return "Если калории известны, запрос к ИИ не нужен."
        }
    }

    private func numberField(_ title: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
        }
    }
}

// MARK: - Подробности о еде

struct FoodDetailSheet: View {
    @EnvironmentObject private var loss: LossStore
    @Environment(\.dismiss) private var dismiss
    var entryID: UUID

    var body: some View {
        NavigationStack {
            Group {
                if let entry = loss.entry(entryID) {
                    content(entry)
                } else {
                    Text("Запись удалена").foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Еда")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func content(_ entry: FoodEntry) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.title).font(.title3.weight(.bold))
                    if let brand = entry.analysis?.brand {
                        Text(brand).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    if entry.text != entry.title {
                        Text("«\(entry.text)»").font(.caption).foregroundStyle(Theme.tertiaryText)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(entry.kcal))")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("ккал").foregroundStyle(Theme.secondaryText)
                        Spacer()
                        if entry.status == .pending { ProgressView() }
                    }
                    if entry.kcal > 0 { MacroBar(nutrients: entry.nutrients) }
                }
                .padding(.vertical, 4)
                if let error = entry.error, entry.status == .failed {
                    Text(error).font(.footnote).foregroundStyle(Theme.recoveryRed)
                }
            }

            Section("Порция и время") {
                Stepper(value: binding(entry, \.multiplier), in: 0.25...5, step: 0.25) {
                    Text("Порция × \(String(format: "%g", entry.multiplier))")
                }
                DatePicker("Когда", selection: binding(entry, \.date), in: ...Date())
                if let portion = entry.analysis?.portion {
                    StatRow(title: "Расчёт на", value: portion)
                }
            }

            if let analysis = entry.analysis, !analysis.items.isEmpty {
                Section("Состав блюда") {
                    ForEach(analysis.items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                if let grams = item.grams {
                                    Text("\(Int(grams)) г").font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                            Text("\(Int(item.nutrients.kcal * entry.multiplier)) ккал").monospacedDigit()
                        }
                    }
                }
            }

            if let per100 = entry.analysis?.per100g {
                Section("На 100 г") {
                    StatRow(title: "Калории", value: "\(Int(per100.kcal)) ккал")
                    StatRow(title: "Белки / жиры / углеводы", value: String(format: "%.1f / %.1f / %.1f г", per100.protein, per100.fat, per100.carbs))
                }
            }

            if let analysis = entry.analysis, !analysis.details.isEmpty || analysis.notes != nil {
                Section("Подробности") {
                    ForEach(analysis.details, id: \.self) { Text($0).font(.footnote) }
                    if let notes = analysis.notes {
                        Text(notes).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    if let confidence = analysis.confidence {
                        StatRow(title: "Точность оценки", value: confidence)
                    }
                }
            }

            if let sources = entry.analysis?.sources, !sources.isEmpty {
                Section("Источники") {
                    ForEach(sources, id: \.url) { source in
                        if let url = URL(string: source.url) {
                            Link(source.title, destination: url).font(.footnote)
                        }
                    }
                }
            }

            Section {
                if entry.mode != .manual {
                    Button {
                        Task { await loss.analyze(entry.id, force: true) }
                    } label: {
                        Label("Пересчитать с ИИ", systemImage: "sparkles")
                    }
                    .disabled(entry.status == .pending)
                }
                Button(role: .destructive) {
                    loss.deleteFood(entry.id)
                    dismiss()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } footer: {
                if let model = entry.analysis?.model {
                    Text("Модель: \(model)")
                }
            }
        }
    }

    private func binding<T>(_ entry: FoodEntry, _ keyPath: WritableKeyPath<FoodEntry, T>) -> Binding<T> {
        Binding(
            get: { loss.entry(entry.id)?[keyPath: keyPath] ?? entry[keyPath: keyPath] },
            set: { value in loss.update(entry.id) { $0[keyPath: keyPath] = value } })
    }
}

// MARK: - История питания

struct FoodHistoryView: View {
    @EnvironmentObject private var loss: LossStore
    @State private var selected: FoodEntry?

    private var days: [Date] {
        let calendar = Calendar.current
        return Array(Set(loss.foods.map { calendar.startOfDay(for: $0.date) })).sorted(by: >)
    }

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                let energy = loss.energy(for: day)
                Section {
                    ForEach(loss.foods(on: day)) { entry in
                        Button { selected = entry } label: { FoodRow(entry: entry) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let entries = loss.foods(on: day)
                        for index in offsets { loss.deleteFood(entries[index].id) }
                    }
                } header: {
                    HStack {
                        Text(Fmt.dayTitle(day))
                        Spacer()
                        Text("\(Int(energy.eaten)) / \(Int(energy.burned)) ккал · \(weightText(energy.weightChange))")
                    }
                }
            }
            if days.isEmpty {
                Text("Записей пока нет").foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("История питания")
        .sheet(item: $selected) { entry in FoodDetailSheet(entryID: entry.id) }
    }
}
