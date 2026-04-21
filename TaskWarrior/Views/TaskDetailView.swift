// TaskDetailView.swift

import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject var vm: TaskViewModel
    @State var task: TWTask
    @State private var showingEdit = false
    @State private var newAnnotation = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Header section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: task.status.iconName)
                            .foregroundStyle(task.status == .completed ? .green : .primary)
                        Text(task.status.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if task.priority != .none {
                            Text("Priority: \(task.priority.displayName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(priorityColor)
                        }
                    }
                    Text(task.description)
                        .font(.title3.weight(.semibold))
                }
            }

            // Metadata
            Section("Details") {
                if let project = task.project {
                    LabeledContent("Project", value: project)
                }
                if let due = task.due {
                    LabeledContent("Due") {
                        Text(due, style: .date)
                            .foregroundStyle(due < Date() ? .red : .primary)
                    }
                }
                if let entry = task.entry {
                    LabeledContent("Created") {
                        Text(entry, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                if let modified = task.modified {
                    LabeledContent("Modified") {
                        Text(modified, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                if task.isActive, let start = task.start {
                    LabeledContent("Active since") {
                        Text(start, style: .relative)
                            .foregroundStyle(.orange)
                    }
                }
                if let wait = task.wait {
                    LabeledContent("Wait until") {
                        Text(wait, style: .date)
                    }
                }
                if let end = task.end {
                    LabeledContent(task.status == .completed ? "Completed" : "Ended") {
                        Text(end, style: .relative)
                    }
                }
                LabeledContent("Urgency") {
                    Text(String(format: "%.1f", task.urgency))
                        .monospacedDigit()
                }
            }

            // Tags
            if !task.tags.isEmpty {
                Section("Tags") {
                    FlowLayout(spacing: 6) {
                        ForEach(task.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Dependencies
            if !task.dependencies.isEmpty {
                Section("Dependencies") {
                    ForEach(task.dependencies, id: \.self) { depUUID in
                        if let dep = vm.tasks[depUUID] {
                            HStack {
                                Image(systemName: dep.status.iconName)
                                    .foregroundStyle(dep.status == .completed ? .green : .secondary)
                                Text(dep.description)
                                    .strikethrough(dep.status == .completed)
                            }
                        } else {
                            Text(depUUID.uuidString.prefix(8) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Annotations
            Section("Annotations") {
                ForEach(task.annotations) { annotation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(annotation.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(annotation.text)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("Add annotation...", text: $newAnnotation)
                        .textFieldStyle(.plain)
                    Button {
                        guard !newAnnotation.isEmpty else { return }
                        task.addAnnotation(newAnnotation)
                        Task { await vm.updateTask(task) }
                        newAnnotation = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newAnnotation.isEmpty)
                }
            }

            // UUID
            Section {
                LabeledContent("UUID") {
                    Text(task.uuid.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Actions
            Section {
                if task.status == .pending {
                    if task.isActive {
                        Button {
                            Task {
                                await vm.stopTask(task)
                                task = vm.tasks[task.uuid] ?? task
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            Task {
                                await vm.startTask(task)
                                task = vm.tasks[task.uuid] ?? task
                            }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                    }

                    Button {
                        Task {
                            await vm.completeTask(task)
                            dismiss()
                        }
                    } label: {
                        Label("Complete", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }

                if task.status == .completed {
                    Button {
                        Task {
                            await vm.undoComplete(task)
                            task = vm.tasks[task.uuid] ?? task
                        }
                    } label: {
                        Label("Mark Pending", systemImage: "arrow.uturn.backward")
                    }
                }

                if task.status != .deleted {
                    Button(role: .destructive) {
                        Task {
                            await vm.deleteTask(task)
                            dismiss()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TaskEditView(mode: .edit(task))
        }
        .onChange(of: showingEdit) { _, isShowing in
            if !isShowing {
                // Refresh from store
                if let updated = vm.tasks[task.uuid] {
                    task = updated
                }
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .secondary
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
