import CryptoKit
import Foundation

// Compile together with OriCmd/App/UpdateVerification.swift.
// keygen <private-key-file> <public-key-file>
// sign <private-key-file> <public-key-file> <dmg> <repository> <version>
@main
struct UpdateSigner {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            guard let command = arguments.first else { throw NSError(domain: "Usage: keygen or sign", code: 1) }
            if command == "keygen", arguments.count == 3 {
                let privateFile = URL(filePath: arguments[1]), publicFile = URL(filePath: arguments[2])
                guard !FileManager.default.fileExists(atPath: publicFile.path) else {
                    throw NSError(domain: "The public key already exists; refusing to replace the trusted publisher", code: 1)
                }
                try FileManager.default.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let descriptor = open(privateFile.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
                guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                let key = Curve25519.Signing.PrivateKey()
                try handle.write(contentsOf: key.rawRepresentation)
                try handle.close()
                try (key.publicKey.rawRepresentation.base64EncodedString() + "\n").write(to: publicFile, atomically: true, encoding: .utf8)
                print("Created the private signing key and its public verification key")
            } else if command == "sign", arguments.count == 7 {
                let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: URL(filePath: arguments[1])))
                let publicText = try String(contentsOfFile: arguments[2], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                guard Data(base64Encoded: publicText) == key.publicKey.rawRepresentation else {
                    throw NSError(domain: "The signing key does not match the app's trusted public key", code: 1)
                }
                let image = URL(filePath: arguments[3]), repository = arguments[4], version = arguments[5]
                let bundleIdentifier = arguments[6]
                guard UpdateVerification.validVersion(version),
                      UpdateVerification.assetPrefixes.contains(where: { image.lastPathComponent == "\($0)-\(version).dmg" }) else {
                    throw NSError(domain: "The version and disk image name must match", code: 1)
                }
                let digest = try UpdateVerification.digest(of: image)
                let manifest = UpdateManifest(schemaVersion: 1, repository: repository, version: version, assetName: image.lastPathComponent,
                                              bundleIdentifier: bundleIdentifier, byteCount: digest.size, sha256: digest.sha256)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(manifest), signature = try key.signature(for: data)
                _ = try UpdateVerification.manifest(data, signature: signature, publicKey: key.publicKey.rawRepresentation,
                                                   repository: repository, version: version, bundleIdentifiers: [bundleIdentifier])
                let base = image.deletingPathExtension()
                try data.write(to: base.appendingPathExtension("manifest.json"), options: .atomic)
                try signature.write(to: base.appendingPathExtension("manifest.sig"), options: .atomic)
                print("Signed \(image.lastPathComponent)")
            } else {
                throw NSError(domain: "Usage: keygen <private> <public>, or sign <private> <public> <dmg> <repository> <version> <bundle identifier>", code: 1)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
