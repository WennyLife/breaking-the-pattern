import AppKit
import SwiftUI
import Sparkle

@MainActor
final class BTPUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = BTPUpdates()
    @Published var showSettings = false
    @Published var isPreparingGame = false
    @Published var automaticChecks = true
    private var controller: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
            DispatchQueue.main.async { self?.automaticChecks = change.newValue ?? false }
        }
    }

    func setAutomaticChecks(_ value: Bool) { controller.updater.automaticallyChecksForUpdates = value }
    func check() { showSettings = false; controller.checkForUpdates(nil) }
    @objc func showUpdates() { showSettings = true }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isPreparingGame {
            throw NSError(domain: "BTP", code: 2, userInfo:
                [NSLocalizedDescriptionKey: L("Aguarde a preparação do jogo terminar para atualizar o BTP.")])
        }
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        // O backup é condição da atualização, inclusive quando a verificação é automática.
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Breaking the Pattern/Backups/Updates")
        do { _ = try BTPUpdateBackup.preserve(app: Bundle.main.bundleURL, root: root) }
        catch { throw NSError(domain: "BTP", code: 3, userInfo: [NSLocalizedDescriptionKey: L(error.localizedDescription)]) }
    }
}

struct BTPUpdatesView: View {
    @ObservedObject var updates: BTPUpdates
    @ObservedObject private var language = BTPLanguage.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 28)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    BTPText("Atualizações do BTP").font(.title2.bold())
                    BTPText("Instalado: BTP \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                BTPText("Novas soluções para os seus jogos").font(.headline)
                BTPText("Receba correções e novos perfis pelo próprio BTP. Você escolhe quando baixar e instalar.")
                BTPText("Seus jogos, configurações e saves são preservados. A versão anterior do BTP fica guardada em backup.")
                    .foregroundStyle(.secondary)
            }.padding(18).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            Toggle(L("Verificar atualizações automaticamente"), isOn: Binding(
                get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
            HStack {
                Button(L("Fechar")) { updates.showSettings = false }
                Spacer()
                Button(L("Verificar atualizações")) { updates.check() }.buttonStyle(.borderedProminent).tint(.green)
                    .disabled(updates.isPreparingGame)
            }
        }.padding(28).frame(width: 500).preferredColorScheme(.dark)
            .environment(\.locale, Locale(identifier: language.code))
    }
}
