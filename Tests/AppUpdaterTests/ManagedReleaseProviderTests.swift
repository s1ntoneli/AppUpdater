import XCTest
@testable import AppUpdater

final class ManagedReleaseProviderTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testFetchReleasesDecodesManagedFeedAndCapturesEntitlement() async throws {
        let responseBody = """
        {
          "success": true,
          "data": {
            "server_time": "2026-03-09T10:30:00.000Z",
            "app": {
              "id": "screensage-macos",
              "name": "ScreenSage",
              "platform": "macos"
            },
            "current_version": {
              "tag_name": "1.7.0",
              "is_latest": false
            },
            "latest": {
              "tag_name": "1.8.0",
              "name": "ScreenSage 1.8.0",
              "published_at": "2026-03-08T16:00:00.000Z"
            },
            "entitlement": {
              "plan": "free",
              "license_model": "free",
              "member_features_active": false,
              "member_features_end_at": null,
              "status_code": "FREE_FEATURES_LOCKED",
              "status_message": "You can update to the latest version, but member-only features require an active membership.",
              "cta": {
                "code": "UPGRADE_MEMBERSHIP",
                "label": "Upgrade",
                "url": "https://screensage.pro/buy"
              }
            },
            "releases": [
              {
                "tag_name": "1.8.0",
                "name": "ScreenSage 1.8.0",
                "body": "- Added batch OCR",
                "html_url": "https://github.com/example/screensage/releases/tag/1.8.0",
                "published_at": "2026-03-08T16:00:00.000Z",
                "prerelease": false,
                "assets": [
                  {
                    "name": "ScreenSage-1.8.0.zip",
                    "content_type": "application/zip",
                    "size": 123,
                    "browser_download_url": "https://example.com/ScreenSage-1.8.0.zip"
                  }
                ],
                "policy": {
                  "install_allowed": true,
                  "member_features_active_after_install": false,
                  "code": "INSTALL_ALLOWED_FEATURES_LOCKED",
                  "message": "This version can be installed, but member-only features will remain locked after installation."
                }
              }
            ],
            "notices": [
              {
                "level": "info",
                "code": "UPDATE_AVAILABLE",
                "message": "A newer version is available."
              }
            ]
          },
          "error": null
        }
        """

        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/feed")
            let body = try XCTUnwrap(Self.requestBody(from: request))
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(json?["license"] as? String, "LIC-123")
            XCTAssertEqual(json?["current_version"] as? String, "1.7.0")
            XCTAssertEqual(json?["device_id"] as? String, "device-1")
            XCTAssertEqual(json?["platform"] as? String, "macos")
            return HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        } dataProvider: {
            Data(responseBody.utf8)
        }

        let provider = ManagedReleaseProvider(
            feedURL: try XCTUnwrap(URL(string: "https://example.com/feed")),
            licenseProvider: { "LIC-123" },
            currentVersionProvider: { "1.7.0" },
            deviceIdProvider: { "device-1" },
            session: session
        )

        let releases = try await provider.fetchReleases(owner: "ignored", repo: "ignored", proxy: nil)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.tagName.description, "1.8.0")
        XCTAssertEqual(releases.first?.policy?.code, "INSTALL_ALLOWED_FEATURES_LOCKED")
        XCTAssertEqual(provider.lastFeed?.entitlement?.statusCode, "FREE_FEATURES_LOCKED")
        XCTAssertEqual(provider.lastFeed?.notices.first?.code, "UPDATE_AVAILABLE")
    }

    func testFetchReleasesThrowsManagedAPIError() async throws {
        let responseBody = """
        {
          "success": false,
          "data": null,
          "error": {
            "code": "LICENSE_INVALID",
            "message": "The provided license key is invalid."
          }
        }
        """

        let session = makeSession { request in
            HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        } dataProvider: {
            Data(responseBody.utf8)
        }

        let provider = ManagedReleaseProvider(
            feedURL: try XCTUnwrap(URL(string: "https://example.com/feed")),
            session: session
        )

        do {
            _ = try await provider.fetchReleases(owner: "ignored", repo: "ignored", proxy: nil)
            XCTFail("Expected fetchReleases to throw")
        } catch let error as ManagedAPIError {
            XCTAssertEqual(error.code, "LICENSE_INVALID")
            XCTAssertEqual(error.message, "The provided license key is invalid.")
        }
    }

    private func makeSession(
        responseProvider: @escaping (URLRequest) throws -> HTTPURLResponse,
        dataProvider: @escaping () -> Data
    ) -> URLSession {
        MockURLProtocol.responseProvider = responseProvider
        MockURLProtocol.dataProvider = dataProvider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBody(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        let data = NSMutableData()
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, length: read)
        }
        return data as Data
    }
}

private final class MockURLProtocol: URLProtocol {
    static var responseProvider: ((URLRequest) throws -> HTTPURLResponse)?
    static var dataProvider: (() -> Data)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let responseProvider = Self.responseProvider else {
                throw NSError(domain: "MockURLProtocol", code: 1)
            }
            let response = try responseProvider(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = Self.dataProvider?() {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
