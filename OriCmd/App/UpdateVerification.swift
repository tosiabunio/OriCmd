import CryptoKit
import Foundation

/// Signed metadata binds the disk image to one publisher, version and app.
nonisolated struct UpdateManifest: Codable, Sendable {
    let schemaVersion: Int
    let repository: String
    let version: String
    let assetName: String
    let bundleIdentifier: String
    let byteCount: Int64
    let sha256: String
}

nonisolated enum UpdateVerification {
    static let maximumImageSize: Int64 = 512 * 1024 * 1024
    /// What the fork's release files are named after: Oriel, or OriCmd, as the fork
    /// was called before.
    static let assetPrefixes = ["Oriel", "OriCmd"]
    /// The fork's own bundle identifier, which replaces the original's
    /// (`ru.themmag.OriCmd`): an update may move the app to it.
    static let forkBundleIdentifier = "io.github.tosiabunio.oriel"

    static func validVersion(_ version: String) -> Bool {
        version.count <= 64 && version.wholeMatch(of: /[0-9]+(?:\.[0-9]+)*(?:[a-z]+[0-9]*)?/) != nil
    }

    /// Verify the original bytes before decoding; never trust a key from the feed.
    /// `bundleIdentifiers`: the apps the update may contain.
    static func manifest(_ data: Data, signature: Data, publicKey: Data, repository: String,
                         version: String, bundleIdentifiers: Set<String>) throws -> UpdateManifest {
        guard data.count <= 16 * 1024, signature.count == 64, publicKey.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: data) else { throw UpdateValidationError.signature }
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        guard manifest.schemaVersion == 1, validVersion(version), manifest.version == version,
              manifest.repository == repository, bundleIdentifiers.contains(manifest.bundleIdentifier),
              assetPrefixes.contains(where: { manifest.assetName == "\($0)-\(version).dmg" }),
              manifest.byteCount > 0, manifest.byteCount <= maximumImageSize,
              manifest.sha256.wholeMatch(of: /[a-f0-9]{64}/) != nil else { throw UpdateValidationError.metadata }
        return manifest
    }

    static func digest(of file: URL, isCancelled: () -> Bool = { false }) throws -> (size: Int64, sha256: String) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while true {
            if isCancelled() { throw CancellationError() }
            guard let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            size += Int64(chunk.count)
            guard size <= maximumImageSize else { throw UpdateValidationError.contents }
            hash.update(data: chunk)
        }
        return (size, hash.finalize().map { String(format: "%02x", $0) }.joined())
    }

    static func image(_ file: URL, matches manifest: UpdateManifest, isCancelled: () -> Bool) throws {
        let digest = try digest(of: file, isCancelled: isCancelled)
        guard digest.size == manifest.byteCount, digest.sha256 == manifest.sha256 else { throw UpdateValidationError.contents }
    }
}

nonisolated enum UpdateValidationError: LocalizedError {
    case signature, metadata, contents

    var errorDescription: String? {
        switch self {
        case .signature: String(localized: "The update signature is invalid.")
        case .metadata: String(localized: "The signed update does not match this release or app.")
        case .contents: String(localized: "The downloaded update does not match its signed checksum and size.")
        }
    }
}
