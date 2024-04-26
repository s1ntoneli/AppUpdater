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
    let activity: NSBackgroundActivityScheduler
    let owner: String
    let repo: String
    let releasePrefix: String

    var slug: String {
        return "\(owner)/\(repo)"
    }
    
    @Published public var downloadedAppBundle: Bundle?
    
    public var allowPrereleases = false

    public init(owner: String, repo: String, releasePrefix: String? = nil, interval: TimeInterval = 24 * 60 * 60) {
        self.owner = owner
        self.repo = repo
        self.releasePrefix = releasePrefix ?? repo

        activity = NSBackgroundActivityScheduler(identifier: "com.gokoding.AppUpdater")
        activity.repeats = true
        activity.interval = interval
        activity.schedule { [unowned self] completion in
            guard !self.activity.shouldDefer else {
                return completion(.deferred)
            }
            Task {
                do {
                    try await self.check()
                } catch {
                    NSLog("check update error \(error)")
                }
            }
        }
    }

    deinit {
        activity.invalidate()
    }

    private enum Error: Swift.Error {
        case bundleExecutableURL
        case codeSigningIdentity
        case invalidDownloadedBundle
    }

    public func check() async throws {
        guard Bundle.main.executableURL != nil else {
            return
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

        func update(with asset: Release.Asset) async throws {
            #if DEBUG
            print("notice: AppUpdater dry-run:", asset)
            #endif

            let tmpdir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Bundle.main.bundleURL, create: true)

            guard let (dst, _) = try await URLSession.shared.downloadTask(with: asset.browser_download_url, to: tmpdir.appendingPathComponent("download")) else { return }
            
            guard let unziped = try await unzip(dst, contentType: asset.content_type) else { return }
            
            let downloadedAppBundle = Bundle(url: unziped)!

            if try await validate(codeSigning: .main, downloadedAppBundle) {
                Task { @MainActor in
                    self.downloadedAppBundle = downloadedAppBundle
                }
            }
        }

        let url = URL(string: "https://api.github.com/repos/\(slug)/releases")!

        guard let task = try await URLSession.shared.dataTask(with: url)?.validate() else {
            return
        }
        let releases = try JSONDecoder().decode([Release].self, from: task.data)

        guard let asset = try releases.findViableUpdate(appVersion: currentVersion, releasePrefix: self.releasePrefix, prerelease: self.allowPrereleases) else { return }

        try await update(with: asset)
    }
    
    public func install(_ downloadedAppBundle: Bundle) throws {
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
}

private struct Release: Decodable {
    let tag_name: Version
    let prerelease: Bool
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let content_type: ContentType
    }
    let assets: [Asset]

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
            case (prefix, _):
                return true
            default:
                return false
            }
        })
    }
}

private enum ContentType: Decodable {
    init(from decoder: Decoder) throws {
        switch try decoder.singleValueContainer().decode(String.self) {
        case "application/x-bzip2", "application/x-xz", "application/x-gzip":
            self = .tar
        case "application/zip":
            self = .zip
        default:
            throw AUError.badInput
        }
    }

    case zip
    case tar
}

extension Release: Comparable {
    static func < (lhs: Release, rhs: Release) -> Bool {
        return lhs.tag_name < rhs.tag_name
    }

    static func == (lhs: Release, rhs: Release) -> Bool {
        return lhs.tag_name == rhs.tag_name
    }
}

private extension Array where Element == Release {
    func findViableUpdate(appVersion: Version, releasePrefix: String, prerelease: Bool) throws -> Release.Asset? {
        let suitableReleases = prerelease ? self : filter { !$0.prerelease }
        guard let latestRelease = suitableReleases.sorted().last else { return nil }
        guard appVersion < latestRelease.tag_name else { throw AUError.cancelled }
        return latestRelease.viableAsset(forRelease: releasePrefix)
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
