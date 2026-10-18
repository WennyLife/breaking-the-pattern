import Foundation
import CryptoKit

enum BTPUpdateBackup {
    static func preserve(app: URL, root: URL) throws -> URL {
        let fm = FileManager.default
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        let rawInfo = try Data(contentsOf: infoURL)
        guard let info = try PropertyListSerialization.propertyList(from: rawInfo, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "org.lendaii.breakingthepattern",
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw NSError(domain: "BTP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não foi possível identificar o BTP para guardar o backup."])
        }
        // Identificador derivado de bytes, sem aceitar nomes como caminhos.
        let record = try Data(contentsOf: app.appendingPathComponent("Contents/Resources/Build.json"))
        let identity = SHA256.hash(data: rawInfo + record).map { String(format: "%02x", $0) }.joined()
        let destination = root.appendingPathComponent(identity)
        if fm.fileExists(atPath: destination.appendingPathComponent("complete.json").path) {
            try verify(destination.appendingPathComponent(app.lastPathComponent))
            return destination
        }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let stage = root.appendingPathComponent(".backup-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        let copy = stage.appendingPathComponent(app.lastPathComponent)
        try run("/usr/bin/ditto", ["--norsrc", app.path, copy.path])
        try verify(copy)
        let metadata: [String: String] = ["version": version, "build": build, "source": app.path,
                                        "created": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: stage.appendingPathComponent("complete.json"), options: .atomic)
        try fm.moveItem(at: stage, to: destination)
        return destination
    }

    static func verify(_ app: URL) throws {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    private static func run(_ command: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BTP", code: Int(process.terminationStatus), userInfo:
                [NSLocalizedDescriptionKey: "Não foi possível guardar e conferir a versão anterior. A atualização foi interrompida; o BTP atual foi preservado."])
        }
    }
}
