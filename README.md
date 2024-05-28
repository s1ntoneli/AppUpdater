# AppUpdater
A simple app-updater for macOS, checks your GitHub releases for a binary asset and silently updates your app.

![CleanShot 2024-04-26 at 18 49 42@2x](https://github.com/s1ntoneli/AppUpdater/assets/2681464/5cb7d9db-3b27-4b96-818e-0df57a012615)

## Caveats

* We make no allowances for ensuring your app is not being actively used by the user
    at the time of update. PR welcome.
* Assets must be named: `\(reponame)-\(semanticVersion).ext`. See [semantics Version](https://github.com/mxcl/Version)
* Will not work if App is installed as a root user.

## Features

* Full semantic versioning support: we understand alpha/beta etc.
* We check the code-sign identity of the download matches the app that is
    running before doing the update. Thus if you don’t code-sign I’m not sure what
    would happen.
* We support zip files or tarballs.

## Usage

```swift
package.dependencies.append(.package(url: "https://github.com/s1ntoneli/AppUpdater.git", from: "0.1.1"))
```

Then:

```swift
// init
var appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater", releasePrefix: "AppUpdaterExample", interval: 3 * 60 * 60)

// check and auto download
appUpdater.check()
appUpdater.check { // success } fail: { err in // failed }

// install
appUpdater.install()
appUpdater.install { // success } fail: { err in // failed }
appUpdater.install(appBundle)

// for auto checking

// If you only care about new updates: subscribe the observable object
appUpdater.$downloadedAppBundle
    .sink { newBundle in
        if let newBundle {
            // do success things
            print("newBundle")
            appUpdater.install()
        }
    }
    .store(in: &cancellables)

// If you prefer callbacks instead
appUpdater.onDownloadSuccess = {
    // do success things
    print("download success")
    appUpdater.install()
}

// and want to get notified when download fails
appUpdater.onDownloadFail = { err in
    // do failing things
    print("download failed")
}

// Get notified when install succeeds
// but now you won't get a callback because the application will restart when the installation is successful
appUpdater.onInstallSuccess = {
    // do success things
    print("install success")
}

// Get notified when install fails
appUpdater.onInstallFail = { err in
    // do failing things
    print("install failed")
}
```

Demo:

```swift
struct ContentView: View {
    @EnvironmentObject var appUpdater: AppUpdater
    
    var body: some View {
        VStack {
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
            
            Button {
                appUpdater.check()
            } label: {
                Text("Check Update")
            }
        }
    }
}

```

## Alternatives

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Mac)

## References
* [AppUpdater](https://github.com/mxcl/AppUpdater)

## My Apps
* [CleanClip](https://cleanclip.cc): The cleanest clipboard manager on macOS.
* [Macaify](https://macaify.com): Fast use of ChatGPT on macOS.
* [Copi](https://copi.cleanclip.cc): A secure clipboard to copy and paste.
