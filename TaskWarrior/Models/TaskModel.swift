// TaskModel.swift
// TaskWarrior for iOS
//
// Task model matching the TaskChampion specification.
// Tasks are key/value maps with string keys and values.

import Foundation

// MARK: - Task Status

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case completed
    case deleted
    case recurring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .deleted: return "Deleted"
        case .recurring: return "Recurring"
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .recurring: return "arrow.triangle.2.circlepath.circle"
        }
    }
}

// MARK: - Task Priority

enum TaskPriority: String, Codable, CaseIterable, Comparable, Identifiable {
    case high = "H"
    case medium = "M"
    case low = "L"
    case none = ""

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .none: return "None"
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .none: return 3
        }
    }

    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Annotation

struct TaskAnnotation: Identifiable, Codable, Comparable {
    let timestamp: Date
    let text: String

    var id: Date { timestamp }

    static func < (lhs: TaskAnnotation, rhs: TaskAnnotation) -> Bool {
        lhs.timestamp < rhs.timestamp
    }
}

// MARK: - Task

/// A Taskwarrior task, backed by a key/value map per the TaskChampion spec.
struct TWTask: Identifiable, Codable, Equatable {
    let uuid: UUID
    internal var properties: [String: String]

    var id: UUID { uuid }

    // MARK: Computed Properties

    var status: TaskStatus {
        get { TaskStatus(rawValue: properties["status"] ?? "pending") ?? .pending }
        set { properties["status"] = newValue.rawValue }
    }

    var description: String {
        get { properties["description"] ?? "" }
        set { properties["description"] = newValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: properties["priority"] ?? "") ?? .none }
        set {
            if newValue == .none {
                properties.removeValue(forKey: "priority")
            } else {
                properties["priority"] = newValue.rawValue
            }
        }
    }

    var project: String? {
        get { properties["project"] }
        set {
            if let v = newValue, !v.isEmpty {
                properties["project"] = v
            } else {
                properties.removeValue(forKey: "project")
            }
        }
    }

    var entry: Date? {
        get { dateValue(for: "entry") }
        set { setDateValue(newValue, for: "entry") }
    }

    var modified: Date? {
        get { dateValue(for: "modified") }
        set { setDateValue(newValue, for: "modified") }
    }

    var start: Date? {
        get { dateValue(for: "start") }
        set { setDateValue(newValue, for: "start") }
    }

    var end: Date? {
        get { dateValue(for: "end") }
        set { setDateValue(newValue, for: "end") }
    }

    var wait: Date? {
        get { dateValue(for: "wait") }
        set { setDateValue(newValue, for: "wait") }
    }

    var due: Date? {
        get { dateValue(for: "due") }
        set { setDateValue(newValue, for: "due") }
    }

    var isActive: Bool { start != nil }

    var isWaiting: Bool {
        guard let wait = wait else { return false }
        return wait > Date()
    }

    // MARK: Tags

    var tags: [String] {
        properties.keys
            .filter { $0.hasPrefix("tag_") }
            .map { String($0.dropFirst(4)) }
            .sorted()
    }

    mutating func addTag(_ tag: String) {
        properties["tag_\(tag)"] = ""
    }

    mutating func removeTag(_ tag: String) {
        properties.removeValue(forKey: "tag_\(tag)")
    }

    func hasTag(_ tag: String) -> Bool {
        properties["tag_\(tag)"] != nil
    }

    // MARK: Annotations

    var annotations: [TaskAnnotation] {
        properties.keys
            .filter { $0.hasPrefix("annotation_") }
            .compactMap { key -> TaskAnnotation? in
                let tsString = String(key.dropFirst(11))
                guard let ts = Int(tsString) else { return nil }
                let date = Date(timeIntervalSince1970: TimeInterval(ts))
                return TaskAnnotation(timestamp: date, text: properties[key] ?? "")
            }
            .sorted()
    }

    mutating func addAnnotation(_ text: String) {
        let ts = Int(Date().timeIntervalSince1970)
        properties["annotation_\(ts)"] = text
    }

    // MARK: Dependencies

    var dependencies: [UUID] {
        properties.keys
            .filter { $0.hasPrefix("dep_") }
            .compactMap { UUID(uuidString: String($0.dropFirst(4))) }
    }

    mutating func addDependency(_ uuid: UUID) {
        properties["dep_\(uuid.uuidString.lowercased())"] = ""
    }

    mutating func removeDependency(_ uuid: UUID) {
        properties.removeValue(forKey: "dep_\(uuid.uuidString.lowercased())")
    }

    // MARK: UDAs (User-Defined Attributes)

    func uda(_ key: String) -> String? { properties[key] }

    mutating func setUDA(_ key: String, value: String?) {
        if let v = value {
            properties[key] = v
        } else {
            properties.removeValue(forKey: key)
        }
    }

    // MARK: Init

    init(uuid: UUID = UUID(), description: String = "", status: TaskStatus = .pending) {
        self.uuid = uuid
        self.properties = [
            "status": status.rawValue,
            "description": description,
            "entry": "\(Int(Date().timeIntervalSince1970))",
            "modified": "\(Int(Date().timeIntervalSince1970))"
        ]
    }

    init(uuid: UUID, properties: [String: String]) {
        self.uuid = uuid
        self.properties = properties
    }

    // MARK: Helpers

    private func dateValue(for key: String) -> Date? {
        guard let str = properties[key], let ts = Double(str) else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    private mutating func setDateValue(_ date: Date?, for key: String) {
        if let d = date {
            properties[key] = "\(Int(d.timeIntervalSince1970))"
        } else {
            properties.removeValue(forKey: key)
        }
    }

    mutating func touchModified() {
        properties["modified"] = "\(Int(Date().timeIntervalSince1970))"
    }

    // MARK: Urgency calculation (simplified Taskwarrior urgency)

    var urgency: Double {
        var u: Double = 0.0

        // Priority
        switch priority {
        case .high: u += 6.0
        case .medium: u += 3.9
        case .low: u += 1.8
        case .none: break
        }

        // Active
        if isActive { u += 4.0 }

        // Due date
        if let due = due {
            let daysUntilDue = due.timeIntervalSinceNow / 86400
            if daysUntilDue < 0 { u += 12.0 }       // overdue
            else if daysUntilDue < 7 { u += 8.0 }    // due soon
            else if daysUntilDue < 14 { u += 4.0 }   // due in 2 weeks
        }

        // Tags
        if !tags.isEmpty { u += 1.0 }

        // Project
        if project != nil { u += 1.0 }

        // Age (older = slightly more urgent, maxes at ~2)
        if let entry = entry {
            let ageDays = -entry.timeIntervalSinceNow / 86400
            u += min(ageDays / 365.0 * 2.0, 2.0)
        }

        return u
    }
}

// MARK: - Sync Operations (TaskChampion protocol)

enum SyncOperation: Codable, Equatable {
    case create(uuid: UUID)
    case delete(uuid: UUID)
    case update(uuid: UUID, property: String, value: String?, timestamp: Date)

    // Custom coding for TaskChampion JSON format
    enum CodingKeys: String, CodingKey {
        case Create, Delete, Update
    }

    struct CreatePayload: Codable { let uuid: String }
    struct DeletePayload: Codable { let uuid: String }
    struct UpdatePayload: Codable {
        let uuid: String
        let property: String
        let value: String?
        let timestamp: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(let uuid):
            try container.encode(CreatePayload(uuid: uuid.uuidString.lowercased()), forKey: .Create)
        case .delete(let uuid):
            try container.encode(DeletePayload(uuid: uuid.uuidString.lowercased()), forKey: .Delete)
        case .update(let uuid, let property, let value, let timestamp):
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(
                UpdatePayload(
                    uuid: uuid.uuidString.lowercased(),
                    property: property,
                    value: value,
                    timestamp: iso.string(from: timestamp)
                ),
                forKey: .Update
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let payload = try? container.decode(CreatePayload.self, forKey: .Create) {
            guard let uuid = UUID(uuidString: payload.uuid) else {
                throw DecodingError.dataCorruptedError(forKey: .Create, in: container, debugDescription: "Invalid UUID")
            }
            self = .create(uuid: uuid)
        } else if let payload = try? container.decode(DeletePayload.self, forKey: .Delete) {
            guard let uuid = UUID(uuidString: payload.uuid) else {
                throw DecodingError.dataCorruptedError(forKey: .Delete, in: container, debugDescription: "Invalid UUID")
            }
            self = .delete(uuid: uuid)
        } else if let payload = try? container.decode(UpdatePayload.self, forKey: .Update) {
            guard let uuid = UUID(uuidString: payload.uuid) else {
                throw DecodingError.dataCorruptedError(forKey: .Update, in: container, debugDescription: "Invalid UUID")
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let ts = iso.date(from: payload.timestamp) ?? Date()
            self = .update(uuid: uuid, property: payload.property, value: payload.value, timestamp: ts)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown operation type"))
        }
    }
}
