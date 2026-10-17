import AppKit
import Foundation

// Launcher genérico dos apps gerados pelo BTP. Lê de Info.plist a pasta de dados
// (BTPDataFolder) e chama Resources/launch-game.sh, como os launchers por jogo faziam.
final class BTPGameLauncher: NSObject, NSApplicationDelegate {
    private var child: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else {
            NSApp.terminate(nil)
            return
        }
        let fm = FileManager.default
        let folder = Bundle.main.object(forInfoDictionaryKey: "BTPDataFolder") as? String
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "BTP Game")
        let dataURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(folder)
        try? fm.createDirectory(at: dataURL.appendingPathComponent("Registros"), withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [
            resources.appendingPathComponent("launch-game.sh").path,
            resources.path,
            dataURL.path
        ]
        proc.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        do {
            try proc.run()
            child = proc
        } catch {
            NSApp.terminate(nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = BTPGameLauncher()
app.delegate = delegate
app.run()
