import Foundation
import HealthKit

enum WorkoutCatalog {
    struct Info {
        var name: String
        var symbol: String
    }

    /// Виды тренировок, которые можно запустить с часов.
    static let startable: [HKWorkoutActivityType] = [
        .running, .walking, .cycling, .traditionalStrengthTraining, .functionalStrengthTraining,
        .highIntensityIntervalTraining, .rowing, .elliptical, .hiking, .yoga, .crossTraining, .other,
    ]

    static func info(for type: HKWorkoutActivityType) -> Info {
        switch type {
        case .running: return Info(name: "Бег", symbol: "figure.run")
        case .walking: return Info(name: "Ходьба", symbol: "figure.walk")
        case .cycling: return Info(name: "Велосипед", symbol: "figure.outdoor.cycle")
        case .traditionalStrengthTraining: return Info(name: "Силовая", symbol: "dumbbell.fill")
        case .functionalStrengthTraining: return Info(name: "Функциональная", symbol: "figure.strengthtraining.functional")
        case .highIntensityIntervalTraining: return Info(name: "ВИИТ", symbol: "figure.highintensity.intervaltraining")
        case .swimming: return Info(name: "Плавание", symbol: "figure.pool.swim")
        case .yoga: return Info(name: "Йога", symbol: "figure.yoga")
        case .hiking: return Info(name: "Хайкинг", symbol: "figure.hiking")
        case .rowing: return Info(name: "Гребля", symbol: "figure.rower")
        case .elliptical: return Info(name: "Эллипс", symbol: "figure.elliptical")
        case .soccer: return Info(name: "Футбол", symbol: "figure.soccer")
        case .basketball: return Info(name: "Баскетбол", symbol: "figure.basketball")
        case .tennis: return Info(name: "Теннис", symbol: "figure.tennis")
        case .boxing: return Info(name: "Бокс", symbol: "figure.boxing")
        case .martialArts: return Info(name: "Единоборства", symbol: "figure.martial.arts")
        case .crossTraining: return Info(name: "Кросс-тренинг", symbol: "figure.cross.training")
        case .coreTraining: return Info(name: "Кор", symbol: "figure.core.training")
        case .pilates: return Info(name: "Пилатес", symbol: "figure.pilates")
        case .mixedCardio: return Info(name: "Кардио", symbol: "figure.mixed.cardio")
        case .stairClimbing, .stairs: return Info(name: "Лестница", symbol: "figure.stair.stepper")
        case .socialDance, .cardioDance: return Info(name: "Танцы", symbol: "figure.socialdance")
        case .flexibility: return Info(name: "Растяжка", symbol: "figure.flexibility")
        case .cooldown: return Info(name: "Заминка", symbol: "figure.cooldown")
        case .climbing: return Info(name: "Скалолазание", symbol: "figure.climbing")
        case .snowboarding: return Info(name: "Сноуборд", symbol: "figure.snowboarding")
        case .downhillSkiing: return Info(name: "Горные лыжи", symbol: "figure.skiing.downhill")
        case .crossCountrySkiing: return Info(name: "Беговые лыжи", symbol: "figure.skiing.crosscountry")
        default: return Info(name: "Активность", symbol: "figure.mixed.cardio")
        }
    }

    static func location(for type: HKWorkoutActivityType) -> HKWorkoutSessionLocationType {
        switch type {
        case .running, .walking, .cycling, .hiking: return .outdoor
        default: return .indoor
        }
    }
}
