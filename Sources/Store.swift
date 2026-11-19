import SwiftUI
import AppKit

// MARK: - Модели

struct BlockedApp: Codable, Hashable, Identifiable {
    var name: String
    var bundleID: String
    var id: String { bundleID }
}

enum TimerOption: String, CaseIterable, Identifiable {
    case unlimited, m15, m25, m30, m45, h1, h2, h4
    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimited: return "Без ограничения"
        case .m15: return "15 минут"
        case .m25: return "25 минут"
        case .m30: return "30 минут"
        case .m45: return "45 минут"
        case .h1: return "1 час"
        case .h2: return "2 часа"
        case .h4: return "4 часа"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .unlimited: return nil
        case .m15: return 15 * 60
        case .m25: return 25 * 60
        case .m30: return 30 * 60
        case .m45: return 45 * 60
        case .h1: return 3600
        case .h2: return 7200
        case .h4: return 14400
        }
    }
}

// MARK: - Значения по умолчанию

private let defaultSites = [
    "instagram.com", "youtube.com", "youtu.be", "m.youtube.com",
    "tiktok.com", "facebook.com", "twitter.com", "x.com",
    "reddit.com", "twitch.tv", "netflix.com", "vk.com",
    "web.telegram.org", "t.me", "open.spotify.com"
]

private let defaultApps = [
    BlockedApp(name: "Telegram", bundleID: "ru.keepcoder.Telegram"),
    BlockedApp(name: "Telegram Desktop", bundleID: "org.telegram.desktop"),
    BlockedApp(name: "Spotify", bundleID: "com.spotify.client")
]

private let markerStart = "# >>> FCS >>>"
private let markerEnd = "# <<< FCS <<<"
// Маркеры прошлой версии (FocusBlock) — чистим при первом включении/выключении
private let legacyMarkers = [("# >>> FocusBlock >>>", "# <<< FocusBlock <<<")]

private let supportDir = "/Library/Application Support/FCS"

// MARK: - Хранилище и логика

final class FCSStore: ObservableObject {
    static let shared = FCSStore()

    @Published var sites: [String]
    @Published var apps: [BlockedApp]
    @Published var isActive: Bool
    @Published var endDate: Date?
    @Published var duration: TimerOption = .unlimited {
        didSet { defaults.set(duration.rawValue, forKey: "duration") }
    }
    @Published var screen: Screen = .focus
    @Published var showAdd = false
    @Published var busy = false
    @Published var errorText: String?
    @Published private(set) var now = Date()

    private let defaults = UserDefaults.standard
    private var tick: Timer?
    private var launchObserver: NSObjectProtocol?

    var totalBlocks: Int { sites.count + apps.count }

    /// Оставшееся время для таймера (nil — без ограничения)
    var remaining: TimeInterval? {
        guard isActive, let end = endDate else { return nil }
        return max(0, end.timeIntervalSince(now))
    }

    private init() {
        let d = UserDefaults.standard
        sites = d.stringArray(forKey: "sites") ?? defaultSites
        if let data = d.data(forKey: "apps"),
           let decoded = try? JSONDecoder().decode([BlockedApp].self, from: data) {
            apps = decoded
        } else {
            apps = defaultApps
        }
        isActive = d.bool(forKey: "active")
        let ts = d.double(forKey: "endDate")
        endDate = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        if let raw = d.string(forKey: "duration"), let o = TimerOption(rawValue: raw) {
            duration = o
        }

        // Если таймер истёк, пока приложение было закрыто, — root-процесс уже снял блок
        if isActive, let end = endDate, end <= Date() {
            isActive = false
            endDate = nil
            persist()
        }

        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        if isActive { startAppGuard() }
    }

    // MARK: Действия

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !busy else { return }
        let end = duration.seconds.map { Date().addingTimeInterval($0) }
        run(active: true, end: end) {
            self.isActive = true
            self.endDate = end
            self.persist()
            self.startAppGuard()
        }
    }

    func stop() {
        guard !busy else { return }
        run(active: false, end: nil) {
            self.isActive = false
            self.endDate = nil
            self.persist()
            self.stopAppGuard()
        }
    }

    /// Добавить сайт. Возвращает текст ошибки или nil.
    @discardableResult
    func addSite(_ raw: String) -> String? {
        guard let host = Self.normalize(raw) else { return "Введите корректный адрес сайта, например example.com" }
        if sites.contains(host) { return "Этот сайт уже в списке" }
        sites.append(host)
        persist()
        if isActive { reapplyHosts() }
        return nil
    }

    func addApp(_ app: BlockedApp) -> String? {
        if apps.contains(where: { $0.bundleID == app.bundleID }) { return "Это приложение уже в списке" }
        apps.append(app)
        persist()
        if isActive { killBlockedApps() }
        return nil
    }

    func removeSite(_ site: String) {
        guard !isActive else { return }
        sites.removeAll { $0 == site }
        persist()
    }

    func removeApp(_ app: BlockedApp) {
        guard !isActive else { return }
        apps.removeAll { $0 == app }
        persist()
    }

    // MARK: Внутреннее

    private func persist() {
        defaults.set(sites, forKey: "sites")
        defaults.set(try? JSONEncoder().encode(apps), forKey: "apps")
        defaults.set(isActive, forKey: "active")
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: "endDate")
        defaults.set(duration.rawValue, forKey: "duration")
    }

    private func onTick() {
        now = Date()
        if isActive { killBlockedApps() } // страховка: ловим запуск между уведомлениями
        if isActive, let end = endDate, end <= now {
            // root-процесс снимет блок сам; здесь только обновляем состояние
            isActive = false
            endDate = nil
            persist()
            stopAppGuard()
        }
    }

    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let slash = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard s.contains("."), !s.hasPrefix("."), !s.hasSuffix("."),
              s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return s
    }

    // MARK: Блокировка приложений

    private func startAppGuard() {
        stopAppGuard()
        killBlockedApps()
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.killBlockedApps() }
    }

    private func stopAppGuard() {
        if let o = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        launchObserver = nil
    }

    private func killBlockedApps() {
        let ids = Set(apps.map { $0.bundleID })
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, ids.contains(id) { app.forceTerminate() }
        }
    }

    // MARK: Блокировка сайтов (/etc/hosts, нужен пароль администратора)

    private func reapplyHosts() {
        run(active: true, end: endDate) { }
    }

    private func run(active: Bool, end: Date?, onSuccess: @escaping () -> Void) {
        busy = true
        errorText = nil
        let sitesSnapshot = sites
        DispatchQueue.global().async {
            let result = Self.applyHosts(active: active, sites: sitesSnapshot, end: end)
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success: onSuccess()
                case .failure(let e): self.errorText = e.localizedDescription
                }
            }
        }
    }

    private static func applyHosts(active: Bool, sites: [String], end: Date?) -> Result<Void, Error> {
        let current = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""

        // 1. «Чистый» hosts без наших блоков
        var markers = [(markerStart, markerEnd)]
        markers.append(contentsOf: legacyMarkers)
        var clean: [String] = []
        var endMarker: String?
        for line in current.components(separatedBy: "\n") {
            if let m = markers.first(where: { $0.0 == line }) { endMarker = m.1; continue }
            if let e = endMarker { if line == e { endMarker = nil }; continue }
            clean.append(line)
        }
        while clean.last == "" { clean.removeLast() }
        let cleanText = clean.joined(separator: "\n") + "\n"

        // 2. hosts с блоком
        var blocked = clean
        blocked.append("")
        blocked.append(markerStart)
        for d in sites {
            for host in [d, "www." + d] {
                blocked.append("0.0.0.0 \(host)")
                blocked.append("::1 \(host)")
            }
        }
        blocked.append(markerEnd)
        let blockedText = blocked.joined(separator: "\n") + "\n"

        // 3. Временные файлы и скрипт, который выполнится от root
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "fcs-" + UUID().uuidString
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try cleanText.write(toFile: dir + "/hosts.clean", atomically: true, encoding: .utf8)
            try blockedText.write(toFile: dir + "/hosts.blocked", atomically: true, encoding: .utf8)

            let timerScript = """
            #!/bin/sh
            END="$1"
            D="\(supportDir)"
            while [ "$(date +%s)" -lt "$END" ]; do sleep 5; done
            cp "$D/hosts.clean" /etc/hosts
            dscacheutil -flushcache
            killall -HUP mDNSResponder
            rm -f "$D/timer.pid"
            """
            try timerScript.write(toFile: dir + "/timer.sh", atomically: true, encoding: .utf8)

            var apply = """
            #!/bin/sh
            D="\(supportDir)"
            mkdir -p "$D"
            if [ -f "$D/timer.pid" ]; then
              kill "$(cat "$D/timer.pid")" 2>/dev/null
              rm -f "$D/timer.pid"
            fi
            """
            if active {
                apply += "\ncp '\(dir)/hosts.clean' \"$D/hosts.clean\""
                apply += "\ncp '\(dir)/hosts.blocked' /etc/hosts"
            } else {
                apply += "\ncp '\(dir)/hosts.clean' /etc/hosts"
            }
            apply += "\ndscacheutil -flushcache\nkillall -HUP mDNSResponder"
            if active, let end = end {
                apply += "\ncp '\(dir)/timer.sh' \"$D/timer.sh\""
                apply += "\nnohup /bin/sh \"$D/timer.sh\" \(Int(end.timeIntervalSince1970)) >/dev/null 2>&1 &"
                apply += "\necho $! > \"$D/timer.pid\""
            }
            apply += "\nexit 0\n"
            try apply.write(toFile: dir + "/apply.sh", atomically: true, encoding: .utf8)
        } catch { return .failure(error) }

        defer { try? fm.removeItem(atPath: dir) }

        let osa = "do shell script \"/bin/sh '\(dir)/apply.sh'\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", osa]
        let err = Pipe()
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
        } catch { return .failure(error) }

        if p.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = msg.contains("-128") || msg.contains("canceled")
                ? "Действие отменено."
                : "Не удалось изменить блокировку сайтов. \(msg)"
            return .failure(NSError(domain: "FCS", code: 1, userInfo: [NSLocalizedDescriptionKey: text]))
        }
        return .success(())
    }
}
