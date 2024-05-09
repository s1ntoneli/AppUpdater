//
//  AppUpdaterExampleApp.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/4/26.
//

import SwiftUI
import AppUpdater
import Combine

@main
struct AppUpdaterExampleApp: App {
    @StateObject var appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60)

    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appUpdater)
                .task {
                    appUpdater.check {
                        print("manual check success")
                    } fail: { err in
                        print("manual check failed", err)
                    }
                    appUpdater.$downloadedAppBundle
                        .sink { newBundle in
                            if let newBundle {
                                // do success things
                                print("newBundle")
                            }
                        }
                        .store(in: &cancellables)
                    appUpdater.onDownloadSuccess = {
                        // do success things
                        print("download success")
                        appUpdater.install()
                    }
                    appUpdater.onDownloadFail = { err in
                        // do failing things
                        print("download failed")
                    }
                    appUpdater.onInstallSuccess = {
                        // do success things
                        print("install success")
                    }
                    appUpdater.onInstallFail = { err in
                        // do failing things
                        print("install failed")
                    }
                }
        }
    }
}
