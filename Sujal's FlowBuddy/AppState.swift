import Foundation
import UserNotifications

// MARK: - Core types

enum FreeActivity: String, CaseIterable, Identifiable, Codable {
    case study = "Study"
    case skill = "Skill-building"
    case exercise = "Exercise"
    case chores = "Chores"
    case relax = "Relaxation"
    case cooking = "Cooking / Meal prep"
    case social = "Social / Going out"
    
    var id: String { rawValue }
}

struct Task: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var start: Date
    var end: Date
    var type: FreeActivity?
    var isCompleted: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        start: Date,
        end: Date,
        type: FreeActivity? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.type = type
        self.isCompleted = isCompleted
    }
}

// One day's schedule for a fixed activity (e.g. Monday 9–5).
struct DaySchedule: Identifiable, Codable {
    var id = UUID()
    var enabled: Bool
    var start: Date
    var end: Date
}

// Recurring activity like Work or School.
struct FixedActivity: Identifiable, Codable {
    var id = UUID()
    var name: String
    var days: [DaySchedule] // index 0 = Sunday, 6 = Saturday
}

// Saved reusable pattern for manual tasks
struct TaskTemplate: Identifiable, Codable {
    let id: UUID
    var title: String
    var defaultDuration: TimeInterval
    var type: FreeActivity?
}

// MARK: - AppState

class AppState: ObservableObject {
    
    // MARK: User basics
    
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }
    
    @Published var userName: String {
        didSet { UserDefaults.standard.set(userName, forKey: "userName") }
    }
    
    @Published var tempName: String = ""
    
    // Global default wake / sleep
    @Published var wakeTime: Date {
        didSet { UserDefaults.standard.set(wakeTime.timeIntervalSinceReferenceDate, forKey: "wakeTime") }
    }
    
    @Published var sleepTime: Date {
        didSet { UserDefaults.standard.set(sleepTime.timeIntervalSinceReferenceDate, forKey: "sleepTime") }
    }
    
    // Fixed recurring activities
    @Published var fixedActivities: [FixedActivity] {
        didSet {
            if let data = try? JSONEncoder().encode(fixedActivities) {
                UserDefaults.standard.set(data, forKey: "fixedActivities")
            }
        }
    }
    
    // Built-in free-time preferences
    @Published var selectedActivities: Set<FreeActivity> {
        didSet {
            let rawValues = selectedActivities.map { $0.rawValue }
            UserDefaults.standard.set(rawValues, forKey: "selectedActivities")
        }
    }
    
    // Custom free-time preferences
    @Published var customPreferences: [String] {
        didSet {
            UserDefaults.standard.set(customPreferences, forKey: "customPreferences")
        }
    }
    
    // Global toggle: let app auto-fill free time or not
    @Published var autoSchedule: Bool {
        didSet { UserDefaults.standard.set(autoSchedule, forKey: "autoSchedule") }
    }
    
    // Task library
    @Published var taskTemplates: [TaskTemplate] {
        didSet {
            if let data = try? JSONEncoder().encode(taskTemplates) {
                UserDefaults.standard.set(data, forKey: "taskTemplates")
            }
        }
    }
    
    // Weekly schedule: 0=Sunday … 6=Saturday
    @Published var currentWeekStart: Date {
        didSet {
            UserDefaults.standard.set(currentWeekStart.timeIntervalSinceReferenceDate,
                                      forKey: "currentWeekStart")
        }
    }
    
    @Published var weekTasks: [Int: [Task]] {
        didSet {
            persistWeekTasks()
        }
    }
    
    // Gamification
    @Published var xp: Int {
        didSet { UserDefaults.standard.set(xp, forKey: "xp") }
    }
    
    @Published var streak: Int {
        didSet { UserDefaults.standard.set(streak, forKey: "streak") }
    }
    
    @Published var lastCompletionDate: Date? {
        didSet {
            if let date = lastCompletionDate {
                UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: "lastCompletionDate")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastCompletionDate")
            }
        }
    }
    
    // Weekly goals (built-in)
    @Published var weeklyGoals: [FreeActivity: Double] {
        didSet {
            var dict: [String: Double] = [:]
            for (activity, hours) in weeklyGoals {
                dict[activity.rawValue] = hours
            }
            UserDefaults.standard.set(dict, forKey: "weeklyGoals")
        }
    }
    
    // Weekly progress (built-in)
    @Published var weeklyProgress: [FreeActivity: Double] {
        didSet {
            var dict: [String: Double] = [:]
            for (activity, hours) in weeklyProgress {
                dict[activity.rawValue] = hours
            }
            UserDefaults.standard.set(dict, forKey: "weeklyProgress")
        }
    }
    
    // Weekly goals for custom activities
    @Published var weeklyGoalsCustom: [String: Double] {
        didSet {
            UserDefaults.standard.set(weeklyGoalsCustom, forKey: "weeklyGoalsCustom")
        }
    }
    
    // Weekly progress for custom activities
    @Published var weeklyProgressCustom: [String: Double] {
        didSet {
            UserDefaults.standard.set(weeklyProgressCustom, forKey: "weeklyProgressCustom")
        }
    }
    
    // Tracking which week the progress belongs to
    @Published var lastWeekStart: Date? {
        didSet {
            if let date = lastWeekStart {
                UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: "lastWeekStart")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastWeekStart")
            }
        }
    }
    
    // MARK: - Init
    
    init() {
        let defaults = UserDefaults.standard
        
        self.hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        self.userName = defaults.string(forKey: "userName") ?? ""
        
        let now = Date()
        let cal = Calendar.current
        
        let defaultWake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        let defaultSleep = cal.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
        
        let wakeInterval = defaults.double(forKey: "wakeTime")
        let sleepInterval = defaults.double(forKey: "sleepTime")
        
        self.wakeTime = wakeInterval == 0 ? defaultWake : Date(timeIntervalSinceReferenceDate: wakeInterval)
        self.sleepTime = sleepInterval == 0 ? defaultSleep : Date(timeIntervalSinceReferenceDate: sleepInterval)
        
        if let data = defaults.data(forKey: "fixedActivities"),
           let decoded = try? JSONDecoder().decode([FixedActivity].self, from: data) {
            self.fixedActivities = decoded
        } else {
            self.fixedActivities = AppState.defaultFixedActivities()
        }
        
        if let rawValues = defaults.array(forKey: "selectedActivities") as? [String] {
            let all = Set(FreeActivity.allCases)
            self.selectedActivities = Set(rawValues.compactMap { raw in
                all.first(where: { $0.rawValue == raw })
            })
        } else {
            self.selectedActivities = [.study, .exercise]
        }
        
        self.customPreferences = defaults.stringArray(forKey: "customPreferences") ?? []
        self.autoSchedule = defaults.object(forKey: "autoSchedule") as? Bool ?? true
        
        if let data = defaults.data(forKey: "taskTemplates"),
           let decoded = try? JSONDecoder().decode([TaskTemplate].self, from: data) {
            self.taskTemplates = decoded
        } else {
            self.taskTemplates = []
        }
        
        self.xp = defaults.integer(forKey: "xp")
        self.streak = defaults.integer(forKey: "streak")
        
        let lastInterval = defaults.double(forKey: "lastCompletionDate")
        self.lastCompletionDate = lastInterval == 0 ? nil : Date(timeIntervalSinceReferenceDate: lastInterval)
        
        if let storedGoals = defaults.dictionary(forKey: "weeklyGoals") as? [String: Double] {
            var map: [FreeActivity: Double] = [:]
            for (key, value) in storedGoals {
                if let activity = FreeActivity(rawValue: key) {
                    map[activity] = value
                }
            }
            self.weeklyGoals = map
        } else {
            self.weeklyGoals = [:]
        }
        
        if let storedProgress = defaults.dictionary(forKey: "weeklyProgress") as? [String: Double] {
            var map: [FreeActivity: Double] = [:]
            for (key, value) in storedProgress {
                if let activity = FreeActivity(rawValue: key) {
                    map[activity] = value
                }
            }
            self.weeklyProgress = map
        } else {
            self.weeklyProgress = [:]
        }
        
        self.weeklyGoalsCustom = defaults.dictionary(forKey: "weeklyGoalsCustom") as? [String: Double] ?? [:]
        self.weeklyProgressCustom = defaults.dictionary(forKey: "weeklyProgressCustom") as? [String: Double] ?? [:]
        
        let lastWeekInterval = defaults.double(forKey: "lastWeekStart")
        self.lastWeekStart = lastWeekInterval == 0 ? nil : Date(timeIntervalSinceReferenceDate: lastWeekInterval)
        
        let storedWeekStartInterval = defaults.double(forKey: "currentWeekStart")
        let today = cal.startOfDay(for: now)
        // Compute start of week directly instead of calling an instance method
        let weekComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let thisWeekStart = cal.date(from: weekComps) ?? today

        
        if storedWeekStartInterval != 0 {
            let storedWeekStart = Date(timeIntervalSinceReferenceDate: storedWeekStartInterval)
            if cal.isDate(storedWeekStart, inSameDayAs: thisWeekStart),
               let data = defaults.data(forKey: "weekTasks"),
               let decoded = try? JSONDecoder().decode([Int: [Task]].self, from: data) {
                self.currentWeekStart = storedWeekStart
                self.weekTasks = decoded
            } else {
                self.currentWeekStart = thisWeekStart
                self.weekTasks = [:]
                generateWeekForCurrent()
            }
        } else {
            self.currentWeekStart = thisWeekStart
            self.weekTasks = [:]
            generateWeekForCurrent()
        }
        
        ensureWeeklyProgressIsForCurrentWeek()

        requestNotificationPermission()
        scheduleNotificationsForToday()
    }
    
    // MARK: - Defaults
    
    static func defaultFixedActivities() -> [FixedActivity] {
        let cal = Calendar.current
        let now = Date()
        
        func makeDay(enabled: Bool, hourStart: Int, hourEnd: Int) -> DaySchedule {
            let start = cal.date(bySettingHour: hourStart, minute: 0, second: 0, of: now) ?? now
            let end = cal.date(bySettingHour: hourEnd, minute: 0, second: 0, of: now) ?? now
            return DaySchedule(enabled: enabled, start: start, end: end)
        }
        
        var workDays: [DaySchedule] = []
        for weekday in 1...7 {
            let enabled = (2...6).contains(weekday) // Mon–Fri
            workDays.append(makeDay(enabled: enabled, hourStart: 9, hourEnd: 17))
        }
        let work = FixedActivity(name: "Work / Job", days: workDays)
        
        var schoolDays: [DaySchedule] = []
        for _ in 1...7 {
            schoolDays.append(makeDay(enabled: false, hourStart: 9, hourEnd: 15))
        }
        let school = FixedActivity(name: "School / Classes", days: schoolDays)
        
        return [work, school]
    }
    
    // MARK: - Onboarding
    
    func finishOnboarding() {
        userName = tempName.isEmpty ? "Friend" : tempName
        hasOnboarded = true
        generateWeekForCurrent()
    }
    
    // MARK: - Week helpers
    
    func startOfWeek(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }
    
    func dateForDayIndex(_ index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index, to: currentWeekStart) ?? currentWeekStart
    }
    
    private func persistWeekTasks() {
        if let data = try? JSONEncoder().encode(weekTasks) {
            UserDefaults.standard.set(data, forKey: "weekTasks")
        }
    }
    
    func generateWeekForCurrent() {
        var newWeek: [Int: [Task]] = [:]
        for idx in 0..<7 {
            let date = dateForDayIndex(idx)
            newWeek[idx] = generateSchedule(for: date, dayIndex: idx)
        }
        weekTasks = newWeek
        scheduleNotificationsForToday()
    }
    
    func regenerateDay(_ dayIndex: Int,
                       energyLevel: Int? = nil,
                       wakeOverride: Date? = nil,
                       sleepOverride: Date? = nil) {
        let date = dateForDayIndex(dayIndex)
        let tasks = generateSchedule(for: date,
                                     dayIndex: dayIndex,
                                     energyLevel: energyLevel,
                                     wakeOverride: wakeOverride,
                                     sleepOverride: sleepOverride)
        weekTasks[dayIndex] = tasks
        scheduleNotificationsForToday()
    }
    
    func tasks(for dayIndex: Int) -> [Task] {
        weekTasks[dayIndex] ?? []
    }
    
    func setTasks(_ tasks: [Task], for dayIndex: Int) {
        weekTasks[dayIndex] = tasks
    }
    
    // MARK: - Fixed activities
    
    func addFixedActivity() {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let end = cal.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        let days = (0..<7).map { _ in DaySchedule(enabled: false, start: start, end: end) }
        let activity = FixedActivity(name: "New activity", days: days)
        fixedActivities.append(activity)
    }
    
    // MARK: - Duration heuristics
    
    private func defaultDuration(forTitle title: String, type: FreeActivity?) -> TimeInterval {
        let baseType = type ?? FreeActivity(rawValue: title)
        switch baseType {
        case .study:
            return 90 * 60
        case .skill:
            return 75 * 60
        case .exercise:
            return 45 * 60
        case .chores:
            return 40 * 60
        case .relax:
            return 30 * 60
        case .cooking:
            return 45 * 60
        case .social:
            return 120 * 60
        case .none:
            if customPreferences.contains(title) {
                return 60 * 60
            } else {
                return 60 * 60
            }
        }
    }
    
    // MARK: - Schedule generation
    
    func generateSchedule(for date: Date,
                          dayIndex: Int,
                          energyLevel: Int? = nil,
                          wakeOverride: Date? = nil,
                          sleepOverride: Date? = nil) -> [Task] {
        var tasks: [Task] = []
        let cal = Calendar.current
        
        let startOfDay = cal.startOfDay(for: date)
        let defaultWake = timeOnDate(from: wakeTime, base: startOfDay)
        let defaultSleep = timeOnDate(from: sleepTime, base: startOfDay)
        
        let todayWake = wakeOverride ?? defaultWake
        let todaySleep = sleepOverride ?? defaultSleep
        
        guard todaySleep > todayWake else { return [] }
        
        // energy: 1=low, 2=medium, 3=high
        let usageFraction: Double
        if let energy = energyLevel {
            switch energy {
            case 1: usageFraction = 0.5
            case 3: usageFraction = 0.9
            default: usageFraction = 0.7
            }
        } else {
            usageFraction = 0.7
        }
        
        var fixedBlocks: [(name: String, start: Date, end: Date)] = []
        let weekday = (cal.component(.weekday, from: date) - 1) // 0..6
        
        for activity in fixedActivities {
            guard weekday >= 0 && weekday < activity.days.count else { continue }
            let ds = activity.days[weekday]
            if !ds.enabled { continue }
            let s = timeOnDate(from: ds.start, base: startOfDay)
            let e = timeOnDate(from: ds.end, base: startOfDay)
            if e > s {
                fixedBlocks.append((activity.name, s, e))
            }
        }
        
        fixedBlocks.sort { $0.start < $1.start }
        
        var freeRanges: [(start: Date, end: Date)] = []
        var cursor = todayWake
        
        for block in fixedBlocks {
            let s = max(block.start, todayWake)
            let e = min(block.end, todaySleep)
            if e <= s { continue }
            
            if s > cursor {
                freeRanges.append((start: cursor, end: s))
            }
            
            let fixedTask = Task(title: block.name, start: s, end: e, type: nil)
            tasks.append(fixedTask)
            cursor = max(cursor, e)
        }
        
        if cursor < todaySleep {
            freeRanges.append((start: cursor, end: todaySleep))
        }
        
        if fixedBlocks.isEmpty {
            freeRanges = [(start: todayWake, end: todaySleep)]
        }
        
        // Auto-fill free time
        if autoSchedule {
            let builtInNames = selectedActivities.map { $0.rawValue }
            let titles = builtInNames + customPreferences
            
            let now = Date()
            var addedMorningRoutine = false
            var addedLunch = false
            var addedDinner = false
            var addedWindDown = false
            
            if !titles.isEmpty {
                let prefsArray = titles
                var prefIndex = 0
                
                for range in freeRanges {
                    var localCursor = range.start
                    
                    while true {
                        if localCursor >= range.end { break }
                        let remaining = range.end.timeIntervalSince(localCursor)
                        if remaining < 20 * 60 { break }
                        
                        let hour = cal.component(.hour, from: localCursor)
                        
                        // Morning routine
                        if !addedMorningRoutine && hour < 10 {
                            let dur = min(45 * 60, remaining * usageFraction)
                            let end = localCursor.addingTimeInterval(dur)
                            tasks.append(Task(title: "Morning routine (get ready, breakfast)",
                                              start: localCursor,
                                              end: end,
                                              type: nil))
                            addedMorningRoutine = true
                            localCursor = end
                            continue
                        }
                        
                        // Lunch
                        if !addedLunch && (11...14).contains(hour) {
                            let dur = min(40 * 60, remaining * usageFraction)
                            let end = localCursor.addingTimeInterval(dur)
                            tasks.append(Task(title: "Lunch / Break",
                                              start: localCursor,
                                              end: end,
                                              type: nil))
                            addedLunch = true
                            localCursor = end
                            continue
                        }
                        
                        // Dinner
                        if !addedDinner && (18...20).contains(hour) {
                            let dur = min(45 * 60, remaining * usageFraction)
                            let end = localCursor.addingTimeInterval(dur)
                            tasks.append(Task(title: "Dinner / Cook & eat",
                                              start: localCursor,
                                              end: end,
                                              type: nil))
                            addedDinner = true
                            localCursor = end
                            continue
                        }
                        
                        // Wind down
                        if !addedWindDown && hour >= 21 {
                            let dur = min(30 * 60, remaining * usageFraction)
                            let end = localCursor.addingTimeInterval(dur)
                            tasks.append(Task(title: "Wind down & get ready for bed",
                                              start: localCursor,
                                              end: end,
                                              type: nil))
                            addedWindDown = true
                            localCursor = end
                            continue
                        }
                        
                        // Normal block
                        let title = prefsArray[prefIndex % prefsArray.count]
                        prefIndex += 1
                        let type = FreeActivity(rawValue: title)
                        
                        var dur = defaultDuration(forTitle: title, type: type) * usageFraction
                        if dur > remaining {
                            dur = max(remaining / 2, 20 * 60)
                        }
                        if dur > remaining { break }
                        
                        let end = localCursor.addingTimeInterval(dur)
                        if end <= now { // don't auto-plan in the past for today
                            localCursor = end
                            continue
                        }
                        
                        tasks.append(Task(title: title,
                                          start: localCursor,
                                          end: end,
                                          type: type))
                        localCursor = end
                    }
                }
            }
        }
        
        tasks.sort { $0.start < $1.start }
        return tasks
    }
    
    private func timeOnDate(from stored: Date, base: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: stored)
        return cal.date(bySettingHour: comps.hour ?? 8,
                        minute: comps.minute ?? 0,
                        second: 0,
                        of: base) ?? base
    }
    
    // MARK: - Manual tasks
    
    func addManualTask(dayIndex: Int, title: String, start: Date, end: Date, activity: FreeActivity?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Custom task" : trimmed
        
        var tasksForDay = tasks(for: dayIndex)
        tasksForDay.append(Task(title: finalTitle, start: start, end: end, type: activity))
        tasksForDay.sort { $0.start < $1.start }
        setTasks(tasksForDay, for: dayIndex)
        scheduleNotificationsForToday()
    }
    
    // MARK: - Weekly progress
    
    private func ensureWeeklyProgressIsForCurrentWeek() {
        let today = Calendar.current.startOfDay(for: Date())
        let thisWeekStart = startOfWeek(for: today)
        
        if let last = lastWeekStart {
            if !Calendar.current.isDate(last, inSameDayAs: thisWeekStart) {
                weeklyProgress = [:]
                weeklyProgressCustom = [:]
            }
        } else {
            weeklyProgress = [:]
            weeklyProgressCustom = [:]
        }
        
        lastWeekStart = thisWeekStart
    }
    
    private func adjustWeeklyProgress(for task: Task, deltaSign: Double) {
        ensureWeeklyProgressIsForCurrentWeek()
        let hours = max(0, task.end.timeIntervalSince(task.start) / 3600.0)
        
        if let type = task.type {
            weeklyProgress[type, default: 0] = max(0, weeklyProgress[type, default: 0] + deltaSign * hours)
        } else if customPreferences.contains(task.title) {
            weeklyProgressCustom[task.title, default: 0] =
                max(0, weeklyProgressCustom[task.title, default: 0] + deltaSign * hours)
        }
    }
    
    // MARK: - Completion & streak
    
    func handleCompletionChange(dayIndex: Int, task: Task, completed: Bool) {
        var tasksForDay = tasks(for: dayIndex)
        guard let idx = tasksForDay.firstIndex(where: { $0.id == task.id }) else { return }
        let wasCompleted = tasksForDay[idx].isCompleted
        if wasCompleted == completed { return }
        
        tasksForDay[idx].isCompleted = completed
        setTasks(tasksForDay, for: dayIndex)
        
        if completed {
            xp += 10
            adjustWeeklyProgress(for: tasksForDay[idx], deltaSign: +1)
        } else {
            xp = max(0, xp - 10)
            adjustWeeklyProgress(for: tasksForDay[idx], deltaSign: -1)
        }
    }
    
    func endDayAndUpdateStreak(dayIndex: Int) -> (completedCount: Int, total: Int) {
        let tasksForDay = tasks(for: dayIndex)
        let total = tasksForDay.count
        let completedCount = tasksForDay.filter { $0.isCompleted }.count
        
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        ensureWeeklyProgressIsForCurrentWeek()
        
        let success = completedCount > 0
        
        if success {
            if let last = lastCompletionDate {
                if cal.isDate(last, inSameDayAs: today.addingTimeInterval(-24 * 60 * 60)) {
                    streak += 1
                } else if !cal.isDate(last, inSameDayAs: today) {
                    streak = 1
                }
            } else {
                streak = 1
            }
            lastCompletionDate = today
        } else {
            streak = 0
            lastCompletionDate = today
        }
        
        return (completedCount, total)
    }
    
    // MARK: - Notifications
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    func scheduleNotificationsForToday() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let idx = cal.component(.weekday, from: today) - 1
        guard idx >= 0 && idx < 7 else { return }
        
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        let tasksForDay = tasks(for: idx)
        let now = Date()
        
        for task in tasksForDay {
            let offsets = [-60, -15]
            
            for minutes in offsets {
                guard let triggerDate = cal.date(byAdding: .minute, value: minutes, to: task.start),
                      triggerDate > now else { continue }
                
                let content = UNMutableNotificationContent()
                content.title = task.title
                if minutes == -60 {
                    content.body = "In 1 hour: \(task.title)"
                } else {
                    content.body = "Starting soon (15 mins): \(task.title)"
                }
                content.sound = .default
                
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = task.id.uuidString + "_\(minutes)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }
        }
    }
    
    // MARK: - Task library
    
    func saveTemplate(title: String, duration: TimeInterval, type: FreeActivity?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let template = TaskTemplate(id: UUID(), title: trimmed, defaultDuration: duration, type: type)
        taskTemplates.append(template)
    }
    
    func deleteTemplates(at offsets: IndexSet) {
        taskTemplates.remove(atOffsets: offsets)
    }
}
