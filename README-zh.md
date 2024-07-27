# AppUpdater
一款适用于 macOS 应用的更新检查库，可检查你的 GitHub 发行版中是否有新的二进制资产文件，并自动静默更新你的应用程序。

[English](./README.md) · **简体中文**

https://github.com/user-attachments/assets/8bc9221d-365e-43ba-99d5-dc5cbd565959

AppUpdater 是对 [mxcl](https://github.com/mxcl/AppUpdater) 的 [AppUpdater](https://github.com/mxcl/AppUpdater) 项目的重写，原因是我不想依赖它所使用的 PromiseKit，而更倾向于使用 async/await 来实现。

## 注意事项

* 资产文件必须按照 `\(name)-\(semanticVersion).ext` 的格式命名。参见 [Semantic Version](https://github.com/mxcl/Version)
* 只支持非沙盒化的应用程序

## 特性

* 完整的语义化版本支持：我们能够理解 alpha/beta 等版本
* 在更新之前,我们会检查下载文件的代码签名是否与当前运行的应用程序匹配。所以如果你没有对应用程序进行代码签名，我不确定会发生什么情况
* 我们支持 zip 文件和 tar 包
* 我们支持代理参数,以便那些无法正常访问 GitHub 的地区的用户也能使用
* 预置一个适用于 SwiftUI 的更新设置页

## 使用简单

### Swift 包管理器
```swift
package.dependencies.append(.package(url: "https://github.com/s1ntoneli/AppUpdater.git", from: "0.1.7"))
```

### 初始化
```swift
var appUpdater = AppUpdater(owner: "s1ntoneli", repo: "AppUpdater")
```

### 检查更新并自动下载
```swift
appUpdater.check()
```

### 手动安装
```swift 
appUpdater.install()
```

### SwiftUI
**AppUpdater 是一个 `ObservableObject`**，可以直接在 SwiftUI 中使用。

### 更多用法

查看 [AppUpdaterExample](https://github.com/s1ntoneli/AppUpdater/tree/main/Examples/AppUpdaterExample/AppUpdaterExample) 项目:

**初始化、监听：** [AppUpdaterExampleApp.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/AppUpdaterExampleApp.swift)

**SwiftUI 设置页：** [AppUpdaterSettings.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/AppUpdaterSettings.swift)

**实现自定义代理：** [GithubProxy.swift](https://github.com/s1ntoneli/AppUpdater/blob/main/Examples/AppUpdaterExample/AppUpdaterExample/GithubProxy.swift)

**代理实现参考 Gist：** [github-api-proxy.js](https://gist.github.com/s1ntoneli/69ef19899710d25c77a93e9b6e433c5b)

## 替代方案

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Windows)

## 参考

* [AppUpdater](https://github.com/mxcl/AppUpdater)

## 我的应用

* [CleanClip](https://cleanclip.app): macOS 上最干净的剪贴板管理器。
* [Macaify](https://macaify.app): 在 macOS 上快速使用 ChatGPT。
* [Copi](https://copi.app): 一款主打安全的剪贴板工具，提供了不依赖系统剪贴板的复制能力。
