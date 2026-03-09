# Managed Feed Provider

`ManagedReleaseProvider` is the integration mode for apps that want to keep AppUpdater's existing download and install flow, while moving release selection and membership messaging to their own backend.

## When to use it

Use this provider when:

- your app still ships update archives through GitHub Releases or another public file host
- your backend needs to decide what membership or entitlement message the user should see
- you want to show all release notes, even when premium features are inactive
- you want AppUpdater to stay as the update engine, instead of rebuilding update UI logic in the app layer

## What the backend should return

The backend still returns the standard envelope:

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

## What AppUpdater does with it

- `data.releases` is decoded into the normal `Release` model
- `entitlement` is exposed as `updater.entitlement`
- `notices` is exposed as `updater.notices`
- `policy` is attached to each `Release`, so your existing update settings UI can show post-install membership messaging

## Typical setup

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

## App-layer responsibilities

The app layer usually only needs to:

- provide `license`, `deviceId`, and optionally `currentVersion`
- localize `entitlement.statusCode`, `policy.code`, and `notices[*].code`
- decide where `cta.url` should open in your UI

The app layer does **not** need to reimplement release selection, archive download, or installation.

## Notes

- release assets should still follow AppUpdater's normal archive expectations
- the backend can point asset URLs to GitHub Releases, R2, or any other downloadable archive host
- this mode is intended for apps where update availability and premium-feature availability are separate concerns
