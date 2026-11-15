import AppKit
import CryptoKit

/// GitHub 최신 릴리스를 확인하고, 새 버전이면 dmg를 내려받아 지금 앱 자리에 바꿔 넣은 뒤 다시 시작한다.
/// 릴리스에 함께 올린 `.sig`(Ed25519 서명)를 앱에 넣은 공개 키로 확인한다. 비밀 키는 개발자만 갖고 있어서,
/// GitHub 계정이나 다운로드 경로가 털려도 다른 파일은 설치하지 않는다(`scripts/sign-update.swift`).
/// 그 밖에 GitHub가 알려 준 SHA-256, 번들 ID와 버전, 코드 서명도 확인한다.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    static let repo = "eddieee-git/mac-app-peeky"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    /// `~/.config/peeky/update-signing.key`의 공개 키.
    nonisolated static let publicKey = "lKHkMa6qNWeTcsBM/gHZUT8bVtobjrZrSlFy4xjEExk="

    struct Release: Equatable {
        let version: String
        let dmg: URL?
        let sha256: String?
        let signature: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing(String)
        case failed(String)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @Published private(set) var state: State = .idle
    @Published var autoInstall: Bool {
        didSet { UserDefaults.standard.set(autoInstall, forKey: "autoInstallUpdates") }
    }

    private var pending: Release?
    private var timer: Timer?
    private static let lastCheckKey = "lastUpdateCheck"
    private static let updatedFromKey = "updatedFromVersion"

    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    private init() {
        autoInstall = UserDefaults.standard.object(forKey: "autoInstallUpdates") as? Bool ?? true
    }

    /// 시작할 때 한 번: 조금 뒤 확인하고, 그 뒤로 몇 시간마다 다시 본다(하루 한 번만 실제로 묻는다).
    func start() {
        announceIfUpdated()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.automaticCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 3 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in Updater.shared.automaticCheck() }
        }
    }

    private func automaticCheck() {
        guard autoInstall else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 86_400 { return }
        Task { await check(install: true) }
    }

    func checkNow() { Task { await check(install: false) } }

    func installPending() {
        guard let pending else { return }
        Task { await install(pending) }
    }

    // MARK: - 확인

    private func check(install: Bool) async {
        if case .installing = state { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Peeky", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw Failure(message: L("아직 올라온 릴리스가 없어요")) }
            guard code == 200, let release = Self.parse(data) else { throw Failure(message: L("GitHub 응답을 읽지 못했어요 (%ld)", code)) }
            guard Self.isNewer(release.version, than: currentVersion) else {
                pending = nil
                state = .upToDate
                return
            }
            pending = release
            state = .available(release.version)
            if install { await self.install(release) }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// GitHub 릴리스 응답에서 버전, 첫 dmg 첨부, 그 SHA-256과 `.sig`를 읽는다.
    nonisolated static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        let url = (dmg?["browser_download_url"] as? String).flatMap(URL.init(string:))
        var sha: String?
        if let digest = dmg?["digest"] as? String, digest.hasPrefix("sha256:") { sha = String(digest.dropFirst(7)).lowercased() }
        let sigName = (dmg?["name"] as? String).map { $0 + ".sig" }
        let sig = assets.first { $0["name"] as? String == sigName }
        let sigURL = (sig?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return Release(version: version, dmg: url, sha256: sha, signature: sigURL)
    }

    /// "0.10.0"이 "0.9.1"보다 새 것이라고 판단하도록 숫자 단위로 비교한다.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - 설치

    /// 지금 앱을 그 자리에서 바꿀 수 있는지. dmg 안에서 바로 실행 중이거나 폴더에 쓸 수 없으면 안 된다.
    nonisolated static func canReplace(_ app: URL) -> Bool {
        let fm = FileManager.default
        let path = app.standardizedFileURL.path
        return path.hasSuffix(".app") && !path.hasPrefix("/Volumes/")
            && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
            && fm.isWritableFile(atPath: path)
    }

    private func install(_ release: Release) async {
        if case .installing = state { return }
        let app = Bundle.main.bundleURL
        guard Self.canReplace(app) else {
            state = .failed(L("이 위치에서는 바꿔 넣을 수 없어요. Peeky를 응용 프로그램 폴더로 옮겨 주세요"))
            return
        }
        state = .installing(release.version)
        let identifier = Bundle.main.bundleIdentifier ?? "com.eddieee.Peeky"
        do {
            let staged = try await Task.detached(priority: .userInitiated) {
                try await Self.prepare(release, replacing: app, identifier: identifier)
            }.value
            UserDefaults.standard.set(currentVersion, forKey: Self.updatedFromKey)
            ItemStore.log("update: installing \(release.version)")
            Self.swapAndRelaunch(staged: staged.app, work: staged.work, destination: app)
        } catch {
            state = .failed(error.localizedDescription)
            ItemStore.log("update failed: \(error.localizedDescription)")
        }
    }

    private func announceIfUpdated() {
        let defaults = UserDefaults.standard
        guard let from = defaults.string(forKey: Self.updatedFromKey) else { return }
        defaults.removeObject(forKey: Self.updatedFromKey)
        if from != currentVersion { state = .upToDate }
        ItemStore.log("updated from \(from) to \(currentVersion)")
    }

    nonisolated private static func prepare(_ release: Release, replacing app: URL,
                                            identifier: String) async throws -> (app: URL, work: URL) {
        guard let dmg = release.dmg, let signatureURL = release.signature else {
            throw Failure(message: L("이 릴리스에는 자동으로 설치할 파일이 없어요"))
        }
        let (downloaded, response) = try await URLSession.shared.download(from: dmg)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure(message: L("내려받지 못했어요 (HTTP %ld)", http.statusCode))
        }
        let (signature, sigResponse) = try await URLSession.shared.data(from: signatureURL)
        if let http = sigResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure(message: L("서명 파일을 내려받지 못했어요 (HTTP %ld)", http.statusCode))
        }
        let data = try Data(contentsOf: downloaded, options: .mappedIfSafe)
        guard isSigned(data, signature: signature) else {
            throw Failure(message: L("업데이트 서명이 맞지 않아요. 설치하지 않았어요"))
        }
        if let expected = release.sha256, try sha256(of: downloaded) != expected {
            throw Failure(message: L("내려받은 파일이 릴리스와 달라요. 설치하지 않았어요"))
        }

        // 바꿔 넣을 자리와 같은 디스크에 작업 폴더를 만들어, 마지막 이동이 한 번에 끝나게 한다.
        let fm = FileManager.default
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        var success = false
        defer { if !success { try? fm.removeItem(at: work) } }
        let mount = work.appendingPathComponent("mnt")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", downloaded.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path],
                failure: L("dmg를 열지 못했어요"))
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"], failure: "") }

        let new = mount.appendingPathComponent("Peeky.app")
        let info = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == identifier,
              info?["CFBundleShortVersionString"] as? String == release.version else {
            throw Failure(message: L("dmg 안의 앱이 Peeky %@가 아니에요", release.version))
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=identifier \"\(identifier)\"", new.path],
                failure: L("새 앱의 코드 서명을 확인하지 못했어요"))

        let staged = work.appendingPathComponent("Peeky.app")
        try run("/usr/bin/ditto", [new.path, staged.path], failure: L("새 앱을 복사하지 못했어요"))
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path], failure: "")
        success = true
        return (staged, work)
    }

    /// `.sig` 내용(base64)이 이 데이터에 대한 우리 키의 서명인지.
    nonisolated static func isSigned(_ data: Data, signature: Data, publicKey: String = publicKey) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let raw = Data(base64Encoded: String(decoding: signature, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return key.isValidSignature(raw, for: data)
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String], failure: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw Failure(message: failure) }
    }

    /// 앱이 끝나기를 기다렸다가 옛 앱을 치우고 새 앱을 놓은 뒤 연다. 옮기다 실패하면 옛 앱을 되돌린다.
    private static func swapAndRelaunch(staged: URL, work: URL, destination: URL) {
        let script = """
        while kill -0 "$0" 2>/dev/null; do sleep 0.2; done
        backup="$3/previous.app"
        if /bin/mv "$2" "$backup"; then
            if /bin/mv "$1" "$2"; then /bin/rm -rf "$3"; else /bin/mv "$backup" "$2"; fi
        fi
        /usr/bin/open "$2"
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, String(ProcessInfo.processInfo.processIdentifier),
                          staged.path, destination.standardizedFileURL.path, work.path]
        do {
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: work)
            return
        }
        NSApp.terminate(nil)
    }
}
