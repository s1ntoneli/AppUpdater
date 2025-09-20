import Foundation

public final class MockReleaseProvider: ReleaseProvider {
    public enum Source {
        case bundled // use `Bundle.module` resources
        case fileURL(URL) // load JSON from a local file URL
    }

    private let source: Source
    private let mockFileName: String
    private let simulatedSteps: Int
    private let simulatedDelay: UInt64

    public init(source: Source = .bundled, mockFileName: String = "releases.mock.json", simulatedSteps: Int = 10, simulatedDelay: UInt64 = 100_000_000) {
        self.source = source
        self.mockFileName = mockFileName
        self.simulatedSteps = max(simulatedSteps, 1)
        self.simulatedDelay = simulatedDelay
    }

    public func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let data: Data
        switch source {
        case .bundled:
            if let url = Bundle.module.url(forResource: mockFileName, withExtension: nil, subdirectory: "Mocks") {
                data = try Data(contentsOf: url)
            } else if let url = Bundle.module.url(forResource: (mockFileName as NSString).deletingPathExtension, withExtension: (mockFileName as NSString).pathExtension.isEmpty ? nil : (mockFileName as NSString).pathExtension) {
                data = try Data(contentsOf: url)
            } else {
                throw AUError.badInput
            }
        case .fileURL(let url):
            data = try Data(contentsOf: url)
        }

        return try JSONDecoder().decode([Release].self, from: data)
    }

    public func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error> {
        return AsyncThrowingStream<DownloadingState, Error> { continuation in
            Task {
                // Simulate progress
                for i in 1...simulatedSteps {
                    try await Task.sleep(nanoseconds: simulatedDelay)
                    let p = Progress(totalUnitCount: Int64(simulatedSteps))
                    p.completedUnitCount = Int64(i)
                    continuation.yield(.progress(p))
                }

                // Materialize a mock zip at saveLocation if requested type is zip, otherwise tar
                do {
                    try await createMockArchive(at: saveLocation, assetName: asset.name)
                    let rsp = URLResponse(url: saveLocation, mimeType: nil, expectedContentLength: -1, textEncodingName: nil)
                    continuation.yield(.finished(saveLocation: saveLocation, response: rsp))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data {
        // Attempt to load a file from bundled Mocks matching the asset name
        let basename = (asset.name as NSString).deletingPathExtension
        let ext = (asset.name as NSString).pathExtension
        // Try at bundle root first
        if let url = Bundle.module.url(forResource: basename, withExtension: ext.isEmpty ? nil : ext) {
            return try Data(contentsOf: url)
        }
        // Try under Mocks subdirectory
        if let url = Bundle.module.url(forResource: basename, withExtension: ext.isEmpty ? nil : ext, subdirectory: "Mocks") {
            return try Data(contentsOf: url)
        }
        // Try case-insensitive search by listing contents of Mocks
        if let mocksURL = Bundle.module.resourceURL?.appendingPathComponent("Mocks") {
            if let enumerator = FileManager.default.enumerator(at: mocksURL, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == asset.name.lowercased() {
                        return try Data(contentsOf: fileURL)
                    }
                }
            }
        }
        throw AUError.badInput
    }

    private func createMockArchive(at url: URL, assetName: String) async throws {
        // Decide archive type by extension
        let ext = (assetName as NSString).pathExtension.lowercased()
        let tempDir = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a minimal .app bundle
        let appName = ((assetName as NSString).deletingPathExtension as NSString).lastPathComponent
        let appDir = tempDir.appendingPathComponent("\(appName).app")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let contentsMacOS = appDir.appendingPathComponent("Contents/MacOS")
        let contentsResources = appDir.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: contentsMacOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentsResources, withIntermediateDirectories: true)
        // Minimal Info.plist
        let infoPlist = appDir.appendingPathComponent("Contents/Info.plist")
        let info = """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
        <plist version=\"1.0\">
        <dict>
            <key>CFBundleName</key><string>\(appName)</string>
            <key>CFBundleIdentifier</key><string>com.example.\(appName)</string>
            <key>CFBundleVersion</key><string>1</string>
            <key>CFBundleShortVersionString</key><string>1.0.0</string>
            <key>CFBundlePackageType</key><string>APPL</string>
            <key>CFBundleExecutable</key><string>\(appName)</string>
        </dict>
        </plist>
        """
        try info.write(to: infoPlist, atomically: true, encoding: .utf8)
        // Create a tiny executable shell script as placeholder
        let exe = contentsMacOS.appendingPathComponent(appName)
        try "#!/bin/sh\necho Mock app launched\nsleep 3\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)

        // Archive
        if ext == "zip" {
            try await shellZip(contentsOf: tempDir, into: url)
        } else if ext == "tar" {
            try await shellTar(contentsOf: tempDir, into: url)
        } else {
            // default to zip
            try await shellZip(contentsOf: tempDir, into: url)
        }

        // Cleanup tempDir
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func shellZip(contentsOf dir: URL, into dst: URL) async throws {
        let proc = Process()
        proc.launchPath = "/usr/bin/zip"
        proc.currentDirectoryPath = dir.path
        proc.arguments = ["-r", dst.path, "."]
        let _ = try await proc.launching()
    }

    private func shellTar(contentsOf dir: URL, into dst: URL) async throws {
        let proc = Process()
        proc.launchPath = "/usr/bin/tar"
        proc.currentDirectoryPath = dir.path
        proc.arguments = ["-czf", dst.path, "."]
        let _ = try await proc.launching()
    }
}
