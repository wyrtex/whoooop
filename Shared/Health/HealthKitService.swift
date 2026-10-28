import Foundation
import HealthKit

struct ProfileHints {
    var age: Int?
    var sex: BiologicalSexOption?
    var weightKg: Double?
    var heightCm: Double?
}

/// Обёртка над HealthKit: только чтение «сырых» данных, без бизнес-логики.
final class HealthKitService {
    static let shared = HealthKitService()

    let store = HKHealthStore()
    static let bpm = HKUnit.count().unitDivided(by: .minute())

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.vo2Max),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.bodyMass),
        ]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Загрузка

    /// `heartRateDays` ограничивает поминутный пульс (самый тяжёлый запрос) — виджетам хватает двух дней.
    func fetchRaw(days: Int, heartRateDays: Int? = nil, now: Date = Date()) async -> RawHealthData {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(days + 1), to: calendar.startOfDay(for: now)) ?? now
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: now) ?? start
        let heartRateStart = heartRateDays
            .flatMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) } ?? start

        async let heartRate = minuteHeartRate(start: heartRateStart, end: now)
        async let resting = daily(.restingHeartRate, unit: Self.bpm, options: .discreteAverage, start: start, end: now)
        async let hrv = values(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: start, end: now)
        async let respiratory = values(.respiratoryRate, unit: Self.bpm, start: start, end: now)
        async let spo2 = values(.oxygenSaturation, unit: .percent(), start: start, end: now)
        async let temperature = values(.appleSleepingWristTemperature, unit: .degreeCelsius(), start: start, end: now)
        async let sleep = sleepSegments(start: start, end: now)
        async let workouts = workouts(start: start, end: now)
        async let active = daily(.activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: now)
        async let basal = daily(.basalEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: now)
        async let steps = daily(.stepCount, unit: .count(), options: .cumulativeSum, start: start, end: now)
        async let vo2 = values(.vo2Max, unit: HKUnit(from: "ml/kg*min"), start: yearAgo, end: now)

        var raw = RawHealthData()
        raw.heartRate = await heartRate
        raw.restingHR = await resting
        raw.hrv = await hrv
        raw.respiratoryRate = await respiratory
        raw.spo2 = await spo2
        raw.wristTemp = await temperature
        raw.sleep = await sleep
        raw.workouts = await workouts
        raw.activeEnergy = await active
        raw.basalEnergy = await basal
        raw.steps = await steps
        raw.vo2max = await vo2
        return raw
    }

    func profileHints() async -> ProfileHints {
        var hints = ProfileHints()
        if let components = try? store.dateOfBirthComponents(),
           let birthday = Calendar.current.date(from: components) {
            hints.age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: hints.sex = .male
            case .female: hints.sex = .female
            default: break
            }
        }
        // Только свежий вес: старая запись (например, годичной давности) испортит расчёт обмена.
        if let weight = await latestSample(.bodyMass), Date().timeIntervalSince(weight.endDate) < 60 * 86400 {
            hints.weightKg = weight.quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
        hints.heightCm = await latest(.height, unit: .meterUnit(with: .centi))
        return hints
    }

    // MARK: - Запросы

    private func samples(of type: HKSampleType, start: Date, end: Date, limit: Int = HKObjectQueryNoLimit, ascending: Bool = true) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
    }

    private func statistics(_ type: HKQuantityType, options: HKStatisticsOptions, start: Date, end: Date, interval: DateComponents) async -> [HKStatistics] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: interval)
            query.initialResultsHandler = { _, collection, _ in
                continuation.resume(returning: collection?.statistics() ?? [])
            }
            store.execute(query)
        }
    }

    private func values(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> [ValueSample] {
        let results = await samples(of: HKQuantityType(id), start: start, end: end)
        return results.compactMap { $0 as? HKQuantitySample }.map {
            ValueSample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await latestSample(id)?.quantity.doubleValue(for: unit)
    }

    private func latestSample(_ id: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        let results = await samples(of: HKQuantityType(id), start: .distantPast, end: Date(), limit: 1, ascending: false)
        return results.first as? HKQuantitySample
    }

    private func daily(_ id: HKQuantityTypeIdentifier, unit: HKUnit, options: HKStatisticsOptions, start: Date, end: Date) async -> [Date: Double] {
        let stats = await statistics(HKQuantityType(id), options: options, start: start, end: end, interval: DateComponents(day: 1))
        var result: [Date: Double] = [:]
        for item in stats {
            let quantity = options.contains(.cumulativeSum) ? item.sumQuantity() : item.averageQuantity()
            if let quantity {
                result[Calendar.current.startOfDay(for: item.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return result
    }

    /// Средний пульс по минутам — компактно и достаточно точно для расчёта нагрузки.
    private func minuteHeartRate(start: Date, end: Date) async -> [HRSample] {
        let stats = await statistics(HKQuantityType(.heartRate), options: .discreteAverage, start: start, end: end, interval: DateComponents(minute: 1))
        return stats.compactMap { item in
            item.averageQuantity().map { HRSample(date: item.startDate, bpm: $0.doubleValue(for: Self.bpm)) }
        }
    }

    private func sleepSegments(start: Date, end: Date) async -> [SourcedSleepSegment] {
        let results = await samples(of: HKCategoryType(.sleepAnalysis), start: start, end: end)
        return results.compactMap { sample -> SourcedSleepSegment? in
            guard let category = sample as? HKCategorySample,
                  let value = HKCategoryValueSleepAnalysis(rawValue: category.value) else { return nil }
            let stage: SleepStage
            var inBed = false
            switch value {
            case .inBed:
                stage = .light
                inBed = true
            case .awake: stage = .awake
            case .asleepCore, .asleepUnspecified: stage = .light
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            @unknown default: return nil
            }
            let revision = category.sourceRevision
            return SourcedSleepSegment(
                sourceID: revision.source.bundleIdentifier,
                isWatch: revision.productType?.hasPrefix("Watch") ?? false,
                isInBed: inBed,
                segment: SleepSegment(start: category.startDate, end: category.endDate, stage: stage))
        }
    }

    private func workouts(start: Date, end: Date) async -> [RawWorkout] {
        let results = await samples(of: HKObjectType.workoutType(), start: start, end: end)
        return results.compactMap { $0 as? HKWorkout }.map { workout in
            let info = WorkoutCatalog.info(for: workout.workoutActivityType)
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let distanceStats = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))
                ?? workout.statistics(for: HKQuantityType(.distanceCycling))
                ?? workout.statistics(for: HKQuantityType(.distanceSwimming))
            return RawWorkout(
                id: workout.uuid,
                activityRaw: workout.workoutActivityType.rawValue,
                name: info.name,
                symbol: info.symbol,
                start: workout.startDate,
                end: workout.endDate,
                energyKcal: energy,
                distanceMeters: distanceStats?.sumQuantity()?.doubleValue(for: .meter()))
        }
    }

    // MARK: - Вес

    /// История веса из «Здоровья» (весы, приложения и записи Pulsar).
    func weightHistory(days: Int) async -> [ValueSample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return await values(.bodyMass, unit: .gramUnit(with: .kilo), start: start, end: Date())
    }

    @discardableResult
    func saveWeight(_ kg: Double, date: Date) async -> Bool {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass), quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
        }
    }

    /// Удаляет только записи, сделанные этим приложением, в пределах секунды от даты.
    func deleteWeight(at date: Date) async {
        let timePredicate = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1), end: date.addingTimeInterval(1), options: [])
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate, sourcePredicate])
        _ = try? await store.deleteObjects(of: HKQuantityType(.bodyMass), predicate: predicate)
    }
}
