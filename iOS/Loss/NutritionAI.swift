import Foundation

/// Запросы к ИИ: подсчёт калорий и план тренировок. Промпты короткие, ответы — компактный JSON.
enum NutritionAI {
    private static let system = "Ты нутрициолог и фитнес-тренер. Отвечай строго одним JSON-объектом без markdown и пояснений. Числа — без единиц измерения. Язык — русский."

    // MARK: Еда

    static func analyzeFood(_ text: String, mode: FoodEntry.Mode) async throws -> FoodAnalysis {
        let schema = """
        {"title":"короткое название","brand":"бренд или null","portion":"на какую порцию посчитано","items":[{"name":"","grams":0,"kcal":0,"protein":0,"fat":0,"carbs":0}],"kcal":0,"protein":0,"fat":0,"carbs":0,"per100g":{"kcal":0,"protein":0,"fat":0,"carbs":0},"details":["факт"],"confidence":"низкая|средняя|высокая","notes":"допущения"}
        """
        let prompt: String
        switch mode {
        case .product:
            prompt = """
            Найди в интернете продукт «\(text)» (официальный сайт производителя, магазины, базы КБЖУ). \
            Если указан вес или упаковка — посчитай на неё, иначе на одну стандартную порцию. \
            В details перечисли всё полезное о продукте: состав, вес упаковки, аллергены, особенности, где найдено. \
            Ответ — JSON: \(schema)
            """
        default:
            prompt = """
            Оцени КБЖУ съеденного: «\(text)». Разбей на компоненты с граммами. \
            Тарелка 24 см; «3/4 тарелки», «большая», «ложка» — переведи в граммы. Если порция не указана — средняя. \
            per100g и details можно не заполнять. Ответ — JSON: \(schema)
            """
        }
        let request = GeminiClient.Request(
            prompt: prompt,
            system: system,
            useSearch: mode == .product,
            maxOutputTokens: mode == .product ? 1500 : 900)
        let response = try await GeminiClient.shared.generate(request)
        let json = try extractJSON(response.text)

        let items: [FoodItem] = (json["items"] as? [[String: Any]] ?? []).map { item in
            FoodItem(name: string(item["name"]) ?? "Компонент", grams: number(item["grams"]), nutrients: nutrients(item))
        }
        var total = nutrients(json)
        if total.kcal <= 0, !items.isEmpty {
            total = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        }
        guard total.kcal > 0 else { throw GeminiError.badResponse("нет калорий в ответе") }

        let per100 = (json["per100g"] as? [String: Any]).map(nutrients)
        return FoodAnalysis(
            title: string(json["title"]) ?? text,
            brand: string(json["brand"]),
            portion: string(json["portion"]),
            items: items,
            total: total,
            per100g: (per100?.kcal ?? 0) > 0 ? per100 : nil,
            details: (json["details"] as? [Any] ?? []).compactMap { string($0) },
            confidence: string(json["confidence"]),
            notes: string(json["notes"]),
            sources: Array(response.sources.prefix(5)),
            model: response.model,
            isManual: false)
    }

    // MARK: План тренировок

    struct PlanContext {
        var profile: UserProfile
        var goalWeight: Double?
        var averageRecovery: Double?
        var workoutsPerWeek: Int
        var averageSteps: Double?
        var wishes: String
    }

    static func trainingPlan(_ context: PlanContext) async throws -> TrainingPlan {
        let p = context.profile
        var facts = "\(p.sex == .male ? "мужчина" : "женщина"), \(p.age) лет, рост \(Int(p.heightCm)) см, вес \(String(format: "%.1f", p.weightKg)) кг"
        if let goal = context.goalWeight { facts += ", цель \(String(format: "%.1f", goal)) кг" }
        if let recovery = context.averageRecovery { facts += ", среднее восстановление \(Int(recovery))%" }
        facts += ", тренировок в неделю: \(context.workoutsPerWeek)"
        if let steps = context.averageSteps { facts += ", шагов в день: \(Int(steps))" }
        let wishes = context.wishes.isEmpty ? "дома, без оборудования" : context.wishes

        let prompt = """
        Составь недельный план (Пн–Вс) для сжигания жира и уменьшения живота. Человек: \(facts). Условия: \(wishes).
        Каждый день: утро — пресс/кор 10–15 мин, вечер — планка и функциональные упражнения 15–20 мин, плюс кардио (шаги, зона 2). \
        Один-два дня лёгкие (восстановление). Нагрузку повышай к концу недели. Подсказки по технике — до 8 слов.
        JSON: {"summary":"2 предложения","days":[{"day":"Пн","focus":"","morning":[{"name":"","amount":"3×15","tip":""}],"evening":[{"name":"","amount":"3×40 сек","tip":""}],"cardio":""}],"tips":["совет по питанию и сну"]}
        """
        let response = try await GeminiClient.shared.generate(
            GeminiClient.Request(prompt: prompt, system: system, maxOutputTokens: 3500, temperature: 0.4))
        let json = try extractJSON(response.text)

        func exercises(_ value: Any?) -> [PlanExercise] {
            (value as? [[String: Any]] ?? []).compactMap { item in
                guard let name = string(item["name"]) else { return nil }
                return PlanExercise(name: name, amount: string(item["amount"]) ?? "", tip: string(item["tip"]))
            }
        }
        let days: [PlanDay] = (json["days"] as? [[String: Any]] ?? []).map { day in
            PlanDay(
                day: string(day["day"]) ?? "",
                focus: string(day["focus"]) ?? "",
                morning: exercises(day["morning"]),
                evening: exercises(day["evening"]),
                cardio: string(day["cardio"]))
        }
        guard days.count >= 7 else { throw GeminiError.badResponse("в плане меньше 7 дней") }
        return TrainingPlan(
            createdAt: Date(),
            summary: string(json["summary"]) ?? "",
            days: Array(days.prefix(7)),
            tips: (json["tips"] as? [Any] ?? []).compactMap { string($0) },
            isAI: true)
    }

    /// Базовый план без ИИ — работает и без ключей.
    static func basicPlan() -> TrainingPlan {
        func ex(_ name: String, _ amount: String, _ tip: String) -> PlanExercise {
            PlanExercise(name: name, amount: amount, tip: tip)
        }
        let coreA = [ex("Скручивания", "3×15", "Поясница прижата к полу"), ex("Обратные скручивания", "3×12", "Поднимайте таз, не раскачивайтесь"), ex("Велосипед", "3×20", "Медленно, локоть к колену")]
        let coreB = [ex("Подъёмы ног лёжа", "3×12", "Не отрывайте поясницу"), ex("Русские скручивания", "3×20", "Корпус под 45°"), ex("Вакуум живота", "5×20 сек", "На выдохе, натощак")]
        let plankA = [ex("Планка на локтях", "3×40 сек", "Тело — прямая линия"), ex("Боковая планка", "2×30 сек на сторону", "Таз не провисает"), ex("Альпинист", "3×30 сек", "Колени к груди в темпе")]
        let plankB = [ex("Приседания", "3×20", "Колени по линии носков"), ex("Выпады", "3×12 на ногу", "Шаг широкий, спина прямая"), ex("Планка с касанием плеч", "3×30 сек", "Без раскачки таза"), ex("Берпи", "3×10", "Ровный темп")]
        let easy = [ex("Растяжка всего тела", "10 мин", "Дышите спокойно"), ex("Кошка-корова", "2×10", "Плавно, с дыханием")]
        let days: [PlanDay] = [
            PlanDay(day: "Пн", focus: "Кор + планка", morning: coreA, evening: plankA, cardio: "8–10 тыс. шагов"),
            PlanDay(day: "Вт", focus: "Ноги и жиросжигание", morning: coreB, evening: plankB, cardio: "30 мин ходьбы в зоне 2"),
            PlanDay(day: "Ср", focus: "Лёгкий день", morning: [ex("Вакуум живота", "5×20 сек", "На выдохе")], evening: easy, cardio: "Прогулка 40 мин"),
            PlanDay(day: "Чт", focus: "Кор + планка", morning: coreA, evening: plankA + [ex("Планка", "1× максимум", "До отказа, без провисания")], cardio: "8–10 тыс. шагов"),
            PlanDay(day: "Пт", focus: "Интервалы", morning: coreB, evening: plankB, cardio: "20 мин интервалов: 1 мин быстро / 1 мин шаг"),
            PlanDay(day: "Сб", focus: "Длинное кардио", morning: coreA, evening: [ex("Планка на локтях", "4×45 сек", "Напрягите ягодицы")], cardio: "60 мин ходьбы, вело или плавания"),
            PlanDay(day: "Вс", focus: "Восстановление", morning: easy, evening: easy, cardio: "Свободная прогулка"),
        ]
        return TrainingPlan(
            createdAt: Date(),
            summary: "Живот уходит вместе с общим жиром: главное — дефицит калорий, а упражнения укрепляют кор и ускоряют расход. Каждую неделю добавляйте 10–15% к повторам или времени.",
            days: days,
            tips: ["Дефицит 300–500 ккал в день — без голодания", "Белок 1,6–2 г на кг веса", "Сон 7–9 часов: недосып повышает аппетит", "Шаги — самый простой способ сжечь больше"],
            isAI: false)
    }

    // MARK: Разбор JSON

    static func extractJSON(_ text: String) throws -> [String: Any] {
        var body = text
        if let start = body.firstIndex(of: "{"), let end = body.lastIndex(of: "}"), start < end {
            body = String(body[start...end])
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.badResponse(String(text.prefix(120)))
        }
        return json
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String {
            let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
            return Double(cleaned)
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "null" ? nil : trimmed
    }

    private static func nutrients(_ json: [String: Any]) -> Nutrients {
        Nutrients(
            kcal: number(json["kcal"]) ?? 0,
            protein: number(json["protein"]) ?? 0,
            fat: number(json["fat"]) ?? 0,
            carbs: number(json["carbs"]) ?? 0)
    }
}
