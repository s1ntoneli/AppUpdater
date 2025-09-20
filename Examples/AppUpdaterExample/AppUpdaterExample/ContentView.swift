//
//  ContentView.swift
//  AppUpdaterExample
//
//  Created by lixindong on 2024/4/26.
//

import SwiftUI
import AppUpdater

struct ContentView: View {
    @EnvironmentObject
    var appUpdater: AppUpdater
    
    @State
    private var router: Routers = .general
    @State
    private var useMockProvider: Bool = UserDefaults.standard.bool(forKey: "useMockProvider")
    @State
    private var languagesText: String = ""
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Routers.appupdater.LinkTo {
                        AppUpdateSettings()
                    }
                    .modifier( stateBadgeModifier )
                }
                Section {
                    Routers.general.LinkTo {
                        GeneralSettings()
                    }
                }
                Section {
                    Routers.license.LinkTo {
                        Text("License")
                    }
                    Routers.about.LinkTo {
                        Text("About")
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        }
        .onAppear { applyProviderFromDefaults() }
    }
    
    @ViewBuilder
    func GeneralSettings() -> some View {
        Text("General Settings")
        Toggle("Use Mock Data", isOn: $useMockProvider)
            .onChange(of: useMockProvider) { newValue in
                UserDefaults.standard.set(newValue, forKey: "useMockProvider")
                if newValue {
                    appUpdater.provider = MockReleaseProvider()
                    appUpdater.skipCodeSignValidation = true
                } else {
                    appUpdater.provider = GithubReleaseProvider()
                    appUpdater.skipCodeSignValidation = false
                }
            }
        Text("Provider: \(useMockProvider ? "Mock" : "GitHub")")
        HStack {
            Text("Changelog Languages (priority order):")
            TextField("e.g., zh-Hans, en", text: $languagesText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Button("Apply") {
                let langs = languagesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                appUpdater.preferredChangelogLanguages = langs
            }
            Button("Use System") {
                languagesText = Locale.preferredLanguages.joined(separator: ", ")
                appUpdater.preferredChangelogLanguages = Locale.preferredLanguages
            }
        }
        Button {
            appUpdater.check()
        } label: {
            Text("Check Updates")
        }
    }

    /// Ensure the toggle reflects and applies provider on appear
    func applyProviderFromDefaults() {
        let newValue = UserDefaults.standard.bool(forKey: "useMockProvider")
        useMockProvider = newValue
        if newValue {
            appUpdater.provider = MockReleaseProvider()
            appUpdater.skipCodeSignValidation = true
        } else {
            appUpdater.provider = GithubReleaseProvider()
            appUpdater.skipCodeSignValidation = false
        }
    }
}

enum Routers {
    case general
    case about
    case license
    
    case appupdater
    
    var name: String {
        switch self {
        case .general:
            return "General"
        
        case .appupdater:
            return "Software Updates Available"
            
        case .about:
            return "About"
        case .license:
            return "License"
        }
    }
    
    var icon: String {
        switch self {
        case .general:
            return "gear"
            
        case .appupdater:
            return ""
            
        case .about:
            return "info"
        case .license:
            return "checkmark.seal.fill"
        }
    }
    
    var iconBgColor: Color {
        switch self {
        case .general:
            return .blue
        case .appupdater:
            return .green
        case .about:
            return .green
        case .license:
            return Color.accentColor
        }
    }
    
    @ViewBuilder func LinkTo(_ destination: () -> some View) -> some View {
        NavigationLink(destination: destination()) {
            SidebarLabel(name: self.name, icon: self.icon, color: self.iconBgColor)
        }
        .tag(self)
    }
    
    @ViewBuilder
    func SidebarLabel(name: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .sidebarSettingsIcon(color: color)
            }
            Text(name)
        }
    }
}

extension View {

    /// Get the view as an icon for the sidebar settings.
    public func sidebarSettingsIcon(color: Color) -> some View {
        let cornerRadius = 4.0
        let shadowRadius = 0.5
        let sideLength = 20.0
        let iconShadowRadius = 4.0
        let iconPadding = 3.0
        let rect = RoundedRectangle(cornerRadius: cornerRadius)
            .shadow(radius: shadowRadius)
            .aspectRatio(contentMode: .fit)
            .frame(width: sideLength, height: sideLength)
        @ViewBuilder var view: some View {
            if #available(macOS 13, *) {
                rect.foregroundStyle(color.gradient)
            } else {
                rect.foregroundStyle(color)
            }
        }
        return view.overlay {
            font(.body.bold())
                .symbolVariant(.square)
                .foregroundStyle(.white)
                .padding(iconPadding)
        }
    }
}

private extension ContentView {
    var stateBadgeModifier: some ViewModifier {
        struct ConditionalBadge: ViewModifier {
            let hasUpdate: Bool
            func body(content: Content) -> some View {
                if hasUpdate { content.badgeCompact(1) } else { content }
            }
        }
        return ConditionalBadge(hasUpdate: {
            if case .none = appUpdater.state { return false } else { return true }
        }())
    }
}

/// draw badge
struct BadgeCompact: ViewModifier {
    var count: Int = 1
    func body(content: Content) -> some View {
        HStack {
            content
            Circle().fill(.red).frame(width: 16, height: 16)
                .overlay {
                    Text("\(count)")
                        .foregroundStyle(.white)
                }
        }
    }
}

extension View {
    func badgeCompact(_ count: Int = 1) -> some View {
        modifier(BadgeCompact(count: count))
    }
}


#Preview {
    ContentView()
}
