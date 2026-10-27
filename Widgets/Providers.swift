import WidgetKit
import AppIntents

struct SummaryEntry: TimelineEntry {
    var date: Date
    var summary: WatchSummary?
    var metrics: [WidgetMetric] = []

    /// День в сводке уже прошёл: значения показываем приглушёнными.
    var isStale: Bool {
        guard let summary else { return false }
        return !Calendar.current.isDate(summary.day, inSameDayAs: date)
    }
}

/// Как часто виджет просит систему обновить его. iOS может откладывать обновления,
/// поэтому в средних и больших виджетах есть кнопка мгновенного обновления.
let widgetRefreshInterval: TimeInterval = 3 * 60

private func makeTimeline(summary: WatchSummary?, metrics: [WidgetMetric] = []) -> Timeline<SummaryEntry> {
    let now = Date()
    var entries = [SummaryEntry(date: now, summary: summary, metrics: metrics)]
    // В полночь перерисовываем виджет, чтобы показать, что данные за вчера.
    if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)),
       midnight.timeIntervalSince(now) < widgetRefreshInterval {
        entries.append(SummaryEntry(date: midnight, summary: summary, metrics: metrics))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(widgetRefreshInterval)))
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), summary: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let stored = WidgetDataLoader.cached()
        completion(SummaryEntry(date: Date(), summary: context.isPreview ? (stored ?? .sample) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        Task {
            let summary = await WidgetDataLoader.load()
            completion(makeTimeline(summary: summary))
        }
    }
}

/// Настраиваемый виджет: пользователь сам выбирает показатели.
struct MetricsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Свои показатели"
    static var description = IntentDescription("Выберите, какие показатели показывать в виджете.")

    @Parameter(title: "Показатель 1", default: .recovery)
    var first: WidgetMetric

    @Parameter(title: "Показатель 2", default: .strain)
    var second: WidgetMetric

    @Parameter(title: "Показатель 3", default: .sleep)
    var third: WidgetMetric

    @Parameter(title: "Показатель 4", default: .hrv)
    var fourth: WidgetMetric

    init() {}

    init(_ first: WidgetMetric, _ second: WidgetMetric, _ third: WidgetMetric, _ fourth: WidgetMetric) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
    }

    var metrics: [WidgetMetric] { [first, second, third, fourth] }
}

struct MetricsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), summary: .sample, metrics: [.recovery, .strain, .sleep, .hrv])
    }

    func snapshot(for configuration: MetricsIntent, in context: Context) async -> SummaryEntry {
        let stored = WidgetDataLoader.cached()
        return SummaryEntry(date: Date(), summary: context.isPreview ? (stored ?? .sample) : stored, metrics: configuration.metrics)
    }

    func timeline(for configuration: MetricsIntent, in context: Context) async -> Timeline<SummaryEntry> {
        makeTimeline(summary: await WidgetDataLoader.load(), metrics: configuration.metrics)
    }

    #if os(watchOS)
    /// На часах настраиваемые виджеты предлагаются готовыми наборами.
    func recommendations() -> [AppIntentRecommendation<MetricsIntent>] {
        [
            AppIntentRecommendation(intent: MetricsIntent(.recovery, .strain, .sleep, .hrv), description: "Восстановление, нагрузка, сон"),
            AppIntentRecommendation(intent: MetricsIntent(.hrv, .restingHR, .stress, .respiratoryRate), description: "ВСР, пульс покоя, стресс"),
            AppIntentRecommendation(intent: MetricsIntent(.strain, .calories, .steps, .stress), description: "Нагрузка, калории, шаги"),
            AppIntentRecommendation(intent: MetricsIntent(.sleep, .sleepHours, .recovery, .hrv), description: "Сон и восстановление"),
        ]
    }
    #endif
}
