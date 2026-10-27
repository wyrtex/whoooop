import SwiftUI

struct RingView: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamp(progress, 0.001, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
        }
        .padding(lineWidth / 2)
    }
}

/// Круглый индикатор со значением внутри — основа главного экрана.
struct ScoreDial: View {
    var title: String
    var value: String
    var progress: Double
    var color: Color
    var size: CGFloat = 100
    var lineWidth: CGFloat = 9

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RingView(progress: progress, color: color, lineWidth: lineWidth)
                Text(value)
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, lineWidth + 4)
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.system(size: max(9, size * 0.11), weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
