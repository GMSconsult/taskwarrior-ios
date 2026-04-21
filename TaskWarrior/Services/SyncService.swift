// SyncService.swift
// TaskWarrior for iOS
//
// Implements TaskChampion sync protocol over HTTP:
// - AddVersion: POST /v1/client/add-version/<parentVersionId>
// - GetChildVersion: GET /v1/client/get-child-version/<parentVersionId>
// - AddSnapshot: POST /v1/client/add-snapshot/<versionId>
// - GetSnapshot: GET /v1/client/snapshot

import Foundation
import CryptoKit

enum SyncError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case conflict(expectedParent: UUID)
    case gone
    case serverError(Int, String)
    case encodingError
    case decodingError
    case networkError(Error)
    case cryptoError(Error)
    case diverged

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Sync not configured"
        case .invalidURL: return "Invalid server URL"
        case .conflict: return "Sync conflict — retrying"
        case .gone: return "Server history expired. Must re-sync from snapshot."
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .encodingError: return "Failed to encode operations"
        case .decodingError: return "Failed to decode server response"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .cryptoError(let e): return "Encryption error: \(e.localizedDescription)"
        case .diverged: return "Task history has diverged from server"
        }
    }
}

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)
}

/// Wrapper for history segments that come as {"operations": [...]}
private struct OperationsWrapper: Decodable {
    let operations: [SyncOperation]
}

actor SyncService {
    private let config: SyncConfig
    private let encryptionKey: SymmetricKey?
    private let session: URLSession

    init(config: SyncConfig) {
        self.config = config
        if let salt = config.salt, !config.encryptionSecret.isEmpty {
            self.encryptionKey = CryptoService.deriveKey(secret: config.encryptionSecret, salt: salt)
        } else {
            self.encryptionKey = nil
        }
        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: urlConfig)
    }

    // MARK: - GetChildVersion

    /// Fetch next version after parentVersionId.
    /// Returns (versionId, operations) or nil if up-to-date.
    func getChildVersion(parentVersionId: UUID) async throws -> (versionId: UUID, ops: [SyncOperation])? {
        guard config.isConfigured, let baseURL = config.baseURL else { throw SyncError.notConfigured }
        guard let key = encryptionKey else { throw SyncError.cryptoError(CryptoError.keyDerivationFailed) }

        let url = baseURL.appendingPathComponent("v1/client/get-child-version/\(parentVersionId.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.clientID, forHTTPHeaderField: "X-Client-Id")

        let (data, response) = try await session.data(for: request)
        let httpResp = response as! HTTPURLResponse

        switch httpResp.statusCode {
        case 200:
            guard let versionIdStr = httpResp.value(forHTTPHeaderField: "X-Version-Id"),
                  let versionId = UUID(uuidString: versionIdStr) else {
                throw SyncError.decodingError
            }
            // Decrypt history segment
            let plaintext = try CryptoService.decrypt(data: data, key: key, versionID: parentVersionId)
            let jsonData = try CryptoService.decompressIfNeeded(plaintext)

            // History segments are JSON arrays of operations,
            // possibly wrapped in {"operations": [...]}
            let ops: [SyncOperation]
            if let array = try? JSONDecoder().decode([SyncOperation].self, from: jsonData) {
                ops = array
            } else if let wrapper = try? JSONDecoder().decode(OperationsWrapper.self, from: jsonData) {
                ops = wrapper.operations
            } else if let single = try? JSONDecoder().decode(SyncOperation.self, from: jsonData) {
                ops = [single]
            } else {
                throw SyncError.decodingError
            }
            return (versionId: versionId, ops: ops)

        case 404:
            return nil // Up to date

        case 410:
            throw SyncError.gone

        default:
            throw SyncError.serverError(httpResp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - AddVersion

    /// Push local operations as a new version.
    /// Returns the new version ID on success.
    func addVersion(parentVersionId: UUID, operations: [SyncOperation]) async throws -> UUID {
        guard config.isConfigured, let baseURL = config.baseURL else { throw SyncError.notConfigured }
        guard let key = encryptionKey else { throw SyncError.cryptoError(CryptoError.keyDerivationFailed) }

        let url = baseURL.appendingPathComponent("v1/client/add-version/\(parentVersionId.uuidString.lowercased())")

        // Encode operations: wrap in {"operations": [...]} then encrypt (no compression)
        let wrapper = ["operations": operations]
        let jsonData = try JSONEncoder().encode(wrapper)
        let encrypted = try CryptoService.encrypt(plaintext: jsonData, key: key, versionID: parentVersionId)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.clientID, forHTTPHeaderField: "X-Client-Id")
        request.setValue("application/vnd.taskchampion.history-segment", forHTTPHeaderField: "Content-Type")
        request.httpBody = encrypted

        let (data, response) = try await session.data(for: request)
        let httpResp = response as! HTTPURLResponse

        switch httpResp.statusCode {
        case 200:
            guard let versionIdStr = httpResp.value(forHTTPHeaderField: "X-Version-Id"),
                  let versionId = UUID(uuidString: versionIdStr) else {
                throw SyncError.decodingError
            }
            return versionId

        case 409:
            // Conflict — server has a newer version
            if let parentStr = httpResp.value(forHTTPHeaderField: "X-Parent-Version-Id"),
               let parent = UUID(uuidString: parentStr) {
                throw SyncError.conflict(expectedParent: parent)
            }
            throw SyncError.conflict(expectedParent: parentVersionId)

        default:
            throw SyncError.serverError(httpResp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - GetSnapshot

    /// Download latest snapshot from server.
    func getSnapshot() async throws -> (versionId: UUID, tasks: [UUID: [String: String]])? {
        guard config.isConfigured, let baseURL = config.baseURL else { throw SyncError.notConfigured }
        guard let key = encryptionKey else { throw SyncError.cryptoError(CryptoError.keyDerivationFailed) }

        let url = baseURL.appendingPathComponent("v1/client/snapshot")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.clientID, forHTTPHeaderField: "X-Client-Id")

        let (data, response) = try await session.data(for: request)
        let httpResp = response as! HTTPURLResponse
        guard httpResp.statusCode == 200 else {
            if httpResp.statusCode == 404 { return nil }
            throw SyncError.serverError(httpResp.statusCode, "")
        }

        guard let versionIdStr = httpResp.value(forHTTPHeaderField: "X-Version-Id"),
              let versionId = UUID(uuidString: versionIdStr) else {
            throw SyncError.decodingError
        }

        let plaintext = try CryptoService.decrypt(data: data, key: key, versionID: versionId)
        let jsonData = try CryptoService.decompressIfNeeded(plaintext)

        // Snapshot is JSON: { "uuid": { "key": "value", ... }, ... }
        let rawSnapshot = try JSONDecoder().decode([String: [String: String]].self, from: jsonData)
        var tasks: [UUID: [String: String]] = [:]
        for (uuidStr, props) in rawSnapshot {
            if let uuid = UUID(uuidString: uuidStr) {
                tasks[uuid] = props
            }
        }

        return (versionId: versionId, tasks: tasks)
    }

    // MARK: - AddSnapshot

    /// Upload a snapshot to the server.
    func addSnapshot(versionId: UUID, tasks: [UUID: TWTask]) async throws {
        guard config.isConfigured, let baseURL = config.baseURL else { throw SyncError.notConfigured }
        guard let key = encryptionKey else { throw SyncError.cryptoError(CryptoError.keyDerivationFailed) }

        // Build snapshot as { uuid_string: properties }
        var snapshot: [String: [String: String]] = [:]
        for (uuid, task) in tasks {
            snapshot[uuid.uuidString.lowercased()] = task.properties
        }

        let jsonData = try JSONEncoder().encode(snapshot)
        let encrypted = try CryptoService.encrypt(plaintext: jsonData, key: key, versionID: versionId)

        let url = baseURL.appendingPathComponent("v1/client/add-snapshot/\(versionId.uuidString.lowercased())")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.clientID, forHTTPHeaderField: "X-Client-Id")
        request.setValue("application/vnd.taskchampion.snapshot", forHTTPHeaderField: "Content-Type")
        request.httpBody = encrypted

        let (_, response) = try await session.data(for: request)
        let httpResp = response as! HTTPURLResponse

        guard httpResp.statusCode == 200 else {
            throw SyncError.serverError(httpResp.statusCode, "")
        }
    }
}
