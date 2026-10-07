import CryptoKit
import Foundation

@main
struct UpdateVerificationTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OriCmd-signature-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(path: "OriCmd-2026.10.0.dmg")
        try Data("disk image fixture".utf8).write(to: image)
        let digest = try UpdateVerification.digest(of: image)
        let key = Curve25519.Signing.PrivateKey()
        let manifest = UpdateManifest(schemaVersion: 1, repository: "tosiabunio/Oriel", version: "2026.10.0",
                                      assetName: image.lastPathComponent, bundleIdentifier: "ru.themmag.OriCmd",
                                      byteCount: digest.size, sha256: digest.sha256)
        let data = try JSONEncoder().encode(manifest), signature = try key.signature(for: data)
        func verify(_ bytes: Data = data, _ sig: Data = signature, _ pub: Data = key.publicKey.rawRepresentation,
                    repository: String = "tosiabunio/Oriel", version: String = "2026.10.0",
                    identifiers: Set<String> = ["ru.themmag.OriCmd"]) throws -> UpdateManifest {
            try UpdateVerification.manifest(bytes, signature: sig, publicKey: pub, repository: repository,
                                            version: version, bundleIdentifiers: identifiers)
        }
        func refuses(_ label: String, _ body: () throws -> Void) throws {
            do { try body() } catch { print("ok   \(label)"); return }
            throw NSError(domain: "Accepted invalid update: \(label)", code: 1)
        }
        let verified = try verify()
        try UpdateVerification.image(image, matches: verified, isCancelled: { false })
        print("ok   genuine signature and disk image")
        // The bridge to the fork's own identity: Oriel- files, the new bundle identifier.
        let moved = UpdateManifest(schemaVersion: 1, repository: "tosiabunio/Oriel", version: "2026.10.0",
                                   assetName: "Oriel-2026.10.0.dmg", bundleIdentifier: UpdateVerification.forkBundleIdentifier,
                                   byteCount: digest.size, sha256: digest.sha256)
        let movedData = try JSONEncoder().encode(moved), movedSignature = try key.signature(for: movedData)
        _ = try verify(movedData, movedSignature, identifiers: ["ru.themmag.OriCmd", UpdateVerification.forkBundleIdentifier])
        print("ok   an Oriel- image with the fork's own bundle identifier is accepted")
        try refuses("the fork's identifier where only the original's is allowed") { _ = try verify(movedData, movedSignature) }
        try refuses("changed manifest") { _ = try verify(data + Data(" ".utf8)) }
        try refuses("wrong publisher key") { _ = try verify(data, signature, Curve25519.Signing.PrivateKey().publicKey.rawRepresentation) }
        try refuses("truncated signature") { _ = try verify(data, signature.dropLast()) }
        try refuses("oversized manifest") { _ = try verify(Data(repeating: 0, count: 16 * 1024 + 1)) }
        try refuses("wrong repository") { _ = try verify(repository: "mmag/OriCmd") }
        try refuses("wrong version") { _ = try verify(version: "2026.10.1") }
        try refuses("wrong app") { _ = try verify(identifiers: ["another.app"]) }
        let fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func refusesField(_ field: String, value: Any, label: String) throws {
            var changed = fields
            changed[field] = value
            let bytes = try JSONSerialization.data(withJSONObject: changed)
            try refuses(label) { _ = try verify(bytes, key.signature(for: bytes)) }
        }
        try refusesField("schemaVersion", value: 2, label: "unsupported signed schema")
        try refusesField("assetName", value: "other.dmg", label: "wrong signed disk image name")
        try refusesField("byteCount", value: 0, label: "empty signed image")
        try refusesField("byteCount", value: UpdateVerification.maximumImageSize + 1, label: "oversized signed image")
        try refusesField("sha256", value: "bad", label: "invalid signed digest")
        try refusesField("repository", value: "another/fork", label: "wrong signed repository")
        try refusesField("version", value: "2026.10.1", label: "wrong signed version")
        try refuses("cancellation") { try UpdateVerification.image(image, matches: verified, isCancelled: { true }) }
        try Data("disk image fixturX".utf8).write(to: image)
        try refuses("changed image contents") { try UpdateVerification.image(image, matches: verified, isCancelled: { false }) }
        try Data("short".utf8).write(to: image)
        try refuses("truncated image") { try UpdateVerification.image(image, matches: verified, isCancelled: { false }) }
        guard !UpdateVerification.validVersion("2026.10.0/../../app"), UpdateVerification.validVersion("2026.10.0rc1") else {
            throw NSError(domain: "Version validation failed", code: 1)
        }
        print("ok   version names cannot contain paths")
    }
}
