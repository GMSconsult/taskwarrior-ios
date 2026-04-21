// TaskRowView.swift

import SwiftUI

struct TaskRowView: View {
    let task: TWTask
    @EnvironmentObject var vm: TaskViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIcon
                .onTapGesture {
                    if task.status == .pending {
                        Task { await vm.completeTask(task) }
                    }
                }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.description)
                        .font(.body)
                        .strikethrough(task.status == .completed)
                        .foregroundStyle(task.status == .completed ? .secondary : .primary)
                        .lineLimit(2)

                    if task.isActive {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    if let project = task.project {
                        Label(project, systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let due = task.due {
                        dueBadge(due)
                    }

                    if !task.tags.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "tag")
                                .font(.system(size: 9))
                            Text(task.tags.prefix(3).joined(separator: ", "))
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Priority
            if task.priority != .none {
                priorityBadge
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Components

    private var statusIcon: some View {
        Image(systemName: task.status.iconName)
            .font(.title3)
            .foregroundStyle(statusColor)
            .frame(width: 28, height: 28)
    }

    private var statusColor: Color {
        switch task.status {
        case .pending: return .secondary
        case .completed: return .green
        case .deleted: return .red
        case .recurring: return .purple
        }
    }

    private func dueBadge(_ due: Date) -> some View {
        let isOverdue = due < Date()
        let isDueSoon = due.timeIntervalSinceNow < 86400 * 2 && !isOverdue

        return HStack(spacing: 2) {
            Image(systemName: "calendar")
                .font(.system(size: 9))
            Text(dueDateText(due))
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(isOverdue ? .red : isDueSoon ? .orange : .secondary)
    }

    private var priorityBadge: some View {
        Text(task.priority.rawValue)
            .font(.caption.weight(.bold).monospaced())
            .frame(width: 22, height: 22)
            .background(priorityColor.opacity(0.15))
            .foregroundStyle(priorityColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var priorityColor: Color {
        switch task.priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .clear
        }
    }

    private func dueDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 0 { return "\(abs(days))d overdue" }
        if days < 7 { return "\(days)d" }

        let formatter = DateFormatter()
        formatter.dateFormat = days < 365 ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}
