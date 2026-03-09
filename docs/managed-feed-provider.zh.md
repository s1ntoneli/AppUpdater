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

## App 端接入清单

一个宿主 App 通常只需要完成这些步骤：

1. 准备固定的后端 feed URL，例如 `/api/public/app-updates/feed`
2. 通过 `licenseProvider` 提供当前 license key
3. 通过 `deviceIdProvider` 提供稳定的设备 ID
4. 如果你的版本来源不是 `Bundle.main.version`，再覆盖 `currentVersionProvider`
5. 像以前一样调用 `updater.check()`
6. 在 App 层对 `entitlement.statusCode`、`policy.code`、`notices[*].code` 做本地化
7. 根据你的产品流打开 `cta.url`

## 典型初始化方式

```swift
final class UpdateCenter: ObservableObject {
    static let shared = UpdateCenter()

    let updater: AppUpdater

    private init() {
        updater = AppUpdater(
            owner: "ignored",
            repo: "ignored",
            provider: ManagedReleaseProvider(
                feedURL: URL(string: "https://example.com/api/public/app-updates/feed")!,
                licenseProvider: { LicenseStore.shared.currentKey },
                currentVersionProvider: { Bundle.main.version.description },
                deviceIdProvider: { DeviceIdentity.shared.stableDeviceID },
                platform: "macos"
            )
        )
    }
}
```

## SwiftUI 宿主示例

```swift
struct UpdatesView: View {
    @EnvironmentObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entitlement = updater.entitlement {
                Text(localizedEntitlementText(for: entitlement.statusCode))
                Text(entitlement.statusMessage)
                    .foregroundStyle(.secondary)
            }

            ForEach(updater.notices, id: \.code) { notice in
                Text(localizedNoticeText(for: notice.code))
            }

            if let release = updater.state.release,
               let policy = release.policy {
                Text(localizedPolicyText(for: policy.code))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Check for Updates") {
                updater.check()
            }
        }
    }
}
```

## 本地化建议

建议把 `code` 作为主判断字段，把 `message` 作为兜底文案。

推荐顺序：

1. 先读取 `code`
2. 在 App 内映射为本地化文案
3. 如果本地还没有这个映射，再退回到后端给的 `message`

典型字段包括：

- `entitlement.statusCode`
  - `MEMBER_FEATURES_ACTIVE`
  - `MEMBER_FEATURES_EXPIRED`
  - `FREE_FEATURES_LOCKED`
- `release.policy.code`
  - `INSTALL_ALLOWED_FEATURES_ACTIVE`
  - `INSTALL_ALLOWED_FEATURES_EXPIRED`
  - `INSTALL_ALLOWED_FEATURES_LOCKED`
- `notices[*].code`
  - `UPDATE_AVAILABLE`
  - `ALREADY_UP_TO_DATE`
  - `MEMBERSHIP_EXPIRED_AFTER_INSTALL`

## 设备 ID 建议

`deviceIdProvider` 应返回当前机器的稳定标识。

推荐特征：

- App 重启后保持不变
- 不同机器之间不同
- 存储在 Keychain 或其他持久化位置
- 不要每次启动都重新生成

如果你的应用已经有设备激活系统，建议直接复用同一个设备 ID。

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
