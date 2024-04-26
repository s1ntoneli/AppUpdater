//
//  AppUpdaterExampleApp.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/4/26.
//

import SwiftUI
import AppUpdater

@main
struct AppUpdaterExampleApp: App {
    @StateObject var appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appUpdater)
                .task {
                    appUpdater.check {
                        
                    } fail: { err in
                        
                    }
                }
        }
    }
}
