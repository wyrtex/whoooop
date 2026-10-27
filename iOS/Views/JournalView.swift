import SwiftUI

enum JournalBehavior: String, CaseIterable, Identifiable, Codable {
    case alcohol, lateCaffeine, lateMeal, screenInBed, highStress, sickness, travel
    case meditation, stretching, hydration, sauna, coldExposure, readingInBed, outdoorLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alcohol: return "Алкоголь"
        case .lateCaffeine: return "Кофеин после 14:00"
        case .lateMeal: return "Поздний ужин"
        case .screenInBed: return "Телефон в кровати"
        case .highStress: return "Сильный стресс"
        case .sickness: return "Болезнь"
        case .travel: return "Перелёт / смена поясов"
        case .meditation: return "Медитация"
        case .stretching: return "Растяжка"
        case .hydration: return "Достаточно воды"
        case .sauna: return "Сауна"
        case .coldExposure: return "Холодный душ"
        case .readingInBed: return "Чтение перед сном"
        case .outdoorLight: return "Утренний свет"
        }
    }

    var symbol: String {
        switch self {
        case .alcohol: return "wineglass.fill"
        case .lateCaffeine: return "cup.and.saucer.fill"
        case .lateMeal: return "fork.knife"
        case .screenInBed: return "iphone"
        case .highStress: return "brain.head.profile"
        case .sickness: return "cross.case.fill"
        case .travel: return "airplane"
        case .meditation: return "figure.mind.and.body"
        case .stretching: return "figure.flexibility"
        case .hydration: return "drop.fill"
        case .sauna: return "flame.fill"
        case .coldExposure: return "snowflake"
        case .readingInBed: return "book.fill"
        case .outdoorLight: return "sun.max.fill"
        }
    }
}

@MainActor
final class JournalStore: ObservableObject {
    /// День (yyyy-MM-dd) → ответы.
    @Published private(set) var entries: [String: [String: Bool]] = [:]

    private let fileName = "journal.v1.json"

    init() {
        entries = Storage.loadFile([String: [String: Bool]].self, name: fileName) ?? [:]
    }

    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func answer(_ behavior: JournalBehavior, on day: Date) -> Bool? {
        entries[Self.key(for: day)]?[behavior.rawValue]
    }

    func set(_ behavior: JournalBehavior, on day: Date, to value: Bool?) {
        let key = Self.key(for: day)
        var entry = entries[key] ?? [:]
        entry[behavior.rawValue] = value
        entries[key] = entry
        Storage.saveFile(entries, name: fileName)
    }

    func answeredCount(on day: Date) -> Int {
        entries[Self.key(for: day)]?.count ?? 0
    }

    struct Impact: Identifiable {
        var behavior: JournalBehavior
        var withValue: Double
        var withoutValue: Double
        var withCount: Int
        var withoutCount: Int
        var id: String { behavior.id }
        var delta: Double { withValue - withoutValue }
    }

    /// Сравнивает восстановление на следующий день с привычкой и без неё.
    func impacts(days: [DayMetrics]) -> [Impact] {
        let calendar = Calendar.current
        var byDay: [String: DayMetrics] = [:]
        for day in days { byDay[Self.key(for: day.day)] = day }

        return JournalBehavior.allCases.compactMap { behavior in
            var with: [Double] = []
            var without: [Double] = []
            for (key, answers) in entries {
                guard let answer = answers[behavior.rawValue],
                      let day = byDay[key],
                      let next = calendar.date(byAdding: .day, value: 1, to: day.day),
                      let recovery = byDay[Self.key(for: next)]?.recovery else { continue }
                if answer { with.append(recovery) } else { without.append(recovery) }
            }
            guard with.count >= 2, without.count >= 2, let a = with.mean, let b = without.mean else { return nil }
            return Impact(behavior: behavior, withValue: a, withoutValue: b, withCount: with.count, withoutCount: without.count)
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }
}

/// Дневник открывается из вкладки «Здоровье» (в навигационном стеке этой вкладки).
struct JournalView: View {
    @EnvironmentObject private var store: HealthDataStore
    @EnvironmentObject private var journal: JournalStore
    @State private var day: Date = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())) ?? Date()

    var body: some View {
            List {
                Section {
                    DatePicker("День", selection: $day, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("Отметьте, что было в этот день — Pulsar сравнит восстановление на следующее утро.")
                }

                Section("Привычки") {
                    ForEach(JournalBehavior.allCases) { behavior in
                        JournalRow(behavior: behavior, value: journal.answer(behavior, on: day)) { value in
                            journal.set(behavior, on: day, to: value)
                        }
                    }
                }

                Section("Влияние на восстановление") {
                    let impacts = journal.impacts(days: store.days)
                    if impacts.isEmpty {
                        Text("Заполняйте дневник хотя бы неделю — здесь появится, какие привычки помогают, а какие мешают восстановлению.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(impacts) { impact in
                        HStack {
                            Image(systemName: impact.behavior.symbol)
                                .frame(width: 26)
                                .foregroundStyle(impact.delta >= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(impact.behavior.title)
                                Text("\(impact.withCount) дн. с привычкой · \(impact.withoutCount) без")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Text("\(Fmt.signed(impact.delta))%")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(impact.delta >= 0 ? Theme.recoveryGreen : Theme.recoveryRed)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Дневник")
    }
}

private struct JournalRow: View {
    var behavior: JournalBehavior
    var value: Bool?
    var onChange: (Bool?) -> Void

    var body: some View {
        HStack {
            Image(systemName: behavior.symbol)
                .foregroundStyle(Theme.strain)
                .frame(width: 26)
            Text(behavior.title)
            Spacer()
            HStack(spacing: 6) {
                choice("Да", selected: value == true) { onChange(value == true ? nil : true) }
                choice("Нет", selected: value == false) { onChange(value == false ? nil : false) }
            }
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.strain : Theme.cardRaised, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderless)
    }
}
