// SettingsView.swift

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: TaskViewModel
    @State private var serverURL: String = ""
    @State private var clientID: String = ""
    @State private var encryptionSecret: String = ""
    @State private var showSecret = false
    @State private var showingResetAlert = false
    @State private var showingExport = false
    @State private var showingSyncResult = false
    @State private var syncResultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                // Stats
                Section("Overview") {
                    LabeledContent("Pending", value: "\(vm.pendingCount)")
                    LabeledContent("Completed today", value: "\(vm.completedTodayCount)")
                    LabeledContent("Overdue", value: "\(vm.overdueCount)")
                    LabeledContent("Total tasks", value: "\(vm.tasks.count)")
                }

                // Sync config
                Section {
                    TextField("Server URL", text: $serverURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    TextField("Client ID (UUID)", text: $clientID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    HStack {
                        if showSecret {
                            TextField("Encryption Secret", text: $encryptionSecret)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Encryption Secret", text: $encryptionSecret)
                        }
                        Button {
                            showSecret.toggle()
                        } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Generate New Client ID") {
                        clientID = UUID().uuidString.lowercased()
                    }
                    .font(.subheadline)
                } header: {
                    Text("Sync Server")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configure a TaskChampion sync server to sync tasks across devices. Use the same Client ID and encryption secret on all replicas. Server URL must use HTTPS.")
                        if !vm.syncConfig.isConfigured {
                            Text("Not configured")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Save / sync buttons
                Section {
                    Button {
                        let config = SyncConfig(
                            serverURL: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                            encryptionSecret: encryptionSecret
                        )
                        vm.updateSyncConfig(config)
                    } label: {
                        Label("Save Configuration", systemImage: "checkmark.circle")
                    }
                    .disabled(serverURL.isEmpty || clientID.isEmpty || encryptionSecret.isEmpty)

                    Button {
                        Task {
                            await vm.sync()
                            switch vm.syncStatus {
                            case .success:
                                syncResultMessage = "Sync completed successfully. \(vm.pendingCount) pending tasks."
                            case .error(let msg):
                                syncResultMessage = "Sync failed: \(msg)"
                            default:
                                syncResultMessage = "Sync finished."
                            }
                            showingSyncResult = true
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            syncStatusView
                        }
                    }
                    .disabled(!vm.syncConfig.isConfigured || vm.syncStatus == .syncing)
                }

                // Sync status
                if case .error(let msg) = vm.syncStatus {
                    Section("Last Sync Error") {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // Data management
                Section("Data") {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Export Tasks (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash")
                    }
                }

                // About
                Section("About") {
                    LabeledContent("App", value: "TaskWarrior for iOS")
                    LabeledContent("Protocol", value: "TaskChampion v1")
                    LabeledContent("Encryption", value: "ChaCha20-Poly1305")
                    Link(destination: URL(string: "https://taskwarrior.org")!) {
                        LabeledContent("Website") {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://gothenburgbitfactory.org/taskchampion/")!) {
                        LabeledContent("TaskChampion Docs") {
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                serverURL = vm.syncConfig.serverURL
                clientID = vm.syncConfig.clientID
                encryptionSecret = vm.syncConfig.encryptionSecret
            }
            .alert("Reset All Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    vm.tasks.removeAll()
                    Task {
                        let store = TaskStore()
                        await store.saveTasks([:])
                        await store.clearPendingOps()
                        await store.saveBaseVersion(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                    }
                }
            } message: {
                Text("This will delete all local tasks and sync data. This cannot be undone.")
            }
            .sheet(isPresented: $showingExport) {
                ExportView()
            }
            .alert("Sync", isPresented: $showingSyncResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncResultMessage)
            }
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        switch vm.syncStatus {
        case .idle:
            EmptyView()
        case .syncing:
            ProgressView()
                .scaleEffect(0.7)
        case .success(let date):
            Text(date, style: .relative)
                .font(.caption)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}

// MARK: - Export View

struct ExportView: View {
    @EnvironmentObject var vm: TaskViewModel
    @Environment(\.dismiss) private var dismiss

    var exportJSON: String {
        let tasks = vm.tasks.values.map { task -> [String: Any] in
            var dict: [String: Any] = ["uuid": task.uuid.uuidString.lowercased()]
            for (key, value) in task.properties {
                dict[key] = value
            }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: tasks, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8)
        else { return "[]" }
        return str
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(exportJSON)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = exportJSON
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }
}
