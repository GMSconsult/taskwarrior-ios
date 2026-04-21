// SyncConfig.swift
// TaskWarrior for iOS

import Foundation

/// Configuration for TaskChampion sync server connection.
struct SyncConfig: Codable, Equatable {
    var serverURL: String
    var clientID: String
    var encryptionSecret: String

    var isConfigured: Bool {
        !serverURL.isEmpty && !clientID.isEmpty && !encryptionSecret.isEmpty
    }

    var baseURL: URL? { URL(string: serverURL) }

    var clientUUID: UUID? { UUID(uuidString: clientID) }

    /// 16-byte salt derived from client ID (used in PBKDF2 key derivation)
    var salt: Data? {
        guard let uuid = clientUUID else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        let (u0, u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11, u12, u13, u14, u15) = uuid.uuid
        bytes[0] = u0; bytes[1] = u1; bytes[2] = u2; bytes[3] = u3
        bytes[4] = u4; bytes[5] = u5; bytes[6] = u6; bytes[7] = u7
        bytes[8] = u8; bytes[9] = u9; bytes[10] = u10; bytes[11] = u11
        bytes[12] = u12; bytes[13] = u13; bytes[14] = u14; bytes[15] = u15
        return Data(bytes)
    }

    static let empty = SyncConfig(serverURL: "", clientID: "", encryptionSecret: "")

    static let storageKey = "taskwarrior_sync_config"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> SyncConfig {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let config = try? JSONDecoder().decode(SyncConfig.self, from: data)
        else { return .empty }
        return config
    }
}
