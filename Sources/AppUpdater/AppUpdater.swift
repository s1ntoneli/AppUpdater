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
    
    @available(*, deprecated, message: "This variable is deprecated. Use state instead.")
    @Published public var downloadedAppBundle: Bundle?
    
    /// update state
    @MainActor
    @Published public var state: UpdateState = .none
    
    /// all releases
    @MainActor
    @Published public var releases: [Release] = []

    public var onDownloadSuccess: OnSuccess? = nil
    public var onDownloadFail: OnFail? = nil
    
    public var onInstallSuccess: OnSuccess? = nil
    public var onInstallFail: OnFail? = nil
    
    public var allowPrereleases = false
    
    private var progressTimer: Timer? = nil
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.shouldUseExtendedBackgroundIdleMode = true
        config.timeoutIntervalForRequest = 3 * 60
        
        return URLSession(configuration: config)
    }()

    public init(owner: String, repo: String, releasePrefix: String? = nil, interval: TimeInterval = 24 * 60 * 60, proxy: URLRequestProxy? = nil) {
        self.owner = owner
        self.repo = repo
        self.releasePrefix = releasePrefix ?? repo
        self.proxy = proxy

        activity = NSBackgroundActivityScheduler(identifier: "AppUpdater.\(Bundle.main.bundleIdentifier ?? "")")
        activity.repeats = true
        activity.interval = interval
        activity.schedule { [unowned self] completion in
            guard !self.activity.shouldDefer else {
                return completion(.deferred)
            }
            self.check(success: {
                onDownloadSuccess?()
                completion(.finished)
            }, fail: { err in
                onDownloadFail?(err)
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
        guard Bundle.main.executableURL != nil else {
            throw Error.bundleExecutableURL
        }
        let currentVersion = Bundle.main.version

        func validate(codeSigning b1: Bundle, _ b2: Bundle) async throws -> Bool {
            do {
                let csi1 = try await b1.codeSigningIdentity()
                let csi2 = try await b2.codeSigningIdentity()
                
                if csi1 == nil || csi2 == nil {
                    throw Error.codeSigningIdentity
                }
                aulog("compairing current: \(csi1) downloaded: \(csi2) equals? \(csi1 == csi2)")
                return csi1 == csi2
            }
        }

        func update(with asset: Release.Asset, belongs release: Release) async throws -> Bundle? {
            aulog("notice: AppUpdater dry-run:", asset)

            let tmpdir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Bundle.main.bundleURL, create: true)

            let downloadState = try await session.downloadTask(with: asset.browser_download_url, to: tmpdir.appendingPathComponent("download"), proxy: proxy)
            
            var dst: URL? = nil
            for try await state in downloadState {
                switch state {
                case .progress(let progress):
                    DispatchQueue.main.async {
                        self.progressTimer?.invalidate()
                        self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                            self.notifyStateChanged(newState: .downloading(release, asset, fraction: progress.fractionCompleted))
                        }
                    }

                    break
                case .finished(let saveLocation, _):
                    dst = saveLocation
                    progressTimer?.invalidate()
                    progressTimer = nil
                }
            }
            
            guard let dst = dst else {
                throw Error.downloadFailed
            }
            
            aulog("notice: AppUpdater downloaded:", dst)

            guard let unziped = try await unzip(dst, contentType: asset.content_type) else {
                throw Error.unzipFailed
            }
            
            aulog("notice: AppUpdater unziped", unziped)
            
            let downloadedAppBundle = Bundle(url: unziped)!

            if try await validate(codeSigning: .main, downloadedAppBundle) {
                aulog("notice: AppUpdater validated", dst)

                return downloadedAppBundle
            } else {
                throw Error.codeSigningIdentity
            }
        }

        let url = URL(string: "https://api.github.com/repos/\(slug)/releases")!

        guard let task = try await URLSession.shared.dataTask(with: url, proxy: proxy)?.validate() else {
            throw Error.bundleExecutableURL
        }
        let releases = try JSONDecoder().decode([Release].self, from: task.data)

        notifyReleasesDidChange(releases)

        guard let (release, asset) = try releases.findViableUpdate(appVersion: currentVersion, releasePrefix: self.releasePrefix, prerelease: self.allowPrereleases) else {
            throw Error.noValidUpdate
        }
        
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
        let installedAppBundle = Bundle.main
        guard let exe = downloadedAppBundle.executable, exe.exists else {
            throw Error.invalidDownloadedBundle
        }
        let finalExecutable = installedAppBundle.path/exe.relative(to: downloadedAppBundle.path)

        try installedAppBundle.path.delete()
        try downloadedAppBundle.path.move(to: installedAppBundle.path)

        let proc = Process()
        if #available(OSX 10.13, *) {
            proc.executableURL = finalExecutable.url
        } else {
            proc.launchPath = finalExecutable.string
        }
        proc.launch()

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
