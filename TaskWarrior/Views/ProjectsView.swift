// ProjectsView.swift

import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject var vm: TaskViewModel

    var projectSummaries: [(name: String, pending: Int, completed: Int)] {
        var dict: [String: (pending: Int, completed: Int)] = [:]

        for task in vm.tasks.values {
            guard let project = task.project else { continue }
            var entry = dict[project] ?? (0, 0)
            if task.status == .pending { entry.pending += 1 }
            if task.status == .completed { entry.completed += 1 }
            dict[project] = entry
        }

        return dict.map { (name: $0.key, pending: $0.value.pending, completed: $0.value.completed) }
            .sorted { $0.pending > $1.pending }
    }

    var unprojectCount: Int {
        vm.tasks.values.filter { $0.project == nil && $0.status == .pending }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !projectSummaries.isEmpty {
                    ForEach(projectSummaries, id: \.name) { summary in
                        NavigationLink {
                            ProjectTasksView(project: summary.name)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.name)
                                        .font(.body.weight(.medium))
                                    Text("\(summary.pending) pending, \(summary.completed) done")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if summary.pending > 0 {
                                    Text("\(summary.pending)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if unprojectCount > 0 {
                    NavigationLink {
                        ProjectTasksView(project: nil)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("(no project)")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                Text("\(unprojectCount) pending")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

                if projectSummaries.isEmpty && unprojectCount == 0 {
                    ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Tasks with projects will appear here"))
                }
            }
            .navigationTitle("Projects")
        }
    }
}

struct ProjectTasksView: View {
    @EnvironmentObject var vm: TaskViewModel
    let project: String?

    var tasks: [TWTask] {
        vm.tasks.values
            .filter { $0.project == project && $0.status == .pending }
            .sorted { $0.urgency > $1.urgency }
    }

    var body: some View {
        List {
            ForEach(tasks) { task in
                NavigationLink {
                    TaskDetailView(task: task)
                } label: {
                    TaskRowView(task: task)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        Task { await vm.completeTask(task) }
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .tint(.green)
                }
            }
        }
        .navigationTitle(project ?? "(no project)")
    }
}
