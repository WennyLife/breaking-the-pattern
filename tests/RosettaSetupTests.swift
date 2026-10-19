import Foundation

@main
struct RosettaSetupTests {
    static func main() throws {
        let helper = URL(fileURLWithPath: "/fixture/RosettaInstaller.app")
        var requested = false
        try BTPRosettaSetup.install(helper: helper, probe: { true }, request: { _ in requested = true })
        precondition(!requested, "An installed Rosetta must not open the installer")

        var checks = 0
        try BTPRosettaSetup.install(helper: helper, probe: {
            checks += 1
            return checks > 1
        }, request: { url in
            precondition(url == helper)
            requested = true
        })
        precondition(requested && checks == 2, "Installation must be followed by an execution check")

        do {
            try BTPRosettaSetup.install(helper: helper, probe: { false }, request: { _ in })
            fatalError("A closed/cancelled installer must not resume preparation")
        } catch {
            precondition(error.localizedDescription.contains("TENTAR NOVAMENTE"))
        }

        do {
            try BTPRosettaSetup.install(helper: helper, probe: { false }, request: { _ in
                throw NSError(domain: "fixture", code: 9)
            })
            fatalError("An installation error must not resume preparation")
        } catch {
            precondition((error as NSError).domain == "fixture")
        }

        do {
            try BTPRosettaSetup.requestInstallation(helper)
            fatalError("An absent helper must produce a recoverable error")
        } catch {
            precondition(error.localizedDescription.contains("pacote oficial"))
        }
        print("Rosetta gate: existing, install/recheck, cancellation, launch error, missing helper passed")
    }
}
