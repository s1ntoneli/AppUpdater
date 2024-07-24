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

    private enum Error: Swift.Error {
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
                return csi1 == csi2
            }
        }

        func update(with asset: Release.Asset, belongs release: Release) async throws -> Bundle? {
            #if DEBUG
            print("notice: AppUpdater dry-run:", asset)
            #endif

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
            
            #if DEBUG
            print("notice: AppUpdater downloaded:", dst)
            #endif

            guard let unziped = try await unzip(dst, contentType: asset.content_type) else {
                throw Error.unzipFailed
            }
            
            #if DEBUG
            print("notice: AppUpdater unziped", unziped)
            #endif
            
            let downloadedAppBundle = Bundle(url: unziped)!

            if try await validate(codeSigning: .main, downloadedAppBundle) {
                #if DEBUG
                print("notice: AppUpdater validated", dst)
                #endif

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
}

public struct Release: Decodable {
    public let tag_name: Version
    public let prerelease: Bool
    public struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let content_type: ContentType
    }
    public let assets: [Asset]
    public let body: String
    public let name: String

    func viableAsset(forRelease releasePrefix: String) -> Asset? {
        return assets.first(where: { (asset) -> Bool in
            let prefix = "\(releasePrefix.lowercased())-\(tag_name)"
            let name = (asset.name as NSString).deletingPathExtension.lowercased()

            #if DEBUG
            print("name, content_type, prefix", name, asset.content_type, prefix)
            #endif

            switch (name, asset.content_type) {
            case ("\(prefix).tar", .tar):
                return true
            case (prefix, .zip):
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
        let suitableReleases = prerelease ? self : filter { !$0.prerelease }
        guard let latestRelease = suitableReleases.sorted().last else { return nil }
        guard appVersion < latestRelease.tag_name else { throw AUError.cancelled }
        guard let asset = latestRelease.viableAsset(forRelease: releasePrefix) else { return nil }
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

private extension Bundle {
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
        
        #if DEBUG
        print("result \(result)")
        #endif
        
        return result
    }
}
