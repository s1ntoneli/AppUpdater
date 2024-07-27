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
    
    let appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater-Test", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60, proxy: GithubProxy())
    
    func initialize() {
        appUpdater.allowPrereleases = UserDefaults.standard.bool(forKey: "betaUpdates")
    }
}
