# Managed Feed Provider

`ManagedReleaseProvider` 适用于这样一种接入方式：

- 继续使用 AppUpdater 现有的下载、校验、安装流程
- 但把 release 列表、会员状态说明、安装后权限提示交给自己的后端返回

## 适用场景

当你的应用满足以下情况时，推荐使用这个模式：

- 安装包仍然放在 GitHub Releases 或其他公共下载源
- 你的后端需要决定用户应看到什么会员/权限提示
- 即使会员功能不可用，仍然希望用户看到所有版本和更新日志
- 希望把更新引擎继续留在 AppUpdater，而不是在 App 层重写一套更新逻辑

## 后端返回什么

后端仍然返回标准的 `{ success, data, error }` 包装结构：

```json
{
  "success": true,
  "data": {
    "latest": { "tag_name": "1.8.0" },
    "entitlement": {
      "status_code": "FREE_FEATURES_LOCKED",
      "status_message": "You can update to the latest version, but member-only features require an active membership."
    },
    "releases": [
      {
        "tag_name": "1.8.0",
        "name": "ScreenSage 1.8.0",
        "body": "- Added batch OCR",
        "html_url": "https://github.com/example/app/releases/tag/1.8.0",
        "prerelease": false,
        "assets": [
          {
            "name": "ScreenSage-1.8.0.zip",
            "content_type": "application/zip",
            "browser_download_url": "https://github.com/example/app/releases/download/1.8.0/ScreenSage-1.8.0.zip"
          }
        ],
        "policy": {
          "install_allowed": true,
          "member_features_active_after_install": false,
          "code": "INSTALL_ALLOWED_FEATURES_LOCKED",
          "message": "This version can be installed, but member-only features will remain locked after installation."
        }
      }
    ],
    "notices": [
      {
        "level": "info",
        "code": "UPDATE_AVAILABLE",
        "message": "A newer version is available."
      }
    ]
  },
  "error": null
}
```

## AppUpdater 会怎么处理

- `data.releases` 继续解码成正常的 `Release`
- `entitlement` 会暴露为 `updater.entitlement`
- `notices` 会暴露为 `updater.notices`
- `policy` 会挂在每个 `Release` 上，便于在现有更新 UI 中展示“安装后会员功能是否可用”

## 典型初始化方式

```swift
let updater = AppUpdater(
    owner: "ignored",
    repo: "ignored",
    provider: ManagedReleaseProvider(
        feedURL: URL(string: "https://example.com/api/public/app-updates/feed")!,
        licenseProvider: { licenseKey },
        currentVersionProvider: { Bundle.main.version.description },
        deviceIdProvider: { deviceId },
        platform: "macos"
    )
)
```

## App 层通常还需要做什么

App 层通常只需要：

- 提供 `license`、`deviceId`，以及可选的 `currentVersion`
- 对 `entitlement.statusCode`、`policy.code`、`notices[*].code` 做本地化
- 决定 `cta.url` 在你的 UI 中如何打开

App 层通常**不需要**重新实现 release 选择、下载或安装逻辑。

## 说明

- release 资产命名仍应满足 AppUpdater 原有的归档格式要求
- 后端返回的下载 URL 可以继续指向 GitHub Releases、R2 或其他下载源
- 这个模式适合“App 可更新性”和“高级功能可用性”需要分开表达的产品
