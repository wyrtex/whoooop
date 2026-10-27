import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct SectionTitle: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var unit: String = ""
    var symbol: String
    var color: Color
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StatRow: View {
    var title: String
    var value: String
    var symbol: String? = nil
    var color: Color = .white

    var body: some View {
        HStack {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 22)
            }
            Text(title)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

struct BigScoreHeader: View {
    var title: String
    var value: String
    var subtitle: String
    var progress: Double
    var color: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RingView(progress: progress, color: color, lineWidth: 16)
                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 200, height: 200)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct BarPart {
    var value: Double
    var color: Color
}

/// Горизонтальная полоса из долей (зоны пульса, стадии сна).
struct StackedBar: View {
    var parts: [BarPart]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let total = max(parts.reduce(0) { $0 + $1.value }, 0.0001)
            let available = proxy.size.width - CGFloat(parts.count) * 2
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { index in
                    if parts[index].value > 0 {
                        Rectangle()
                            .fill(parts[index].color)
                            .frame(width: max(2, available * parts[index].value / total))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct ZoneBreakdown: View {
    var zoneSeconds: [Double]
    var maxHR: Double

    var body: some View {
        VStack(spacing: 10) {
            ForEach((0..<min(zoneSeconds.count, StrainEngine.zoneCount)).reversed(), id: \.self) { zone in
                let total = max(zoneSeconds.reduce(0, +), 1)
                HStack(spacing: 10) {
                    Text(StrainEngine.zoneTitle(zone))
                        .font(.caption.weight(.semibold))
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.cardRaised)
                            Capsule()
                                .fill(Theme.zoneColors[zone])
                                .frame(width: max(4, proxy.size.width * zoneSeconds[zone] / total))
                        }
                    }
                    .frame(height: 10)
                    Text(Fmt.duration(zoneSeconds[zone]))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                    Text(StrainEngine.zoneRange(zone, maxHR: maxHR))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.tertiaryText)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
}

struct InsightRow: View {
    var insight: CoachInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.title3)
                .foregroundStyle(Theme.toneColor(insight.tone))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                Text(insight.body)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(Theme.background, for: .tabBar)
    }
}

/// Отклонение от личной нормы в виде «+5% к норме».
func baselineDelta(value: Double?, mean: Double?, unit: String, digits: Int = 0, relative: Bool = false) -> String? {
    guard let value, let mean, mean != 0 else { return nil }
    if relative {
        return Fmt.signed((value / mean - 1) * 100) + "% к норме"
    }
    return Fmt.signed(value - mean, digits: digits) + " \(unit) к норме"
}
