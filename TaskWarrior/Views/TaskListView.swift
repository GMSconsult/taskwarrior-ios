// TaskListView.swift

import SwiftUI

struct TaskListView: View {
    @EnvironmentObject var vm: TaskViewModel
    @State private var showingAddTask = false
    @State private var showingSort = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status filter bar
                StatusFilterBar()

                // Task list
                if vm.filteredTasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Tasks")
            .searchable(text: $vm.searchText, prompt: "Search tasks...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    syncButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(TaskViewModel.SortOption.allCases) { option in
                            Button {
                                vm.sortBy = option
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if vm.sortBy == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddTask = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                TaskEditView(mode: .add)
            }
        }
    }

    // MARK: - Subviews

    private var taskList: some View {
        List {
            ForEach(vm.filteredTasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    TaskRowView(task: task)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if task.status == .pending {
                        Button {
                            Task { await vm.completeTask(task) }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
                    if task.status == .completed {
                        Button {
                            Task { await vm.undoComplete(task) }
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.orange)
                    }
                }
                .swipeActions(edge: .leading) {
                    if task.status == .pending {
                        if task.isActive {
                            Button {
                                Task { await vm.stopTask(task) }
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .tint(.orange)
                        } else {
                            Button {
                                Task { await vm.startTask(task) }
                            } label: {
                                Label("Start", systemImage: "play.fill")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await vm.sync()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: vm.filterStatus == .completed ? "checkmark.circle" : "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(vm.filterStatus == .completed ? "No completed tasks" : "No tasks")
                .font(.title3)
                .foregroundStyle(.secondary)
            if vm.filterStatus == .pending {
                Button("Add a task") { showingAddTask = true }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    private var syncButton: some View {
        Button {
            Task { await vm.sync() }
        } label: {
            switch vm.syncStatus {
            case .idle:
                Image(systemName: "arrow.triangle.2.circlepath")
            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)
            case .success:
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .disabled(vm.syncStatus == .syncing || !vm.syncConfig.isConfigured)
    }
}

// MARK: - Status Filter Bar

struct StatusFilterBar: View {
    @EnvironmentObject var vm: TaskViewModel

    private let filters: [(TaskStatus?, String, String)] = [
        (.pending, "Pending", "circle"),
        (.completed, "Done", "checkmark.circle"),
        (.deleted, "Deleted", "trash"),
        (nil, "All", "tray.full"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.1) { status, label, icon in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.filterStatus = status
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.caption)
                            Text(label)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(vm.filterStatus == status
                            ? Color.primary.opacity(0.12)
                            : Color.clear
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(vm.filterStatus == status ? .primary : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}
