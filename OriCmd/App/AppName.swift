import Foundation

extension Bundle {
    /// The app's name as people see it (Oriel, the fork's name); its code and
    /// executable keep the original's name, OriCmd.
    nonisolated var appName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Oriel"
    }
}
