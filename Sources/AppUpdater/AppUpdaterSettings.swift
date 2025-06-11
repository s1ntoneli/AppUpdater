//
//  AppUpdateSettings.swift
//  CleanClip
//
//  Created by lixindong on 2024/7/23.
//  Copyright © 2024 zuimeijia. All rights reserved.
//

import Foundation
import SwiftUI
import MarkdownUI
import Version

@available(macOS 13.0, *)
public struct AppUpdateSettings: View {
    @EnvironmentObject var updater: AppUpdater
    
    @AppStorage("betaUpdates")
    private var betaUpdates: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollViewReader { reader in
            Form {
                Section {
                    /// toggle beta updates
                    Toggle("Beta Updates", isOn: $betaUpdates)
                        .onChange(of: betaUpdates) { newValue in
                            updater.allowPrereleases = newValue
                            updater.check()
                        }
                }
                Section {
                    if case .none = updater.state {
                        Text("No Updates Available")
                    } else {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("New Version Available")

                                Spacer()
                                Group {
                                    if case .newVersionDetected(_, _) = updater.state {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    if case .downloading(_, _, let fraction) = updater.state {
                                        Button {
                                        } label: {
                                            Text("\(Int(fraction * 10000) / 100)%")
                                        }
                                        .disabled(true)
                                    }
                                    if case .downloaded(_, _, let newBundle) = updater.state {
                                        Button {
                                            updater.install(newBundle)
                                        } label: {
                                            Text("Update Now")
                                        }
                                    }
                                }
                            }
                            /// changelog
                            if let changelog = updater.state.release?.body {
                                Markdown {
                                    changelog
                                }
                            }
                        }
                        Button {
                            openURL(url: updater.state.release?.htmlUrl ?? "")
                        } label: {
                            Text("More Info...")
                        }
                        .buttonStyle(.link)
                    }
                }
                ForEach(updater.releases.filter({ $0 != updater.state.release }), id: \.tagName) { release in
                    /// changelog
                    ReleaseRow(release: release)
//                        .background {
//                            GeometryReader {
//                                let frame = $0.frame(in: .global)
//                                Color.clear.onChange(of: frame.size) { newValue in
//                                    DispatchQueue.main.async {
//                                        withAnimation {
//                                            reader.scrollTo(0, anchor: .init(x: 0, y: -(frame.minY + newValue.height) ))
//                                        }
//                                    }
//                                }
//                            }
//                        }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 600)
        }
    }
    
    func openURL(url: String) {
        let url = URL(string: url)!

        if NSWorkspace.shared.open(url) {
            print("success")
        } else {
            print("failed")
        }
    }
}

struct ReleaseRow: View {
    let release: Release
    
    @State private var showChangelog = false
    
    var body: some View {
        Section {
            HStack {
                Text(release.tagName.description)
                Spacer()
                Image(systemName: showChangelog ? "chevron.down" : "chevron.right")
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation {
                    showChangelog.toggle()
                }
            }
            if showChangelog {
                Markdown {
                    release.body
                }
                .id(release.htmlUrl)
            }
        }
    }
}
