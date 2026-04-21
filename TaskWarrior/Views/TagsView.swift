// TagsView.swift

import SwiftUI

struct TagsView: View {
    @EnvironmentObject var vm: TaskViewModel

    var tagSummaries: [(tag: String, count: Int)] {
        var dict: [String: Int] = [:]
        for task in vm.tasks.values where task.status == .pending {
            for tag in task.tags {
                dict[tag, default: 0] += 1
            }
        }
        return dict.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            List {
                if tagSummaries.isEmpty {
                    ContentUnavailableView("No Tags", systemImage: "tag", description: Text("Tagged tasks will appear here"))
                } else {
                    ForEach(tagSummaries, id: \.tag) { summary in
                        NavigationLink {
                            TagTasksView(tag: summary.tag)
                        } label: {
                            HStack {
                                Label(summary.tag, systemImage: "tag")
                                    .font(.body)
                                Spacer()
                                Text("\(summary.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
        }
    }
}

struct TagTasksView: View {
    @EnvironmentObject var vm: TaskViewModel
    let tag: String

    var tasks: [TWTask] {
        vm.tasks.values
            .filter { $0.hasTag(tag) && $0.status == .pending }
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
        .navigationTitle("+" + tag)
    }
}
