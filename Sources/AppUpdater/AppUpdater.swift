//
//  AppUpdaterGithub.swift
//  SecureYourClipboard
//
//  Created by lixindong on 2024/4/26.
//

import Foundation
import class AppKit.NSBackgroundActivityScheduler
import var AppKit.NSApp
import Foundation
import Version
import Path

public class AppUpdater: ObservableObject {
    public typealias OnSuccess = () -> Void
    public typealias OnFail = (Swift.Error) -> Void

    let activity: NSBackgroundActivityScheduler
    let owner: String
    let repo: String
    let releasePrefix: String

    var slug: String {
        return "\(owner)/\(repo)"
    }
    
    var proxy: URLRequestProxy?
    public var provider: ReleaseProvider
    
    @available(*, deprecated, message: "This variable is deprecated. Use state instead.")
    @Published public var downloadedAppBundle: Bundle?
    
    /// update state
    @MainActor
    @Published public var state: UpdateState = .none
    
    /// all releases
    @MainActor
    @Published public var releases: [Release] = []

    /// last error captured for diagnostics
    @MainActor
    @Published public var lastError: Swift.Error?

    /// in-app debug traces for UI diagnostics
    @MainActor
    @Published public var debugInfo: [String] = []

    public var onDownloadSuccess: OnSuccess? = nil
    public var onDownloadFail: OnFail? = nil
    
    public var onInstallSuccess: OnSuccess? = nil
    public var onInstallFail: OnFail? = nil
    
    public var allowPrereleases = false
    /// Whether to append debug traces into `debugInfo` for UI
    public var enableDebugInfo = false
    /// Skip code signing validation (useful for mock/testing).
    public var skipCodeSignValidation = false
    
    /// Preferred languages when selecting a localized changelog from a release body.
    /// Default uses system preferred languages.
    public var preferredChangelogLanguages: [String] = Locale.preferredLanguages
    
    private var progressTimer: Timer? = nil
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForRequest = 3 * 60
        
        return URLSession(configuration: config)
    }()

    public init(owner: String, repo: String, releasePrefix: String? = nil, interval: TimeInterval = 24 * 60 * 60, proxy: URLRequestProxy? = nil, provider: ReleaseProvider = GithubReleaseProvider()) {
        self.owner = owner
        self.repo = repo
        self.releasePrefix = releasePrefix ?? repo
        self.proxy = proxy
        self.provider = provider

        activity = NSBackgroundActivityScheduler(identifier: "AppUpdater.\(Bundle.main.bundleIdentifier ?? "")")
        activity.repeats = true
        activity.interval = interval
        activity.schedule { [unowned self] completion in
            guard !self.activity.shouldDefer else {
                return completion(.deferred)
            }
            self.check(success: { [self] in
                self.onDownloadSuccess?()
                completion(.finished)
            }, fail: { [self] err in
                self.onDownloadFail?(err)
                completion(.finished)
            })
        }
    }

    deinit {
        activity.invalidate()
    }

    public enum Error: Swift.Error {
        case bundleExecutableURL
        case codeSigningIdentity
        case invalidDownloadedBundle
        case noValidUpdate
        case unzipFailed
        case downloadFailed
    }
    
    public func check(success: OnSuccess? = nil, fail: OnFail? = nil) {
        Task {
            do {
                try await checkThrowing()
                success?()
            } catch {
                trace("check failed:", String(describing: error))
                Task { @MainActor in self.lastError = error }
                fail?(error)
            }
        }
    }
    
    public func install(success: OnSuccess? = nil, fail: OnFail? = nil) {
        guard let appBundle = downloadedAppBundle else {
            fail?(Error.invalidDownloadedBundle)
            return
        }
        install(appBundle, success: success, fail: fail)
    }

    public func install(_ appBundle: Bundle, success: OnSuccess? = nil, fail: OnFail? = nil) {
        do {
            try installThrowing(appBundle)
            success?()
            onInstallSuccess?()
        } catch {
            fail?(error)
            onInstallFail?(error)
        }
    }

    public func checkThrowing() async throws {
        trace("begin check for", slug)
        guard Bundle.main.executableURL != nil else {
            throw Error.bundleExecutableURL
        }
        let currentVersion = Bundle.main.version

        func validate(codeSigning b1: Bundle, _ b2: Bundle) async throws -> Bool {
            do {
                let csi1 = try? await b1.codeSigningIdentity()
                let csi2 = try? await b2.codeSigningIdentity()

                if csi1 == nil || csi2 == nil {
                    return skipCodeSignValidation
                }
                trace("compairing current: \(csi1) downloaded: \(csi2) equals? \(csi1 == csi2)")
                return skipCodeSignValidation || (csi1 == csi2)
            }
        }

        func update(with asset: Release.Asset, belongs release: Release) async throws -> Bundle? {
            aulog("notice: AppUpdater dry-run:", asset)
            trace("update start:", release.tagName.description, asset.name)

            let tmpdir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Bundle.main.bundleURL, create: true)

            let downloadState = try await provider.download(asset: asset, to: tmpdir.appendingPathComponent("download"), proxy: proxy)
            
            var dst: URL? = nil
            for try await state in downloadState {
                switch state {
                case .progress(let progress):
                    trace("downloading", Int(progress.fractionCompleted * 100), "%")
                    DispatchQueue.main.async {
                        self.progressTimer?.invalidate()
                        self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                            self.notifyStateChanged(newState: .downloading(release, asset, fraction: progress.fractionCompleted))
                        }
                    }

                    break
                case .finished(let saveLocation, _):
                    trace("download finished at", saveLocation.path)
                    dst = saveLocation
                    progressTimer?.invalidate()
                    progressTimer = nil
                }
            }
            
            guard let dst = dst else {
                trace("download failed: destination missing")
                throw Error.downloadFailed
            }
            
            aulog("notice: AppUpdater downloaded:", dst)

            guard let unziped = try await unzip(dst, contentType: asset.content_type) else {
                trace("unzip failed")
                throw Error.unzipFailed
            }
            
            aulog("notice: AppUpdater unziped", unziped)
            
            let downloadedAppBundle = Bundle(url: unziped)!

            if try await validate(codeSigning: .main, downloadedAppBundle) {
                aulog("notice: AppUpdater validated", dst)
                trace("codesign validated ok")

                return downloadedAppBundle
            } else {
                trace("codesign mismatch")
                throw Error.codeSigningIdentity
            }
        }

        trace("fetch releases")
        let releases = try await provider.fetchReleases(owner: owner, repo: repo, proxy: proxy)
        trace("fetched releases count:", releases.count)

        notifyReleasesDidChange(releases)

        guard let (release, asset) = try releases.findViableUpdate(appVersion: currentVersion, releasePrefix: self.releasePrefix, prerelease: self.allowPrereleases) else {
            trace("no viable update for", currentVersion.description, "prefix", self.releasePrefix, "prerelease", self.allowPrereleases)
            throw Error.noValidUpdate
        }
        
        trace("viable release:", release.tagName.description, "asset:", asset.name)
        notifyStateChanged(newState: .newVersionDetected(release, asset))

        if let bundle = try await update(with: asset, belongs: release) {
            /// @deprecated
            Task { @MainActor in
                self.downloadedAppBundle = bundle
            }
            /// in new version:
            notifyStateChanged(newState: .downloaded(release, asset, bundle))
        }
    }
    
    public func installThrowing(_ downloadedAppBundle: Bundle) throws {
        trace("install start")
        let installedAppBundle = Bundle.main
        guard let exe = downloadedAppBundle.executable, exe.exists else {
            trace("invalid downloaded bundle")
            throw Error.invalidDownloadedBundle
        }
        let finalExecutable = installedAppBundle.path/exe.relative(to: downloadedAppBundle.path)

        try installedAppBundle.path.delete()
        try downloadedAppBundle.path.move(to: installedAppBundle.path)
        trace("bundle replaced")

        let proc = Process()
        if #available(OSX 10.13, *) {
            proc.executableURL = finalExecutable.url
        } else {
            proc.launchPath = finalExecutable.string
        }
        proc.launch()
        trace("launched new app")

        // seems to work, though for sure, seems asking a lot for it to be reliable!
        //TODO be reliable! Probably get an external applescript to ask us this one to quit then exec the new one
        NSApp.terminate(self)
    }
    
    private func notifyStateChanged(newState: UpdateState) {
        Task { @MainActor in
            state = newState
        }
    }
    
    private func notifyReleasesDidChange(_ releases: [Release]) {
        Task { @MainActor in
            self.releases = releases
        }
    }

    // MARK: - Localized Changelog via attachments or body

    /// Try to load a localized changelog from release assets with naming like
    /// `CHANGELOG.<lang>.md|txt` (case-insensitive). Falls back to parsing the
    /// release body for embedded language blocks, then to original body.
    ///
    /// **Logic:**
    /// For each preferred language (in order):
    ///   1. Check if there's a matching asset file (e.g., CHANGELOG.zh.md)
    ///   2. Check if there's a matching language block in body (<!-- au:lang=xx -->)
    ///   3. If body has NO language blocks at all, treat entire body as that language's content
    /// If no match found for any preferred language:
    ///   - Fallback logic: default block > en block > first available > original body
    public func localizedChangelog(for release: Release) async -> String? {
        // Parse body sections once
        let sections = Release.parseLanguageSections(from: release.body)
        let hasLanguageBlocks = !sections.isEmpty

        // Try each preferred language in order
        for lang in preferredChangelogLanguages {
            let candidates = languageCandidates(for: lang)

            // 1) Try asset file for this language
            if let asset = findChangelogAsset(in: release.assets, candidates: candidates) {
                if let data = try? await provider.fetchAssetData(asset: asset, proxy: proxy),
                   let text = String(data: data, encoding: .utf8) {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            // 2) Try body section for this language (if language blocks exist)
            if hasLanguageBlocks {
                for candidate in candidates {
                    if let matched = sections[candidate] {
                        return matched
                    }
                }
            } else {
                // 3) No language blocks - treat entire body as base language
                // Return body for the first preferred language (typically the base language)
                return release.body.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // No match for any preferred language
        if hasLanguageBlocks {
            // Fallback: default block > en block > first available
            if let def = sections["default"] { return def }
            if let en = sections["en"] { return en }
            return sections.values.first ?? release.body
        } else {
            // No language blocks - return original body
            return release.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func languageCandidates(for raw: String) -> [String] {
        func normalize(_ raw: String) -> String {
            raw.replacingOccurrences(of: "_", with: "-").lowercased()
        }

        var parts = normalize(raw).split(separator: "-").map(String.init)
        if parts.first == "zh" {
            if parts.contains("cn") || parts.contains("hans") { parts = ["zh", "hans"] }
            if parts.contains("tw") || parts.contains("hk") || parts.contains("hant") { parts = ["zh", "hant"] }
        }
        var c: [String] = []
        for i in stride(from: parts.count, through: 1, by: -1) {
            c.append(parts[0..<i].joined(separator: "-"))
        }
        if let base = parts.first, !c.contains(base) { c.append(base) }
        return c
    }

    private func languageCandidatesList(_ langs: [String]) -> [String] {
        var list: [String] = []
        for raw in langs { list.append(contentsOf: languageCandidates(for: raw)) }
        // Ensure uniqueness preserving order
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    private func findChangelogAsset(in assets: [Release.Asset], candidates: [String]) -> Release.Asset? {
        let names = assets.map { $0.name }
        // Try patterns like CHANGELOG.<lang>.md/.txt (case-insensitive)
        for lang in candidates {
            let patterns = [
                "CHANGELOG.\(lang).md",
                "CHANGELOG.\(lang).markdown",
                "CHANGELOG.\(lang).txt",
                "Changelog.\(lang).md",
                "Changelog.\(lang).txt"
            ]
            for p in patterns {
                if let idx = names.firstIndex(where: { $0.lowercased() == p.lowercased() }) {
                    return assets[idx]
                }
            }
        }
        return nil
    }
}

public struct Release: Decodable {
    let tag_name: Version
    public var tagName: Version { tag_name }
    
    public let prerelease: Bool
    public struct Asset: Decodable {
        public let name: String
        let browser_download_url: URL
        public var downloadUrl: URL { browser_download_url }
        
        let content_type: ContentType
        public var contentTyle: ContentType { content_type }
    }
    public let assets: [Asset]
    public let body: String
    public let name: String
    
    let html_url: String
    public var htmlUrl: String { html_url }
    
    enum CodingKeys: CodingKey {
        case tag_name
        case prerelease
        case assets
        case body
        case name
        case html_url
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tag_name = (try? container.decodeIfPresent(Version.self, forKey: .tag_name)) ?? .null
        self.prerelease = try container.decode(Bool.self, forKey: .prerelease)
        self.assets = try container.decode([Release.Asset].self, forKey: .assets)
        self.body = try container.decode(String.self, forKey: .body)
        self.name = try container.decode(String.self, forKey: .name)
        self.html_url = try container.decode(String.self, forKey: .html_url)
    }

    func viableAsset(forRelease releasePrefix: String) -> Asset? {
        return assets.first(where: { (asset) -> Bool in
            let prefix = "\(releasePrefix.lowercased())-\(tag_name)"
            let name = (asset.name as NSString).deletingPathExtension.lowercased()
            let fileExtension = (asset.name as NSString).pathExtension

            aulog("name, content_type, prefix, fileExtension", name, asset.content_type, prefix, fileExtension)

            switch (name, asset.content_type, fileExtension) {
            case ("\(prefix).tar", .tar, "tar"):
                return true
            case (prefix, .zip, "zip"):
                return true
            default:
                return false
            }
        })
    }
}

public enum ContentType: Decodable {
    public init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "application/x-bzip2", "application/x-xz", "application/x-gzip":
            self = .tar
        case "application/zip":
            self = .zip
        default:
            self = .unknown
        }
    }

    case zip
    case tar
    case unknown
}

extension Release: Comparable {
    public static func < (lhs: Release, rhs: Release) -> Bool {
        return lhs.tag_name < rhs.tag_name
    }

    public static func == (lhs: Release, rhs: Release) -> Bool {
        return lhs.tag_name == rhs.tag_name
    }
}

private extension Array where Element == Release {
    func findViableUpdate(appVersion: Version, releasePrefix: String, prerelease: Bool) throws -> (Release, Release.Asset)? {
        aulog(appVersion, "releasePrefix:", releasePrefix, "prerelease", prerelease, "in", self)
        
        let suitableReleases = prerelease ? self : filter { !$0.prerelease }
        aulog("found releases", suitableReleases)

        guard let latestRelease = suitableReleases.sorted().last else { return nil }
        aulog("latestRelease", latestRelease)

        guard appVersion < latestRelease.tag_name else { throw AUError.cancelled }
        aulog("\(appVersion) < \(latestRelease.tag_name)")

        guard let asset = latestRelease.viableAsset(forRelease: releasePrefix) else { return nil }
        aulog("found asset", latestRelease, asset)

        return (latestRelease, asset)
    }
}

private func unzip(_ url: URL, contentType: ContentType) async throws -> URL? {

    let proc = Process()
    if #available(OSX 10.13, *) {
        proc.currentDirectoryURL = url.deletingLastPathComponent()
    } else {
        proc.currentDirectoryPath = url.deletingLastPathComponent().path
    }

    switch contentType {
    case .tar:
        proc.launchPath = "/usr/bin/tar"
        proc.arguments = ["xf", url.path]
    case .zip:
        proc.launchPath = "/usr/bin/unzip"
        proc.arguments = [url.path]
    default:
        throw AUError.badInput
    }

    func findApp() async throws -> URL? {
        let cnts = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.isDirectoryKey], options: .skipsSubdirectoryDescendants)
        for url in cnts {
            guard url.pathExtension == "app" else { continue }
            guard let foo = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, foo else { continue }
            return url
        }
        return nil
    }

    let _ = try await proc.launching()
    return try await findApp()
}

public extension Bundle {
    func isCodeSigned() async -> Bool {
        let proc = Process()
        proc.launchPath = "/usr/bin/codesign"
        proc.arguments = ["-dv", bundlePath]
        return (try? await proc.launching()) != nil
    }

    func codeSigningIdentity() async throws -> String? {
        let proc = Process()
        proc.launchPath = "/usr/bin/codesign"
        proc.arguments = ["-dvvv", bundlePath]
        
        let (_, err) = try await proc.launching()
        guard let errInfo = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.split(separator: "\n") else {
            return nil
        }
        let result = errInfo.filter { $0.hasPrefix("Authority=") }
            .first.map { String($0.dropFirst(10)) }
        
        aulog("result \(result)")
        
        return result
    }
}

// MARK: - Debug Trace helper
extension AppUpdater {
    @inline(__always)
    func trace(_ items: Any...) {
        aulog(items)
        guard enableDebugInfo else { return }
        let msg = items.map { String(describing: $0) }.joined(separator: " ")
        Task { @MainActor in
            self.debugInfo.append(msg)
        }
    }
}
