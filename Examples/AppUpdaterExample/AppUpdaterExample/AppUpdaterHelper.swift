//
//  AppUpdaterHelper.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/7/27.
//

import Foundation
import AppUpdater

class AppUpdaterHelper {
    
    static let shared = AppUpdaterHelper()
    
    let appUpdater: AppUpdater
    
    init() {
        let useMock = UserDefaults.standard.bool(forKey: "useMockProvider")
        if useMock {
            let mock = MockReleaseProvider()
            let updater = AppUpdater(owner: "mock", repo: "mock", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60, proxy: nil, provider: mock)
            updater.skipCodeSignValidation = true
            updater.enableDebugInfo = true
            self.appUpdater = updater
        } else {
            let updater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater-Test", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60)
            updater.enableDebugInfo = true
            self.appUpdater = updater
        }
    }

    func initialize() {
        appUpdater.allowPrereleases = UserDefaults.standard.bool(forKey: "betaUpdates")
    }
}
