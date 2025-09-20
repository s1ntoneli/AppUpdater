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

## 架构与概念

- 核心：`AppUpdater` 检查 GitHub Releases，选择合适资产，下载、校验签名并安装。
- 视图：`AppUpdateSettings`（SwiftUI）展示当前状态与发行说明（Markdown 渲染）。
- Provider：数据来源抽象。
  - `GithubReleaseProvider`（默认）直连 GitHub。
  - `MockReleaseProvider`（离线）从包内资源读取 Release 与附件，模拟下载进度并生成最小 .app 压缩包。

## Provider 与 Mock

- 通过初始化或运行时切换 provider：

```swift
let updater = AppUpdater(owner: "...", repo: "...", provider: GithubReleaseProvider())
// 或
updater.provider = MockReleaseProvider()
updater.skipCodeSignValidation = true // 使用 Mock 时建议跳过签名校验
```

- Mock 数据：
  - Releases JSON：`Sources/AppUpdater/Resources/Mocks/releases.mock.json`
  - 多语言更新说明附件：包内的 `CHANGELOG.<lang>.md`
  - 模拟下载：`MockReleaseProvider.download` 按进度流式输出，并生成最小 `.app` 压缩包。

## 本地化（Localization）

- UI 文案：`AppUpdaterSettings` 已本地化（英文、简体中文）。如需新增语言，在 `Sources/AppUpdater/Resources` 下添加 `*.lproj/Localizable.strings`。
- 更新日志本地化：提供两种独立方式，你可任选其一（亦可混用，附件优先）。
  1) 方式一：通过正文注释块（下节）
  2) 方式二：通过附件文件（再下节）

### 方式一：通过正文注释块

在 Release 的正文中，使用 HTML 注释包裹不同语言的内容：

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

可选地提供默认块作为兜底：

```
<!-- au:default -->
- General improvements
<!-- au:end -->
```

选择策略：优先从 `AppUpdater.preferredChangelogLanguages`（默认 `Locale.preferredLanguages`）中择优匹配；若无匹配则回退到 `default`，仍无则尝试 `en`，最后回退到第一个语言块。若正文没有任何语言块，则原样显示整个正文。

### 方式二：通过附件文件

- 也可以在 GitHub Release 中附加语言专属的文件，命名例如：
  - `CHANGELOG.en.md`、`CHANGELOG.zh-Hans.md`、`CHANGELOG.zh-Hant.md`（也支持 `.txt`）
- AppUpdater 会优先读取这些附件（按用户语言偏好匹配）；若没有匹配才会回退到正文中的多语言块解析方案。
- 示例与 Mock 已内置这些附件文件，便于离线测试。

## 示例 App（macOS）

- 打开 `Examples/AppUpdaterExample/AppUpdaterExample.xcodeproj`
- 在 General 页面：
  - 勾选 “Use Mock Data” 离线演示
  - 在 “Changelog Languages” 输入如 `fr, ja, en`，点击 Apply
  - 点击 “Check Updates”，进入 “Software Updates Available” 查看本地化更新日志
- 示例工程 Debug 构建已配置为无需签名的本地构建。

### 调试与诊断

- 在更新设置页（Software Updates Available）中有 “Diagnostics” 区域，可打印各步骤的日志。
- 打开 “Enable Logs” 后会记录：获取 releases、选中的 release/asset、下载进度、解压结果、代码签名校验等。
- “Last Error” 会展示最近一次 `check()` 或安装流程中的错误，便于定位问题。

## 命令行 Mock Runner

- 运行：`swift run AppUpdaterMockRunner --langs=fr,ja,en`
- 终端会打印状态流转与本地化更新说明（优先附件，其次正文标记块）。

## 常见问题

- UI 中更新日志为空？
  - 使用 GitHub provider 时，请确保 Release 正文包含语言块，或在 Release 中附加 `CHANGELOG.<lang>.md` 作为附件。
  - 使用 Mock provider 时，示例 v2.0.0 已附带多语言附件用于演示。
  - 可通过 `updater.preferredChangelogLanguages = ["zh-Hans", "en"]` 或示例页面的输入框设置语言优先级。

## Mock Provider 与本地测试

- 内置 `MockReleaseProvider`，无需网络即可测试完整流程：
  - 使用 `Sources/AppUpdater/Resources/Mocks/releases.mock.json` 作为 Release 数据源。
  - 运行时生成最小化 `.app` 并打包为 zip，模拟下载进度。
  - 测试时可设置 `appUpdater.skipCodeSignValidation = true` 跳过签名校验。

- 命令行快速运行：
  - 执行 `swift run AppUpdaterMockRunner`
  - 会输出状态变化，整个过程不会覆盖你已安装的应用。

- 示例 App（macOS）：
  - 在 General Settings 中切换 “Use Mock Provider”（重启示例 App 生效），点击 “Check Updates”。

## 替代方案

* [Sparkle](https://github.com/sparkle-project/Sparkle)
* [Squirrel](https://github.com/Squirrel/Squirrel.Windows)

## 参考

* [AppUpdater](https://github.com/mxcl/AppUpdater)

## 我的应用

* [CleanClip](https://cleanclip.app): macOS 上最干净的剪贴板管理器。
* [Macaify](https://macaify.app): 在 macOS 上快速使用 ChatGPT。
* [Copi](https://copi.app): 一款主打安全的剪贴板工具，提供了不依赖系统剪贴板的复制能力。
