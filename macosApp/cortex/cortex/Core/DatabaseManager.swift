import Foundation
import SQLite3

// MARK: - Database Models

public struct ActivityRecord {
    let id: Int?
    let timestamp: Double
    let activity: String
    let productive: Bool
    let app: String
    let bundleId: String?
    let domain: String?
    
    public init(timestamp: Double = Date().timeIntervalSince1970, 
         activity: String, 
         productive: Bool, 
         app: String, 
         bundleId: String? = nil, 
         domain: String? = nil) {
        self.id = nil
        self.timestamp = timestamp
        self.activity = activity
        self.productive = productive
        self.app = app
        self.bundleId = bundleId
        self.domain = domain
    }
}

public struct Rule {
    let id: Int?
    let name: String
    let naturalLanguage: String
    let ruleJSON: String
    let isActive: Bool
    let createdAt: Double
    
    public init(name: String, naturalLanguage: String, ruleJSON: String, isActive: Bool = true) {
        self.id = nil
        self.name = name
        self.naturalLanguage = naturalLanguage
        self.ruleJSON = ruleJSON
        self.isActive = isActive
        self.createdAt = Date().timeIntervalSince1970
    }
}

// MARK: - DatabaseManager Protocol

public protocol DatabaseManagerProtocol {
    func initialize() throws
    func logActivity(_ record: ActivityRecord) throws -> Int
    func getRecentActivities(limit: Int) throws -> [ActivityRecord]
    func getActivitiesInTimeRange(from: Double, to: Double) throws -> [ActivityRecord]
    func close()
}

// MARK: - DatabaseManager Implementation

class DatabaseManager: DatabaseManagerProtocol {
    
    private var db: OpaquePointer?
    private let dbName = "cortex_activity.sqlite"
    
    init() throws {
        try initialize()
    }
    
    deinit {
        close()
    }
    
    // MARK: - Database Lifecycle
    
    func initialize() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dbPath = documentsPath.appendingPathComponent(dbName).path
        
        print("📁 Database path: \(dbPath)")
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            throw DatabaseError.connectionFailed
        }
        
        print("✅ Database connection established")
        
        try createTables()
        try runMigrations()
    }
    
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            print("📁 Database connection closed")
        }
    }
    
    // MARK: - Table Creation
    
    private func createTables() throws {
        try createActivityTable()
        try createRulesTable()
    }
    
    private func createActivityTable() throws {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS activity_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                activity TEXT NOT NULL,
                productive INTEGER NOT NULL,
                app TEXT NOT NULL,
                bundle_id TEXT,
                domain TEXT,
                created_at REAL DEFAULT (datetime('now'))
            );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            throw DatabaseError.tableCreationFailed("activity_log")
        }
        
        print("✅ Activity table ready")
    }
    
    private func createRulesTable() throws {
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                natural_language TEXT NOT NULL,
                rule_json TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL DEFAULT (datetime('now'))
            );
        """
        
        if sqlite3_exec(db, createTableSQL, nil, nil, nil) != SQLITE_OK {
            throw DatabaseError.tableCreationFailed("rules")
        }
        
        print("✅ Rules table ready")
    }
    
    // MARK: - Migrations
    
    private func runMigrations() throws {
        // Add migration logic here as the schema evolves
        try addMissingColumns()
        try createIndexes()
    }
    
    private func addMissingColumns() throws {
        // Check if bundle_id column exists, if not add it
        if !columnExists(table: "activity_log", column: "bundle_id") {
            let addBundleIdSQL = "ALTER TABLE activity_log ADD COLUMN bundle_id TEXT"
            if sqlite3_exec(db, addBundleIdSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ Added bundle_id column to activity_log")
            } else {
                print("❌ Failed to add bundle_id column")
            }
        }
        
        // Check if domain column exists, if not add it
        if !columnExists(table: "activity_log", column: "domain") {
            let addDomainSQL = "ALTER TABLE activity_log ADD COLUMN domain TEXT"
            if sqlite3_exec(db, addDomainSQL, nil, nil, nil) == SQLITE_OK {
                print("✅ Added domain column to activity_log")
            } else {
                print("❌ Failed to add domain column")
            }
        }
    }
    
    private func columnExists(table: String, column: String) -> Bool {
        let pragmaSQL = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        defer { sqlite3_finalize(statement) }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let columnName = sqlite3_column_text(statement, 1) {
                let name = String(cString: columnName)
                if name == column {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func createIndexes() throws {
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_activity_timestamp ON activity_log(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_activity_app ON activity_log(app);",
            "CREATE INDEX IF NOT EXISTS idx_activity_bundle_id ON activity_log(bundle_id);",
            "CREATE INDEX IF NOT EXISTS idx_rules_active ON rules(is_active);"
        ]
        
        for indexSQL in indexes {
            if sqlite3_exec(db, indexSQL, nil, nil, nil) != SQLITE_OK {
                print("⚠️ Failed to create index: \(indexSQL)")
            }
        }
        
        print("✅ Database indexes created")
    }
    
    // MARK: - Activity Operations
    
    func logActivity(_ record: ActivityRecord) throws -> Int {
        if db == nil {
            print("❌ Database connection is NULL - attempting to reinitialize")
            try initialize()
            guard db != nil else {
                throw DatabaseError.connectionFailed
            }
        }
        
        let insertSQL = """
            INSERT INTO activity_log (timestamp, activity, productive, app, bundle_id, domain) 
            VALUES (?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare SQL statement: \(errorMessage)")
            throw DatabaseError.preparationFailed
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_double(statement, 1, record.timestamp)
        
        record.activity.withCString { cString in
            sqlite3_bind_text(statement, 2, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        
        sqlite3_bind_int(statement, 3, record.productive ? 1 : 0)
        
        record.app.withCString { cString in
            sqlite3_bind_text(statement, 4, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        
        if let bundleId = record.bundleId {
            bundleId.withCString { cString in
                sqlite3_bind_text(statement, 5, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(statement, 5)
        }
        
        if let domain = record.domain {
            domain.withCString { cString in
                sqlite3_bind_text(statement, 6, cString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(statement, 6)
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.insertFailed
        }
        
        let insertedId = Int(sqlite3_last_insert_rowid(db))
        
        print("📊 Activity logged: [\(record.activity)] ID=\(insertedId)")
        
        return insertedId
    }
    
    func getRecentActivities(limit: Int = 10) throws -> [ActivityRecord] {
        let selectSQL = """
            SELECT id, timestamp, activity, productive, app, bundle_id, domain 
            FROM activity_log 
            ORDER BY timestamp DESC 
            LIMIT ?
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.preparationFailed
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_int(statement, 1, Int32(limit))
        
        var activities: [ActivityRecord] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let activity = try parseActivityRecord(from: statement)
            activities.append(activity)
        }
        
        return activities
    }
    
    func getActivitiesInTimeRange(from startTime: Double, to endTime: Double) throws -> [ActivityRecord] {
        if db == nil {
            print("❌ Database connection is NULL in getActivitiesInTimeRange - attempting to reinitialize")
            try initialize()
            guard db != nil else {
                throw DatabaseError.connectionFailed
            }
        }
        
        let selectSQL = """
            SELECT id, timestamp, activity, productive, app, bundle_id, domain 
            FROM activity_log 
            WHERE timestamp >= ? AND timestamp <= ?
            ORDER BY timestamp DESC
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to prepare SQL statement in getActivitiesInTimeRange: \(errorMessage)")
            throw DatabaseError.preparationFailed
        }
        
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_double(statement, 1, startTime)
        sqlite3_bind_double(statement, 2, endTime)
        
        var activities: [ActivityRecord] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let activity = try parseActivityRecord(from: statement)
            activities.append(activity)
        }
        
        return activities
    }
    
    
    
    // MARK: - Parsing Helpers
    
    private func parseActivityRecord(from statement: OpaquePointer?) throws -> ActivityRecord {
        guard let statement = statement else {
            throw DatabaseError.parseError
        }
        
        let id = Int(sqlite3_column_int(statement, 0))
        let timestamp = sqlite3_column_double(statement, 1)
        
        guard let activityCString = sqlite3_column_text(statement, 2) else {
            throw DatabaseError.parseError
        }
        let activity = String(cString: activityCString)
        
        let productive = sqlite3_column_int(statement, 3) == 1
        
        guard let appCString = sqlite3_column_text(statement, 4) else {
            throw DatabaseError.parseError
        }
        let app = String(cString: appCString)
        
        let bundleId: String?
        if let bundleIdCString = sqlite3_column_text(statement, 5) {
            bundleId = String(cString: bundleIdCString)
        } else {
            bundleId = nil
        }
        
        let domain: String?
        if let domainCString = sqlite3_column_text(statement, 6) {
            domain = String(cString: domainCString)
        } else {
            domain = nil
        }
        
        var record = ActivityRecord(
            timestamp: timestamp,
            activity: activity,
            productive: productive,
            app: app,
            bundleId: bundleId,
            domain: domain
        )
        
        // Use reflection to set the id (since it's let)
        return ActivityRecord(
            timestamp: timestamp,
            activity: activity,
            productive: productive,
            app: app,
            bundleId: bundleId,
            domain: domain
        )
    }
    
    private func parseRule(from statement: OpaquePointer?) throws -> Rule {
        guard let statement = statement else {
            throw DatabaseError.parseError
        }
        
        let id = Int(sqlite3_column_int(statement, 0))
        
        guard let nameCString = sqlite3_column_text(statement, 1) else {
            throw DatabaseError.parseError
        }
        let name = String(cString: nameCString)
        
        guard let nlCString = sqlite3_column_text(statement, 2) else {
            throw DatabaseError.parseError
        }
        let naturalLanguage = String(cString: nlCString)
        
        guard let jsonCString = sqlite3_column_text(statement, 3) else {
            throw DatabaseError.parseError
        }
        let ruleJSON = String(cString: jsonCString)
        
        let isActive = sqlite3_column_int(statement, 4) == 1
        let createdAt = sqlite3_column_double(statement, 5)
        
        return Rule(
            name: name,
            naturalLanguage: naturalLanguage,
            ruleJSON: ruleJSON,
            isActive: isActive
        )
    }
}

// MARK: - Error Types

enum DatabaseError: Error, LocalizedError {
    case connectionFailed
    case tableCreationFailed(String)
    case preparationFailed
    case insertFailed
    case updateFailed
    case deleteFailed
    case parseError
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to database"
        case .tableCreationFailed(let table):
            return "Failed to create table: \(table)"
        case .preparationFailed:
            return "Failed to prepare SQL statement"
        case .insertFailed:
            return "Failed to insert record"
        case .updateFailed:
            return "Failed to update record"
        case .deleteFailed:
            return "Failed to delete record"
        case .parseError:
            return "Failed to parse database record"
        }
    }
}
