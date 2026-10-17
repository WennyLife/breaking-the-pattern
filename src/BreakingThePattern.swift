import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

// MARK: - Hardware Detector (Apple Silicon & Display Auto-Scale)
struct HardwareInfo {
    let chipName: String
    let cpuCores: Int
    let ramGB: Int
    let screenWidth: Int
    let screenHeight: Int
    let refreshRate: Int

    var isHighEndChip: Bool {
        let lower = chipName.lowercased()
        return lower.contains("pro") || lower.contains("max") || lower.contains("ultra") || lower.contains("m4") || lower.contains("m5")
    }

    static func detect() -> HardwareInfo {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = "Apple Silicon"
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            brand = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var cores: Int32 = 8
        var coresSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &cores, &coresSize, nil, 0)

        let ram = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))

        let screen = NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let hz = screen?.maximumFramesPerSecond ?? 60

        return HardwareInfo(
            chipName: brand,
            cpuCores: Int(cores),
            ramGB: ram,
            screenWidth: Int(frame.width),
            screenHeight: Int(frame.height),
            refreshRate: hz
        )
    }
}

// MARK: - Game Profile Definition
struct GameProfile: Identifiable, Equatable, Codable {
    var id: String
    var icon: String
    var title: String
    var executable: String
    var requiredFolders: [String]
    var physicsCapFPS: Int?
    var folderPath: String?
    var isBrokenAndReady: Bool // Preparation state only; gameplay validation is separate.
}

struct GamePreset {
    let id: String
    let icon: String
    let title: String
    let executable: String
    let requiredFolders: [String]
    let physicsCapFPS: Int?
}

let knownPresets: [GamePreset] = [
    GamePreset(
        id: "gtasa",
        icon: "🔫",
        title: "Grand Theft Auto: San Andreas",
        executable: "gta_sa.exe",
        requiredFolders: ["anim", "audio", "data", "models"],
        physicsCapFPS: 60
    ),
    GamePreset(
        id: "codbo2",
        icon: "🎖️",
        title: "Call of Duty: Black Ops II",
        executable: "t6sp.exe",
        requiredFolders: ["zone"],
        physicsCapFPS: nil
    ),
    GamePreset(
        id: "codbo",
        icon: "🎖️",
        title: "Call of Duty: Black Ops",
        executable: "BlackOps.exe",
        requiredFolders: ["zone"],
        physicsCapFPS: nil
    ),
    GamePreset(
        id: "nfsu2",
        icon: "🏎️",
        title: "Need for Speed Underground 2",
        executable: "SPEED2.EXE",
        requiredFolders: ["CARS", "TRACKS", "GLOBAL", "SOUND"],
        physicsCapFPS: nil
    ),
    GamePreset(
        id: "nfsmw",
        icon: "🚓",
        title: "Need for Speed: Most Wanted",
        executable: "speed.exe",
        requiredFolders: ["CARS", "TRACKS", "GLOBAL", "SOUND"],
        physicsCapFPS: nil
    )
]

enum BreakState: Equatable {
    case empty
    case readyToBreak
    case readyToInstallAndBreak(URL)
    case breaking
    case readyToPlay
    case errorMissingFiles([String])
    case errorRuntime(String)
    case errorSecurityMalware(String) // Legacy state identifier; no size-based malware detection.
}

struct DiscoveredGame {
    let rootURL: URL
    let matchedPreset: GamePreset?
    let executable: String
    let isInstaller: Bool
    let installerURL: URL?
}

// MARK: - Main ViewModel
@MainActor
final class BTPViewModel: ObservableObject {
    @Published var hardware = HardwareInfo.detect()
    @Published var selectedChipOverride: String = "auto"
    @Published var profiles: [GameProfile] = []
    @Published var selectedProfileID: String = ""
    @Published var state: BreakState = .empty
    @Published var progress: Double = 0.0
    @Published var progressText: String = "Nenhum jogo instalado ainda. Arraste uma pasta ou clique abaixo."
    @Published var isGameRunning: Bool = false
    @Published var isDropTargeted: Bool = false

    private var appSupportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Breaking the Pattern")
    }

    private var libraryFileURL: URL {
        appSupportURL.appendingPathComponent("installed_games.json")
    }

    init() {
        loadProfilesFromDisk()
    }

    private func loadProfilesFromDisk() {
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: libraryFileURL),
           var saved = try? JSONDecoder().decode([GameProfile].self, from: data) {
            // Upgrade legacy or incorrect profiles if needed
            for i in 0..<saved.count {
                if saved[i].id == "codbo" && (saved[i].folderPath?.contains("Black Ops II") == true || saved[i].folderPath?.contains("Black_Ops_II") == true) {
                    saved[i].id = "codbo2"
                    saved[i].title = "Call of Duty: Black Ops II"
                    saved[i].executable = "t6sp.exe"
                    saved[i].requiredFolders = ["zone"]
                }
            }
            self.profiles = saved
        } else {
            self.profiles = []
        }

        // Discover prepared app bundles; their presence does not validate gameplay.
        let knownAutos: [(String, String, String, String, [String], Int?, String, String)] = [
            (
                "gtasa",
                "🔫",
                "Grand Theft Auto: San Andreas",
                "gta_sa.exe",
                ["anim", "audio", "data", "models"],
                60,
                "Applications/Grand Theft Auto San Andreas.app",
                "Library/Application Support/Breaking the Pattern/Games/GTA San Andreas"
            ),
            (
                "nfsu2",
                "🏎️",
                "Need for Speed Underground 2",
                "SPEED2.EXE",
                ["CARS", "TRACKS", "GLOBAL", "SOUND"],
                nil,
                "Applications/Need for Speed Underground 2.app",
                "Library/Application Support/Need for Speed Underground 2/Game"
            ),
            (
                "codbo2",
                "🎖️",
                "Call of Duty: Black Ops II",
                "t6sp.exe",
                ["zone"],
                nil,
                "Applications/Call of Duty Black Ops II.app",
                "Downloads/Call_of_Duty_Black_Ops_II/Call of Duty Black Ops II"
            )
        ]

        for (id, icon, title, exe, reqs, cap, appRel, folderRel) in knownAutos {
            let appURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(appRel)
            let folderURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(folderRel)
            if fm.fileExists(atPath: appURL.path) && fm.fileExists(atPath: folderURL.path) {
                if let existingIdx = self.profiles.firstIndex(where: { $0.id == id }) {
                    self.profiles[existingIdx].isBrokenAndReady = true
                    self.profiles[existingIdx].folderPath = folderURL.path
                    self.profiles[existingIdx].executable = exe
                } else {
                    self.profiles.append(GameProfile(
                        id: id,
                        icon: icon,
                        title: title,
                        executable: exe,
                        requiredFolders: reqs,
                        physicsCapFPS: cap,
                        folderPath: folderURL.path,
                        isBrokenAndReady: true
                    ))
                }
            }
        }

        saveProfilesToDisk()

        if let last = UserDefaults.standard.string(forKey: "btp_last_selected_profile"),
           profiles.contains(where: { $0.id == last }) {
            selectProfile(last)
        } else if let unconfigured = profiles.first(where: { !$0.isBrokenAndReady }) {
            selectProfile(unconfigured.id)
        } else if let first = profiles.first {
            selectProfile(first.id)
        } else {
            selectedProfileID = ""
            state = .empty
            progress = 0
            progressText = "Nenhum jogo instalado ainda. Arraste uma pasta ou clique abaixo."
        }
    }

    private func saveProfilesToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: libraryFileURL, options: .atomic)
        }
    }

    func iconImage(for profile: GameProfile) -> NSImage? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let appNames: [String] = {
            switch profile.id {
            case "gtasa": return ["Grand Theft Auto San Andreas.app"]
            case "nfsu2": return ["Need for Speed Underground 2.app"]
            case "codbo2": return ["Call of Duty Black Ops II.app", "Call of Duty Black Ops.app"]
            case "codbo": return ["Call of Duty Black Ops.app"]
            case "nfsmw": return ["Need for Speed Most Wanted.app"]
            default: return ["\(profile.title).app"]
            }
        }()

        for name in appNames {
            let appURL = home.appendingPathComponent("Applications/\(name)")
            if fm.fileExists(atPath: appURL.path) {
                let icnsURL = appURL.appendingPathComponent("Contents/Resources/GameIcon.icns")
                if fm.fileExists(atPath: icnsURL.path), let img = NSImage(contentsOf: icnsURL) {
                    return img
                }
                let fullIcns = appURL.appendingPathComponent("Contents/Resources/GameIconFull.icns")
                if fm.fileExists(atPath: fullIcns.path), let img = NSImage(contentsOf: fullIcns) {
                    return img
                }
                let img = NSWorkspace.shared.icon(forFile: appURL.path)
                img.size = NSSize(width: 128, height: 128)
                return img
            }
        }

        // Bundled icon fallback (shown even before Break)
        let bundledName: String? = {
            switch profile.id {
            case "gtasa": return "GTASAGameIcon"
            case "nfsu2": return "NFSU2GameIcon"
            case "codbo2": return "CODBO2GameIcon"
            case "codbo": return "CODBO2GameIcon"
            default: return nil
            }
        }()
        if let bName = bundledName {
            if let path = Bundle.main.path(forResource: bName, ofType: "icns"),
               let img = NSImage(contentsOfFile: path) {
                return img
            }
            let devPath = "/Users/lendaii/Movies/antigravity/breaking-the-pattern/src/\(bName).icns"
            if let img = NSImage(contentsOfFile: devPath) {
                return img
            }
        }

        if let folder = profile.folderPath {
            let folderURL = URL(fileURLWithPath: folder)
            let candidates = [
                folderURL.appendingPathComponent("GameIcon.icns"),
                folderURL.appendingPathComponent("data/Icons/app.ico"),
                folderURL.appendingPathComponent("icon.ico")
            ]
            for c in candidates {
                if fm.fileExists(atPath: c.path), let img = NSImage(contentsOf: c) {
                    return img
                }
            }
        }

        return nil
    }

    var currentProfile: GameProfile? {
        profiles.first(where: { $0.id == selectedProfileID }) ?? profiles.first
    }

    var chipSummaryText: String {
        switch selectedChipOverride {
        case "m5pro": return "Apple M5 Pro • 3440×1440 @ 155Hz"
        case "m3pro": return "Apple M3 Pro • ProMotion @ 120Hz"
        case "m1air": return "MacBook Air M1 • Retina @ 60Hz"
        default:
            return "\(hardware.chipName) • \(hardware.screenWidth)×\(hardware.screenHeight) @ \(hardware.refreshRate)Hz"
        }
    }

    var targetFPSLimitValue: Int {
        if currentProfile?.executable.lowercased().hasSuffix("conviction_game.exe") == true {
            return 60
        }
        if let cap = currentProfile?.physicsCapFPS {
            return cap
        }
        switch selectedChipOverride {
        case "m1air": return 60
        case "m3pro": return 120
        case "m5pro": return 0
        default:
            if hardware.isHighEndChip && hardware.refreshRate > 60 {
                return 0
            }
            return 60
        }
    }

    // A suggested limit is configuration guidance, not a performance measurement.
    var autoScaleDescription: String {
        if let cap = currentProfile?.physicsCapFPS {
            return "Limite sugerido: \(cap) FPS"
        }
        let limit = targetFPSLimitValue
        return limit == 0 ? "Sem limite sugerido; medir no jogo" : "Limite sugerido: \(limit) FPS"
    }

    var resolutionDescription: String {
        switch selectedChipOverride {
        case "m1air": return "Referência: 2560 × 1600 @ 60Hz"
        case "m3pro": return "Referência: 3024 × 1964 @ 120Hz"
        case "m5pro": return "Referência: 3440 × 1440 @ 155Hz"
        default:
            return "\(hardware.screenWidth) × \(hardware.screenHeight) pt · \(hardware.refreshRate)Hz"
        }
    }

    var integrityDescription: String {
        guard let p = currentProfile else {
            return "Nenhum jogo selecionado"
        }
        switch state {
        case .empty:
            return "Aguardando pasta do jogo..."
        case .readyToInstallAndBreak:
            return "📦 Instalador Windows Detectado"
        case .errorSecurityMalware:
            return "Arquivo requer revisão"
        case .errorMissingFiles(let missing):
            return "❌ Faltando: \(missing.joined(separator: ", "))"
        case .errorRuntime:
            return "Revisar aviso de execução"
        default:
            return "Itens exigidos presentes: \(p.executable)"
        }
    }

    func selectProfile(_ id: String) {
        selectedProfileID = id
        UserDefaults.standard.set(id, forKey: "btp_last_selected_profile")
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        let p = profiles[idx]
        if let path = p.folderPath {
            validateFolder(URL(fileURLWithPath: path), forProfileIndex: idx)
        } else {
            state = .empty
            progress = 0
            progressText = "Arraste a pasta de \(p.title) ou clique no quadro tracejado"
        }
    }

    func removeProfile(_ id: String) {
        profiles.removeAll(where: { $0.id == id })
        saveProfilesToDisk()
        if selectedProfileID == id {
            if let first = profiles.first {
                selectProfile(first.id)
            } else {
                selectedProfileID = ""
                state = .empty
                progress = 0
                progressText = "Nenhum jogo instalado ainda. Arraste uma pasta ou clique abaixo."
            }
        }
    }

    func chooseFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Selecione a pasta do jogo Windows"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            handleDroppedFolder(url)
        }
    }

    func discoverGame(at url: URL) -> DiscoveredGame {
        let fm = FileManager.default
        var candidateDirs: [URL] = [url]

        // Inspect subdirectories up to 2 levels deep
        if let subdirs = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for sub in subdirs {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                    candidateDirs.append(sub)
                    if let subsubdirs = try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                        for subsub in subsubdirs {
                            var isSubDir: ObjCBool = false
                            if fm.fileExists(atPath: subsub.path, isDirectory: &isSubDir), isSubDir.boolValue {
                                candidateDirs.append(subsub)
                            }
                        }
                    }
                }
            }
        }

        // 1. Look for known game executables
        for dir in candidateDirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let lowerMap = Dictionary(uniqueKeysWithValues: contents.map { ($0.lowercased(), $0) })

            // Check for Call of Duty: Black Ops II (t6sp.exe, t6mp.exe, t6zm.exe)
            if lowerMap["t6sp.exe"] != nil || lowerMap["t6mp.exe"] != nil {
                let exe = lowerMap["t6sp.exe"] ?? lowerMap["t6mp.exe"] ?? "t6sp.exe"
                let preset = knownPresets.first(where: { $0.id == "codbo2" })!
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: exe, isInstaller: false, installerURL: nil)
            }

            // Check for Call of Duty: Black Ops 1 (BlackOps.exe)
            if lowerMap["blackops.exe"] != nil || lowerMap["blackopsmp.exe"] != nil {
                let exe = lowerMap["blackops.exe"] ?? lowerMap["blackopsmp.exe"] ?? "BlackOps.exe"
                let preset = knownPresets.first(where: { $0.id == "codbo" })!
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: exe, isInstaller: false, installerURL: nil)
            }

            // Check for Grand Theft Auto: San Andreas (gta_sa.exe)
            if lowerMap["gta_sa.exe"] != nil || lowerMap["gt4-san_andreas.exe"] != nil {
                let exe = lowerMap["gta_sa.exe"] ?? "gta_sa.exe"
                let preset = knownPresets.first(where: { $0.id == "gtasa" })!
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: exe, isInstaller: false, installerURL: nil)
            }

            // Check for Need for Speed Underground 2 (SPEED2.EXE)
            if lowerMap["speed2.exe"] != nil {
                let exe = lowerMap["speed2.exe"] ?? "SPEED2.EXE"
                let preset = knownPresets.first(where: { $0.id == "nfsu2" })!
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: exe, isInstaller: false, installerURL: nil)
            }

            // Check for Need for Speed: Most Wanted (speed.exe)
            if lowerMap["speed.exe"] != nil {
                let exe = lowerMap["speed.exe"] ?? "speed.exe"
                let preset = knownPresets.first(where: { $0.id == "nfsmw" })!
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: exe, isInstaller: false, installerURL: nil)
            }
        }

        // 2. Check for Windows Installer (setup.exe + data1.cab)
        for dir in candidateDirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let lowerMap = Dictionary(uniqueKeysWithValues: contents.map { ($0.lowercased(), $0) })
            let dirLower = dir.lastPathComponent.lowercased()

            if let cab = lowerMap["data1.cab"], lowerMap["data1.hdr"] != nil {
                let cabURL = dir.appendingPathComponent(cab)
                let isGTA = dirLower.contains("gta") || dirLower.contains("san andreas") || contents.contains(where: { $0.lowercased().contains("gta") })
                let preset = isGTA ? knownPresets.first(where: { $0.id == "gtasa" }) : nil
                return DiscoveredGame(rootURL: dir, matchedPreset: preset, executable: preset?.executable ?? "gta_sa.exe", isInstaller: true, installerURL: cabURL)
            }
        }

        // 3. Fallback: escolhe o .exe principal de qualquer jogo pelo ranking de candidatos.
        //    O caminho fica relativo à pasta arrastada, para que o BREAK leve a pasta inteira
        //    (jogos com o .exe em bin/ ou Binaries/Win32/ precisam dos dados da pasta de cima).
        if let best = rankGameExecutables(in: url).first {
            let cleanTitle = url.lastPathComponent.replacingOccurrences(of: "_", with: " ")
            let preset = GamePreset(
                id: url.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-"),
                icon: "🎮",
                title: cleanTitle,
                executable: best,
                requiredFolders: [],
                physicsCapFPS: nil
            )
            return DiscoveredGame(rootURL: url, matchedPreset: preset, executable: best, isInstaller: false, installerURL: nil)
        }

        // 4. Default generic
        let fallbackTitle = url.lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let genericPreset = GamePreset(
            id: url.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-"),
            icon: "🎮",
            title: fallbackTitle,
            executable: "game.exe",
            requiredFolders: [],
            physicsCapFPS: nil
        )
        return DiscoveredGame(rootURL: url, matchedPreset: genericPreset, executable: "game.exe", isInstaller: false, installerURL: nil)
    }

    /// Lista os .exe da pasta (até 4 níveis), do mais provável para o menos provável de ser o jogo.
    /// Descarta instaladores, redistribuíveis, launchers e reportadores de crash; entre os
    /// restantes, pesa tamanho do arquivo, semelhança com o nome da pasta e profundidade.
    func rankGameExecutables(in folder: URL) -> [String] {
        let fm = FileManager.default
        let root = folder.resolvingSymlinksInPath()
        let skip = ["setup", "install", "unins", "redist", "vcredist", "vc_redist", "dxsetup", "dxwebsetup",
                    "directx", "dotnet", "physx", "oalinst", "crash", "report", "launcher", "updater",
                    "config", "settings", "ue4prereq", "easyanticheat", "battleye", "touchup", "cleanup"]
        let folderWords = root.lastPathComponent.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 }
        var scored: [(String, Double)] = []
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        for case let file as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            let name = file.lastPathComponent.lowercased()
            guard name.hasSuffix(".exe"), !skip.contains(where: { name.contains($0) }) else { continue }
            let rel = String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            let lowRel = rel.lowercased()
            if lowRel.contains("redist") || lowRel.contains("directx") { continue }
            let size = Double((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var score = log2(max(size, 1))
            let stem = String(name.dropLast(4))
            if folderWords.contains(where: { stem.contains($0) || $0.contains(stem) }) { score += 6 }
            score -= Double(walker.level - 1) * 0.5
            scored.append((rel, score))
        }
        return scored.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    func handleDroppedFolder(_ url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            state = .errorRuntime("Selecione uma pasta de jogo válida (não um arquivo avulso).")
            return
        }

        let discovered = discoverGame(at: url)
        let rootURL = discovered.rootURL
        guard let preset = discovered.matchedPreset else { return }

        let targetIndex: Int
        if let existingIdx = profiles.firstIndex(where: { $0.id == preset.id || ($0.id == "codbo" && preset.id == "codbo2") }) {
            profiles[existingIdx].id = preset.id
            profiles[existingIdx].title = preset.title
            profiles[existingIdx].icon = preset.icon
            profiles[existingIdx].executable = discovered.executable
            profiles[existingIdx].requiredFolders = preset.requiredFolders
            profiles[existingIdx].folderPath = rootURL.path
            targetIndex = existingIdx
        } else {
            let newProfile = GameProfile(
                id: preset.id,
                icon: preset.icon,
                title: preset.title,
                executable: discovered.executable,
                requiredFolders: preset.requiredFolders,
                physicsCapFPS: preset.physicsCapFPS,
                folderPath: rootURL.path,
                isBrokenAndReady: false
            )
            profiles.append(newProfile)
            targetIndex = profiles.count - 1
        }

        saveProfilesToDisk()
        selectedProfileID = profiles[targetIndex].id

        if discovered.isInstaller, let cabURL = discovered.installerURL {
            state = .readyToInstallAndBreak(cabURL)
            progress = 0
            progressText = "📦 Passo 1: Clique abaixo para instalar/extrair o jogo no Mac e obter o executável principal."
        } else {
            validateFolder(rootURL, forProfileIndex: targetIndex)
        }
    }

    private func validateFolder(_ url: URL, forProfileIndex idx: Int) {
        let fm = FileManager.default
        let p = profiles[idx]
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let lowerMap = Dictionary(uniqueKeysWithValues: contents.map { ($0.lowercased(), $0) })

        // These checks establish only that expected paths are present.
        // Executable size alone cannot establish authenticity or detect malware.

        if lowerMap["ivsasetup.exe"] != nil {
            profiles[idx].isBrokenAndReady = false
            saveProfilesToDisk()
            state = .errorRuntime("Esta pasta contém apenas o instalador do Mod 'GTA IV: San Andreas' (IVSASetup.exe), que exige o GTA IV instalado.")
            progress = 0
            progressText = "Bloqueado: pasta de Mod detectada (não é o jogo completo)"
            return
        }

        // Detect Windows InstallShield DVD Installer (setup.exe + data1.cab + data1.hdr)
        if lowerMap[p.executable.lowercased()] == nil,
           let cabName = lowerMap["data1.cab"],
           lowerMap["data1.hdr"] != nil {
            profiles[idx].isBrokenAndReady = false
            saveProfilesToDisk()
            let cabURL = url.appendingPathComponent(cabName)
            state = .readyToInstallAndBreak(cabURL)
            progress = 0
            progressText = "📦 Passo 1: Clique abaixo para instalar/extrair o jogo no Mac e obter o executável principal."
            return
        }

        // Check if executable is present (directly or dynamically resolved)
        var executablePresent = false
        if lowerMap[p.executable.lowercased()] != nil || fm.fileExists(atPath: url.appendingPathComponent(p.executable).path) {
            executablePresent = true
        } else if p.id == "codbo2" && (lowerMap["t6sp.exe"] != nil || lowerMap["t6mp.exe"] != nil) {
            executablePresent = true
            profiles[idx].executable = lowerMap["t6sp.exe"] ?? lowerMap["t6mp.exe"]!
            saveProfilesToDisk()
        } else if p.id == "codbo" && (lowerMap["blackops.exe"] != nil || lowerMap["blackopsmp.exe"] != nil) {
            executablePresent = true
        }

        var missing: [String] = []
        if !executablePresent {
            missing.append(p.executable)
        }

        for req in p.requiredFolders {
            if lowerMap[req.lowercased()] == nil {
                // If zone/ is missing, check if it's zone/common or case insensitive
                missing.append("\(req)/")
            }
        }

        if !missing.isEmpty {
            profiles[idx].isBrokenAndReady = false
            saveProfilesToDisk()
            state = .errorMissingFiles(missing)
            progress = 0
            progressText = "Bloqueado: corrija os arquivos ausentes antes do Break"
        } else if profiles[idx].isBrokenAndReady {
            state = .readyToPlay
            progress = 100
            progressText = "✅ App preparado. Abra o jogo para testar compatibilidade e FPS."
        } else {
            state = .readyToBreak
            progress = 0
            progressText = "⚡ Passo 2: \(profiles[idx].executable) encontrado. Clique em BREAK para preparar o app."
        }
    }

    func performInstallAndBreak(cabURL: URL) {
        guard let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }) else { return }
        let installerDir = cabURL.deletingLastPathComponent()
        let fm = FileManager.default
        let targetDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Breaking the Pattern/Games/GTA San Andreas")

        let bundledUnshield = Bundle.main.path(forResource: "unshield", ofType: nil)
            ?? "/Users/lendaii/Movies/antigravity/breaking-the-pattern/bin/unshield"

        guard fm.isExecutableFile(atPath: bundledUnshield) else {
            state = .errorRuntime("Motor extrator 'unshield' não encontrado no pacote do app.")
            return
        }

        state = .breaking
        progress = 5
        progressText = "Passo 1: Extraindo arquivos do instalador Windows no Mac..."

        let groups: [(String, Double, String)] = [
            ("GTA SA EXECUTABLE", 15, "Extraindo executável principal (gta_sa.exe) do data1.cab..."),
            ("Root Data", 25, "Extraindo bibliotecas de áudio (eax.dll, ogg.dll, vorbis.dll)..."),
            ("data", 35, "Extraindo configurações e mapas (data/)..."),
            ("text", 42, "Extraindo textos e traduções (text/)..."),
            ("anim", 55, "Extraindo animações e cutscenes (anim/ - 280 MB)..."),
            ("audio", 65, "Extraindo bancos de som (audio/SFX e CONFIG)..."),
            ("movies", 72, "Extraindo vídeos de abertura (movies/)..."),
            ("models", 88, "Extraindo modelos 3D e texturas (models/gta3.img - 1.2 GB)...")
        ]

        Task.detached(priority: .userInitiated) {
            do {
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

                for (group, pct, label) in groups {
                    await MainActor.run {
                        self.progress = pct
                        self.progressText = label
                    }
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: bundledUnshield)
                    proc.arguments = ["-g", group, "-d", targetDir.path, "x", cabURL.path]
                    proc.standardOutput = Pipe()
                    proc.standardError = Pipe()
                    try proc.run()
                    proc.waitUntilExit()
                }

                await MainActor.run {
                    self.progress = 95
                    self.progressText = "Organizando gta_sa.exe e clonando rádios/áudio via APFS..."
                }

                let extractedExe = targetDir.appendingPathComponent("GTA_SA_EXECUTABLE/gta_sa.exe")
                let finalExe = targetDir.appendingPathComponent("gta_sa.exe")
                if fm.fileExists(atPath: extractedExe.path) {
                    try? fm.removeItem(at: finalExe)
                    try fm.moveItem(at: extractedExe, to: finalExe)
                    try? fm.removeItem(at: targetDir.appendingPathComponent("GTA_SA_EXECUTABLE"))
                }

                let rootDataDir = targetDir.appendingPathComponent("Root_Data")
                if let rootItems = try? fm.contentsOfDirectory(atPath: rootDataDir.path) {
                    for item in rootItems {
                        let src = rootDataDir.appendingPathComponent(item)
                        let dst = targetDir.appendingPathComponent(item)
                        try? fm.removeItem(at: dst)
                        try? fm.moveItem(at: src, to: dst)
                    }
                    try? fm.removeItem(at: rootDataDir)
                }

                let srcAudio = installerDir.appendingPathComponent("audio")
                let dstAudio = targetDir.appendingPathComponent("audio")
                if fm.fileExists(atPath: srcAudio.path) {
                    try? fm.createDirectory(at: dstAudio, withIntermediateDirectories: true)
                    if let subItems = try? fm.contentsOfDirectory(atPath: srcAudio.path) {
                        for sub in subItems {
                            let s = srcAudio.appendingPathComponent(sub)
                            let d = dstAudio.appendingPathComponent(sub)
                            if !fm.fileExists(atPath: d.path) {
                                let cp = Process()
                                cp.executableURL = URL(fileURLWithPath: "/bin/cp")
                                cp.arguments = ["-Rc", s.path, d.path]
                                try? cp.run()
                                cp.waitUntilExit()
                            }
                        }
                    }
                }

                await MainActor.run {
                    self.progress = 0
                    self.progressText = "✅ gta_sa.exe extraído. Clique em ⚡ BREAK para preparar o app."
                    self.profiles[idx].folderPath = targetDir.path
                    self.profiles[idx].isBrokenAndReady = false
                    self.saveProfilesToDisk()
                    self.state = .readyToBreak
                }
            } catch {
                await MainActor.run {
                    self.state = .errorRuntime("Falha ao extrair instalador Windows: \(error.localizedDescription)")
                }
            }
        }
    }

    func performBreak() {
        guard let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }),
              let path = profiles[idx].folderPath else { return }

        state = .breaking
        progress = 15
        progressText = "Preparando BTP HyperMetal + Neural (Metal e x87)..."

        if selectedProfileID == "gtasa" {
            let scriptPath = Bundle.main.path(forResource: "break-gtasa", ofType: "sh")
                ?? "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-gtasa.sh"
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.progress = 30
                    self.progressText = "Preparando o perfil GTA SA e os componentes de compatibilidade..."
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    self.progress = 60
                    self.progressText = "Preparando ícone e cópias APFS, quando disponíveis..."
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [scriptPath, path]
                let logURL = URL(fileURLWithPath: "/tmp/btp_break_gtasa.log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    proc.standardOutput = handle
                    proc.standardError = handle
                }
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        await MainActor.run {
                            self.progress = 100
                            self.progressText = "✅ GTA San Andreas.app preparado. Teste o jogo com limite de 60 FPS."
                            self.profiles[idx].isBrokenAndReady = true
                            self.saveProfilesToDisk()
                            self.state = .readyToPlay
                        }
                    } else {
                        let errLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                        await MainActor.run {
                            self.state = .errorRuntime("Erro ao preparar o pacote GTA San Andreas: \(errLog.suffix(200))")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .errorRuntime("Falha ao executar preparação: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        if selectedProfileID == "codbo2" {
            let scriptPath = Bundle.main.path(forResource: "break-codbo2", ofType: "sh")
                ?? "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-codbo2.sh"
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.progress = 30
                    self.progressText = "Configurando o perfil BTP HyperMetal para teste..."
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    self.progress = 65
                    self.progressText = "Preparando Call of Duty Black Ops II.app..."
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [scriptPath, path]
                let logURL = URL(fileURLWithPath: "/tmp/btp_break_codbo2.log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    proc.standardOutput = handle
                    proc.standardError = handle
                }
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        await MainActor.run {
                            self.progress = 100
                            self.progressText = "✅ Black Ops II.app preparado. Jogabilidade ainda precisa de teste."
                            self.profiles[idx].isBrokenAndReady = true
                            self.saveProfilesToDisk()
                            self.state = .readyToPlay
                        }
                    } else {
                        let errLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                        await MainActor.run {
                            self.state = .errorRuntime("Erro ao preparar Call of Duty: Black Ops II: \(errLog.suffix(200))")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .errorRuntime("Falha ao executar preparação: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        if selectedProfileID == "codbo" {
            let scriptPath = Bundle.main.path(forResource: "break-codbo", ofType: "sh")
                ?? "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-codbo.sh"
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.progress = 30
                    self.progressText = "Configurando o perfil BTP HyperMetal para teste..."
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    self.progress = 65
                    self.progressText = "Preparando Call of Duty Black Ops.app..."
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [scriptPath, path]
                let logURL = URL(fileURLWithPath: "/tmp/btp_break_codbo.log")
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    proc.standardOutput = handle
                    proc.standardError = handle
                }
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        await MainActor.run {
                            self.progress = 100
                            self.progressText = "✅ Black Ops.app preparado. Jogabilidade ainda precisa de teste."
                            self.profiles[idx].isBrokenAndReady = true
                            self.saveProfilesToDisk()
                            self.state = .readyToPlay
                        }
                    } else {
                        let errLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                        await MainActor.run {
                            self.state = .errorRuntime("Erro ao preparar Call of Duty: Black Ops: \(errLog.suffix(200))")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .errorRuntime("Falha ao executar preparação: \(error.localizedDescription)")
                    }
                }
            }
            return
        }


        // Qualquer outro jogo: BREAK genérico (analisa o .exe, escolhe o motor gráfico e gera o .app).
        let scriptPath = Bundle.main.path(forResource: "break-game", ofType: "sh")
            ?? "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-game.sh"
        let title = profiles[idx].title
        let executable = profiles[idx].executable
        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath, "--title", title, "--game-dir", path, "--exe", executable]
            let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("btp_break_generic.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            let logHandle = try? FileHandle(forWritingTo: logURL)
            // Cada linha "[n/5] ..." do script vira o texto e a porcentagem da barra.
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                logHandle?.write(chunk)
                let text = String(decoding: chunk, as: UTF8.self)
                for line in text.split(separator: "\n") {
                    guard line.hasPrefix("["), let slash = line.firstIndex(of: "/"),
                          let step = Double(line[line.index(after: line.startIndex)..<slash]) else { continue }
                    let label = line.split(separator: "]", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    Task { @MainActor in
                        self.progress = 15 + step / 5 * 80
                        self.progressText = label
                    }
                }
            }
            do {
                try proc.run()
                proc.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    await MainActor.run {
                        self.progress = 100
                        self.progressText = "✅ \(title).app preparado. Valide a jogabilidade ao abrir."
                        self.profiles[idx].isBrokenAndReady = true
                        self.saveProfilesToDisk()
                        self.state = .readyToPlay
                    }
                } else {
                    let errLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                    await MainActor.run {
                        self.state = .errorRuntime("Erro ao preparar \(title): \(errLog.suffix(300))")
                    }
                }
            } catch {
                await MainActor.run {
                    self.state = .errorRuntime("Falha ao executar preparação: \(error.localizedDescription)")
                }
            }
        }
    }

    func launchGame() {
        let fm = FileManager.default
        let appName: String
        switch selectedProfileID {
        case "nfsu2":
            appName = "Need for Speed Underground 2.app"
        case "gtasa":
            appName = "Grand Theft Auto San Andreas.app"
        case "codbo2":
            appName = "Call of Duty Black Ops II.app"
        case "codbo":
            appName = "Call of Duty Black Ops.app"
        case "nfsmw":
            appName = "Need for Speed Most Wanted.app"
        default:
            appName = "\(currentProfile?.title ?? "Game").app"
        }

        let installedApp = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/\(appName)")
        if fm.fileExists(atPath: installedApp.path) {
            NSWorkspace.shared.openApplication(at: installedApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    Task { @MainActor in
                        self.state = .errorRuntime("Não foi possível iniciar o jogo: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        let title = currentProfile?.title ?? "jogo"
        state = .errorRuntime("O aplicativo de \(title) ainda não foi preparado. Clique em BREAK primeiro.")
    }
}

// MARK: - SwiftUI Interface (Original Sleek Dark Layout with Real Game Icons)
struct ContentView: View {
    @StateObject private var vm = BTPViewModel()

    private var headerIconImage: NSImage? {
        if let p = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: p) {
            return img
        }
        return NSImage(contentsOfFile: "/Users/lendaii/Movies/antigravity/breaking-the-pattern/src/AppIcon.png")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Header Bar
            HStack {
                HStack(spacing: 8) {
                    if let nsImg = headerIconImage {
                        Image(nsImage: nsImg)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text("⚡")
                            .font(.system(size: 16))
                    }
                    Text("BREAKING THE PATTERN")
                        .font(.system(size: 14, weight: .bold))
                    Text("v0.1.2")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Chip detectado:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $vm.selectedChipOverride) {
                        Text("\(vm.hardware.chipName) • \(vm.hardware.screenWidth)×\(vm.hardware.screenHeight) @ \(vm.hardware.refreshRate)Hz").tag("auto")
                        Text("Simular: Apple M5 Pro (155Hz)").tag("m5pro")
                        Text("Simular: Apple M3 Pro (120Hz)").tag("m3pro")
                        Text("Simular: MacBook Air M1 (60Hz)").tag("m1air")
                    }
                    .labelsHidden()
                    .frame(width: 280)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main 2-Column Split
            HStack(spacing: 0) {
                // Left Sidebar
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("BIBLIOTECA DE JOGOS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !vm.profiles.isEmpty {
                            Text("\(vm.profiles.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 4)

                    if vm.profiles.isEmpty {
                        VStack(spacing: 8) {
                            Spacer().frame(height: 12)
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("Nenhum jogo instalado")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Arraste uma pasta aqui ou clique abaixo para instalar.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                            Spacer().frame(height: 12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundStyle(Color.primary.opacity(0.12))
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 8) {
                                ForEach(vm.profiles) { profile in
                                    HStack(spacing: 6) {
                                        Button {
                                            vm.selectProfile(profile.id)
                                        } label: {
                                            HStack(spacing: 8) {
                                                if let img = vm.iconImage(for: profile) {
                                                    Image(nsImage: img)
                                                        .resizable()
                                                        .interpolation(.high)
                                                        .scaledToFit()
                                                        .frame(width: 26, height: 26)
                                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                                                } else {
                                                    Text(profile.icon)
                                                        .font(.system(size: 18))
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(profile.title)
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                    Text("Executável (\(profile.executable))")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text(profile.isBrokenAndReady ? "Preparado" : "Configurar")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color(nsColor: .controlBackgroundColor))
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            vm.removeProfile(profile.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary.opacity(0.6))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remover da lista")
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(vm.selectedProfileID == profile.id
                                                  ? Color.accentColor.opacity(0.16)
                                                  : Color(nsColor: .controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(vm.selectedProfileID == profile.id
                                                    ? Color.accentColor.opacity(0.6)
                                                    : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    Button {
                        vm.chooseFolderWithPanel()
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Adicionar Jogo...")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    Spacer()

                    Divider()

                    HStack {
                        Text("HUD de FPS no jogo:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("⌘ ⌥ 9")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    // Sleek Native PayPal & GitHub links
                    HStack(spacing: 6) {
                        Button {
                            if let url = URL(string: "https://www.paypal.com/donate/?business=uildsonaraujo@gmail.com&currency_code=BRL") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("☕")
                                Text("Doar PayPal")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let url = URL(string: "https://github.com/WennyLife/breaking-the-pattern") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("⭐")
                                Text("GitHub")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15)))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .frame(width: 255)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))

                Divider()

                // Right Workspace Area
                VStack(alignment: .leading, spacing: 14) {
                    // Top Dashed Drop Zone
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                vm.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.22),
                                style: StrokeStyle(lineWidth: 2, dash: [6])
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )

                        if let profile = vm.currentProfile, let path = profile.folderPath {
                            HStack(spacing: 14) {
                                if let img = vm.iconImage(for: profile) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                                } else {
                                    Text(profile.icon)
                                        .font(.system(size: 26))
                                        .frame(width: 44, height: 44)
                                        .background(Color(nsColor: .windowBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(profile.title)
                                            .font(.system(size: 14, weight: .bold))
                                        Text(profile.executable)
                                            .font(.system(size: 11, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(nsColor: .windowBackgroundColor))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Button("Trocar Pasta") {
                                    vm.chooseFolderWithPanel()
                                }
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 16)
                        } else if let profile = vm.currentProfile {
                            VStack(spacing: 6) {
                                if let img = vm.iconImage(for: profile) {
                                    Image(nsImage: img)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Text(profile.icon)
                                        .font(.system(size: 26))
                                }
                                Text("Arraste a pasta de \(profile.title) aqui")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Ou clique aqui para selecionar a pasta no Finder (\(profile.executable))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                        } else {
                            VStack(spacing: 6) {
                                Text("📂")
                                    .font(.system(size: 26))
                                Text("Arraste a pasta do jogo ou do instalador aqui")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Ou clique aqui para selecionar a pasta no Finder")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                        }
                    }
                    .frame(height: 86)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.chooseFolderWithPanel()
                    }
                    .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url {
                                Task { @MainActor in
                                    vm.handleDroppedFolder(url)
                                }
                            }
                        }
                        return true
                    }

                    // Diagnostic Banner
                    if case .readyToInstallAndBreak = vm.state {
                        HStack(alignment: .top, spacing: 10) {
                            Text("📦")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Instalador de Windows Detectado (setup.exe + data1.cab)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.cyan)
                                Text("O BTP tentará extrair os arquivos desta mídia no Mac. O suporte depende do instalador; depois, prepare o app e teste a jogabilidade.")
                                    .font(.system(size: 11))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                    } else if case .errorSecurityMalware(let msg) = vm.state {
                        HStack(alignment: .top, spacing: 10) {
                            Text("🚨")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Arquivo requer revisão")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red)
                                Text(msg)
                                    .font(.system(size: 11))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.18)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.55), lineWidth: 1.5))
                    } else if case .errorMissingFiles(let missing) = vm.state {
                        HStack(alignment: .top, spacing: 10) {
                            Text("⚠️")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Pasta Incompleta Detectada Antes do Break")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red)
                                Text("Faltam os seguintes itens obrigatórios na pasta: \(missing.joined(separator: ", ")). Selecione a pasta completa do jogo para continuar.")
                                    .font(.system(size: 11))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.35), lineWidth: 1))
                    } else if case .errorRuntime(let msg) = vm.state {
                        HStack(alignment: .top, spacing: 10) {
                            Text("🛡️")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Aviso do Vigia de Execução")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.orange)
                                Text(msg)
                                    .font(.system(size: 11))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    }

                    // 2x2 Diagnostic Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DiagnosticCard(title: "Motor Gráfico & CPU", value: "BTP HyperMetal + Neural", valueColor: .primary)
                            .help("Rótulos BTP para componentes de compatibilidade: Wine, Rosetta, tradução gráfica para Metal e x87sidecar. Não indicam uso do Neural Engine da Apple.")
                        DiagnosticCard(title: "Limite sugerido · FPS não medido", value: vm.autoScaleDescription, valueColor: .green)
                            .help("Sugestão do perfil, sem garantia de desempenho ou de aplicação automática. Confirme a configuração e meça o FPS durante a partida.")
                        DiagnosticCard(title: "Tela detectada / Referência", value: vm.resolutionDescription, valueColor: .primary)
                            .help("A tela detectada é expressa em pontos lógicos do macOS. A resolução de renderização e a tela cheia são configuradas e verificadas no jogo.")
                        DiagnosticCard(title: "Presença dos arquivos", value: vm.integrityDescription, valueColor: .primary)
                            .help("Verifica a presença dos caminhos exigidos pelo perfil. Não autentica os arquivos nem realiza uma análise de malware.")
                    }

                    Spacer()

                    // Progress Bar & Main CTA Button
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(vm.progressText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(vm.progress))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        ProgressView(value: vm.progress, total: 100)
                            .progressViewStyle(.linear)

                        Button {
                            switch vm.state {
                            case .readyToBreak:
                                vm.performBreak()
                            case .readyToInstallAndBreak(let cabURL):
                                vm.performInstallAndBreak(cabURL: cabURL)
                            case .readyToPlay, .errorRuntime:
                                vm.launchGame()
                            case .empty:
                                vm.chooseFolderWithPanel()
                            default:
                                break
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(buttonLabel)
                                    .font(.system(size: 14, weight: .bold))
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(buttonColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(isButtonDisabled)

                        if case .readyToPlay = vm.state {
                            HStack {
                                Spacer()
                                Button {
                                    vm.performBreak()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("⚡")
                                        Text("Preparar novamente com BTP HyperMetal")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 780, height: 470)
    }

    private var buttonLabel: String {
        switch vm.state {
        case .empty: return "📂 SELECIONAR PASTA DO JOGO"
        case .readyToInstallAndBreak: return "📦 PASSO 1: INSTALAR JOGO NO MAC (EXTRAIR .CAB)"
        case .readyToBreak: return "⚡ PASSO 2: BREAK (PREPARAR APP DE MAC)"
        case .breaking: return "⚙️ PREPARANDO APLICATIVO DE MAC..."
        case .readyToPlay, .errorRuntime: return "🎮 ABRIR JOGO"
        case .errorMissingFiles: return "🚫 PASTA INCOMPLETA"
        case .errorSecurityMalware: return "⚠️ REVISAR ARQUIVO"
        }
    }

    private var buttonColor: Color {
        switch vm.state {
        case .readyToBreak, .readyToInstallAndBreak, .breaking: return Color.accentColor
        case .readyToPlay, .errorRuntime: return Color.green
        case .empty: return Color.secondary
        case .errorMissingFiles: return Color.gray.opacity(0.4)
        case .errorSecurityMalware: return Color.red.opacity(0.75)
        }
    }

    private var isButtonDisabled: Bool {
        switch vm.state {
        case .breaking, .errorMissingFiles, .errorSecurityMalware: return true
        default: return false
        }
    }
}

struct DiagnosticCard: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - App Entry Point
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let iconImage = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = iconImage
        }
        let contentView = ContentView()
            .preferredColorScheme(.dark)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 470),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Breaking the Pattern"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
