import SwiftUI

// MARK: - Root + Tabs

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false
    @State private var selectedDayIndex: Int = Calendar.current.component(.weekday, from: Date()) - 1
    @State private var showSummaryAlert = false
    @State private var lastSummaryText = ""
    
    var body: some View {
        TabView {
            TodayView(
                selectedDayIndex: $selectedDayIndex,
                showSummaryAlert: $showSummaryAlert,
                lastSummaryText: $lastSummaryText
            )
            .tabItem {
                Label("Today", systemImage: "sun.max.fill")
            }
            
            PlannerView()
                .tabItem {
                    Label("Plan", systemImage: "slider.horizontal.3")
                }
            
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
        }
        .onAppear {
            showOnboarding = !appState.hasOnboarded
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .alert(isPresented: $showSummaryAlert) {
            Alert(
                title: Text("Day Summary"),
                message: Text(lastSummaryText),
                dismissButton: .default(Text("Nice!"))
            )
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Welcome")) {
                    TextField("Your name", text: $appState.tempName)
                }
                
                Section(header: Text("Default wake / sleep")) {
                    DatePicker("Wake time", selection: $appState.wakeTime, displayedComponents: .hourAndMinute)
                    DatePicker("Sleep time", selection: $appState.sleepTime, displayedComponents: .hourAndMinute)
                }
                
                Section(header: Text("Fixed activities (work, school, etc.)")) {
                    FixedActivitiesList()
                }
                
                Section(header: Text("Free time preferences")) {
                    ForEach(FreeActivity.allCases) { activity in
                        HStack {
                            Text(activity.rawValue)
                            Spacer()
                            if appState.selectedActivities.contains(activity) {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appState.selectedActivities.contains(activity) {
                                appState.selectedActivities.remove(activity)
                            } else {
                                appState.selectedActivities.insert(activity)
                            }
                        }
                    }
                    CustomPreferencesEditor()
                }
                
                Section(header: Text("Scheduling mode")) {
                    Picker("Mode", selection: $appState.autoSchedule) {
                        Text("Auto-fill free time").tag(true)
                        Text("Manual only").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Set up FlowBuddy")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        appState.finishOnboarding()
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Fixed activities shared components

struct FixedActivitiesList: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ForEach(appState.fixedActivities.indices, id: \.self) { idx in
            let activity = appState.fixedActivities[idx]
            let binding = $appState.fixedActivities[idx]
            
            NavigationLink(destination: FixedActivityEditor(activity: binding)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.headline)
                    Text(summary(for: activity))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        
        Button {
            appState.addFixedActivity()
        } label: {
            Label("Add another fixed activity", systemImage: "plus.circle")
        }
    }
    
    func summary(for activity: FixedActivity) -> String {
        let cal = Calendar.current
        let dayNames = cal.shortWeekdaySymbols
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        var parts: [String] = []
        for idx in 0..<activity.days.count {
            let day = activity.days[idx]
            if day.enabled {
                let name = dayNames[idx]
                let s = formatter.string(from: day.start)
                let e = formatter.string(from: day.end)
                parts.append("\(name) \(s)–\(e)")
            }
        }
        return parts.isEmpty ? "No days set" : parts.joined(separator: ", ")
    }
}

struct FixedActivityEditor: View {
    @Binding var activity: FixedActivity
    
    var body: some View {
        Form {
            Section(header: Text("Name")) {
                TextField("Activity name", text: $activity.name)
            }
            
            Section(header: Text("Schedule by day")) {
                ForEach(activity.days.indices, id: \.self) { idx in
                    DayScheduleRow(
                        dayName: Calendar.current.weekdaySymbols[idx],
                        schedule: $activity.days[idx]
                    )
                }
            }
        }
        .navigationTitle(activity.name)
    }
}

struct DayScheduleRow: View {
    let dayName: String
    @Binding var schedule: DaySchedule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $schedule.enabled) {
                Text(dayName)
            }
            if schedule.enabled {
                DatePicker("Start", selection: $schedule.start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $schedule.end, displayedComponents: .hourAndMinute)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Custom preferences editor

struct CustomPreferencesEditor: View {
    @EnvironmentObject var appState: AppState
    @State private var newPreference: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your own activities")
                .font(.subheadline)
            
            ForEach(appState.customPreferences, id: \.self) { pref in
                HStack {
                    Text(pref)
                    Spacer()
                    Button(role: .destructive) {
                        remove(pref)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                }
            }
            
            HStack {
                TextField("e.g. Content creation, YouTube", text: $newPreference)
                Button {
                    addPreference()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newPreference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    
    func addPreference() {
        let trimmed = newPreference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !appState.customPreferences.contains(trimmed) {
            appState.customPreferences.append(trimmed)
        }
        newPreference = ""
    }
    
    func remove(_ pref: String) {
        appState.customPreferences.removeAll { $0 == pref }
    }
}

// MARK: - Day selector

struct WeekDaySelector: View {
    @Binding var selectedIndex: Int
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        let cal = Calendar.current
        let shortNames = cal.shortWeekdaySymbols // Sun … Sat
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<7) { idx in
                    let date = appState.dateForDayIndex(idx)
                    let isToday = cal.isDateInToday(date)
                    
                    Button(action: {
                        selectedIndex = idx
                    }) {
                        VStack(spacing: 4) {
                            Text(shortNames[idx])
                                .font(.caption)
                            Text("\(cal.component(.day, from: date))")
                                .font(.headline)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedIndex == idx ? Color.accentColor : Color.secondary.opacity(isToday ? 0.18 : 0.08))
                        )
                        .foregroundColor(selectedIndex == idx ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Today view

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedDayIndex: Int
    
    @Binding var showSummaryAlert: Bool
    @Binding var lastSummaryText: String
    
    @State private var showAddTaskSheet = false
    @State private var energyLevel: Int = 2 // 1=low,2=normal,3=high
    @State private var wakeOverride: Date? = nil
    @State private var sleepOverride: Date? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                WeekDaySelector(selectedIndex: $selectedDayIndex)
                    .padding(.top, 8)
                
                header
                
                if appState.tasks(for: selectedDayIndex).isEmpty {
                    Spacer()
                    Text("No tasks yet.\nTap “Regenerate schedule” or add one.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(appState.tasks(for: selectedDayIndex)) { task in
                            TaskRow(task: task) { completed in
                                appState.handleCompletionChange(dayIndex: selectedDayIndex, task: task, completed: completed)
                            }
                        }
                    }
                }
                
                controls
                
                Button(action: endDay) {
                    Text("End day & see summary")
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding([.horizontal, .bottom])
                }
            }
            .navigationTitle("Today")
        }
        .sheet(isPresented: $showAddTaskSheet) {
            AddTaskView(isPresented: $showAddTaskSheet, dayIndex: selectedDayIndex)
        }
    }
    
    var header: some View {
        let date = appState.dateForDayIndex(selectedDayIndex)
        let df = DateFormatter()
        df.dateStyle = .medium
        
        return VStack(alignment: .leading, spacing: 4) {
            Text("Hi, \(appState.userName.isEmpty ? "Friend" : appState.userName) 👋")
                .font(.title2)
                .bold()
            Text("Let’s make today productive but chill.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(df.string(from: date))
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            
            HStack {
                HStack {
                    Image(systemName: "flame.fill")
                    Text("Streak: \(appState.streak)d")
                }
                Spacer()
                HStack {
                    Image(systemName: "star.circle.fill")
                    Text("XP: \(appState.xp)")
                }
            }
            .font(.footnote)
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }
    
    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Energy and wake/sleep overrides for this day
            HStack {
                Text("Energy today:")
                    .font(.caption)
                Spacer()
                Picker("", selection: $energyLevel) {
                    Text("Low").tag(1)
                    Text("Normal").tag(2)
                    Text("High").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 200)
            }
            
            HStack {
                DatePicker("Wake", selection: Binding(
                    get: {
                        wakeOverride ?? appState.wakeTime
                    },
                    set: { newVal in
                        wakeOverride = newVal
                    }
                ), displayedComponents: .hourAndMinute)
                
                DatePicker("Sleep", selection: Binding(
                    get: {
                        sleepOverride ?? appState.sleepTime
                    },
                    set: { newVal in
                        sleepOverride = newVal
                    }
                ), displayedComponents: .hourAndMinute)
            }
            .font(.caption)
            
            HStack {
                Button(action: {
                    appState.regenerateDay(
                        selectedDayIndex,
                        energyLevel: energyLevel,
                        wakeOverride: wakeOverride,
                        sleepOverride: sleepOverride
                    )
                }) {
                    Label("Regenerate schedule", systemImage: "arrow.clockwise")
                }
                
                Spacer()
                
                Button(action: {
                    showAddTaskSheet = true
                }) {
                    Label("Add task", systemImage: "plus.circle.fill")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    func endDay() {
        let result = appState.endDayAndUpdateStreak(dayIndex: selectedDayIndex)
        let percent = result.total > 0 ? Int(Double(result.completedCount) / Double(result.total) * 100) : 0
        lastSummaryText = """
        You completed \(result.completedCount) of \(result.total) tasks (\(percent)%).
        Streak: \(appState.streak) day(s).
        XP: \(appState.xp)
        """
        showSummaryAlert = true
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: Task
    var onCompletionChange: (Bool) -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                onCompletionChange(!task.isCompleted)
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted, color: .primary)
                Text("\(timeString(task.start)) – \(timeString(task.end))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let type = task.type {
                    Text(type.rawValue)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Add task view

struct AddTaskView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    let dayIndex: Int
    
    @State private var title: String = ""
    @State private var start: Date = Date()
    @State private var end: Date = Date().addingTimeInterval(60 * 60)
    @State private var selectedActivity: FreeActivity? = nil
    @State private var saveAsTemplate: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Details")) {
                    TextField("Task title", text: $title)
                }
                
                Section(header: Text("Time")) {
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                }
                
                Section(header: Text("Type (optional)")) {
                    Picker("Type", selection: Binding(
                        get: { selectedActivity },
                        set: { selectedActivity = $0 }
                    )) {
                        Text("None").tag(FreeActivity?.none)
                        ForEach(FreeActivity.allCases) { activity in
                            Text(activity.rawValue).tag(FreeActivity?.some(activity))
                        }
                    }
                }
                
                Section {
                    Toggle("Save this setup to task library", isOn: $saveAsTemplate)
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if end > start {
                            appState.addManualTask(dayIndex: dayIndex,
                                                   title: title,
                                                   start: start,
                                                   end: end,
                                                   activity: selectedActivity)
                            
                            if saveAsTemplate {
                                let duration = end.timeIntervalSince(start)
                                appState.saveTemplate(title: title,
                                                      duration: duration,
                                                      type: selectedActivity)
                            }
                        }
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Planner view

struct PlannerView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic")) {
                    TextField("Name", text: $appState.userName)
                    DatePicker("Default wake", selection: $appState.wakeTime, displayedComponents: .hourAndMinute)
                    DatePicker("Default sleep", selection: $appState.sleepTime, displayedComponents: .hourAndMinute)
                }
                
                Section(header: Text("Fixed activities (work, school, etc.)")) {
                    FixedActivitiesList()
                }
                
                Section(header: Text("Free time preferences")) {
                    ForEach(FreeActivity.allCases) { activity in
                        HStack {
                            Text(activity.rawValue)
                            Spacer()
                            if appState.selectedActivities.contains(activity) {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if appState.selectedActivities.contains(activity) {
                                appState.selectedActivities.remove(activity)
                            } else {
                                appState.selectedActivities.insert(activity)
                            }
                        }
                    }
                    CustomPreferencesEditor()
                }
                
                Section(header: Text("Weekly goals (hours/week)")) {
                    if FreeActivity.allCases.isEmpty {
                        Text("No activities yet.")
                    } else {
                        ForEach(FreeActivity.allCases) { activity in
                            let binding = Binding<Double>(
                                get: { appState.weeklyGoals[activity] ?? 0 },
                                set: { appState.weeklyGoals[activity] = max(0, min(40, $0)) }
                            )
                            HStack {
                                Text(activity.rawValue)
                                Spacer()
                                Stepper(
                                    value: binding,
                                    in: 0...40,
                                    step: 0.5
                                ) {
                                    Text("\(binding.wrappedValue, specifier: "%.1f") h")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Weekly goals for your own activities (hours/week)")) {
                    if appState.customPreferences.isEmpty {
                        Text("Add your own activities above to set goals for them.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(appState.customPreferences, id: \.self) { pref in
                            let binding = Binding<Double>(
                                get: { appState.weeklyGoalsCustom[pref] ?? 0 },
                                set: { appState.weeklyGoalsCustom[pref] = max(0, min(40, $0)) }
                            )
                            HStack {
                                Text(pref)
                                Spacer()
                                Stepper(
                                    value: binding,
                                    in: 0...40,
                                    step: 0.5
                                ) {
                                    Text("\(binding.wrappedValue, specifier: "%.1f") h")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Task library")) {
                    if appState.taskTemplates.isEmpty {
                        Text("You can save tasks from the Today tab.\nWhen adding a task, toggle “Save this setup to task library”.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(appState.taskTemplates) { template in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title)
                                    .font(.subheadline)
                                if let type = template.type {
                                    Text(type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("Default: \(Int(template.defaultDuration / 60)) min")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete(perform: appState.deleteTemplates)
                    }
                }
                
                Section(header: Text("Scheduling mode")) {
                    Picker("Mode", selection: $appState.autoSchedule) {
                        Text("Auto (app fills free time)").tag(true)
                        Text("Manual (I'll plan myself)").tag(false)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section {
                    Button {
                        appState.generateWeekForCurrent()
                    } label: {
                        Label("Regenerate this week's schedule", systemImage: "arrow.clockwise.circle")
                    }
                }
            }
            .navigationTitle("Plan")
        }
    }
}

// MARK: - Stats view

struct StatsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 16)
                    
                    topStats
                    
                    funMeter
                    
                    weeklyGoalsSection
                    
                    Text("Tip: Complete tasks during the day and hit “End day & see summary” in the Today tab to keep your streak alive 🔥. Weekly goal progress updates as soon as you finish tasks.")
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            .navigationTitle("Stats")
        }
    }
    
    var topStats: some View {
        VStack(spacing: 12) {
            Text("Your progress")
                .font(.title2)
                .bold()
            
            HStack {
                statCard(icon: "flame.fill",
                         title: "Streak",
                         value: "\(appState.streak)d")
                
                statCard(icon: "star.circle.fill",
                         title: "XP",
                         value: "\(appState.xp)")
                
                let level = max(1, appState.xp / 100 + 1)
                statCard(icon: "medal.fill",
                         title: "Level",
                         value: "Lv \(level)")
            }
        }
        .padding(.horizontal)
    }
    
    var funMeter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fun meter (today)")
                .font(.headline)
            let (text, emoji) = funBalance()
            HStack {
                Text(emoji)
                Text(text)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    var weeklyGoalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly goals")
                .font(.headline)
            
            let hasAnyGoal =
                !appState.weeklyGoals.values.filter({ $0 > 0 }).isEmpty ||
                !appState.weeklyGoalsCustom.values.filter({ $0 > 0 }).isEmpty
            
            if !hasAnyGoal {
                Text("No weekly goals set yet.\nSet them in the Plan tab to track your progress.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(FreeActivity.allCases) { activity in
                    let goal = appState.weeklyGoals[activity] ?? 0
                    if goal > 0 {
                        let progress = appState.weeklyProgress[activity] ?? 0
                        let fraction = min(progress / max(goal, 0.001), 1.0)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(activity.rawValue)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(progress, specifier: "%.1f") / \(goal, specifier: "%.1f") h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: fraction)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                ForEach(appState.customPreferences, id: \.self) { pref in
                    let goal = appState.weeklyGoalsCustom[pref] ?? 0
                    if goal > 0 {
                        let progress = appState.weeklyProgressCustom[pref] ?? 0
                        let fraction = min(progress / max(goal, 0.001), 1.0)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(pref)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(progress, specifier: "%.1f") / \(goal, specifier: "%.1f") h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: fraction)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    func statCard(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.07))
        .cornerRadius(12)
    }
    
    func funBalance() -> (String, String) {
        let funSet: Set<FreeActivity> = [.relax, .social, .cooking]
        let productiveSet: Set<FreeActivity> = [.study, .skill, .exercise, .chores]
        
        var funHours: Double = 0
        var prodHours: Double = 0
        
        let cal = Calendar.current
        let today = cal.component(.weekday, from: Date()) - 1
        let tasks = appState.tasks(for: today)
        
        for task in tasks {
            guard let type = task.type else { continue }
            let hours = max(0, task.end.timeIntervalSince(task.start) / 3600.0)
            if funSet.contains(type) {
                funHours += hours
            } else if productiveSet.contains(type) {
                prodHours += hours
            }
        }
        
        let total = funHours + prodHours
        if total == 0 {
            return ("No tracked tasks yet – plan something in the Today tab 😊", "🤷‍♂️")
        }
        
        let ratio = prodHours / total
        
        switch ratio {
        case ..<0.4:
            return ("Very chill day (more fun than work)", "😌")
        case 0.4...0.7:
            return ("Balanced day (nice mix of work and fun)", "⚖️")
        default:
            return ("Heavy day (lots of work) – remember to rest too", "💪")
        }
    }
}
