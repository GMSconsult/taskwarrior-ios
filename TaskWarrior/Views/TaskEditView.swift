// TaskEditView.swift

import SwiftUI

struct TaskEditView: View {
    @EnvironmentObject var vm: TaskViewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case add
        case edit(TWTask)
    }

    let mode: Mode

    @State private var description: String = ""
    @State private var priority: TaskPriority = .none
    @State private var project: String = ""
    @State private var tagsText: String = ""
    @State private var hasDue: Bool = false
    @State private var dueDate: Date = Date()
    @State private var hasWait: Bool = false
    @State private var waitDate: Date = Date()
    @State private var status: TaskStatus = .pending

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingTask: TWTask? {
        if case .edit(let task) = mode { return task }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Project") {
                    TextField("Project name", text: $project)
                        .autocorrectionDisabled()

                    if !vm.allProjects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(vm.allProjects, id: \.self) { proj in
                                    Button(proj) { project = proj }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(project == proj ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.08))
                                        .clipShape(Capsule())
                                        .foregroundStyle(project == proj ? .primary : .secondary)
                                }
                            }
                        }
                    }
                }

                Section("Tags") {
                    TextField("Tags (comma separated)", text: $tagsText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if !vm.allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(vm.allTags, id: \.self) { tag in
                                    Button(tag) {
                                        var tags = parseTags()
                                        if tags.contains(tag) {
                                            tags.removeAll { $0 == tag }
                                        } else {
                                            tags.append(tag)
                                        }
                                        tagsText = tags.joined(separator: ", ")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(parseTags().contains(tag) ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.08))
                                    .clipShape(Capsule())
                                    .foregroundStyle(parseTags().contains(tag) ? .primary : .secondary)
                                }
                            }
                        }
                    }
                }

                Section("Due Date") {
                    Toggle("Has due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Wait") {
                    Toggle("Wait until", isOn: $hasWait)
                    if hasWait {
                        DatePicker("Wait until", selection: $waitDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if isEditing {
                    Section("Status") {
                        Picker("Status", selection: $status) {
                            ForEach(TaskStatus.allCases) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveTask()
                        dismiss()
                    }
                    .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let task = existingTask {
                    description = task.description
                    priority = task.priority
                    project = task.project ?? ""
                    tagsText = task.tags.joined(separator: ", ")
                    hasDue = task.due != nil
                    dueDate = task.due ?? Date()
                    hasWait = task.wait != nil
                    waitDate = task.wait ?? Date()
                    status = task.status
                }
            }
        }
    }

    private func parseTags() -> [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func saveTask() {
        Task {
            if var task = existingTask {
                // Edit existing
                task.description = description.trimmingCharacters(in: .whitespaces)
                task.priority = priority
                task.project = project.isEmpty ? nil : project
                task.status = status

                // Update tags
                for tag in task.tags { task.removeTag(tag) }
                for tag in parseTags() { task.addTag(tag) }

                task.due = hasDue ? dueDate : nil
                task.wait = hasWait ? waitDate : nil

                await vm.updateTask(task)
            } else {
                // New task
                var task = TWTask(description: description.trimmingCharacters(in: .whitespaces))
                task.priority = priority
                task.project = project.isEmpty ? nil : project

                for tag in parseTags() { task.addTag(tag) }

                task.due = hasDue ? dueDate : nil
                task.wait = hasWait ? waitDate : nil

                await vm.addTask(task)
            }
        }
    }
}
