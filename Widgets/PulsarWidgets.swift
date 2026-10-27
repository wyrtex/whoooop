import SwiftUI
import WidgetKit

enum WidgetFamilies {
    #if os(watchOS)
    static let single: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
    static let overview: [WidgetFamily] = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
    static let vitals: [WidgetFamily] = [.accessoryRectangular, .accessoryCircular, .accessoryInline]
    static let custom: [WidgetFamily] = [.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline]
    #else
    static let single: [WidgetFamily] = [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    static let overview: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    static let vitals: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
    static let custom: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline]
    #endif
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.overview", provider: SummaryProvider()) { entry in
            OverviewView(entry: entry)
        }
        .configurationDisplayName("Обзор дня")
        .description("Восстановление, нагрузка и сон в трёх кольцах.")
        .supportedFamilies(WidgetFamilies.overview)
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.recovery", provider: SummaryProvider()) { entry in
            SingleMetricView(entry: entry, metric: .recovery)
        }
        .configurationDisplayName("Восстановление")
        .description("Готовность организма к нагрузке сегодня.")
        .supportedFamilies(WidgetFamilies.single)
    }
}

struct StrainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.strain", provider: SummaryProvider()) { entry in
            SingleMetricView(entry: entry, metric: .strain)
        }
        .configurationDisplayName("Нагрузка")
        .description("Нагрузка за день и целевой диапазон.")
        .supportedFamilies(WidgetFamilies.single)
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.sleep", provider: SummaryProvider()) { entry in
            SingleMetricView(entry: entry, metric: .sleep)
        }
        .configurationDisplayName("Сон")
        .description("Качество сна и часы сна относительно потребности.")
        .supportedFamilies(WidgetFamilies.single)
    }
}

struct StressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.stress", provider: SummaryProvider()) { entry in
            SingleMetricView(entry: entry, metric: .stress)
        }
        .configurationDisplayName("Стресс")
        .description("Текущий уровень стресса по шкале 0–3.")
        .supportedFamilies(WidgetFamilies.single)
    }
}

struct VitalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "pulsar.vitals", provider: SummaryProvider()) { entry in
            VitalsView(entry: entry)
        }
        .configurationDisplayName("Показатели здоровья")
        .description("ВСР, пульс покоя, дыхание, SpO₂ и стресс.")
        .supportedFamilies(WidgetFamilies.vitals)
    }
}

struct CustomMetricsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "pulsar.custom", intent: MetricsIntent.self, provider: MetricsProvider()) { entry in
            CustomMetricsView(entry: entry)
        }
        .configurationDisplayName("Свои показатели")
        .description("Выберите до четырёх показателей.")
        .supportedFamilies(WidgetFamilies.custom)
    }
}

@main
struct PulsarWidgetBundle: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        RecoveryWidget()
        StrainWidget()
        SleepWidget()
        StressWidget()
        VitalsWidget()
        CustomMetricsWidget()
    }
}
