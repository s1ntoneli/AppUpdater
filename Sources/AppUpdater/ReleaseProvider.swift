import Foundation

public protocol ReleaseProvider {
    func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release]
    func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Error>
    func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data
}

public struct GithubReleaseProvider: ReleaseProvider {
    typealias PageLoader = (URL, URLRequestProxy?) async throws -> Data

    private let loadPage: PageLoader

    public init() {
        self.loadPage = { url, proxy in
            guard let task = try await URLSession.shared.dataTask(with: url, proxy: proxy)?.validate() else {
                throw AUError.invalidCallingConvention
            }
            return task.data
        }
    }

    init(loadPage: @escaping PageLoader) {
        self.loadPage = loadPage
    }

    public func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        let slug = "\(owner)/\(repo)"
        let decoder = JSONDecoder()
        var releases: [Release] = []
        var page = 1

        // GitHub returns only 30 releases by default. Fetch 100 at a time and
        // continue until the final partial page so history views can show the
        // complete release timeline without issuing dozens of small requests.
        while page <= 20 {
            let url = URL(string: "https://api.github.com/repos/\(slug)/releases?per_page=100&page=\(page)")!
            let data = try await loadPage(url, proxy)
            let batch = try decoder.decode([Release].self, from: data)
            releases.append(contentsOf: batch)

            if batch.count < 100 {
                break
            }
            page += 1
        }

        return releases
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
