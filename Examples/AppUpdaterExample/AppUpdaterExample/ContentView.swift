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
            
            if case .none = appUpdater.state {
                Text("No New Version")
            } else {
                // changelog
                if let release = appUpdater.state.release {
                    Text(release.body)
                }
                
                // new version detected
                if case .newVersionDetected = appUpdater.state {
                    Text("New Version Detected")
                        .bold()
                }
                
                // downloading
                if case .downloading(_, _, let fraction) = appUpdater.state {
                    Text("Downloading \(fraction)")
                        .bold()
                }
                
                // new bundle is ready to install
                if case .downloaded(_, _, let newBundle) = appUpdater.state {
                    Text("New Version Available")
                        .bold()
                    Button {
                        appUpdater.install(newBundle)
                    } label: {
                        Text("Update Now")
                    }.buttonStyle(.borderedProminent)
                }
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
