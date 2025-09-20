import Foundation

public protocol ReleaseProvider {
    func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release]
    func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error>
    func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data
}

public struct GithubReleaseProvider: ReleaseProvider {
    public init() {}

    public func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let slug = "\(owner)/\(repo)"
        let url = URL(string: "https://api.github.com/repos/\(slug)/releases")!
        guard let task = try await URLSession.shared.dataTask(with: url, proxy: proxy)?.validate() else {
            throw AUError.invalidCallingConvention
        }
        return try JSONDecoder().decode([Release].self, from: task.data)
    }

    public func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error> {
        return try await URLSession.shared.downloadTask(with: asset.downloadUrl, to: saveLocation, proxy: proxy)
    }

    public func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data {
        guard let result = try await URLSession.shared.dataTask(with: asset.downloadUrl, proxy: proxy)?.validate() else {
            throw AUError.invalidCallingConvention
        }
        return result.data
    }
}
