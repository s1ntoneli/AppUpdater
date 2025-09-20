# AppUpdater
A simple app-updater for macOS, checks your GitHub releases for a binary asset and silently updates your app. 

**English** · [简体中文](./README-zh.md)

https://github.com/user-attachments/assets/8bc9221d-365e-43ba-99d5-dc5cbd565959

AppUpdater is a rewrite of [mxcl](https://github.com/mxcl)'s [AppUpdater](https://github.com/mxcl/AppUpdater), because I don't want to depend on the PromiseKit it uses and would prefer to implement it using async/await.

## Caveats

* Assets must be named: `\(name)-\(semanticVersion).ext`. See [Semantic Version](https://github.com/mxcl/Version)
* Only non-sandboxed apps are supported
* Implement a settings update page suitable for SwiftUI

## Features  

* Full semantic versioning support: we understand alpha/beta etc.
* We check that the code-sign identity of the download matches the running app before updating. So if you don't code-sign I'm not sure what would happen.
* We support zip files or tarballs.
* We support a proxy parameter for those unable to normally access GitHub

## Super Easy to Use

### Swift Package Manager
```swift 
package.dependencies.append(.package(url: "https://github.com/s1ntoneli/AppUpdater.git", from: "0.1.5"))
```

### Initialize
```swift
var appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater")
```

### Check for Updates and Auto Download
```swift
appUpdater.check()
```

### Manual Install
```swift
appUpdater.install()
```

### SwiftUI
**AppUpdater is an ObservableObject**, can be used directly in SwiftUI.

### More Usage

See the [AppUpdaterExample](https://github.com/s1ntoneli/AppUpdater/tree/main/Examples/AppUpdaterExample/AppUpdaterExample) project:

**Initialize, Listen:** [AppUpdaterExampleApp.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/AppUpdaterExampleApp.swift)

**SwiftUI AppUpdaterSettings：** [AppUpdaterSettings.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/AppUpdaterSettings.swift)

**Implement Custom Proxy:** [GithubProxy.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/GithubProxy.swift)

**Proxy Implementation Reference Gist:** [github-api-proxy.js](https://gist.github.com/s1ntoneli/69ef19899710d25c77a93e9b6e433c5b)

## Architecture & Concepts

- Core: `AppUpdater` checks GitHub releases, selects a viable asset, downloads, validates code-signing, and installs.
- View: `AppUpdateSettings` (SwiftUI) shows current state and the release notes (MarkdownUI).
- Providers: data source abstraction.
  - `GithubReleaseProvider` (default) talks to GitHub API and assets.
  - `MockReleaseProvider` (offline) serves releases and assets from package resources, simulating progress and producing a minimal .app archive.

## Providers & Mock

- Swap providers via initializer or at runtime:

```swift
let updater = AppUpdater(owner: "...", repo: "...", provider: GithubReleaseProvider())
// or
updater.provider = MockReleaseProvider()
updater.skipCodeSignValidation = true // recommended when using mocks
```

- Mock data source:
  - Releases JSON: `Sources/AppUpdater/Resources/Mocks/releases.mock.json`
  - Changelog attachments: `CHANGELOG.<lang>.md` files in package resources
  - Simulated download: `MockReleaseProvider.download` streams progress and outputs a minimal `.app` inside a zip/tar as needed.

## Localization

- UI strings in `AppUpdaterSettings` are localized (English, Simplified Chinese). You may contribute more locales via `Sources/AppUpdater/Resources`.
- Localized changelog: AppUpdater can pick a localized section from your GitHub release body depending on the user's preferred languages.

### Localized Changelog Format

Add language-marked blocks in the release body using HTML comments:

```
<!-- au:lang=zh-Hans -->
- 修复若干问题
- 新增偏好设置项
<!-- au:end -->

<!-- au:lang=en -->
- Fix several issues
- Add a new preference option
<!-- au:end -->
```

Optionally, provide a default block used as a fallback:

```
<!-- au:default -->
- General improvements
<!-- au:end -->
```

AppUpdater selects the best match from `AppUpdater.preferredChangelogLanguages` (default: `Locale.preferredLanguages`), then falls back to `default`, then `en`, then the first block. If no blocks are found, the original release body is shown as-is.

### Localized Changelog via Attachments

- Alternatively, attach language-specific files to the GitHub release with names like:
  - `CHANGELOG.en.md`, `CHANGELOG.zh-Hans.md`, `CHANGELOG.zh-Hant.md`, etc. (`.txt` also works)
- AppUpdater will prefer these attachments (matching the user's preferred languages), and fall back to the body-based blocks above.
- In Example/Mock, these files live under the package resources and are wired up for offline testing.

## Example App (macOS)

- Open `Examples/AppUpdaterExample/AppUpdaterExample.xcodeproj`
- General page:
  - Toggle “Use Mock Data” to run fully offline
  - Set “Changelog Languages” (e.g. `fr, ja, en`) and Apply
  - Click “Check Updates” and open “Software Updates Available” to see localized notes
- The Example is configured for ad‑hoc Debug builds without a signing team.

### Diagnostics

- In the update settings screen, the “Diagnostics” section can print a step‑by‑step trace of the update flow.
- Toggle “Enable Logs” to capture logs such as fetching releases, selected release/asset, download progress, unzip results, and code‑sign validation.
- “Last Error” shows the most recent failure surfaced by `check()` or installation.

## CLI Mock Runner

- Run: `swift run AppUpdaterMockRunner --langs=fr,ja,en`
- Prints state transitions and the localized changelog (prefers attachments, then body blocks).

## Troubleshooting

- Empty changelog in UI?
  - If using GitHub provider, ensure the release body includes language blocks or attach `CHANGELOG.<lang>.md` assets.
  - With Mock provider, v2.0.0 includes multiple attachment files for offline tests.
  - You can set `updater.preferredChangelogLanguages = ["zh-Hans", "en"]` or via the Example’s input.

## Mock Provider & Local Testing

- A built-in `MockReleaseProvider` is available to test the full update flow without network:
  - Uses `Sources/AppUpdater/Resources/Mocks/releases.mock.json` to feed releases.
  - Materializes a minimal `.app` inside a zip at runtime and simulates download progress.
  - Set `appUpdater.skipCodeSignValidation = true` for mock installs.

- Quick CLI runner:
  - Build & run: `swift run AppUpdaterMockRunner`
  - Shows state transitions and completes without touching your installed app.

- Example app (macOS):
  - Toggle “Use Mock Provider” in General Settings (restart example app to take effect) and click “Check Updates”.

## Alternatives

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Mac)

## References
* [AppUpdater](https://github.com/mxcl/AppUpdater)

## My Apps
* [CleanClip](https://cleanclip.cc): The cleanest clipboard manager on macOS.
* [Macaify](https://macaify.com): Fast use of ChatGPT on macOS.
* [Copi](https://copi.cleanclip.cc): A secure clipboard to copy and paste.
