// TaskStore.swift
// TaskWarrior for iOS
//
// Local persistence layer for tasks and sync operations.
// Uses UserDefaults + JSON for simplicity; production would use SQLite.

import Foundation

/// Manages local task storage and pending operations for sync.
actor TaskStore {
    private let tasksKey = "taskwarrior_tasks"
    private let opsKey = "taskwarrior_pending_ops"
    private let versionKey = "taskwarrior_base_version"

    // MARK: - Tasks

    func loadTasks() -> [UUID: TWTask] {
        guard let data = UserDefaults.standard.data(forKey: tasksKey),
              let tasks = try? JSONDecoder().decode([UUID: TWTask].self, from: data)
        else { return [:] }
        return tasks
    }

    func saveTasks(_ tasks: [UUID: TWTask]) {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
    }

    // MARK: - Pending Operations

    func loadPendingOps() -> [SyncOperation] {
        guard let data = UserDefaults.standard.data(forKey: opsKey),
              let ops = try? JSONDecoder().decode([SyncOperation].self, from: data)
        else { return [] }
        return ops
    }

    func savePendingOps(_ ops: [SyncOperation]) {
        if let data = try? JSONEncoder().encode(ops) {
            UserDefaults.standard.set(data, forKey: opsKey)
        }
    }

    func appendOps(_ newOps: [SyncOperation]) {
        var ops = loadPendingOps()
        ops.append(contentsOf: newOps)
        savePendingOps(ops)
    }

    func clearPendingOps() {
        savePendingOps([])
    }

    // MARK: - Base Version

    func loadBaseVersion() -> UUID {
        guard let str = UserDefaults.standard.string(forKey: versionKey),
              let uuid = UUID(uuidString: str)
        else {
            // Nil UUID = empty database per spec
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        }
        return uuid
    }

    func saveBaseVersion(_ version: UUID) {
        UserDefaults.standard.set(version.uuidString.lowercased(), forKey: versionKey)
    }

    // MARK: - Apply operations to task map

    static func applyOperations(_ ops: [SyncOperation], to tasks: inout [UUID: TWTask]) {
        for op in ops {
            switch op {
            case .create(let uuid):
                if tasks[uuid] == nil {
                    tasks[uuid] = TWTask(uuid: uuid)
                }
            case .delete(let uuid):
                tasks.removeValue(forKey: uuid)
            case .update(let uuid, let property, let value, _):
                if tasks[uuid] != nil {
                    if let value = value {
                        tasks[uuid]!.properties[property] = value
                    } else {
                        tasks[uuid]!.properties.removeValue(forKey: property)
                    }
                }
            }
        }
    }

    // MARK: - Generate operations from task mutation

    func generateCreateOps(for task: TWTask) -> [SyncOperation] {
        var ops: [SyncOperation] = [.create(uuid: task.uuid)]
        let now = Date()
        for (key, value) in task.properties {
            ops.append(.update(uuid: task.uuid, property: key, value: value, timestamp: now))
        }
        return ops
    }

    func generateUpdateOps(uuid: UUID, oldProperties: [String: String], newProperties: [String: String]) -> [SyncOperation] {
        var ops: [SyncOperation] = []
        let now = Date()
        let allKeys = Set(oldProperties.keys).union(Set(newProperties.keys))
        for key in allKeys {
            let oldVal = oldProperties[key]
            let newVal = newProperties[key]
            if oldVal != newVal {
                ops.append(.update(uuid: uuid, property: key, value: newVal, timestamp: now))
            }
        }
        return ops
    }

    func generateDeleteOps(uuid: UUID) -> [SyncOperation] {
        return [.delete(uuid: uuid)]
    }

    // MARK: - Snapshot handling

    func replaceAllTasks(from snapshot: [UUID: [String: String]]) -> [UUID: TWTask] {
        var tasks: [UUID: TWTask] = [:]
        for (uuid, props) in snapshot {
            tasks[uuid] = TWTask(uuid: uuid, properties: props)
        }
        saveTasks(tasks)
        savePendingOps([])
        return tasks
    }
}
