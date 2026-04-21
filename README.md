# TaskWarrior for iOS

A native SwiftUI iOS client for [Taskwarrior](https://taskwarrior.org/) with full [TaskChampion](https://gothenburgbitfactory.org/taskchampion/) sync protocol support.

## Features

- **Full TaskChampion Protocol** — Create, Update, Delete operations with version-chain sync
- **End-to-End Encryption** — PBKDF2 key derivation (600k iterations) + ChaCha20-Poly1305 AEAD
- **Sync with any TaskChampion server** — Compatible with `taskchampion-sync-server`, syncs with Taskwarrior 3.x on desktop
- **Task Management** — priorities (H/M/L), projects, tags, annotations, dependencies, due dates, wait dates
- **Urgency Scoring** — Simplified Taskwarrior urgency calculation for smart sorting
- **Swipe Actions** — Complete, start/stop, undo from task list
- **Pull to Refresh** — Triggers sync
- **Filter & Search** — By status, project, tag, and free text
- **Sort Options** — Urgency, priority, due date, age, description, project, modified
- **Export** — JSON export of all tasks

## Architecture

```
TaskWarrior/
├── Models/
│   ├── TaskModel.swift          # TWTask, SyncOperation, TaskStatus, TaskPriority
│   └── SyncConfig.swift         # Server URL, client ID, encryption secret
├── Services/
│   ├── TaskStore.swift          # Local persistence + operation generation
│   ├── CryptoService.swift      # PBKDF2 + ChaCha20-Poly1305 per TC spec
│   └── SyncService.swift        # HTTP sync client (4 endpoints)
├── ViewModels/
│   └── TaskViewModel.swift      # Main state + sync orchestration
└── Views/
    ├── ContentView.swift        # Tab bar root
    ├── TaskListView.swift       # Main task list with filters
    ├── TaskRowView.swift        # Individual task row
    ├── TaskDetailView.swift     # Full task detail + annotations
    ├── TaskEditView.swift       # Add/edit task form
    ├── ProjectsView.swift       # Project browser
    ├── TagsView.swift           # Tag browser
    └── SettingsView.swift       # Sync config + data management
```

## Sync Protocol

Implements the full TaskChampion HTTP sync protocol:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/client/get-child-version/<parentVersionId>` | GET | Pull next version |
| `/v1/client/add-version/<parentVersionId>` | POST | Push local changes |
| `/v1/client/snapshot` | GET | Download full snapshot |
| `/v1/client/add-snapshot/<versionId>` | POST | Upload snapshot |

### Encryption Wire Format

```
[1 byte version=0x01] [12 bytes nonce] [ciphertext + 16 bytes tag]
```

AAD: `[1 byte app_id=0x01] [16 bytes version_id]`

### Operation Format

```json
[
  {"Create": {"uuid": "..."}},
  {"Update": {"uuid": "...", "property": "description", "value": "Buy milk", "timestamp": "2025-01-01T00:00:00Z"}},
  {"Delete": {"uuid": "..."}}
]
```

## Setup

### Requirements

- iOS 17.0+
- Xcode 15.4+
- A TaskChampion sync server (optional, for sync)

### Build

1. Open `TaskWarrior.xcodeproj` in Xcode
2. Select your team in Signing & Capabilities
3. Build and run on device or simulator

### Configure Sync

1. Set up a TaskChampion sync server:
   ```bash
   docker run -d -p 8080:8080 gothenburgbitfactory/taskchampion-sync-server
   ```

2. In the app, go to Settings and enter:
   - **Server URL**: `https://your-server:8080` (or `http://` for local)
   - **Client ID**: Same UUID used in your `~/.config/task/taskrc` (`sync.server.client_id`)
   - **Encryption Secret**: Same as `sync.encryption_secret` in taskrc

3. Tap "Save Configuration" then "Sync Now"

### Matching Desktop Config

Your `~/.config/task/taskrc` should have:
```
sync.server.url=https://your-server:8080
sync.server.client_id=YOUR-UUID-HERE
sync.encryption_secret=YOUR-SECRET-HERE
```

Use the **same** `client_id` and `encryption_secret` on all replicas (including this iOS app).

## Task Model

Per the TaskChampion spec, tasks are key/value maps. Recognized keys:

| Key | Description |
|-----|-------------|
| `status` | pending, completed, deleted, recurring |
| `description` | Task summary |
| `priority` | H, M, or L |
| `project` | Project name |
| `due` | Unix timestamp |
| `wait` | Hidden until timestamp |
| `entry` | Creation timestamp |
| `modified` | Last modification timestamp |
| `start` | Active since timestamp |
| `end` | Completion/deletion timestamp |
| `tag_<name>` | Tag presence |
| `annotation_<ts>` | Annotation text |
| `dep_<uuid>` | Dependency |

Any unrecognized keys are preserved as UDAs.

## Known Limitations

- No recurrence support (TaskChampion doesn't implement recurrence directly)
- Operational transformation during conflicts uses last-write-wins rather than full OT rebase
- Local storage uses UserDefaults/JSON; production should use SQLite
- No background sync (requires manual pull-to-refresh or sync button)

## License

This is an independent client. Taskwarrior and TaskChampion are projects of the Gothenburg Bit Factory, licensed under MIT.
