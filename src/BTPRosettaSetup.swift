import Foundation

// LaunchServices presents Apple's own installer for this Intel-only helper.
// BTP never downloads Rosetta binaries or accepts Apple's licence on behalf of the user.
enum BTPRosettaSetup {
    static func isAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-x86_64", "/usr/bin/true"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }

    static func install(helper: URL,
                        probe: () -> Bool = isAvailable,
                        request: (URL) throws -> Void = requestInstallation) throws {
        if probe() { return }
        try request(helper)
        guard probe() else {
            throw failure("O Rosetta ainda não está disponível. A instalação pode ter sido cancelada. Clique em TENTAR NOVAMENTE para instalar e continuar.")
        }
    }

    static func requestInstallation(_ helper: URL) throws {
        let executable = helper.appendingPathComponent("Contents/MacOS/BTPRosettaRequest")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw failure("O componente de instalação do Rosetta não foi encontrado. Reinstale o BTP pelo pacote oficial.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", "-n", helper.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(600)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard !process.isRunning else {
            process.terminate() // Only our `open` waiter, never Apple's installer.
            throw failure("A instalação do Rosetta está demorando. Conclua o aviso do macOS e clique em TENTAR NOVAMENTE.")
        }
        // `open` can report a launch failure after showing the installer. The
        // caller checks actual x86 execution, not a launch status or a receipt.
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "BTP.Rosetta", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
