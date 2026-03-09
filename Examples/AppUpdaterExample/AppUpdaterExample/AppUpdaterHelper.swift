//
//  AppUpdaterHelper.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/7/27.
//

import Foundation
import AppUpdater

enum ExampleProviderMode: String, CaseIterable, Identifiable {
    case github
    case managed
    case mock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github:
            return "GitHub"
        case .managed:
            return "Managed Feed"
        case .mock:
            return "Mock"
        }
    }

    var description: String {
        switch self {
        case .github:
            return "Fetches releases directly from GitHub Releases."
        case .managed:
            return "Fetches releases from a backend feed and exposes entitlement / policy metadata."
        case .mock:
            return "Runs fully offline using bundled mock release data."
        }
    }
}

final class AppUpdaterHelper {
    static let shared = AppUpdaterHelper()

    static let providerModeKey = "providerMode"
    static let legacyUseMockProviderKey = "useMockProvider"
    static let managedFeedURLKey = "managedFeedURL"
    static let managedLicenseKey = "managedLicenseKey"
    static let managedDeviceIDKey = "managedDeviceID"

    static let defaultManagedFeedURL = "https://example.com/api/public/app-updates/feed"
    static let defaultManagedLicenseKey = "EXAMPLE-LICENSE"
    static let defaultManagedDeviceID = "example-device-id"

    let appUpdater: AppUpdater

    init() {
        let updater = AppUpdater(
            owner: "s1ntoneli",
            repo: "AppUpdater-Test",
            releasePrefix: "AppUpdaterExample",
            interval: 3 * 60 * 60,
            proxy: nil,
            provider: GithubReleaseProvider()
        )
        updater.enableDebugInfo = true
        self.appUpdater = updater
        applyStoredConfiguration()
    }

    func initialize() {
        appUpdater.allowPrereleases = UserDefaults.standard.bool(forKey: "betaUpdates")
        applyStoredConfiguration()
    }

    func applyStoredConfiguration() {
        configure(appUpdater, with: Self.currentProviderMode())
    }

    func updateProviderMode(_ mode: ExampleProviderMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.providerModeKey)
        UserDefaults.standard.set(mode == .mock, forKey: Self.legacyUseMockProviderKey)
        configure(appUpdater, with: mode)
    }

    func updateManagedConfiguration(feedURL: String, licenseKey: String, deviceID: String) {
        UserDefaults.standard.set(feedURL, forKey: Self.managedFeedURLKey)
        UserDefaults.standard.set(licenseKey, forKey: Self.managedLicenseKey)
        UserDefaults.standard.set(deviceID, forKey: Self.managedDeviceIDKey)
        if Self.currentProviderMode() == .managed {
            configure(appUpdater, with: .managed)
        }
    }

    static func currentProviderMode() -> ExampleProviderMode {
        if let raw = UserDefaults.standard.string(forKey: providerModeKey),
           let mode = ExampleProviderMode(rawValue: raw) {
            return mode
        }
        if UserDefaults.standard.bool(forKey: legacyUseMockProviderKey) {
            return .mock
        }
        return .github
    }

    static func storedManagedFeedURL() -> String {
        UserDefaults.standard.string(forKey: managedFeedURLKey) ?? defaultManagedFeedURL
    }

    static func storedManagedLicenseKey() -> String {
        UserDefaults.standard.string(forKey: managedLicenseKey) ?? defaultManagedLicenseKey
    }

    static func storedManagedDeviceID() -> String {
        UserDefaults.standard.string(forKey: managedDeviceIDKey) ?? defaultManagedDeviceID
    }

    private func configure(_ updater: AppUpdater, with mode: ExampleProviderMode) {
        updater.provider = makeProvider(for: mode)
        updater.skipCodeSignValidation = mode == .mock
    }

    private func makeProvider(for mode: ExampleProviderMode) -> ReleaseProvider {
        switch mode {
        case .github:
            return GithubReleaseProvider()
        case .managed:
            let url = URL(string: Self.storedManagedFeedURL())
                ?? URL(string: Self.defaultManagedFeedURL)!
            return ManagedReleaseProvider(
                feedURL: url,
                licenseProvider: { Self.storedManagedLicenseKey() },
                deviceIdProvider: { Self.storedManagedDeviceID() },
                platform: "macos"
            )
        case .mock:
            return MockReleaseProvider()
        }
    }
}
