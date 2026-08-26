import Foundation
import AppUpdater
import Combine
import Darwin

private final class ScreenSageGithubProxy: URLRequestProxy {
    override func apply(to urlString: String) -> String {
        "https://github-api-proxy.screensage.pro?url=\(urlString)"
    }
}

@main
struct Runner {
    static func main() async {
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        if args.contains("--live-screensage") {
            await runLiveScreenSageUpdateCheck()
            return
        }

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

    private static func runLiveScreenSageUpdateCheck() async {
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
        case unexpectedAsset(String)
        case invalidSignature
        case unexpectedSigningIdentity(String)
        case missingExecutable
        case unexpectedArchitecture(app: String, pi: String)
        case missingDownloadedState
        case fileInspectionFailed(String)
    }
}
