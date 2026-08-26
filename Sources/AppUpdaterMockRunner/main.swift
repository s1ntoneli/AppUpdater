import Foundation
import AppUpdater
import AppKit
import Combine
import Darwin

private final class ScreenSageGithubProxy: URLRequestProxy {
    override func apply(to urlString: String) -> String {
        "https://github-api-proxy.screensage.pro?url=\(urlString)"
    }
}

@main
struct Runner {
    static func main() {
        let args = Array(ProcessInfo.processInfo.arguments.dropFirst())
        if args.contains("--live-screensage") {
            let expectedVersion = args
                .first { $0.hasPrefix("--expected-version=") }?
                .replacingOccurrences(of: "--expected-version=", with: "")
            let installDisposable = args.contains("--install-disposable")
            if installDisposable {
                let application = NSApplication.shared
                let delegate = DisposableInstallDelegate(expectedVersion: expectedVersion)
                application.delegate = delegate
                application.setActivationPolicy(.prohibited)
                application.run()
            } else {
                Task {
                    await runLiveScreenSageUpdateCheck(
                        expectedVersion: expectedVersion,
                        installDisposable: false
                    )
                    exit(0)
                }
                dispatchMain()
            }
            return
        }

        Task {
            await runMockUpdateCheck(args: args)
            exit(0)
        }
        dispatchMain()
    }

    private final class DisposableInstallDelegate: NSObject, NSApplicationDelegate {
        private let expectedVersion: String?

        init(expectedVersion: String?) {
            self.expectedVersion = expectedVersion
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            Task {
                await Runner.runLiveScreenSageUpdateCheck(
                    expectedVersion: expectedVersion,
                    installDisposable: true
                )
            }
        }
    }

    private static func runMockUpdateCheck(args: [String]) async {
        print("[MockRunner] Starting mock update check…")
        let updater = AppUpdater(owner: "mock", repo: "mock", releasePrefix: "AppUpdaterExample", interval: 24*60*60, proxy: nil, provider: MockReleaseProvider())
        updater.skipCodeSignValidation = true
        // Optional: override preferred languages via args or env `APPUPDATER_LANGS` (comma-separated)
        let env = ProcessInfo.processInfo.environment
        let langsArg: String? = args.first { $0.hasPrefix("--langs=") }?.replacingOccurrences(of: "--langs=", with: "")
            ?? env["APPUPDATER_LANGS"]
        if let langsArg, !langsArg.isEmpty {
            let langs = langsArg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            updater.preferredChangelogLanguages = langs
            print("[MockRunner] preferredChangelogLanguages = \(langs)")
        }

        var cancellables = Set<AnyCancellable>()
        updater.$state
            .sink { state in
                Task {
                switch state {
                case .none:
                    print("[MockRunner] State: none")
                case .newVersionDetected(let rel, _):
                    print("[MockRunner] Detected: v\(rel.tagName)")
                    print("[MockRunner] Assets: \(rel.assets.map { $0.name })")
                    let localized = rel.localizedBody(preferredLanguages: updater.preferredChangelogLanguages)
                    print("[MockRunner] Localized changelog:\n\(localized)\n---")
                    let attached = await updater.localizedChangelog(for: rel) ?? "<nil>"
                    print("[MockRunner] Attached changelog (resolved):\n\(attached)\n===")
                case .downloading(let rel, _, let fraction):
                    print("[MockRunner] Downloading v\(rel.tagName): \(Int(fraction*100))%")
                case .downloaded(let rel, _, _):
                    print("[MockRunner] Downloaded v\(rel.tagName)")
                }
                }
            }
            .store(in: &cancellables)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            updater.check {
                print("[MockRunner] success callback")
                cont.resume()
            } fail: { err in
                print("[MockRunner] fail callback: \(err)")
                cont.resume()
            }
        }
        print("[MockRunner] Done.")
    }

    private static func runLiveScreenSageUpdateCheck(
        expectedVersion: String?,
        installDisposable: Bool
    ) async {
#if arch(arm64)
        let expectedArchitecture = "arm64"
#elseif arch(x86_64)
        let expectedArchitecture = "x86_64"
#else
#error("The ScreenSage live update check supports only arm64 and x86_64.")
#endif

        print("[LiveRunner] Starting ScreenSage update check for \(expectedArchitecture)…")
        let updater = AppUpdater(
            owner: "ScreenSage",
            repo: "ScreenSageApp",
            releasePrefix: "ScreenSage",
            interval: 24 * 60 * 60,
            proxy: ScreenSageGithubProxy()
        )
        // The runner itself is not signed with ScreenSage's Developer ID. The
        // downloaded app is still independently required to have a valid
        // signature below.
        updater.skipCodeSignValidation = true
        updater.enableDebugInfo = true

        do {
            try await updater.checkThrowing()

            for _ in 0..<50 {
                let state = await MainActor.run { updater.state }
                if case .downloaded(let release, let asset, let bundle) = state {
                    if let expectedVersion, release.tagName.description != expectedVersion {
                        throw LiveRunnerError.unexpectedVersion(
                            expected: expectedVersion,
                            actual: release.tagName.description
                        )
                    }
                    guard asset.name == "ScreenSage-\(release.tagName)-\(expectedArchitecture).zip" else {
                        throw LiveRunnerError.unexpectedAsset(asset.name)
                    }
                    guard await bundle.codeSignatureIsValid() else {
                        throw LiveRunnerError.invalidSignature
                    }
                    let signingDescription = try codeSigningDescription(at: bundle.bundleURL)
                    let expectedAuthority = "Authority=Developer ID Application: Nanjing Zuimeijia Technology Co., Ltd. (JDZMWLF652)"
                    let expectedTeam = "TeamIdentifier=JDZMWLF652"
                    guard signingDescription.contains(expectedAuthority),
                          signingDescription.contains(expectedTeam) else {
                        throw LiveRunnerError.unexpectedSigningIdentity(signingDescription)
                    }
                    guard let executableURL = bundle.executableURL else {
                        throw LiveRunnerError.missingExecutable
                    }

                    let appDescription = try fileDescription(at: executableURL)
                    let piURL = bundle.bundleURL
                        .appendingPathComponent("Contents/Resources/PiRuntime/pi")
                    let piDescription = try fileDescription(at: piURL)
                    let expectedDescription = "Mach-O 64-bit executable \(expectedArchitecture)"
                    guard appDescription.contains(expectedDescription),
                          piDescription.contains(expectedDescription) else {
                        throw LiveRunnerError.unexpectedArchitecture(
                            app: appDescription,
                            pi: piDescription
                        )
                    }

                    print("[LiveRunner] Selected: \(asset.name)")
                    print("[LiveRunner] Downloaded: \(asset.downloadUrl.absoluteString)")
                    print("[LiveRunner] App: \(appDescription)")
                    print("[LiveRunner] Pi: \(piDescription)")
                    print("[LiveRunner] Signature: valid, JDZMWLF652")
                    print("[LiveRunner] PASS")

                    if installDisposable {
                        try validateDisposableInstallTarget()
                        print("[LiveRunner] Installing into disposable bundle: \(Bundle.main.bundleURL.path)")
                        fflush(stdout)
                        try await MainActor.run {
                            try updater.installThrowing(bundle)
                        }
                    }
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            throw LiveRunnerError.missingDownloadedState
        } catch {
            fputs("[LiveRunner] FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func fileDescription(at url: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = [url.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let description = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw LiveRunnerError.fileInspectionFailed(description)
        }
        return description
    }

    private static func validateDisposableInstallTarget() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let allowedPath = environment["APPUPDATER_DISPOSABLE_INSTALL_BUNDLE"] else {
            throw LiveRunnerError.unsafeInstallTarget("missing APPUPDATER_DISPOSABLE_INSTALL_BUNDLE")
        }

        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let allowedURL = URL(fileURLWithPath: allowedPath).standardizedFileURL
        guard bundleURL == allowedURL,
              bundleURL.pathExtension == "app",
              !bundleURL.path.hasPrefix("/Applications/") else {
            throw LiveRunnerError.unsafeInstallTarget(bundleURL.path)
        }
    }

    private static func codeSigningDescription(at url: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--verbose=4", url.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let description = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw LiveRunnerError.fileInspectionFailed(description)
        }
        return description
    }

    private enum LiveRunnerError: Error {
        case unexpectedVersion(expected: String, actual: String)
        case unexpectedAsset(String)
        case invalidSignature
        case unexpectedSigningIdentity(String)
        case unsafeInstallTarget(String)
        case missingExecutable
        case unexpectedArchitecture(app: String, pi: String)
        case missingDownloadedState
        case fileInspectionFailed(String)
    }
}
