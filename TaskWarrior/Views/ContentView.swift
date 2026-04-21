// ContentView.swift

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: TaskViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(0)

            ProjectsView()
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
                .tag(1)

            TagsView()
                .tabItem {
                    Label("Tags", systemImage: "tag")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .tint(.primary)
    }
}
