import CryptoKit
import Foundation

@main
struct UpdateVerificationTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "OriCmd-signature-tests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appending(path: "OriCmd-1.2.dmg")
        try Data("disk image fixture".utf8).write(to: image)
        let digest = try UpdateVerification.digest(of: image)
        let key = Curve25519.Signing.PrivateKey()
        let manifest = UpdateManifest(schemaVersion: 1, repository: "tosiabunio/OriCmd", version: "1.2",
                                      assetName: image.lastPathComponent, bundleIdentifier: "ru.themmag.OriCmd",
                                      byteCount: digest.size, sha256: digest.sha256)
        let data = try JSONEncoder().encode(manifest), signature = try key.signature(for: data)
        func verify(_ bytes: Data = data, _ sig: Data = signature, _ pub: Data = key.publicKey.rawRepresentation,
                    repository: String = "tosiabunio/OriCmd", version: String = "1.2", identifier: String = "ru.themmag.OriCmd") throws -> UpdateManifest {
            try UpdateVerification.manifest(bytes, signature: sig, publicKey: pub, repository: repository,
                                            version: version, bundleIdentifier: identifier)
        }
        func refuses(_ label: String, _ body: () throws -> Void) throws {
            do { try body() } catch { print("ok   \(label)"); return }
            throw NSError(domain: "Accepted invalid update: \(label)", code: 1)
        }
        let verified = try verify()
        try UpdateVerification.image(image, matches: verified, isCancelled: { false })
        print("ok   genuine signature and disk image")
        try refuses("changed manifest") { _ = try verify(data + Data(" ".utf8)) }
        try refuses("wrong publisher key") { _ = try verify(data, signature, Curve25519.Signing.PrivateKey().publicKey.rawRepresentation) }
        try refuses("truncated signature") { _ = try verify(data, signature.dropLast()) }
        try refuses("oversized manifest") { _ = try verify(Data(repeating: 0, count: 16 * 1024 + 1)) }
        try refuses("wrong repository") { _ = try verify(repository: "mmag/OriCmd") }
        try refuses("wrong version") { _ = try verify(version: "1.3") }
        try refuses("wrong app") { _ = try verify(identifier: "another.app") }
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
        try refusesField("version", value: "1.3", label: "wrong signed version")
        try refuses("cancellation") { try UpdateVerification.image(image, matches: verified, isCancelled: { true }) }
        try Data("disk image fixturX".utf8).write(to: image)
        try refuses("changed image contents") { try UpdateVerification.image(image, matches: verified, isCancelled: { false }) }
        try Data("short".utf8).write(to: image)
        try refuses("truncated image") { try UpdateVerification.image(image, matches: verified, isCancelled: { false }) }
        guard !UpdateVerification.validVersion("1.2/../../app"), UpdateVerification.validVersion("1.2rc1") else {
            throw NSError(domain: "Version validation failed", code: 1)
        }
        print("ok   version names cannot contain paths")
    }
}
