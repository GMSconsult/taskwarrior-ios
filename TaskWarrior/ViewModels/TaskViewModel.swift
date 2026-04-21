// TaskViewModel.swift
// TaskWarrior for iOS

import Foundation
import SwiftUI

@MainActor
class TaskViewModel: ObservableObject {
    @Published var tasks: [UUID: TWTask] = [:]
    @Published var syncStatus: SyncStatus = .idle
    @Published var syncConfig: SyncConfig = .load()
    @Published var filterStatus: TaskStatus? = .pending
    @Published var filterProject: String? = nil
    @Published var filterTag: String? = nil
    @Published var searchText: String = ""
    @Published var sortBy: SortOption = .urgency

    private let store = TaskStore()
    private var syncService: SyncService?

    enum SortOption: String, CaseIterable, Identifiable {
        case urgency = "Urgency"
        case priority = "Priority"
        case due = "Due Date"
        case entry = "Age"
        case description = "Description"
        case project = "Project"
        case modified = "Modified"

        var id: String { rawValue }
    }

    // MARK: - Computed

    var filteredTasks: [TWTask] {
        var result = Array(tasks.values)

        // Status filter
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }

        // Exclude deleted unless explicitly showing deleted
        if filterStatus != .deleted {
            result = result.filter { $0.status != .deleted }
        }

        // Hide waiting tasks from pending unless searching
        if filterStatus == .pending && searchText.isEmpty {
            result = result.filter { !$0.isWaiting }
        }

        // Project filter
        if let project = filterProject {
            result = result.filter { $0.project == project }
        }

        // Tag filter
        if let tag = filterTag {
            result = result.filter { $0.hasTag(tag) }
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.description.lowercased().contains(query) ||
                ($0.project?.lowercased().contains(query) ?? false) ||
                $0.tags.contains { $0.lowercased().contains(query) }
            }
        }

        // Sort
        switch sortBy {
        case .urgency:
            result.sort { $0.urgency > $1.urgency }
        case .priority:
            result.sort { $0.priority < $1.priority }
        case .due:
            result.sort { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
        case .entry:
            result.sort { ($0.entry ?? .distantPast) > ($1.entry ?? .distantPast) }
        case .description:
            result.sort { $0.description.lowercased() < $1.description.lowercased() }
        case .project:
            result.sort { ($0.project ?? "zzz") < ($1.project ?? "zzz") }
        case .modified:
            result.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        }

        return result
    }

    var allProjects: [String] {
        Set(tasks.values.compactMap { $0.project }).sorted()
    }

    var allTags: [String] {
        Set(tasks.values.flatMap { $0.tags }).sorted()
    }

    var pendingCount: Int {
        tasks.values.filter { $0.status == .pending }.count
    }

    var completedTodayCount: Int {
        let calendar = Calendar.current
        return tasks.values.filter { task in
            task.status == .completed &&
            task.end != nil &&
            calendar.isDateInToday(task.end!)
        }.count
    }

    var overdueCount: Int {
        tasks.values.filter { task in
            task.status == .pending &&
            task.due != nil &&
            task.due! < Date()
        }.count
    }

    // MARK: - Lifecycle

    func loadTasks() async {
        tasks = await store.loadTasks()
    }

    // MARK: - Task Operations

    func addTask(_ task: TWTask) async {
        var newTask = task
        newTask.touchModified()
        tasks[newTask.uuid] = newTask

        let ops = await store.generateCreateOps(for: newTask)
        await store.appendOps(ops)
        await store.saveTasks(tasks)
    }

    func updateTask(_ task: TWTask) async {
        guard let oldTask = tasks[task.uuid] else { return }

        var updatedTask = task
        updatedTask.touchModified()
        tasks[updatedTask.uuid] = updatedTask

        let ops = await store.generateUpdateOps(
            uuid: updatedTask.uuid,
            oldProperties: oldTask.properties,
            newProperties: updatedTask.properties
        )
        if !ops.isEmpty {
            await store.appendOps(ops)
        }
        await store.saveTasks(tasks)
    }

    func completeTask(_ task: TWTask) async {
        var updated = task
        updated.status = .completed
        updated.end = Date()
        await updateTask(updated)
    }

    func deleteTask(_ task: TWTask) async {
        var updated = task
        updated.status = .deleted
        updated.end = Date()
        await updateTask(updated)
    }

    func startTask(_ task: TWTask) async {
        var updated = task
        updated.start = Date()
        await updateTask(updated)
    }

    func stopTask(_ task: TWTask) async {
        var updated = task
        updated.start = nil
        await updateTask(updated)
    }

    func undoComplete(_ task: TWTask) async {
        var updated = task
        updated.status = .pending
        updated.end = nil
        await updateTask(updated)
    }

    // MARK: - Sync

    func updateSyncConfig(_ config: SyncConfig) {
        syncConfig = config
        config.save()
        syncService = SyncService(config: config)
    }

    func sync() async {
        guard syncConfig.isConfigured else {
            syncStatus = .error("Sync not configured")
            return
        }

        if syncService == nil {
            syncService = SyncService(config: syncConfig)
        }

        syncStatus = .syncing

        do {
            try await performSync()
            syncStatus = .success(Date())
        } catch {
            let msg = error.localizedDescription
            syncStatus = .error(msg)
        }
    }

    private func performSync() async throws {
        guard let service = syncService else { throw SyncError.notConfigured }

        var baseVersion = await store.loadBaseVersion()
        var lastConflictParent: UUID? = nil

        // Phase 1: Pull remote changes
        do {
            while true {
                guard let result = try await service.getChildVersion(parentVersionId: baseVersion) else {
                    break // Up to date
                }

                // Apply remote ops to local tasks
                TaskStore.applyOperations(result.ops, to: &tasks)
                baseVersion = result.versionId
                await store.saveBaseVersion(baseVersion)
            }

            // If we're still at nil UUID and have no tasks, try snapshot
            // (server may have returned 404 instead of 410 for nil base)
            let nilUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            if baseVersion == nilUUID && tasks.isEmpty {
                if let snapshot = try await service.getSnapshot() {
                    tasks = await store.replaceAllTasks(from: snapshot.tasks)
                    baseVersion = snapshot.versionId
                    await store.saveBaseVersion(baseVersion)
                }
            }
        } catch SyncError.gone {
            // History expired — recover from snapshot
            if let snapshot = try await service.getSnapshot() {
                tasks = await store.replaceAllTasks(from: snapshot.tasks)
                baseVersion = snapshot.versionId
                await store.saveBaseVersion(baseVersion)
            } else {
                // No snapshot on server — reset to empty and start fresh
                tasks.removeAll()
                baseVersion = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                await store.saveTasks(tasks)
                await store.saveBaseVersion(baseVersion)
                await store.clearPendingOps()
            }
        }

        await store.saveTasks(tasks)

        // Phase 2: Push local changes
        let pendingOps = await store.loadPendingOps()
        if pendingOps.isEmpty { return }

        var retries = 0
        while !pendingOps.isEmpty && retries < 5 {
            do {
                let newVersion = try await service.addVersion(
                    parentVersionId: baseVersion,
                    operations: pendingOps
                )
                baseVersion = newVersion
                await store.saveBaseVersion(baseVersion)
                await store.clearPendingOps()
                return

            } catch SyncError.conflict(let expectedParent) {
                // Check for divergence
                if expectedParent == lastConflictParent {
                    throw SyncError.diverged
                }
                lastConflictParent = expectedParent

                // Pull the missing version and retry
                while true {
                    guard let result = try await service.getChildVersion(parentVersionId: baseVersion) else {
                        break
                    }
                    // TODO: Proper OT rebase. For now, just apply remote ops.
                    // In production, transform local ops against remote ops.
                    TaskStore.applyOperations(result.ops, to: &tasks)
                    baseVersion = result.versionId
                    await store.saveBaseVersion(baseVersion)
                }

                await store.saveTasks(tasks)
                retries += 1

            } catch SyncError.gone {
                // History expired — fetch snapshot
                if let snapshot = try await service.getSnapshot() {
                    tasks = await store.replaceAllTasks(from: snapshot.tasks)
                    baseVersion = snapshot.versionId
                    await store.saveBaseVersion(baseVersion)
                    return
                }
                throw SyncError.gone
            }
        }
    }
}
