import HealthKit

extension HealthKitService {
    /// Запускает приложение на Apple Watch с выбранной тренировкой.
    func startWatchWorkout(_ activity: HKWorkoutActivityType, completion: @escaping (Error?) -> Void) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = WorkoutCatalog.location(for: activity)
        store.startWatchApp(with: configuration) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}
