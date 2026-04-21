// CryptoService.swift
// TaskWarrior for iOS
//
// Implements TaskChampion encryption:
// - Key derivation: PBKDF2 with HMAC-SHA256, 600,000 iterations
// - Encryption: ChaCha20-Poly1305 AEAD
// - AAD: 1 byte app_id (0x01) + 16 bytes version_id
// - Wire format: 1 byte version (0x01) + 12 bytes nonce + ciphertext

import Foundation
import CryptoKit
import CommonCrypto
import zlib

struct CryptoService {

    // MARK: - Key Derivation

    /// Derive 32-byte key using PBKDF2-HMAC-SHA256 with 600,000 iterations.
    /// Salt is the 16-byte client UUID.
    static func deriveKey(secret: String, salt: Data) -> SymmetricKey? {
        guard let secretData = secret.data(using: .utf8) else { return nil }
        var derivedKey = [UInt8](repeating: 0, count: 32)

        let status = secretData.withUnsafeBytes { secretBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    secretBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    secretData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    600_000,
                    &derivedKey,
                    32
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return SymmetricKey(data: derivedKey)
    }

    // MARK: - Build AAD

    /// AAD = 1 byte app_id (always 1) + 16 bytes version_id
    static func buildAAD(versionID: UUID) -> Data {
        var aad = Data(capacity: 17)
        aad.append(0x01) // app_id

        let u = versionID.uuid
        let bytes: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                              u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        aad.append(contentsOf: bytes)
        return aad
    }

    // MARK: - Encrypt

    /// Encrypt data using ChaCha20-Poly1305.
    /// Returns: 1 byte version + 12 bytes nonce + ciphertext+tag
    static func encrypt(plaintext: Data, key: SymmetricKey, versionID: UUID) throws -> Data {
        let nonce = ChaChaPoly.Nonce()
        let aad = buildAAD(versionID: versionID)

        let sealedBox = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aad)

        var result = Data(capacity: 1 + 12 + sealedBox.ciphertext.count + sealedBox.tag.count)
        result.append(0x01) // format version
        result.append(contentsOf: nonce)
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)
        return result
    }

    // MARK: - Decrypt

    /// Decrypt data. Input format: 1 byte version + 12 bytes nonce + ciphertext+tag
    static func decrypt(data: Data, key: SymmetricKey, versionID: UUID) throws -> Data {

        guard data.count > 13 else {
            throw CryptoError.invalidData
        }

        let formatVersion = data[data.startIndex]
        guard formatVersion == 0x01 else {
            throw CryptoError.unsupportedVersion(formatVersion)
        }

        let nonceData = data[(data.startIndex + 1)..<(data.startIndex + 13)]
        let ciphertextAndTag = data[(data.startIndex + 13)...]
        guard ciphertextAndTag.count >= 16 else {
            throw CryptoError.invalidData
        }

        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let aad = buildAAD(versionID: versionID)

        // ChaChaPoly.SealedBox expects nonce + ciphertext + tag combined
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: ciphertextAndTag.dropLast(16),
            tag: ciphertextAndTag.suffix(16)
        )

        return try ChaChaPoly.open(sealedBox, using: key, authenticating: aad)
    }

    // MARK: - Compression

    /// Compress data using zlib.
    static func compress(_ data: Data) throws -> Data {
        var destLen = uLong(compressBound(uLong(data.count)))
        var dest = [UInt8](repeating: 0, count: Int(destLen))

        let result = data.withUnsafeBytes { srcBytes -> Int32 in
            let src = srcBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return zlib.compress(&dest, &destLen, src, uLong(data.count))
        }

        guard result == Z_OK else {
            throw CryptoError.compressionFailed
        }
        return Data(dest.prefix(Int(destLen)))
    }

    // MARK: - Decompression

    /// Decompress data if it starts with zlib header (0x78), otherwise return as-is.
    static func decompressIfNeeded(_ data: Data) throws -> Data {
        guard data.count >= 2 else { return data }
        let firstByte = data[data.startIndex]
        // zlib magic: 0x78 (0x01, 0x5e, 0x9c, 0xda, 0xbb, etc for second byte)
        guard firstByte == 0x78 else { return data }

        // Use Apple's built-in zlib decompression via NSData
        let nsData = data as NSData
        // Try decompressing with increasing buffer sizes
        var decompressedSize = data.count * 4
        for _ in 0..<8 {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decompressedSize)
            defer { buffer.deallocate() }
            var destLen = decompressedSize

            let result = data.withUnsafeBytes { srcBytes -> Int32 in
                let src = srcBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return uncompress(buffer, &destLen, src, uLong(data.count))
            }

            if result == Z_OK {
                return Data(bytes: buffer, count: destLen)
            } else if result == Z_BUF_ERROR {
                decompressedSize *= 2
                continue
            } else {
                throw CryptoError.decompressionFailed
            }
        }
        throw CryptoError.decompressionFailed
    }
}

enum CryptoError: Error, LocalizedError {
    case invalidData
    case unsupportedVersion(UInt8)
    case keyDerivationFailed
    case decompressionFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .invalidData: return "Invalid encrypted data"
        case .unsupportedVersion(let v): return "Unsupported encryption version: \(v)"
        case .keyDerivationFailed: return "Failed to derive encryption key"
        case .decompressionFailed: return "Failed to decompress data"
        case .compressionFailed: return "Failed to compress data"
        }
    }
}
