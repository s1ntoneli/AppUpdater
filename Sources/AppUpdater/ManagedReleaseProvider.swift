import Foundation
import Version

public struct ManagedReleaseFeed: Decodable {
    public struct App: Decodable, Equatable {
        public let id: String
        public let name: String
        public let platform: String
    }

    public struct CurrentVersion: Decodable, Equatable {
        public let tagName: String
        public let isLatest: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case isLatest = "is_latest"
        }
    }

    public struct Latest: Decodable, Equatable {
        public let tagName: String
        public let name: String
        public let publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case publishedAt = "published_at"
        }
    }

    public struct Entitlement: Decodable, Equatable {
        public struct CTA: Decodable, Equatable {
            public let code: String
            public let label: String
            public let url: String
        }

        public let plan: String
        public let licenseModel: String
        public let memberFeaturesActive: Bool
        public let memberFeaturesEndAt: String?
        public let statusCode: String
        public let statusMessage: String
        public let cta: CTA?

        enum CodingKeys: String, CodingKey {
            case plan
            case licenseModel = "license_model"
            case memberFeaturesActive = "member_features_active"
            case memberFeaturesEndAt = "member_features_end_at"
            case statusCode = "status_code"
            case statusMessage = "status_message"
            case cta
        }
    }

    public struct Notice: Decodable, Equatable {
        public let level: String
        public let code: String
        public let message: String
    }

    public let serverTime: String?
    public let app: App?
    public let currentVersion: CurrentVersion?
    public let latest: Latest?
    public let entitlement: Entitlement?
    public let releases: [Release]
    public let notices: [Notice]

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case app
        case currentVersion = "current_version"
        case latest
        case entitlement
        case releases
        case notices
    }
}

public struct ManagedReleasePolicy: Decodable, Equatable {
    public let installAllowed: Bool
    public let memberFeaturesActiveAfterInstall: Bool
    public let code: String
    public let message: String

    enum CodingKeys: String, CodingKey {
        case installAllowed = "install_allowed"
        case memberFeaturesActiveAfterInstall = "member_features_active_after_install"
        case code
        case message
    }
}

public struct ManagedAPIError: Decodable, Swift.Error, Equatable {
    public let code: String
    public let message: String
}

public protocol ManagedReleaseFeedProviding: ReleaseProvider {
    var lastFeed: ManagedReleaseFeed? { get }
}

private struct ManagedReleaseFeedEnvelope: Decodable {
    let success: Bool
    let data: ManagedReleaseFeed?
    let error: ManagedAPIError?
}

private struct ManagedReleaseFeedRequest: Encodable {
    let license: String?
    let currentVersion: String?
    let deviceId: String?
    let platform: String

    enum CodingKeys: String, CodingKey {
        case license
        case currentVersion = "current_version"
        case deviceId = "device_id"
        case platform
    }
}

public final class ManagedReleaseProvider: ManagedReleaseFeedProviding {
    public typealias StringProvider = () -> String?

    public enum Error: Swift.Error {
        case missingFeedData
    }

    public private(set) var lastFeed: ManagedReleaseFeed?

    private let feedURL: URL
    private let licenseProvider: StringProvider
    private let currentVersionProvider: StringProvider
    private let deviceIdProvider: StringProvider
    private let platform: String
    private let additionalHeaders: [String: String]
    private let session: URLSession

    public init(
        feedURL: URL,
        licenseProvider: @escaping StringProvider = { nil },
        currentVersionProvider: @escaping StringProvider = {
            let version = Bundle.main.version.description
            return version == "null" ? nil : version
        },
        deviceIdProvider: @escaping StringProvider = { nil },
        platform: String = "macos",
        additionalHeaders: [String: String] = [:],
        session: URLSession = .shared
    ) {
        self.feedURL = feedURL
        self.licenseProvider = licenseProvider
        self.currentVersionProvider = currentVersionProvider
        self.deviceIdProvider = deviceIdProvider
        self.platform = platform
        self.additionalHeaders = additionalHeaders
        self.session = session
    }

    public func fetchReleases(owner: String, repo: String, proxy: URLRequestProxy?) async throws -> [Release] {
        var request = URLRequest(url: feedURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(ManagedReleaseFeedRequest(
            license: licenseProvider(),
            currentVersion: currentVersionProvider(),
            deviceId: deviceIdProvider(),
            platform: platform
        ))

        guard let result = try await session.dataTask(with: request, proxy: proxy) else {
            throw AUError.invalidCallingConvention
        }

        if let envelope = try? JSONDecoder().decode(ManagedReleaseFeedEnvelope.self, from: result.data) {
            guard envelope.success, let data = envelope.data else {
                throw envelope.error ?? Error.missingFeedData
            }
            _ = try result.validate()
            lastFeed = data
            return data.releases
        }

        _ = try result.validate()
        throw Error.missingFeedData
    }

    public func download(asset: Release.Asset, to saveLocation: URL, proxy: URLRequestProxy?) async throws -> AsyncThrowingStream<DownloadingState, Swift.Error> {
        try await session.downloadTask(with: asset.downloadUrl, to: saveLocation, proxy: proxy)
    }

    public func fetchAssetData(asset: Release.Asset, proxy: URLRequestProxy?) async throws -> Data {
        guard let result = try await session.dataTask(with: asset.downloadUrl, proxy: proxy)?.validate() else {
            throw AUError.invalidCallingConvention
        }
        return result.data
    }
}
