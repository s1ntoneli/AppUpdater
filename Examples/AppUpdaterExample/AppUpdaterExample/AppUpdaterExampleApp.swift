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
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    
    @State
    var appUpdater = AppUpdaterHelper.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 745, height: 515)
                .environmentObject(appUpdater.appUpdater)
        }
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        /// AppUpdater initializer
        AppUpdaterHelper.shared.initialize()
        /// checking updates
        let appUpdater = AppUpdaterHelper.shared.appUpdater
        
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
            // do success things; keep manual install via UI to avoid replacing the running app during tests
            print("download success")
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
