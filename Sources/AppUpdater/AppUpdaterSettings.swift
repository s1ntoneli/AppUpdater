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
    @State private var showDiagnostics: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollViewReader { reader in
            Form {
                Section {
                    /// toggle beta updates
                    Toggle(NSLocalizedString("Beta Updates", bundle: .module, comment: ""), isOn: $betaUpdates)
                        .onChange(of: betaUpdates) { newValue in
                            updater.allowPrereleases = newValue
                            updater.check()
                        }
                }
                Section {
                    if case .none = updater.state {
                        Text(NSLocalizedString("No Updates Available", bundle: .module, comment: ""))
                    } else {
                        VStack(alignment: .leading) {
                            HStack {
                                let title = NSLocalizedString("New Version Available", bundle: .module, comment: "")
                                let ver = updater.state.release?.tagName.description ?? ""
                                Text(ver.isEmpty ? title : "\(title) \(ver)")

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
                                            Text(NSLocalizedString("Update Now", bundle: .module, comment: ""))
                                        }
                                    }
                                }
                            }
                            /// changelog
                            LocalizedChangelogView(release: updater.state.release)
                        }
                        Button {
                            openURL(url: updater.state.release?.htmlUrl ?? "")
                        } label: {
                            Text(NSLocalizedString("More Info...", bundle: .module, comment: ""))
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
            .overlay(alignment: .bottomTrailing) {
                FloatingDiagnostics(show: $showDiagnostics)
            }
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

struct FloatingDiagnostics: View {
    @EnvironmentObject var updater: AppUpdater
    @Binding var show: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if show {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Diagnostics").font(.headline)
                        Spacer()
                        Button {
                            show = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle("Enable Logs", isOn: Binding(get: { updater.enableDebugInfo }, set: { updater.enableDebugInfo = $0 }))
                        .toggleStyle(.switch)
                    if let err = updater.lastError {
                        Text("Last Error: \(String(describing: err))")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if updater.debugInfo.isEmpty {
                                Text("No logs yet").foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(updater.debugInfo.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(width: 420, height: 180)
                    HStack {
                        Button("Clear Logs") { updater.debugInfo.removeAll() }
                        Spacer()
                        Button("Check Now") { updater.check() }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(radius: 4)
            }
            HStack(spacing: 6) {
                if show == false {
                    if updater.lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Button(show ? "Hide Diagnostics" : "Diagnostics") { show.toggle() }
            }
            .padding(.trailing, 6)
        }
        .padding(12)
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject var updater: AppUpdater
    @State private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Toggle("Enable Logs", isOn: Binding(get: {
                    updater.enableDebugInfo
                }, set: { updater.enableDebugInfo = $0 }))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if let err = updater.lastError {
                Text("Last Error: \(String(describing: err))")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if updater.debugInfo.isEmpty {
                Text("No logs yet")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(updater.debugInfo.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
            }

            HStack {
                Button("Clear Logs") { updater.debugInfo.removeAll() }
                Spacer()
                Button("Check Now") { updater.check() }
            }
        }
    }
}

struct LocalizedChangelogView: View {
    @EnvironmentObject var updater: AppUpdater
    let release: Release?

    @State private var text: String? = nil

    var body: some View {
        Group {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Markdown { text }
            } else {
                Text(NSLocalizedString("No Changelog Available", bundle: .module, comment: ""))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: updater.preferredChangelogLanguages.joined(separator: ",") + (release?.tagName.description ?? "")) {
            guard let release else { text = nil; return }
            text = await updater.localizedChangelog(for: release)
        }
    }
}

struct ReleaseRow: View {
    let release: Release
    @EnvironmentObject var updater: AppUpdater

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
                LocalizedChangelogView(release: release)
                    .id(release.htmlUrl)
            }
        }
    }
}
