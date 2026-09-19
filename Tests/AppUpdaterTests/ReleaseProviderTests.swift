import XCTest
@testable import AppUpdater

final class ReleaseProviderTests: XCTestCase {
    func testReleasePreservesNonSemanticVersionTag() throws {
        let release = try decodeRelease(tag: "preview-0.3.0")

        XCTAssertEqual(release.rawTagName, "preview-0.3.0")
        XCTAssertEqual(release.tagName, .null)
    }

    func testFetchReleasesLoadsFullPagesUntilFinalPartialPage() async throws {
        let recorder = PageRequestRecorder()
        let firstPage = try makeReleasePage(tags: (0..<100).map { "1.0.\($0)" })
        let secondPage = try makeReleasePage(tags: ["0.9.0"])
        let provider = GithubReleaseProvider { url, _ in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
            let perPage = components?.queryItems?.first(where: { $0.name == "per_page" })?.value
            await recorder.record(page: page, perPage: perPage)

            switch page {
            case "1": return firstPage
            case "2": return secondPage
            default: return Data("[]".utf8)
            }
        }

        let releases = try await provider.fetchReleases(owner: "ScreenSage", repo: "ScreenSageApp", proxy: nil)

        XCTAssertEqual(releases.count, 101)
        XCTAssertEqual(releases.first?.rawTagName, "1.0.0")
        XCTAssertEqual(releases.last?.rawTagName, "0.9.0")
        let requests = await recorder.requests
        XCTAssertEqual(requests.map(\.page), ["1", "2"])
        XCTAssertEqual(requests.map(\.perPage), ["100", "100"])
    }

    private func decodeRelease(tag: String) throws -> Release {
        let data = try makeReleasePage(tags: [tag])
        return try XCTUnwrap(JSONDecoder().decode([Release].self, from: data).first)
    }

    private func makeReleasePage(tags: [String]) throws -> Data {
        let releases = tags.map { tag in
            [
                "tag_name": tag,
                "prerelease": false,
                "assets": [],
                "body": "",
                "name": tag,
                "html_url": "https://example.invalid/releases/\(tag)"
            ] as [String: Any]
        }
        return try JSONSerialization.data(withJSONObject: releases)
    }
}

private actor PageRequestRecorder {
    struct Request: Equatable {
        let page: String?
        let perPage: String?
    }

    private(set) var requests: [Request] = []

    func record(page: String?, perPage: String?) {
        requests.append(Request(page: page, perPage: perPage))
    }
}
