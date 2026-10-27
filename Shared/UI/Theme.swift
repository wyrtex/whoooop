import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

enum Theme {
    static let background = Color(hex: 0x0A0C10)
    static let card = Color(hex: 0x151920)
    static let cardRaised = Color(hex: 0x1D222B)
    static let separator = Color.white.opacity(0.08)
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.4)

    static let recoveryGreen = Color(hex: 0x1FD67A)
    static let recoveryYellow = Color(hex: 0xF6C744)
    static let recoveryRed = Color(hex: 0xFF4D5E)
    static let strain = Color(hex: 0x2F8CFF)
    static let sleep = Color(hex: 0x9D8CFF)
    static let stress = Color(hex: 0xFF9142)
    static let heart = Color(hex: 0xFF4D6D)
    static let neutral = Color(hex: 0x8A94A6)

    static func recoveryColor(_ value: Double?) -> Color {
        guard let value else { return neutral }
        switch RecoveryBand(value) {
        case .green: return recoveryGreen
        case .yellow: return recoveryYellow
        case .red: return recoveryRed
        }
    }

    static func stressColor(_ level: Double) -> Color {
        switch level {
        case ..<1: return recoveryGreen
        case ..<2: return recoveryYellow
        default: return stress
        }
    }

    static let zoneColors: [Color] = [
        Color(hex: 0x5B6475),
        Color(hex: 0x4FC3F7),
        Color(hex: 0x1FD67A),
        Color(hex: 0xF6C744),
        Color(hex: 0xFF9142),
        Color(hex: 0xFF4D5E),
    ]

    static func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .awake: return Color(hex: 0xF2F4F8)
        case .rem: return Color(hex: 0x7EC8FF)
        case .light: return Color(hex: 0x9D8CFF)
        case .deep: return Color(hex: 0x5B3FD9)
        }
    }

    static func toneColor(_ tone: CoachInsight.Tone) -> Color {
        switch tone {
        case .positive: return recoveryGreen
        case .neutral: return strain
        case .warning: return recoveryYellow
        }
    }
}
