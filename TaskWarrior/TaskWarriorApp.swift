// TaskWarriorApp.swift

import SwiftUI

@main
struct TaskWarriorApp: App {
    @StateObject private var viewModel = TaskViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .task {
                    await viewModel.loadTasks()
                }
        }
    }
}
