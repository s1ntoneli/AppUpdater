import XCTest
@testable import AppUpdater

final class ReleaseArchitectureSelectionTests: XCTestCase {
    func testSelectsMatchingArchitectureArchive() throws {
        let release = try makeRelease(assetNames: [
            "ScreenSage-0.4.3-x86_64.zip",
            "ScreenSage-0.4.3-arm64.zip",
            "ScreenSage-0.4.3.dmg"
        ])

        XCTAssertEqual(
            release.viableAsset(forRelease: "ScreenSage", preferredArchitecture: .arm64)?.name,
            "ScreenSage-0.4.3-arm64.zip"
        )
        XCTAssertEqual(
            release.viableAsset(forRelease: "ScreenSage", preferredArchitecture: .x86_64)?.name,
            "ScreenSage-0.4.3-x86_64.zip"
        )
    }

    func testFallsBackToLegacyUniversalArchive() throws {
        let release = try makeRelease(assetNames: ["ScreenSage-0.4.3.zip"])

        XCTAssertEqual(
            release.viableAsset(forRelease: "ScreenSage", preferredArchitecture: .arm64)?.name,
            "ScreenSage-0.4.3.zip"
        )
        XCTAssertEqual(
            release.viableAsset(forRelease: "ScreenSage", preferredArchitecture: .x86_64)?.name,
            "ScreenSage-0.4.3.zip"
        )
    }

    func testDoesNotInstallTheOtherArchitecture() throws {
        let release = try makeRelease(assetNames: ["ScreenSage-0.4.3-x86_64.zip"])

        XCTAssertNil(
            release.viableAsset(forRelease: "ScreenSage", preferredArchitecture: .arm64)
        )
    }

    private func makeRelease(assetNames: [String]) throws -> Release {
        let assets = assetNames.map { name in
            [
                "name": name,
                "browser_download_url": "https://example.invalid/\(name)",
                "content_type": name.hasSuffix(".zip") ? "application/zip" : "application/octet-stream"
            ]
        }
        let object: [String: Any] = [
            "tag_name": "0.4.3",
            "prerelease": false,
            "assets": assets,
            "body": "",
            "name": "0.4.3",
            "html_url": "https://example.invalid/releases/0.4.3"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
