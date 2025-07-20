import Foundation

// MARK: - Rule Types

public enum RuleType: String, Codable {
    case timeWindow = "time_window"
    case count = "count"
    case schedule = "schedule"
    case combo = "combo"
}

public enum RuleOperator: String, Codable {
    case greaterThan = ">"
    case lessThan = "<"
    case equal = "=="
    case greaterOrEqual = ">="
    case lessOrEqual = "<="
}

public enum LogicalOperator: String, Codable {
    case and = "AND"
    case or = "OR"
}

// MARK: - Rule Condition Models

public struct RuleCondition: Codable {
    public let field: String // "activity", "app", "domain", "bundle_id"
    public let `operator`: RuleOperator
    public let value: RuleValue
    
    public init(field: String, `operator`: RuleOperator, value: RuleValue) {
        self.field = field
        self.`operator` = `operator`
        self.value = value
    }
}

public enum RuleValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([RuleValue])
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let arrayValue = try? container.decode([RuleValue].self) {
            self = .array(arrayValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else {
            throw DecodingError.typeMismatch(RuleValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown RuleValue type"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Rule Definition Models

public struct CompiledRule: Codable {
    let id: String
    let name: String
    let type: RuleType
    let conditions: [RuleCondition]
    let logicalOperator: LogicalOperator? // For combining conditions
    let timeWindow: TimeWindowConfig?
    let countConfig: CountConfig?
    let scheduleConfig: ScheduleConfig?
    let actions: [RuleAction]
    let priority: Int
    let isActive: Bool
    
    public init(id: String = UUID().uuidString, 
         name: String, 
         type: RuleType, 
         conditions: [RuleCondition], 
         logicalOperator: LogicalOperator? = nil,
         timeWindow: TimeWindowConfig? = nil,
         countConfig: CountConfig? = nil,
         scheduleConfig: ScheduleConfig? = nil,
         actions: [RuleAction],
         priority: Int = 0,
         isActive: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.conditions = conditions
        self.logicalOperator = logicalOperator
        self.timeWindow = timeWindow
        self.countConfig = countConfig
        self.scheduleConfig = scheduleConfig
        self.actions = actions
        self.priority = priority
        self.isActive = isActive
    }
}

public struct TimeWindowConfig: Codable {
    public let durationSeconds: Int // e.g., 600 for 10 minutes
    public let lookbackSeconds: Int // e.g., 3600 for 1 hour window
    public let threshold: Int // minimum occurrences
    
    public init(durationSeconds: Int, lookbackSeconds: Int, threshold: Int) {
        self.durationSeconds = durationSeconds
        self.lookbackSeconds = lookbackSeconds
        self.threshold = threshold
    }
}

public struct CountConfig: Codable {
    let maxCount: Int
    let resetInterval: Int? // seconds, nil = no reset
}

public struct ScheduleConfig: Codable {
    public let startTime: String // "09:00"
    public let endTime: String // "17:00"
    public let daysOfWeek: [Int] // 1-7, Monday=1
    public let timezone: String? // "America/New_York", nil = local
    
    public init(startTime: String, endTime: String, daysOfWeek: [Int], timezone: String? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.daysOfWeek = daysOfWeek
        self.timezone = timezone
    }
}

public struct RuleAction: Codable {
    public let type: ActionType
    public let parameters: [String: RuleValue]
    
    public init(type: ActionType, parameters: [String: RuleValue] = [:]) {
        self.type = type
        self.parameters = parameters
    }
}

public enum ActionType: String, Codable {
    case popup = "popup"
    case llmPopup = "llm_popup"
    case notification = "notification"
    case block = "block"
    case motivationalLockScreen = "motivational_lock_screen"
    case screenTimeShield = "screen_time_shield"
    case closeBrowserTab = "close_browser_tab"
    case webhook = "webhook"
    case log = "log"
    case browserBack = "browser_back"
    case appSwitch = "app_switch"
}

// MARK: - Rule Violation

public struct RuleViolation {
    let rule: CompiledRule
    let triggerActivity: ActivityRecord
    let context: ViolationContext
    let timestamp: Date
}

public struct ViolationContext {
    let matchingActivities: [ActivityRecord]
    let totalDuration: TimeInterval?
    let totalCount: Int?
    let timeWindow: (start: Date, end: Date)?
}

// MARK: - RuleEngine Protocol

public protocol RuleEngineProtocol {
    func addRule(_ rule: CompiledRule) throws
    func removeRule(id: String) throws
    func getRules() -> [CompiledRule]
    func evaluateRules(for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> [RuleViolation]
    func compileRule(from naturalLanguage: String, using llmClient: LLMClientProtocol) async throws -> CompiledRule
}

// MARK: - RuleEngine Implementation

class RuleEngine: RuleEngineProtocol {
    
    private var rules: [String: CompiledRule] = [:]
    private let ruleQueue = DispatchQueue(label: "com.cortex.ruleengine", qos: .userInitiated)
    
    // MARK: - Rule Management
    
    func addRule(_ rule: CompiledRule) throws {
        ruleQueue.sync {
            rules[rule.id] = rule
        }
        print("📜 Rule added: \(rule.name)")
    }
    
    func removeRule(id: String) throws {
        ruleQueue.sync {
            rules.removeValue(forKey: id)
        }
        print("📜 Rule removed: \(id)")
    }
    
    func getRules() -> [CompiledRule] {
        return ruleQueue.sync {
            Array(rules.values).filter { $0.isActive }.sorted { $0.priority > $1.priority }
        }
    }
    
    // MARK: - Rule Evaluation
    
    func evaluateRules(for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> [RuleViolation] {
        let activeRules = getRules()
        var violations: [RuleViolation] = []
        
        for rule in activeRules {
            if let violation = try await evaluateRule(rule, for: activity, with: database) {
                violations.append(violation)
                print("🚨 Rule violation detected: \(rule.name)")
            }
        }
        
        return violations
    }
    
    private func evaluateRule(_ rule: CompiledRule, for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> RuleViolation? {
        // First check if the activity matches the rule conditions
        guard matchesConditions(activity, conditions: rule.conditions, operator: rule.logicalOperator) else {
            return nil
        }
        
        // Then check the specific rule type
        switch rule.type {
        case .timeWindow:
            return try await evaluateTimeWindowRule(rule, for: activity, with: database)
        case .count:
            return try await evaluateCountRule(rule, for: activity, with: database)
        case .schedule:
            return try await evaluateScheduleRule(rule, for: activity, with: database)
        case .combo:
            return try await evaluateComboRule(rule, for: activity, with: database)
        }
    }
    
    // MARK: - Condition Matching
    
    private func matchesConditions(_ activity: ActivityRecord, conditions: [RuleCondition], operator: LogicalOperator?) -> Bool {
        guard !conditions.isEmpty else { return true }
        
        let results = conditions.map { condition in
            return matchesCondition(activity, condition: condition)
        }
        
        switch `operator` ?? .and {
        case .and:
            return results.allSatisfy { $0 }
        case .or:
            return results.contains(true)
        }
    }
    
    private func matchesCondition(_ activity: ActivityRecord, condition: RuleCondition) -> Bool {
        let fieldValue: String
        
        switch condition.field {
        case "activity":
            fieldValue = activity.activity
        case "app":
            fieldValue = activity.app
        case "bundle_id":
            fieldValue = activity.bundleId ?? ""
        case "domain":
            fieldValue = activity.domain ?? ""
        default:
            return false
        }
        
        switch condition.value {
        case .string(let value):
            return compareStrings(fieldValue, condition.`operator`, value)
        case .int(let value):
            return compareNumbers(Double(fieldValue) ?? 0, condition.`operator`, Double(value))
        case .double(let value):
            return compareNumbers(Double(fieldValue) ?? 0, condition.`operator`, value)
        case .bool(let value):
            return compareBools(Bool(fieldValue) ?? false, condition.`operator`, value)
        case .array(_):
            // Array comparison not supported for field conditions
            return false
        }
    }
    
    private func compareStrings(_ field: String, _ op: RuleOperator, _ value: String) -> Bool {
        switch op {
        case .equal:
            return field == value
        case .greaterThan, .greaterOrEqual, .lessThan, .lessOrEqual:
            return field.localizedCompare(value) == .orderedSame
        }
    }
    
    private func compareNumbers(_ field: Double, _ op: RuleOperator, _ value: Double) -> Bool {
        switch op {
        case .equal:
            return field == value
        case .greaterThan:
            return field > value
        case .greaterOrEqual:
            return field >= value
        case .lessThan:
            return field < value
        case .lessOrEqual:
            return field <= value
        }
    }
    
    private func compareBools(_ field: Bool, _ op: RuleOperator, _ value: Bool) -> Bool {
        switch op {
        case .equal:
            return field == value
        default:
            return false
        }
    }
    
    // MARK: - Specific Rule Type Evaluations
    
    private func evaluateTimeWindowRule(_ rule: CompiledRule, for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> RuleViolation? {
        guard let timeWindow = rule.timeWindow else { return nil }
        
        let now = activity.timestamp
        let windowStart = now - Double(timeWindow.lookbackSeconds)
        
        let recentActivities = try database.getActivitiesInTimeRange(from: windowStart, to: now)
        let matchingActivities = recentActivities.filter { recentActivity in
            matchesConditions(recentActivity, conditions: rule.conditions, operator: rule.logicalOperator)
        }
        
        // Calculate total duration of matching activities
        let totalDuration = calculateDuration(matchingActivities, windowSeconds: timeWindow.durationSeconds)
        
        if totalDuration >= Double(timeWindow.durationSeconds) {
            let context = ViolationContext(
                matchingActivities: matchingActivities,
                totalDuration: totalDuration,
                totalCount: matchingActivities.count,
                timeWindow: (Date(timeIntervalSince1970: windowStart), Date(timeIntervalSince1970: now))
            )
            
            return RuleViolation(
                rule: rule,
                triggerActivity: activity,
                context: context,
                timestamp: Date()
            )
        }
        
        return nil
    }
    
    private func evaluateCountRule(_ rule: CompiledRule, for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> RuleViolation? {
        guard let countConfig = rule.countConfig else { return nil }
        
        let lookbackTime: Double
        if let resetInterval = countConfig.resetInterval {
            lookbackTime = activity.timestamp - Double(resetInterval)
        } else {
            // No reset interval - check all time
            lookbackTime = 0
        }
        
        let recentActivities = try database.getActivitiesInTimeRange(from: lookbackTime, to: activity.timestamp)
        let matchingActivities = recentActivities.filter { recentActivity in
            matchesConditions(recentActivity, conditions: rule.conditions, operator: rule.logicalOperator)
        }
        
        if matchingActivities.count > countConfig.maxCount {
            let context = ViolationContext(
                matchingActivities: matchingActivities,
                totalDuration: nil,
                totalCount: matchingActivities.count,
                timeWindow: nil
            )
            
            return RuleViolation(
                rule: rule,
                triggerActivity: activity,
                context: context,
                timestamp: Date()
            )
        }
        
        return nil
    }
    
    private func evaluateScheduleRule(_ rule: CompiledRule, for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> RuleViolation? {
        guard let scheduleConfig = rule.scheduleConfig else { return nil }
        
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: activity.timestamp)
        
        // Check day of week
        let weekday = calendar.component(.weekday, from: now)
        let mondayBasedWeekday = weekday == 1 ? 7 : weekday - 1 // Convert Sunday=1 to Monday=1
        
        guard scheduleConfig.daysOfWeek.contains(mondayBasedWeekday) else {
            return nil
        }
        
        // Check time range
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        let currentTime = timeFormatter.string(from: now)
        
        if currentTime >= scheduleConfig.startTime && currentTime <= scheduleConfig.endTime {
            // Activity occurred during restricted time
            let context = ViolationContext(
                matchingActivities: [activity],
                totalDuration: nil,
                totalCount: 1,
                timeWindow: nil
            )
            
            return RuleViolation(
                rule: rule,
                triggerActivity: activity,
                context: context,
                timestamp: Date()
            )
        }
        
        return nil
    }
    
    private func evaluateComboRule(_ rule: CompiledRule, for activity: ActivityRecord, with database: DatabaseManagerProtocol) async throws -> RuleViolation? {
        // Combo rules combine multiple rule types
        // For now, implement as time window + count combination
        
        var violations: [RuleViolation] = []
        
        if let timeViolation = try await evaluateTimeWindowRule(rule, for: activity, with: database) {
            violations.append(timeViolation)
        }
        
        if let countViolation = try await evaluateCountRule(rule, for: activity, with: database) {
            violations.append(countViolation)
        }
        
        // Return violation if any sub-rule triggered
        return violations.first
    }
    
    // MARK: - Utility Methods
    
    private func calculateDuration(_ activities: [ActivityRecord], windowSeconds: Int) -> Double {
        guard !activities.isEmpty else { return 0 }
        
        let sortedActivities = activities.sorted { $0.timestamp < $1.timestamp }
        var totalDuration: Double = 0
        
        for i in 0..<sortedActivities.count {
            let activity = sortedActivities[i]
            let nextActivity = i < sortedActivities.count - 1 ? sortedActivities[i + 1] : nil
            
            if let next = nextActivity {
                // Use time between activities as duration (max 10 seconds per activity)
                let gap = min(next.timestamp - activity.timestamp, 10.0)
                totalDuration += gap
            } else {
                // Last activity, assume 2 seconds duration
                totalDuration += 2.0
            }
        }
        
        return totalDuration
    }
    
    // MARK: - Natural Language Compilation
    
    func compileRule(from naturalLanguage: String, using llmClient: LLMClientProtocol) async throws -> CompiledRule {
        // This would use the LLM to convert natural language to rule JSON
        // For now, return a simple implementation
        
        // Example: "Don't let me watch YouTube Shorts for more than 5 minutes per hour"
        // Would become a time window rule
        
        let prompt = """
        Convert this natural language rule into a structured JSON rule:
        "\(naturalLanguage)"
        
        Return only valid JSON in this format:
        {
            "name": "rule name",
            "type": "time_window|count|schedule|combo",
            "conditions": [
                {"field": "activity|app|domain|bundle_id", "operator": ">|<|==|>=|<=", "value": "value"}
            ],
            "logicalOperator": "AND|OR",
            "timeWindow": {"durationSeconds": 300, "lookbackSeconds": 3600, "threshold": 1},
            "actions": [{"type": "popup", "parameters": {"message": "Stop watching!"}}]
        }
        """
        
        // For now, create a default Instagram scrolling rule
        let defaultRule = CompiledRule(
            name: "Instagram Scrolling Limit",
            type: .timeWindow,
            conditions: [
                RuleCondition(field: "activity", operator: .equal, value: .string("instagram_scrolling"))
            ],
            timeWindow: TimeWindowConfig(durationSeconds: 10, lookbackSeconds: 15, threshold: 2),
            actions: [
                RuleAction(type: .popup, parameters: ["message": .string("You've been scrolling Instagram too long!")])
            ]
        )
        
        return defaultRule
    }
}

// MARK: - Error Types

enum RuleEngineError: Error, LocalizedError {
    case invalidRule(String)
    case compilationFailed(String)
    case evaluationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidRule(let message):
            return "Invalid rule: \(message)"
        case .compilationFailed(let message):
            return "Rule compilation failed: \(message)"
        case .evaluationFailed(let message):
            return "Rule evaluation failed: \(message)"
        }
    }
}