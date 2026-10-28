import SwiftUI
import WidgetKit

// MARK: - Один показатель (восстановление, нагрузка, сон, стресс)

struct SingleMetricView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SummaryEntry
    var metric: WidgetMetric

    var body: some View {
        content
            .opacity(entry.isStale && !family.isAccessory ? 0.55 : 1)
            .pulsarBackground(family)
    }

    private var content: AnyView {
        let s = entry.summary
        switch family {
        case .accessoryCircular:
            return AnyView(MetricGauge(metric: metric, summary: s))
        case .accessoryRectangular:
            return AnyView(
                HStack(spacing: 8) {
                    MetricGauge(metric: metric, summary: s)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(metric.valueWithUnit(s))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .widgetAccentable()
                        Text(metric.detail(s))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                })
        case .accessoryInline:
            return AnyView(Label("\(metric.title) \(metric.valueWithUnit(s))", systemImage: metric.symbol))
        #if os(watchOS)
        case .accessoryCorner:
            return AnyView(
                Text(metric.value(s))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .widgetCurvesContent()
                    .widgetLabel {
                        Gauge(value: metric.progress(s)) {
                            Text(metric.shortTitle)
                        }
                        .tint(metric.color(s))
                    })
        #endif
        default:
            guard s != nil else { return AnyView(NoDataView()) }
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: metric.symbol)
                        Text(metric.title.uppercased())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(metric.color(s))
                    MetricRing(metric: metric, summary: s, lineWidth: 9, showsTitle: false)
                        .frame(maxWidth: .infinity)
                    Text(metric.detail(s))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                })
        }
    }
}

// MARK: - Обзор дня: три кольца

struct OverviewView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SummaryEntry

    var body: some View {
        content
            .opacity(entry.isStale && !family.isAccessory ? 0.55 : 1)
            .pulsarBackground(family)
    }

    private let main: [WidgetMetric] = [.sleep, .recovery, .strain]

    private var content: AnyView {
        let s = entry.summary
        switch family {
        case .accessoryCircular:
            return AnyView(NestedRings(summary: s, lineWidth: 4, spacing: 1.5).padding(2))
        case .accessoryRectangular:
            return AnyView(
                HStack(spacing: 4) {
                    ForEach(main, id: \.self) { MetricColumn(metric: $0, summary: s) }
                })
        case .accessoryInline:
            return AnyView(Text("\(WidgetMetric.recovery.valueWithUnit(s)) · \(WidgetMetric.strain.value(s)) · сон \(WidgetMetric.sleep.valueWithUnit(s))"))
        #if os(iOS)
        case .systemMedium:
            guard s != nil else { return AnyView(NoDataView(showsRefresh: true)) }
            return AnyView(
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        ForEach(main, id: \.self) { MetricRing(metric: $0, summary: s, lineWidth: 7) }
                    }
                    FooterBar(entry: entry, leading: "ВСР \(WidgetMetric.hrv.valueWithUnit(s)) · ПП \(WidgetMetric.restingHR.value(s)) · стресс \(WidgetMetric.stress.value(s))")
                })
        case .systemLarge:
            guard let summary = s else { return AnyView(NoDataView(showsRefresh: true)) }
            return AnyView(OverviewLargeView(entry: entry, summary: summary))
        #endif
        default:
            guard s != nil else { return AnyView(NoDataView()) }
            return AnyView(
                VStack(spacing: 8) {
                    NestedRings(summary: s, lineWidth: 8, spacing: 2)
                        .frame(width: 84, height: 84)
                    HStack(spacing: 2) {
                        ForEach([WidgetMetric.recovery, .strain, .sleep], id: \.self) { metric in
                            VStack(spacing: 0) {
                                Text(metric.value(s))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(metric.color(s))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text(metric.shortTitle)
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                })
        }
    }
}

#if os(iOS)
private struct OverviewLargeView: View {
    var entry: SummaryEntry
    var summary: WatchSummary

    private let vitals: [WidgetMetric] = [.hrv, .restingHR, .respiratoryRate, .spo2, .stress, .activeCalories]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PULSAR")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.5)
                Spacer()
                UpdatedLabel(entry: entry)
                RefreshButton()
            }
            HStack(spacing: 14) {
                ForEach([WidgetMetric.sleep, .recovery, .strain], id: \.self) {
                    MetricRing(metric: $0, summary: summary, lineWidth: 8)
                }
            }
            .frame(height: 96)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(vitals, id: \.self) { WidgetTile(metric: $0, summary: summary) }
            }
            if let title = summary.insightTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    if let body = summary.insightBody {
                        Text(body)
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
        }
    }
}
#endif

// MARK: - Показатели здоровья

struct VitalsView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SummaryEntry

    var body: some View {
        content.pulsarBackground(family)
    }

    private var content: AnyView {
        let s = entry.summary
        switch family {
        case .accessoryRectangular:
            return AnyView(
                VStack(alignment: .leading, spacing: 1) {
                    vitalLine(.hrv, s)
                    vitalLine(.restingHR, s)
                    vitalLine(.stress, s)
                }
                .frame(maxWidth: .infinity, alignment: .leading))
        case .accessoryCircular:
            return AnyView(MetricGauge(metric: .hrv, summary: s))
        case .accessoryInline:
            return AnyView(Text("ВСР \(WidgetMetric.hrv.valueWithUnit(s)) · ПП \(WidgetMetric.restingHR.value(s))"))
        #if os(iOS)
        case .systemMedium:
            guard s != nil else { return AnyView(NoDataView(showsRefresh: true)) }
            return AnyView(
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ПОКАЗАТЕЛИ ЗДОРОВЬЯ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.recoveryGreen)
                        Spacer()
                        UpdatedLabel(entry: entry)
                        RefreshButton()
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach([WidgetMetric.hrv, .restingHR, .respiratoryRate, .spo2, .stress, .steps], id: \.self) {
                            WidgetTile(metric: $0, summary: s)
                        }
                    }
                })
        #endif
        default:
            guard s != nil else { return AnyView(NoDataView()) }
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    Text("ЗДОРОВЬЕ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.recoveryGreen)
                    ForEach([WidgetMetric.hrv, .restingHR, .respiratoryRate, .spo2], id: \.self) { metric in
                        HStack(spacing: 4) {
                            Image(systemName: metric.symbol)
                                .font(.caption2)
                                .foregroundStyle(metric.color(s))
                                .frame(width: 14)
                            Text(metric.title)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(metric.value(s))
                                .font(.system(.footnote, design: .rounded).weight(.bold))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                })
        }
    }

    private func vitalLine(_ metric: WidgetMetric, _ s: WatchSummary?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: metric.symbol)
                .frame(width: 14)
            Text(metric.title)
            Spacer(minLength: 2)
            Text(metric.valueWithUnit(s))
                .fontWeight(.semibold)
                .widgetAccentable()
        }
        .font(.caption2)
        .lineLimit(1)
    }
}

// MARK: - Настраиваемый набор показателей

struct CustomMetricsView: View {
    @Environment(\.widgetFamily) private var family
    var entry: SummaryEntry

    var body: some View {
        content
            .opacity(entry.isStale && !family.isAccessory ? 0.55 : 1)
            .pulsarBackground(family)
    }

    private var metrics: [WidgetMetric] {
        entry.metrics.isEmpty ? [.recovery, .strain, .sleep, .hrv] : entry.metrics
    }

    private var content: AnyView {
        let s = entry.summary
        switch family {
        case .accessoryCircular:
            return AnyView(MetricGauge(metric: metrics[0], summary: s))
        case .accessoryRectangular:
            return AnyView(
                HStack(spacing: 4) {
                    ForEach(Array(metrics.prefix(3)), id: \.self) { MetricColumn(metric: $0, summary: s) }
                })
        case .accessoryInline:
            return AnyView(Text(metrics.prefix(2).map { "\($0.shortTitle) \($0.valueWithUnit(s))" }.joined(separator: " · ")))
        #if os(watchOS)
        case .accessoryCorner:
            let metric = metrics[0]
            return AnyView(
                Text(metric.value(s))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .widgetCurvesContent()
                    .widgetLabel {
                        Gauge(value: metric.progress(s)) {
                            Text(metric.shortTitle)
                        }
                        .tint(metric.color(s))
                    })
        #endif
        #if os(iOS)
        case .systemMedium:
            guard s != nil else { return AnyView(NoDataView(showsRefresh: true)) }
            return AnyView(
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ForEach(metrics, id: \.self) { MetricRing(metric: $0, summary: s, lineWidth: 6) }
                    }
                    FooterBar(entry: entry)
                })
        #endif
        default:
            guard s != nil else { return AnyView(NoDataView()) }
            return AnyView(
                Grid(horizontalSpacing: 10, verticalSpacing: 12) {
                    GridRow {
                        WidgetTile(metric: metrics[0], summary: s)
                        WidgetTile(metric: metrics[1], summary: s)
                    }
                    GridRow {
                        WidgetTile(metric: metrics[2], summary: s)
                        WidgetTile(metric: metrics[3], summary: s)
                    }
                })
        }
    }
}
