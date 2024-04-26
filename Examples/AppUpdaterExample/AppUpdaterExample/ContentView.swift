//
//  ContentView.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/4/26.
//

import SwiftUI
import AppUpdater

struct ContentView: View {
    @EnvironmentObject var appUpdater: AppUpdater
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            if let appBundle = appUpdater.downloadedAppBundle {
                HStack {
                    Text("New Version Available")
                    Button {
                        appUpdater.install(appBundle)
                    } label: {
                        Text("Update Now")
                    }.buttonStyle(.borderedProminent)
                }
            } else {
                Text("No New Version")
            }
            
            Divider()
            
            Button {
                appUpdater.check()
            } label: {
                Text("Check Update")
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
