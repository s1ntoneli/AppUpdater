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

## Alternatives

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Mac)

## References
* [AppUpdater](https://github.com/mxcl/AppUpdater)

## My Apps
* [CleanClip](https://cleanclip.cc): The cleanest clipboard manager on macOS.
* [Macaify](https://macaify.com): Fast use of ChatGPT on macOS.
* [Copi](https://copi.cleanclip.cc): A secure clipboard to copy and paste.
