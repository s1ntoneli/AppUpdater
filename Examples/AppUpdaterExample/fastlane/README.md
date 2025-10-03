fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac release

```sh
[bundle exec] fastlane mac release
```

Push a new release build to the App Store

### mac test_changelog_assets

```sh
[bundle exec] fastlane mac test_changelog_assets
```

Test: list localized changelog assets that would be uploaded

### mac test_github_upload

```sh
[bundle exec] fastlane mac test_github_upload
```

Test: create a GitHub release with only localized changelog assets

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
