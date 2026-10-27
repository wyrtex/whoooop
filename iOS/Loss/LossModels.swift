import Foundation

struct Nutrients: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double

    static let zero = Nutrients(kcal: 0, protein: 0, fat: 0, carbs: 0)

    func scaled(_ factor: Double) -> Nutrients {
        Nutrients(kcal: kcal * factor, protein: protein * factor, fat: fat * factor, carbs: carbs * factor)
    }

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(kcal: lhs.kcal + rhs.kcal, protein: lhs.protein + rhs.protein, fat: lhs.fat + rhs.fat, carbs: lhs.carbs + rhs.carbs)
    }
}

struct FoodItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var grams: Double?
    var nutrients: Nutrients
}

struct FoodAnalysis: Codable, Hashable {
    var title: String
    var brand: String?
    var portion: String?
    var items: [FoodItem]
    var total: Nutrients
    var per100g: Nutrients?
    var details: [String]
    var confidence: String?
    var notes: String?
    var sources: [GeminiSource]
    var model: String?
    var isManual: Bool
}

struct FoodEntry: Codable, Hashable, Identifiable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case describe, product, manual
        var id: String { rawValue }

        var title: String {
            switch self {
            case .describe: return "Описание"
            case .product: return "Точный продукт"
            case .manual: return "Вручную"
            }
        }
    }

    enum Status: String, Codable {
        case pending, done, failed
    }

    var id = UUID()
    var date: Date
    var text: String
    var mode: Mode
    var multiplier: Double = 1
    var status: Status
    var analysis: FoodAnalysis?
    var error: String?

    var nutrients: Nutrients { (analysis?.total ?? .zero).scaled(multiplier) }
    var kcal: Double { nutrients.kcal }
    var title: String { analysis?.title ?? text }

    var meal: String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return "Завтрак"
        case 11..<16: return "Обед"
        case 16..<22: return "Ужин"
        default: return "Перекус"
        }
    }
}

struct WeightEntry: Codable, Hashable, Identifiable {
    enum Source: String, Codable {
        case app, health, profile
    }

    var id = UUID()
    var date: Date
    var kg: Double
    var source: Source
}

struct PlanExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: String
    var tip: String?
}

struct PlanDay: Codable, Hashable, Identifiable {
    var id = UUID()
    var day: String
    var focus: String
    var morning: [PlanExercise]
    var evening: [PlanExercise]
    var cardio: String?
}

struct TrainingPlan: Codable, Hashable {
    var createdAt: Date
    var summary: String
    var days: [PlanDay]
    var tips: [String]
    var isAI: Bool

    /// План начинается с понедельника.
    func day(for date: Date) -> PlanDay? {
        guard !days.isEmpty else { return nil }
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = воскресенье
        let index = (weekday + 5) % 7
        return days[min(index, days.count - 1)]
    }
}

struct LossSettings: Codable, Equatable {
    var goalWeight: Double?
    var dailyDeficit: Double = 500
    var reminderEnabled = false
    var reminderHour = 21
    var reminderMinute = 30
    var planWishes = ""
}

struct EnergyDay: Identifiable {
    var day: Date
    var eaten: Double
    var active: Double
    var basal: Double
    var basalEstimated: Bool
    var hasFood: Bool

    var id: Date { day }
    var burned: Double { active + basal }
    var balance: Double { eaten - burned }
    /// ≈ 7700 ккал на килограмм жировой ткани.
    var weightChange: Double { balance / 7700 }
}
