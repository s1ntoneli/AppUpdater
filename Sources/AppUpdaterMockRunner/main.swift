import Foundation
import AppUpdater
import Combine

@main
struct Runner {
    static func main() async {
        print("[MockRunner] Starting mock update check…")
        let updater = AppUpdater(owner: "mock", repo: "mock", releasePrefix: "AppUpdaterExample", interval: 24*60*60, proxy: nil, provider: MockReleaseProvider())
        updater.skipCodeSignValidation = true
        // Optional: override preferred languages via args or env `APPUPDATER_LANGS` (comma-separated)
        let args = ProcessInfo.processInfo.arguments.dropFirst()
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
}
