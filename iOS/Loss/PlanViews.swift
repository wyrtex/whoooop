import SwiftUI

struct TodayPlanCard: View {
    @EnvironmentObject private var loss: LossStore
    @EnvironmentObject private var store: HealthDataStore

    var body: some View {
        Card {
            SectionTitle(title: "Тренировки на сегодня", trailing: loss.plan.map { $0.isAI ? "план ИИ" : "базовый план" })
            if let plan = loss.plan, let day = plan.day(for: Date()) {
                if let recovery = store.today?.recovery, recovery < 34 {
                    Label("Восстановление \(Int(recovery))% — сделайте облегчённый вариант: половину подходов.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.recoveryYellow)
                }
                Text(day.focus).font(.headline)
                PlanBlock(title: "Утро", symbol: "sunrise.fill", exercises: day.morning, date: Date())
                PlanBlock(title: "Вечер", symbol: "moon.stars.fill", exercises: day.evening, date: Date())
                if let cardio = day.cardio {
                    Label(cardio, systemImage: "figure.walk")
                        .font(.subheadline)
                        .foregroundStyle(Theme.strain)
                }
                NavigationLink {
                    PlanView()
                } label: {
                    HStack {
                        Text("Весь план на неделю")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("План на неделю, чтобы уходили живот и жир: утром пресс и кор, вечером планка и функциональные упражнения, плюс кардио.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                GeneratePlanButton()
            }
        }
    }
}

struct PlanBlock: View {
    @EnvironmentObject private var loss: LossStore
    var title: String
    var symbol: String
    var exercises: [PlanExercise]
    var date: Date

    var body: some View {
        if !exercises.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(exercises) { exercise in
                    Button {
                        loss.toggle(exercise, on: date)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: loss.isDone(exercise, on: date) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(loss.isDone(exercise, on: date) ? Theme.recoveryGreen : Theme.tertiaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(exercise.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(exercise.amount)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Theme.strain)
                                }
                                if let tip = exercise.tip {
                                    Text(tip).font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct GeneratePlanButton: View {
    @EnvironmentObject private var loss: LossStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await loss.generatePlan() }
            } label: {
                HStack {
                    if loss.isGeneratingPlan { ProgressView().tint(.black) }
                    Label(loss.hasAIKeys ? "Составить план с ИИ" : "Составить базовый план", systemImage: "sparkles")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.strain, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
            .disabled(loss.isGeneratingPlan)
            if let error = loss.planError {
                Text(error).font(.caption).foregroundStyle(Theme.recoveryRed)
            }
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var loss: LossStore

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: today) ?? today
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan = loss.plan {
                    Card {
                        SectionTitle(title: plan.isAI ? "План от ИИ" : "Базовый план", trailing: "от \(Fmt.shortDay(plan.createdAt))")
                        Text(plan.summary).font(.subheadline)
                    }
                    ForEach(Array(plan.days.enumerated()), id: \.element.id) { index, day in
                        let date = index < weekDates.count ? weekDates[index] : Date()
                        Card {
                            HStack {
                                Text(day.day).font(.headline)
                                Text(day.focus).foregroundStyle(Theme.secondaryText)
                                Spacer()
                                if Calendar.current.isDateInToday(date) {
                                    Text("сегодня").font(.caption.weight(.bold)).foregroundStyle(Theme.recoveryGreen)
                                }
                            }
                            PlanBlock(title: "Утро", symbol: "sunrise.fill", exercises: day.morning, date: date)
                            PlanBlock(title: "Вечер", symbol: "moon.stars.fill", exercises: day.evening, date: date)
                            if let cardio = day.cardio {
                                Label(cardio, systemImage: "figure.walk").font(.footnote).foregroundStyle(Theme.strain)
                            }
                        }
                    }
                    if !plan.tips.isEmpty {
                        Card {
                            SectionTitle(title: "Советы")
                            ForEach(plan.tips, id: \.self) { tip in
                                Label(tip, systemImage: "lightbulb.fill").font(.footnote)
                            }
                        }
                    }
                }
                Card {
                    SectionTitle(title: "Пересоставить план")
                    TextField("Пожелания: есть турник, 20 минут, болит колено…", text: $loss.settings.planWishes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                    Text("План хранится на устройстве — ИИ вызывается только по этой кнопке.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                    GeneratePlanButton()
                    if loss.plan?.isAI == true {
                        Button("Вернуть базовый план") { loss.useBasicPlan() }
                            .font(.footnote)
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("План тренировок")
        .navigationBarTitleDisplayMode(.inline)
    }
}
