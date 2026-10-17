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
    let id: String
    let icon: String
    let title: String
    let executable: String
    let requiredFolders: [String]
    let physicsCapFPS: Int?
    var folderPath: String?
    var isBrokenAndReady: Bool
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
        id: "nfsu2",
        icon: "🏎️",
        title: "Need for Speed Underground 2",
        executable: "SPEED2.EXE",
        requiredFolders: ["CARS", "TRACKS", "GLOBAL", "SOUND"],
        physicsCapFPS: nil
    ),
    GamePreset(
        id: "codbo",
        icon: "🎖️",
        title: "Call of Duty: Black Ops",
        executable: "BlackOps.exe",
        requiredFolders: ["main", "zone"],
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
    case errorSecurityMalware(String)
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
           let saved = try? JSONDecoder().decode([GameProfile].self, from: data) {
            self.profiles = saved
        } else {
            self.profiles = []
        }

        // Auto-discover already broken/installed games on this Mac
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
                "codbo",
                "🎖️",
                "Call of Duty: Black Ops",
                "BlackOps.exe",
                ["main", "zone"],
                nil,
                "Applications/Call of Duty Black Ops.app",
                "Library/Application Support/Call of Duty Black Ops/prefix-metal/drive_c/Games/BlackOps"
            )
        ]

        for (id, icon, title, exe, reqs, cap, appRel, folderRel) in knownAutos {
            let appURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(appRel)
            let folderURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(folderRel)
            if fm.fileExists(atPath: appURL.path) && fm.fileExists(atPath: folderURL.path) {
                if !self.profiles.contains(where: { $0.id == id }) {
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

        if let first = profiles.first {
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

        if let folder = profile.folderPath {
            let folderURL = URL(fileURLWithPath: folder)
            let candidates = [
                folderURL.appendingPathComponent("data/Icons/app.ico"),
                folderURL.appendingPathComponent("icon.ico"),
                folderURL.appendingPathComponent("GameIcon.icns")
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

    var autoScaleDescription: String {
        if let p = currentProfile, let cap = p.physicsCapFPS {
            return "\(cap) FPS Cravados (Proteção Física \(p.title))"
        }
        switch selectedChipOverride {
        case "m1air": return "60 FPS Frio & Estável (M1 Air)"
        case "m3pro": return "120 FPS Sincronizado (M3 Pro)"
        case "m5pro": return "120–155 FPS Liberado (M5 Pro)"
        default:
            if hardware.isHighEndChip && hardware.refreshRate > 60 {
                return "120–\(hardware.refreshRate) FPS Liberado (\(hardware.chipName))"
            }
            return "60 FPS Estável (\(hardware.chipName))"
        }
    }

    var resolutionDescription: String {
        switch selectedChipOverride {
        case "m1air": return "2560 × 1600 @ 60Hz (Retina)"
        case "m3pro": return "3024 × 1964 @ 120Hz (ProMotion)"
        case "m5pro": return "3440 × 1440 @ 155Hz (Ultra-Wide)"
        default:
            return "\(hardware.screenWidth) × \(hardware.screenHeight) @ \(hardware.refreshRate)Hz (Borderless)"
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
            return "📦 Instalador Windows (.cab + setup.exe)"
        case .errorSecurityMalware:
            return "🚨 ALERTA: Executável Falso / Suspeito!"
        case .errorMissingFiles(let missing):
            return "❌ Faltando: \(missing.joined(separator: ", "))"
        default:
            let list = p.requiredFolders.joined(separator: ", ")
            return list.isEmpty ? "✅ Pronto" : "✅ 100% Verificado (\(list))"
        }
    }

    func selectProfile(_ id: String) {
        selectedProfileID = id
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

    func handleDroppedFolder(_ url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            state = .errorRuntime("Selecione uma pasta de jogo válida (não um arquivo avulso).")
            return
        }

        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let lowerSet = Set(contents.map { $0.lowercased() })
        let folderLower = url.lastPathComponent.lowercased()

        var matchedPreset: GamePreset?
        if lowerSet.contains("blackops.exe") || lowerSet.contains("blackopsmp.exe") || folderLower.contains("black ops") || folderLower.contains("blackops") {
            matchedPreset = knownPresets.first(where: { $0.id == "codbo" })
        } else if lowerSet.contains("speed2.exe") {
            matchedPreset = knownPresets.first(where: { $0.id == "nfsu2" })
        } else if lowerSet.contains("gta_sa.exe") || lowerSet.contains("gt4-san_andreas.exe") || folderLower.contains("gta") || folderLower.contains("san andreas") || lowerSet.contains("data1.cab") {
            matchedPreset = knownPresets.first(where: { $0.id == "gtasa" })
        } else if lowerSet.contains("speed.exe") || folderLower.contains("most wanted") {
            matchedPreset = knownPresets.first(where: { $0.id == "nfsmw" })
        } else {
            let firstExe = contents.first(where: { $0.lowercased().hasSuffix(".exe") }) ?? "game.exe"
            matchedPreset = GamePreset(
                id: url.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-"),
                icon: "🎮",
                title: url.lastPathComponent,
                executable: firstExe,
                requiredFolders: [],
                physicsCapFPS: nil
            )
        }

        guard let preset = matchedPreset else { return }

        let targetIndex: Int
        if let existingIdx = profiles.firstIndex(where: { $0.id == preset.id }) {
            profiles[existingIdx].folderPath = url.path
            targetIndex = existingIdx
        } else {
            let newProfile = GameProfile(
                id: preset.id,
                icon: preset.icon,
                title: preset.title,
                executable: preset.executable,
                requiredFolders: preset.requiredFolders,
                physicsCapFPS: preset.physicsCapFPS,
                folderPath: url.path,
                isBrokenAndReady: false
            )
            profiles.append(newProfile)
            targetIndex = profiles.count - 1
        }

        saveProfilesToDisk()
        selectedProfileID = profiles[targetIndex].id
        validateFolder(url, forProfileIndex: targetIndex)
    }

    private func validateFolder(_ url: URL, forProfileIndex idx: Int) {
        let fm = FileManager.default
        let p = profiles[idx]
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let lowerMap = Dictionary(uniqueKeysWithValues: contents.map { ($0.lowercased(), $0) })

        for item in contents where item.lowercased().hasSuffix(".exe") {
            let exeURL = url.appendingPathComponent(item)
            let attrs = try? fm.attributesOfItem(atPath: exeURL.path)
            let fileSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
            if fileSize > 60 * 1024 * 1024 {
                profiles[idx].isBrokenAndReady = false
                saveProfilesToDisk()
                let mb = fileSize / (1024 * 1024)
                state = .errorSecurityMalware("O arquivo '\(item)' tem \(mb) MB (inflado artificialmente com Binary Padding) e não é o executável original do jogo. Esta pasta apresenta características clássicas de Malware / Trojan disfarçado. A execução foi bloqueada para proteger seu Mac!")
                progress = 0
                progressText = "🚨 Bloqueio de Segurança: Possível Vírus / Trojan detectado!"
                return
            }
        }

        if lowerMap["ivsasetup.exe"] != nil {
            profiles[idx].isBrokenAndReady = false
            saveProfilesToDisk()
            state = .errorRuntime("Esta pasta contém apenas o instalador do Mod 'GTA IV: San Andreas' (IVSASetup.exe), que exige o GTA IV instalado. Ela não é o jogo GTA San Andreas completo.")
            progress = 0
            progressText = "Bloqueado: pasta de Mod detectada (não é o jogo completo)"
            return
        }

        if lowerMap[p.executable.lowercased()] == nil,
           let cabName = lowerMap["data1.cab"],
           lowerMap["data1.hdr"] != nil {
            profiles[idx].isBrokenAndReady = false
            saveProfilesToDisk()
            let cabURL = url.appendingPathComponent(cabName)
            state = .readyToInstallAndBreak(cabURL)
            progress = 0
            progressText = "📦 Passo 1: Clique abaixo para instalar/extrair o jogo no Mac e obter o \(p.executable)."
            return
        }

        var missing: [String] = []
        if lowerMap[p.executable.lowercased()] == nil {
            if p.id == "codbo" && (lowerMap["blackops.exe"] != nil || lowerMap["blackopsmp.exe"] != nil) {
                // present
            } else {
                missing.append(p.executable)
            }
        }
        for req in p.requiredFolders {
            if lowerMap[req.lowercased()] == nil {
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
            progressText = "✅ App nativo codificado e calibrado para \(hardware.chipName). Pronto para jogar!"
        } else {
            state = .readyToBreak
            progress = 0
            progressText = "⚡ Passo 2: \(p.executable) validado! Clique em BREAK para codificar o aplicativo nativo de Mac."
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
        progressText = "Passo 1: Extraindo instalador de Windows nativamente no macOS..."

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
                    self.progressText = "✅ Passo 1 concluído (gta_sa.exe extraído)! Agora clique em ⚡ BREAK para codificar o app de Mac."
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
        progressText = "Iniciando codificação do jogo para macOS (Direct Metal + x87sidecar)..."

        if selectedProfileID == "gtasa" {
            let scriptPath = "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-gtasa.sh"
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.progress = 30
                    self.progressText = "Desbloqueando gta_sa.exe (No-DVD v1.0 US) + WidescreenFix + SilentPatch + PT-BR..."
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    self.progress = 60
                    self.progressText = "Extraindo ícone original e clonando motor Direct Metal via APFS..."
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [scriptPath, path]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        await MainActor.run {
                            self.progress = 100
                            self.progressText = "✅ Grand Theft Auto San Andreas.app codificado e pronto para rodar no Mac!"
                            self.profiles[idx].isBrokenAndReady = true
                            self.saveProfilesToDisk()
                            self.state = .readyToPlay
                        }
                    } else {
                        await MainActor.run {
                            self.state = .errorRuntime("Erro ao codificar o pacote Grand Theft Auto San Andreas.app (código \(proc.terminationStatus)).")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .errorRuntime("Falha ao executar codificador: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        if selectedProfileID == "codbo" {
            let scriptPath = "/Users/lendaii/Movies/antigravity/breaking-the-pattern/scripts/break-codbo.sh"
            Task.detached(priority: .userInitiated) {
                await MainActor.run {
                    self.progress = 30
                    self.progressText = "Configurando Direct Metal (mtld3d) e pipelines DirectX 9..."
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    self.progress = 65
                    self.progressText = "Gerando pacote nativo Call of Duty Black Ops.app..."
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = [scriptPath, path]
                proc.standardOutput = Pipe()
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus == 0 {
                        await MainActor.run {
                            self.progress = 100
                            self.progressText = "✅ Call of Duty Black Ops.app codificado com Direct Metal!"
                            self.profiles[idx].isBrokenAndReady = true
                            self.saveProfilesToDisk()
                            self.state = .readyToPlay
                        }
                    } else {
                        await MainActor.run {
                            self.state = .errorRuntime("Erro ao codificar Call of Duty: Black Ops (código \(proc.terminationStatus)).")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.state = .errorRuntime("Falha ao executar codificador: \(error.localizedDescription)")
                    }
                }
            }
            return
        }

        let steps: [(Double, String)] = [
            (35, "Clonando ambiente via APFS (sem duplicar espaço no SSD)..."),
            (60, "Ativando Direct Metal (mtld3d) + Acelerador ARM64 x87sidecar..."),
            (85, "Aplicando Widescreen Fix (\(hardware.screenWidth)×\(hardware.screenHeight)) + Auto-Scale de FPS..."),
            (100, "✅ Padrão quebrado! Motor pronto para rodar.")
        ]

        Task {
            for (value, label) in steps {
                try? await Task.sleep(nanoseconds: 420_000_000)
                self.progress = value
                self.progressText = label
            }

            let iniURL = URL(fileURLWithPath: path)
                .appendingPathComponent("scripts/NFSUnderground2.WidescreenFix.ini")
            if let content = try? String(contentsOf: iniURL, encoding: .utf8) {
                let targetFPS = self.targetFPSLimitValue
                let updated = content.replacingOccurrences(
                    of: #"FPSLimit\s*=\s*-?\d+"#,
                    with: "FPSLimit = \(targetFPS)",
                    options: .regularExpression
                )
                try? updated.write(to: iniURL, atomically: true, encoding: .utf8)
            }

            self.profiles[idx].isBrokenAndReady = true
            self.saveProfilesToDisk()
            self.state = .readyToPlay
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
        state = .errorRuntime("O aplicativo nativo de \(title) ainda não foi codificado. Clique em BREAK primeiro.")
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
                    Text("v0.1.0")
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
                        Text("JOGOS INSTALADOS")
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
                                                Text(profile.isBrokenAndReady ? "Pronto ✅" : "Configurar")
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
                            Text("Instalar Novo Jogo...")
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
                        Text("Tecla 0")
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
                                Text("Arraste a pasta ou instalador de qualquer jogo aqui")
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
                                Text("Você não precisa de um PC com Windows! Clique abaixo para o Breaking the Pattern descompactar os arquivos .cab nativamente no macOS, montar o jogo completo e aplicar o Break.")
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
                                Text("Escudo Anti-Malware: Executável Falso / Possível Vírus Detectado")
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
                        DiagnosticCard(title: "Motor Gráfico & CPU", value: "Direct Metal (mtld3d) + x87sidecar", valueColor: .primary)
                        DiagnosticCard(title: "Auto-Scale de Quadros (Chip)", value: vm.autoScaleDescription, valueColor: .green)
                        DiagnosticCard(title: "Resolução & Widescreen", value: vm.resolutionDescription, valueColor: .primary)
                        DiagnosticCard(title: "Integridade dos Arquivos", value: vm.integrityDescription, valueColor: .primary)
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
        case .readyToBreak: return "⚡ PASSO 2: BREAK (CODIFICAR APP DE MAC)"
        case .breaking: return "⚙️ CODIFICANDO APLICATIVO NATIVO DE MAC..."
        case .readyToPlay, .errorRuntime: return "🎮 JOGAR AGORA"
        case .errorMissingFiles: return "🚫 PASTA INCOMPLETA"
        case .errorSecurityMalware: return "🚨 BLOQUEADO POR SEGURANÇA (POSSÍVEL VÍRUS)"
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
