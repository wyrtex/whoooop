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

private func makeTimeline(metrics: [WidgetMetric] = []) -> Timeline<SummaryEntry> {
    let now = Date()
    let summary = SharedSnapshot.load()
    var entries = [SummaryEntry(date: now, summary: summary, metrics: metrics)]
    // В полночь перерисовываем виджет, чтобы показать, что данные за вчера.
    if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
        entries.append(SummaryEntry(date: midnight, summary: summary, metrics: metrics))
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60)))
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), summary: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let stored = SharedSnapshot.load()
        completion(SummaryEntry(date: Date(), summary: context.isPreview ? (stored ?? .sample) : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        completion(makeTimeline())
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
        let stored = SharedSnapshot.load()
        return SummaryEntry(date: Date(), summary: context.isPreview ? (stored ?? .sample) : stored, metrics: configuration.metrics)
    }

    func timeline(for configuration: MetricsIntent, in context: Context) async -> Timeline<SummaryEntry> {
        makeTimeline(metrics: configuration.metrics)
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
