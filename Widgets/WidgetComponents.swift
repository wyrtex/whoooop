import SwiftUI
import WidgetKit

extension WidgetFamily {
    var isAccessory: Bool {
        #if os(watchOS)
        return true
        #else
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
        #endif
    }
}

extension View {
    /// Фон обязателен для виджетов iOS 17 / watchOS 10.
    func pulsarBackground(_ family: WidgetFamily) -> some View {
        containerBackground(for: .widget) {
            if family.isAccessory {
                Color.clear
            } else {
                LinearGradient(colors: [Theme.cardRaised, Theme.background], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Круговой индикатор для экрана блокировки и циферблата.
struct MetricGauge: View {
    var metric: WidgetMetric
    var summary: WatchSummary?

    var body: some View {
        Gauge(value: metric.progress(summary)) {
            Image(systemName: metric.symbol)
        } currentValueLabel: {
            Text(metric.value(summary))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(metric.color(summary))
        .widgetAccentable()
    }
}

/// Кольцо со значением внутри для виджетов рабочего стола.
struct MetricRing: View {
    var metric: WidgetMetric
    var summary: WatchSummary?
    var lineWidth: CGFloat = 7
    var showsTitle = true

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RingView(progress: metric.progress(summary), color: metric.color(summary), lineWidth: lineWidth)
                Text(metric.value(summary))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, lineWidth + 2)
            }
            if showsTitle {
                Text(metric.shortTitle)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// Плитка «значение + подпись» (не путать с MetricTile в приложении).
struct WidgetTile: View {
    var metric: WidgetMetric
    var summary: WatchSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: metric.symbol)
                Text(metric.shortTitle)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(metric.color(summary))
            .lineLimit(1)
            Text(metric.valueWithUnit(summary))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Компактная колонка для прямоугольного виджета: значение над подписью.
struct MetricColumn: View {
    var metric: WidgetMetric
    var summary: WatchSummary?

    var body: some View {
        VStack(spacing: 0) {
            Text(metric.value(summary))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(metric.color(summary))
                .widgetAccentable()
            Text(metric.shortTitle)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct NoDataView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "applewatch")
                .font(.title3)
            Text("Откройте Pulsar")
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.secondary)
    }
}

/// «Обновлено 10:24» или «Данные за вчера».
struct UpdatedLabel: View {
    var entry: SummaryEntry

    var body: some View {
        if let summary = entry.summary {
            Text(entry.isStale ? "Данные за \(Fmt.shortDay(summary.day))" : "Обновлено \(Fmt.time(summary.generatedAt))")
                .font(.system(size: 9))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
        }
    }
}

/// Вложенные кольца «восстановление / нагрузка / сон».
struct NestedRings: View {
    var summary: WatchSummary?
    var lineWidth: CGFloat
    var spacing: CGFloat

    var body: some View {
        ZStack {
            RingView(progress: WidgetMetric.recovery.progress(summary), color: WidgetMetric.recovery.color(summary), lineWidth: lineWidth)
            RingView(progress: WidgetMetric.strain.progress(summary), color: Theme.strain, lineWidth: lineWidth)
                .padding(lineWidth + spacing)
            RingView(progress: WidgetMetric.sleep.progress(summary), color: Theme.sleep, lineWidth: lineWidth)
                .padding(2 * (lineWidth + spacing))
        }
        .widgetAccentable()
    }
}
