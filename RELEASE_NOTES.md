# Release Notes

<!--
cspell:words pubspec erickzanardo xcframeworks cupertino codesign codecov rkishan appbundle proto tlsv kingdomseed Peetee Aditya serde
 -->

## 1.6.95 (April 29, 2026)

- 🩺 Doctor: allow `FLUTTER_TARGET` override (commonly customized for flavor-specific entry points) and downgrade other `FLUTTER_*` build setting overrides from error to warning

## 1.6.94 (April 28, 2026)

- 🐦 Support for Flutter 3.41.8
  - Fixes iOS profile mode failing to connect to the Dart VM
  - Updater: enrich patch install failure messages with diagnostics
  - Updater: smaller binary via `panic=abort` and dropped backtrace features
  - Updater: atomic state writes and surface flush errors in disk_io
  - shorebird_code_push v2.0.6
- ✨ Add `--json` output mode for agentic CLI consumption
- 🩺 Doctor: detect hard-coded `FLUTTER_*` build settings in `Runner.xcodeproj/project.pbxproj` (covers both standard apps and Flutter modules)

## 1.6.93 (April 21, 2026)

- 🐦 Support for Flutter 3.41.7 & Dart 3.11.5
- 🔧 Updater: resumable downloads with streaming to disk
- 🔧 Updater: replace serde_yaml with hand-rolled parser for smaller binary
- 🔧 Updater: graceful handling of concurrent updates and SHOREBIRD_NO_UPDATE
- ✨ Capture build trace + privacy-safe summary on release
- ✨ Hint at --dart-define/--obfuscate mismatch on link failure
- ✨ Reject ExportOptions.plist with manageAppVersionAndBuildNumber
- ✨ Include snapshots in patch debug dump
- 🐛 Fix: only pass --shorebird-trace to build commands that support it
- 🐛 Fix: detect --obfuscate and --split-debug-info after --
- 🐛 Fix: fetch latest refs before resolving --flutter-version

## 1.6.92 (March 26, 2026)

- 🐦 Support for Flutter 3.41.6 & Dart 3.11.4

## 1.6.91 (March 25, 2026)

- 🔐 Support API keys for authentication ([docs](https://docs.shorebird.dev/account/api-keys/))
  - `login:ci` command has been deprecated
  - Create API keys through the [web console](https://console.shorebird.dev)

## 1.6.90 (March 24, 2026)

- 🐦 Support for Flutter 3.41.5 & Dart 3.11.3
- ✨ Add semantic DEX diffing to suppress false native change warnings
- ✨ Suggest cache clean in build failure recommendations
- 🔐 Revoke sessions on CLI logout
- ⚠️ Warn that preview reinstalls the app on mobile
- 🤫 Suppress Gradle welcome message during init
- 🐛 Fix: select correct executable in Windows preview
- 🐛 Fix: show friendly error message when GitHub is down
- 🐛 Fix: list orgs and exit gracefully when init is non-interactive
- 🐛 Fix: resolve JWT issuer from ShorebirdEnv instead of from Auth URL

## 1.6.89 (March 18, 2026)

- 🐛 Fix: roll back Flutter 3.41.4 to address increased link times
- 🍎 Add `.pkg` distribution warning to macOS post-release instructions
- 🧹 Remove Plan model from protocol package

## 1.6.88 (March 13, 2026)

- 📉 Link percentage improvements (for Flutter 3.41.4)
- 🔍 Improved debug dumps for obfuscated patches (for Flutter 3.41.4)
- 🐛 Fix: invalidate bootstrap stamp when Flutter version changes
- 🐛 Fix: clean stale obfuscation map from supplement directory

## 1.6.87 (March 5, 2026)

- 🔐 `shorebird login` now uses the new Shorebird auth service.

## 1.6.86 (March 4, 2026)

- 🐦 Support for Flutter 3.41.4

## 1.6.85 (March 2, 2026)

- 🐦 Support for Flutter 3.41.3

## 1.6.84 (February 27, 2026)

- ✨ Add `--obfuscate` support to the `release` command (starting with Flutter 3.41.2)
- ✨ Add `--confirm` flag to `release` and `patch` commands
- 🔐 Support RSA JWK key stores for Shorebird auth
- 🐛 Fix: use forward slashes in AAB ZIP entries on Windows
- 🍎 Fix: add dSYM artifact proxy patterns for new filenames

## 1.6.83 (February 20, 2026)

- 🐦 Support for Flutter 3.41.2
- ✨ Add AuthProvider to code push protocol

## 1.6.82 (February 13, 2026)

- 🐦 Support for Flutter 3.41.1

## 1.6.81 (February 11, 2026)

- 🐦 Support for Flutter 3.41.0
- ✨ Add `--public-key-cmd` and `--sign-cmd` support for external signing tools
- ✨ Add features param to code push protocol
- 🐛 Fix: support PKCS#1 private key format for patch signing

## 1.6.80 (February 3, 2026)

- 🐦 Support for Flutter 3.38.9

## 1.6.79 (February 3, 2026)

- 🐦‍⬛ Fix regression in Flutter 3.38.7. readCurrentPatch returning null: shorebird#3488
- 🐛 Fix: `--flutter-version=hash` stopped working.
- 🐛 Fix: stop unnecessary rebuild on every CLI invocation.
- 🍎 Improve error displayed for malformed plist files.
- 🍧 Allow adding flavors without resetting base app_id.
- ✨ Improve release selection UX with date display and truncation.
- 📝 Don't reformat AndroidManifest.xml when modifying it.
- ⚠️ Warn if `patch_verification` is in shorebird.yaml but `public-key-path` is not set.

## 1.6.78 (January 26, 2026)

- ⚙️ Fix: using FlutterEngineGroup could cause patches to fail.

## 1.6.77 (January 16, 2026)

- 🐦 Support for Flutter 3.38.7
- ⏱️ Support patch_verification: install_only for faster boot of very large patches.

## 1.6.76 (January 11, 2026)

- 🐦 Support for Flutter 3.38.6

## 1.6.75 (January 6, 2026)

- 🐛 Re-enable Flutter 3.38.5 as default (iOS crasher fixed).
- ✅ Remove y/N confirmation from both `shorebird patch` and `shorebird release`.
- 🍎 Asset changes on iOS now show a Assets.car diff.

## 1.6.74 (December 29, 2025)

- 🔄 Temporarily roll back to 3.38.4 while we investigate a crash on iOS.

## 1.6.73 (December 19, 2025)

- 🐦 Hotfix for 3.38.5 to fix an issue where releases with rolled back patches
  were not always updating properly.
- 🛤️ Added `shorebird patches set-track` command, which lets you put a given
  patch number on any track you'd like.

## 1.6.72 (December 16, 2025)

- 🐦 Support for Flutter 3.38.5

## 1.6.71 (December 5, 2025)

- 🐦 Support for Flutter 3.38.4
- 🩹 Handle unsupported Flutter versions more gracefully, thanks @EclipseAditya!

## 1.6.70 (November 26, 2025)

- 🩹 Fix Shorebird builds with Dart hooks and Dart 3.10.0 and 3.10.1.

## 1.6.69 (November 24, 2025)

- 🐦 Support for Flutter 3.38.3

## 1.6.68 (November 24, 2025)

- 🐦 Support for Flutter 3.38.2
- 📈 Better analytics for improved customer support

## 1.6.67 (November 17, 2025)

- 🐦 Support for Flutter 3.38.1

## 1.6.66 (October 27, 2025)

- 🐦 Support for Flutter 3.35.7
- 🩹 Fix broken troubleshooting links
- 🧹 Various dependency upgrades

## 1.6.65 (October 14, 2025)

- 🐦 Support for Flutter 3.35.6
- 🍧 Enable flavor support for single platforms by warning instead of erroring
  when no flavor is provided to an app that supports flavors.
- 🔎 Handle missing shorebird.yaml file gracefully when promoting a patch
  (thanks @Peetee06!)

## 1.6.64 (October 9, 2025)

- 🐞 fix: only validate patches on boot. This improves startup time and
  performance for apps that use patch signing.

## 1.6.63 (September 30, 2025)

- 🪟 fix: use correct executable on windows when multiple executables are generated (thanks @kingdomseed!)

## 1.6.62 (September 29, 2025)

- 🐦 Support for Flutter 3.35.5

## 1.6.61 (September 23, 2025)

- 🐞 Fix bug where Flutter 3.35.4 would incorrectly use Dart 3.9.0

## 1.6.60 (September 17, 2025)

- 🐛 Fix platform flavor support check

## 1.6.59 (September 17, 2025)

- 🐦 Support for Flutter 3.35.4
- 🍧 Better handling for platforms that don't support flavors
- 🧹 Various dependency upgrades

## 1.6.58 (September 5, 2025)

- 🐦 Support for Flutter 3.35.3

## 1.6.57 (August 26, 2025)

- 🐦 Support for Flutter 3.35.2

## 1.6.56 (August 6, 2025)

- 🐛 Fixes a bug where `shorebird preview` fails due to unavailable iOS devices

## 1.6.55 (July 25, 2025)

- 🐦 Support for Flutter 3.32.8

## 1.6.54 (July 25, 2025)

- Performance improvements for very large (50k+ function) applications
  - Multi-second reduction in patch load time (startup speed)
  - Multi-minute reduction in patch compile time.
  - Small reduction in patch memory use and disk space requirements.

Apps need to make a new release with Flutter 3.32.7 or later to benefit from
these improvements.

## 1.6.53 (July 24, 2025)

- ⚡️ fail fast if existing release already exists
  - only applies when specifying `--build-name` (and optionally `--build-number`)

## 1.6.52 (July 17, 2025)

- 🐦 Support for Flutter 3.32.7
- 📈 Increase minimum link percentage threshold to 90%

## 1.6.51 (July 15, 2025)

- 🪟 Fixes a Windows bug where large build identifiers (the `4` in `1.2.3+4`)
  would be misreported due to overflow. You are only affected if you publish
  Windows desktop apps and use build identifiers greater than 65,525 (2^16 - 1).

## 1.6.50 (July 10, 2025)

- 🐦 Support for Flutter 3.32.6
- 📦 Update bundletool from 1.17.1 to 1.18.1
- 🧹 Remove legacy, deprecated `shorebird run` command

## 1.6.49 (June 26, 2025)

- 🐦 Support for Flutter 3.32.5
- 🧹 Various dependency upgrades

## 1.6.48 (June 19, 2025)

- 🪟 Forward `--target` and additional args to build step on Windows

## 1.6.47 (June 17, 2025)

- 🐦 Add app_id to patch path on desktop targets

## 1.6.46 (June 17, 2025)

- ✨ Add new `shorebird create` command

## 1.6.45 (June 16, 2025)

- 🐦 Support for Flutter 3.32.4
- 🧹 Various dependency upgrades

## 1.6.44 (June 12, 2025)

- 🐦 Support for Flutter 3.32.3
- 🧹 Various dependency upgrades

## 1.6.43 (June 5, 2025)

- 🐦 Support for Flutter 3.32.2
- 🩹 Fix crashes present in 3.32.1

## 1.6.42 (June 4, 2025)

- 📈 iOS linking improvements
- 🩹 Fix crashes on non-arm64 platforms

## 1.6.41 (May 30, 2025)

- 🐦 Support for Flutter 3.32.1
- 🍎 Upload podfile lock hashes for iOS and macOS

## 1.6.40 (May 29, 2025)

- 📈 iOS linking improvements (especially when using `--split-debug-info`)
- 🛤️ Support for custom update tracks

## 1.6.39 (May 27, 2025)

- 🐦 Support for Flutter 3.32.0

## 1.6.38 (May 16, 2025)

- ✅ No intended changes. Last expected release before Flutter 3.32.0.

## 1.6.37 (May 13, 2025)

- 👀 `shorebird preview` deprecate `--staging` in favor of `--track=staging`
- 🧹 Various dependency upgrades

## 1.6.36 (April 23, 2025)

- 💯 show release download progress in `shorebird preview`
- 🪵 diagnostic improvements for low linking edge cases on iOS
- 🧹 Various dependency upgrades

## 1.6.35 (April 23, 2025)

- 🪵 improve debug logs in cases where patches have low link percentages
- 🧹 Various dependency upgrades

## 1.6.34 (April 16, 2025)

- 📚 Fix several broken docs links

## 1.6.33 (April 15, 2025)

- 🐦 Support for Flutter 3.29.3
- 🍧 Fix `shorebird init` flavor case sensitivity
- 🧹 Various dependency upgrades

## 1.6.32 (March 27, 2025)

- 🪧 Add `shorebird release` build failure recommendations
- 🐧 Fix `shorebird release linux` not forwarding all build args
- 🐛 Fix diff generation due to whitespace in paths on windows

## 1.6.31 (March 26, 2025)

- 🚀 iOS patch performance improvements (sorted field table)
- 🧹 Remove outdated note from `shorebird release` output

## 1.6.30 (March 24, 2025)

- 🐛 Fix using older Flutter versions that do not include `flutter config`
- 🪟 Fix build failures caused by whitespace in paths on windows
- 🧹 Various dependency upgrades

## 1.6.29 (March 18, 2025)

- 🪵 improve `gradlew` logs during `shorebird init`
- 🧼 sanitize executable paths on windows
- 📦 fix `bundletool` execution on windows

## 1.6.28 (March 17, 2025)

- ⚙️ add `shorebird flutter config` command
- 🪟 `shorebird release windows` should support `--flutter-version=<hash>`
- 🧹 Various dependency upgrades

## 1.6.27 (March 15, 2025)

- 🩹 Fix error in `shorebird release windows` when no `--flutter-version` is specified.

## 1.6.26 (March 14, 2025)

- 🐦 Support for Flutter 3.29.2
- ✨ `shorebird release` supports `--flutter-version=latest`
- ⚠️ Show warning when running `shorebird patch` without an explicit `--release-version`
- 🧹 Various dependency upgrades

## 1.6.25 (March 12, 2025)

- ☕️ Use `jdk-dir` override from `flutter config` if specified
- 🔐 Add patch signing support for hybrid apps (`aar` and `ios-framework`)

## 1.6.24 (March 12, 2025)

- 🛠️ Stream `flutter build` logs during `shorebird release` and `shorebird patch`
- ⚠️ Improve `flutter build` errors during `shorebird release` and `shorebird patch`
- 🧹 Various dependency upgrades

## 1.6.23 (March 10, 2025)

- 🍎 Fix async ffi crashes (seen in package:cupertino_http)

## 1.6.22 (March 7, 2025)

- 🐦 Support for Flutter 3.29.1
- 🧹 Various dependency upgrades

## 1.6.21 (March 7, 2025)

- 🎯 Fix iOS patching errors due to Dart SDK hash mismatches

## 1.6.20 (February 27, 2025)

- 🐚 Fix `powershell` execution on Windows due to whitespace in file paths
- 🧹 Various dependency upgrades

## 1.6.19 (February 19, 2025)

- 📝 Fix `shorebird release` descriptions for `--build-name` and `--build-number`

## 1.6.18 (February 18, 2025)

- ↩️ Fix rollbacks when automatic updates are disabled

## 1.6.17 (February 14, 2025)

- 🐦 Support for Flutter 3.29.0

## 1.6.16 (February 12, 2025)

- 🩹 Updates package:shorebird_code_push integration to apply rollbacks when
  checking for patches.

## 1.6.15 (February 12, 2025)

- 🎯 Fix iOS compilation crash due to incorrect object pool detection
- ℹ Improve error messages for certain recognized issues
- 📦 Improve handling of archiving failures

## 1.6.14 (February 7, 2025)

- 🪵 Improved logging for patch downloads and applications.

## 1.6.13 (February 7, 2025)

- 🩹 Fixes an issue with iOS patching on Flutter 3.27.4 (missing
  analyze_snapshot_arm64)
- 🖥️ Desktop platforms are now out of beta!

## 1.6.12 (February 6, 2025)

- 🐦 Support for Flutter 3.27.4

## 1.6.11 (February 5, 2025)

- 🛡️ Add `--min-link-percentage` to patch command
- 📦 Export patch debug information when running in Codemagic CI/CD

## 1.6.10 (February 4, 2025)

- 🪟 Fix a bug where `pkg:shorebird_code_push` was not working for Windows
  apps
- 🧩 Improve handling of missing platforms in `shorebird patch`
- 🤖 Improve handling of malformed CI tokens

## 1.6.9 (February 3, 2025)

- 🩹 Write patch debug info when running `shorebird patch ios-framework`

## 1.6.8 (January 31, 2025)

- 🐧 Linux support is now in beta!
- 🍎 macOS preview supports staged patches
- 🪟 Windows preview supports staged patches

## 1.6.7 (January 27, 2025)

- 🍎 Shorebird macOS apps can now run on Intel Macs!
- 🏃 macOS patches now run at full speed (there is no longer a performance
  impact for patched code).

## 1.6.6 (January 23, 2025)

- 🪟 Remove native change detection from Windows because builds are not stable
  between machines.

## 1.6.5 (January 22, 2025)

- 🐦 Support for Flutter 3.27.3
- 🍡 Add flavor support to macOS
- 🕵 Improvements to `shorebird preview`
- 🗓️ Add support for `shorebird patch [platform] --release-version=latest` to
  patch the most recently updated release.

## 1.6.4 (January 16, 2025)

- 🔐 Add support for signed patches on Windows
- ✨ `shorebird patch` releases list should filter by specified platform
- 👀 Fix various `shorebird preview` errors on macOS (`ditto`)
- 🧑‍🔧 Improve error message when running `shorebird release macos` on an unsupported Flutter project

## 1.6.3 (January 14, 2025)

- 🐦 Support for Flutter 3.27.2
- 🩹 Fix `shorebird release` entitlement validation when `plist` contains comments

## 1.6.2 (January 14, 2025)

- 🔎 Detect native changes in Windows patches
- 👀 Fix `shorebird preview` on Android systems with no hardware keys

## 1.6.1 (January 13, 2025)

- 🤖 Fix link rendering in CI environments

## 1.6.0 (January 9, 2025)

- 🪟 Windows beta support!

## 1.5.5 (January 6, 2025)

- 🔐 Add custom keystore support to `shorebird preview`
- 🧑‍⚕️ `shorebird doctor` verifies lock files are tracked in source control
- 🧹 Remove flutter version check from `shorebird doctor`

## 1.5.4 (December 20, 2024)

- ✨ Add `--no-confirm` flag to `shorebird release` and `shorebird patch`
- 🩹 Fix bug which caused incompatibility with package:shorebird_code_push v1.x
- 🪵 Improve logging for failed `shorebird release ios` commands.

## 1.5.3 (December 17, 2024)

- 🐦 Support for Flutter 3.27.1
- 📂 Fix too many open files issue (downgraded pkg:archive)

## 1.5.2 (December 17, 2024)

- 🩹 Fix iOS patching bug where gen_snapshot was not found

## 1.5.1 (December 16, 2024)

- 🍎 macOS Desktop beta

## 1.5.0 (December 13, 2024)

- 🐦 Support for Flutter 3.27.0

## 1.4.16 (December 9, 2024)

- 🍎 iOS linker improvements (additional class table improvements)
- 🖥️ Additional preparation for MacOS support

## 1.4.15 (December 6, 2024)

- 🐛 Fix bug (edge case) where `shorebird release ios` can upload stale supplement artifacts

## 1.4.14 (December 5, 2024)

- 🍎 iOS linker improvements (improved class table sort)
- 🖥️ Prepare for MacOS support
- 🍄 Various dependency upgrades

## 1.4.13 (November 20, 2024)

- 🍎 Provide more build status updates for iOS release and patch
- 👀 Improve error messages for iOS preview

## 1.4.12 (November 14, 2024)

- 🍎 Remove logic to provide custom ExportOptions.plist to iOS builds. This was
  in place to prevent Xcode from changing build numbers post-build, which
  confuses Shorebird. This no longer seems to be an issue, and the
  ExportOptions.plist behavior was causing issues with apps using extensions
  (see https://github.com/shorebirdtech/shorebird/issues/1956). If you see
  a different version of your app in App Store Connect than in your Shorebird
  release, this is likely caused by this change, and you should let us know.

## 1.4.11 (November 14, 2024)

- 🐦 Support for Flutter 3.24.5

## 1.4.10 (November 8, 2024)

- 🛠️ Fix Updater issuer where older patches would be used if state failed to deserialize (https://github.com/shorebirdtech/shorebird/issues/2612)

## 1.4.9 (November 4, 2024)

- 📦 Release new Flutter 3.24.4 revision to support `package:shorebird_code_push` rewrite (v2.0.0-dev.1)
- 🦀 Improved logs in the Shorebird Updater
- 🧑‍🔧 Fix gradle version detection in `shorebird doctor`

## 1.4.8 (October 29, 2024)

- 📦 Add `shorebird releases get-apk` command
- 🛠️ Fix error handling when building ipa fails using Xcode 16
- 🐌 Add warning when windows artifact download is slower than expected

## 1.4.7 (October 28, 2024)

- 🐦 Support for Flutter 3.24.4
- 🪵 Include gradle tasks when releasing android

## 1.4.6 (October 24, 2024)

- 🍧 Fix issue with `shorebird release ios` where flavored apps would sometimes
  upload the incorrect binary.

## 1.4.5 (October 23, 2024)

- 🧑‍🔧 Fix bug when patching with `--split-debug-info` on iOS
  - `shorebird release` and `shorebird patch` now have first party support for `--split-debug-info`
- 🪵 Do not output error message when `-h` flag is passed

## 1.4.4 (October 22, 2024)

- 📈 Add download progress to patch commands

## 1.4.3 (October 21, 2024)

- 🧑‍⚕️ Fix `shorebird doctor -v` download speed test on Windows
- 🍎 Enforce minimum Flutter version for `shorebird release ios-framework`

## 1.4.2 (October 18, 2024)

- 📦 Include artifact download speed test in `shorebird doctor -v`

## 1.4.1 (October 15, 2024)

- 🪵 Improve progress logs for artifact uploads
- 🛜 Add various URL reachability checks to `shorebird doctor`
- 👨‍🔧 Fix bug which caused unnecessary artifact downloads on windows

## 1.4.0 (October 9, 2024)

- 🏢 Support for organizations! (Sharing groups of apps with groups of people.)

## 1.3.5 (September 30, 2024)

- 🪵 Improve AOT Tools logging and exception reporting
- 🏢 Preparation for organizations support

## 1.3.4 (September 24, 2024)

- 🪵 Improve logging for link failures
- 🛜 Add api.shorebird.dev validator to `shorebird doctor`
- 🍄 Upgrade bundletool to 1.17.1

## 1.3.3 (September 12, 2024)

- 🐦 Support for Flutter 3.24.3

## 1.3.2 (September 4, 2024)

- 🐦 Support for Flutter 3.24.2

## 1.3.1 (September 4, 2024)

- 🔧 Fix an issue where certain packages could interact poorly with the
  Shorebird updater, causing patches to be unexpectedly uninstalled. See
  https://github.com/shorebirdtech/updater/issues/211 for more information.
- 🔗 Remove link percentage from `shorebird patch ios` summary logs.
- #️⃣ Fix issue where `shorebird release ios` would not accept git commit hashes
  for the `--flutter-version` argument.

## 1.3.0 (August 28, 2024)

- ❗️**BREAKING** Remove deprecated `shorebird build` commands
- 📉 Reduce FFI memory usage
- ✨ Show progress when updating cached artifacts
- 🗒️ Include `shorebird.yaml` in diagnostic metadata

## 1.2.2 (August 21, 2024)

- 🐦 Support for Flutter 3.24.1
- 📈 Improve iOS patch performance (exclude selector offsets from op hash)

## 1.2.1 (August 19, 2024)

- 📈 Improve iOS patch performance (exclude static field loads from op hash)

## 1.2.0 (August 8, 2024)

- 🐦 Support for Flutter 3.24.0

## 1.1.27 (August 6, 2024)

- 📈 Improve iOS patch performance (fix gdt detection for orri)

## 1.1.26 (August 1, 2024)

- 📈 Improve iOS patch performance (exclude snapshot padding)

## 1.1.25 (July 29, 2024)

- 📈 Improve iOS patch performance (tolerate duplicate code objects)

## 1.1.24 (July 26, 2024)

- 📈 Improve iOS patch performance

## 1.1.23 (July 26, 2024)

- 👾 Fix issue where a space in the path to a Flutter project would cause iOS
  patching to fail.
- 🛗 Fix issue that would cause `shorebird_code_push` to incorrectly report that
  a new patch was available for download.
- #️⃣ Update release command's `flutter-version` argument to accept Flutter
  revisions (git commit hashes) in addition to version numbers.

## 1.1.22 (July 23, 2024)

- 📈 Improve iOS patch performance

## 1.1.21 (July 23, 2024)

- 🛞 Update API contract with server to support patch rollbacks.

## 1.1.20 (July 18, 2024)

- 🐦 Support for Flutter 3.22.3

## 1.1.19 (July 15, 2024)

- 📦 Fix a bug where artifacts (aot_tools.dill, bundletool.jar) could sometimes get corrupted by an interrupted download.
- 🚨 Better usage exception handling
- ✨ Display human readable Flutter versions (e.g. 3.22.2) in addition to Flutter version hashes in more places.
- 🪵 Better error logging on Windows
- 📊 Improve linker diagnostics

## 1.1.18 (July 11, 2024)

- 🩹 Fix `shorebird release android` when using older Flutter versions
- 🔎 Include flutter revision in release and patch metadata

## 1.1.17 (July 10, 2024)

- 📈 Improve iOS patch performance
- 🍄 Add `shorebird patches promote` command

## 1.1.16 (July 9, 2024)

- 🍎 Fix an issue where iOS patches would sometimes exhibit incorrect behavior (e.g scrolling, animations, lerping issues)
- 🔗 Consolidate docs.shorebird.dev links in CLI

## 1.1.15 (July 3, 2024)

- ✨ Add `--display-name` to `shorebird init`

## 1.1.14 (July 3, 2024)

- 📈 Improve iOS patch performance (GDT sort)
- 🤖 Add JetBrains Toolbox Android Studio detection for Linux
- 🩹 Always respect `--build-name` and `--build-number` args

## 1.1.13 (June 26, 2024)

- 🍧 Fix an issue where iOS app extensions were incorrectly recognized as flavors.
- 🪵 Improve error messaging when a release is not previewable.
- 🏢 Ensure patch builds use the same version number as the release to prevent
  spurious "native changes" warnings.

## 1.1.12 (June 19, 2024)

- 🩹 fix iOS patches rendering issues (black screen)
- 🔎 fix iOS native assets detection
- 👀 fix `shorebird preview` using stale artifacts
- 🗑️ fix `shorebird cache clear` bug
- 🍧 add flavor validation
- 🤖 add gradlew version to `shorebird doctor`
- 🪵 improve logging

## 1.1.11 (June 11, 2024)

🫴 Fixes a bug in iOS where try/catch blocks could be ignored after patching.
🏎️ Improves iOS patch performance by 10-15%.
🚫 Disable Flutter 3.22.1 and earlier for iOS.

We found and fixed a bug in the Dart runtime, whereby sometimes "catch" blocks
would be ignored after applying a Shorebird patch. This bug has been present in
all versions of Shorebird Flutter for iOS prior to 3.22.2. This bug did not
affect Android.

After careful evaluation we decided this try/catch issue was severe enough that
we would be remiss to allow continued use of older versions of Flutter for iOS
releases. We have therefore decided to only support Flutter 3.22.2 and later
for iOS releases at this time.

## 1.1.10 (June 6, 2024)

- 🔒 Support for signed patches (beta)
- 🐦 Support for Flutter 3.22.2
- ✍️ Write linker debug info when linking fails
- 📈 Improve iOS patch performance

Patch signing allows customers to configure Shorebird apps to require
cryptographically signed patches. This is another level of security
for businesses which require such. More information:
https://shorebird.dev/blog/patch-signing-beta/
https://docs.shorebird.dev/guides/patch-signing/

## 1.1.9 (June 3, 2024)

- 🧑‍⚕️ Adds logs directory path and more info about Java version to `shorebird doctor` output
- 🍧 Support Android flavors that start with multiple uppercase letters
- 🩺 Improves `shorebird doctor` messaging when system Flutter version is different than Shorebird Flutter version
- 🪵 Improves quality of log output
- ⏫ Tells you when new versions of Shorebird are available
- 🎯 Better handling of `--dart-define` and `--dart-define-from-file` (both work before and after -- now)
- 🥒 Better locating app.dill when patching iOS releases
- 🔗 Improve iOS patch speed

## 1.1.8 (May 28, 2024)

- 🐦 Support for Flutter 3.22.1

## 1.1.7 (May 28, 2024)

- Updates patch command to prompt for release version.
- Adds the ability to sign patches. Read more at https://docs.shorebird.dev/guides/patch-signing

## 1.1.6 (May 15, 2024)

- 🩹 Reverts a windows powershell fix for exporting `FLUTTER_STORAGE_BASE_URL`

## 1.1.5 (May 15, 2024)

- 🐦 Upgrade to Flutter 3.22.0 and Dart 3.4.0
- 💾 Pre-cache Flutter assets when switching revisions
- 🪵 Improvements to exception logs

## 1.1.4 (May 14, 2024)

- 🩹 Fixes `Could not find an option named "dump-debug-info"` for older versions of Flutter.

## 1.1.3 (May 13, 2024)

- 🩹 Fix `shorebird patch` not always installing required Flutter version.

## 1.1.2 (May 10, 2024)

- 🩹 Fix `shorebird release` not forwarding args after `--` to `Flutter`.

## 1.1.1 (May 10, 2024)

- 🩹 Fix `shorebird release` to support `--artifact` and `--export-method`.

## 1.1.0 (May 9, 2024)

- ♊ `shorebird release` and `shorebird patch` now accept `--platforms` to
  specify which platforms to release or patch. This allows you to release or
  patch multiple platforms in a single command.
  For example, `shorebird release --platforms android,ios` will release to both Android and iOS platforms.
- 🏜️ `shorebird release` now supports `--dry-run` like `shorebird patch`.
- 🪲 `shorebird` commands now save a file with debug info which can be manually
  / optionally sent to our team for help debugging any issue you encounter.

Multiple platform support required an extensive re-write of the release and
patch commands. If you encounter any issues, please let us know!

## 1.0.5 (May 6, 2024)

- 🔗 Improve iOS patch speed when adding/removing classes

## 1.0.4 (April 25, 2024)

- 🩹 Revert "Improve consistency of Shorebird artifact downloads" from 1.0.3 ([#1958](https://github.com/shorebirdtech/shorebird/pull/1958))
  - This introduced a bug which prevented customers from releasing/patching using older Flutter revisions.

## 1.0.3 (April 25, 2024)

- 🐦 Support for Flutter 3.19.6
- 🖨️ Improve logging for patch commands to include Flutter version being used to build
- 💾 Improve consistency of Shorebird artifact downloads
- ✅ Add validation that shorebird.yaml is present in pubspec.yaml assets section
- 🌌 Improved handling of multi-dimensional Android flavors
- 🔗 `--debug-linker` flag added to `patch ios` command to help debug low link percentages

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v1.0.3

## 1.0.2 (April 18, 2024)

- 🍢 Fix a kebab-casing issue with Android Flavors
- 📝 Include Flutter version in patch command logs

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v1.0.2

## 1.0.1 (April 17, 2024)

- 🚀 Improve link percentage by ~10-15% for all iOS patches
- 🩹 Fix potentially incorrect behavior in optimized try/catch on iOS patches
- 🥞 Fix potential crashes when using dwarf stack traces on iOS patches
- 🖇️ Fix potential errors on iOS patches due to link table alignment bug in the snapshot
- 💥 Fix issue where patching a release with multiple platforms built with different flutter versions would crash.
- 🪵 Improve logs to only include stack traces when using `--verbose`
- 🔍 Fix issue where `shorebird init` would not find a `pubspec.yaml` due to malformed values
- ❅ Fix flaky failures when encoding archives (observed in `shorebird preview` on Windows)
- 📝 Include patch instructions after all `release` commands
- 🔗 Link to the Shorebird Console when a release already exists
- 🚉 Support `--target-platforms` on android release and patch commands
- 🍧 Fix `shorebird release android` with camelCase flavor names

This is a required upgrade due to the issue present in all previous `shorebird`
versions where it was possible to create invalid (crashing) patches if the same
release number was used for multiple platforms but built with different Flutter
versions.

Please upgrade using `shorebird upgrade`.

ℹ️ [Shorebird Status](https://docs.shorebird.dev/status) tracks any known issues.

## 1.0.0 (April 8, 2024)

🎉🎉🎉🎉🎉🎉 It's here! 🎉🎉🎉🎉🎉🎉

We’re excited to announce Shorebird 1.0, including stable support for iOS!

🚀 iOS is production-ready!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v1.0.0

## 1.0.0-rc.1 (April 4, 2024)

- ⭐ Fix sync\* to be much faster on iOS.
- 🚫 Removed deprecated (error-prone) --force flag from `shorebird release` and `shorebird patch`.

This release contains all fixes we intended for 1.0. Unless any critical bugs
come in in the next few days, we will release 1.0 next Monday!

Removed support for creating new iOS releases with Flutter versions older than 3.19.5 in `shorebird release ios`
since those versions contain the "beta" and "alpha" iOS engines. Patching
is still possible for any existing iOS releases.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v1.0.0-rc.1

## 0.28.1 (April 3, 2024)

- 🐦 Support for Flutter 3.19.5
- 💥 Fix iOS crash when booting from patch due to a bug in our canonical pc implementation
- 🛣️ Fix hang when creating release with Fastlane
- 💬 Suggest re-running command with --verbose on failure
- 🍦 Detect flavors when running `shorebird preview` for better prompting (@erickzanardo's first contribution! 🎉)

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.28.1

## 0.28.0 (March 28, 2024)

🚀 Apps with a patch applied on iOS run much faster than previously.
💾 `shorebird release` saves XCode Version and OS to console.shorebird.dev
to help diagnose any later issues during patching.

Shorebird's Flutter 3.19.4 contains a re-write of our Dart build pipeline on iOS
which eliminates any slowdowns caused by patching Dart code in most cases. We
built a new mechanism to make patched code build much more similarly to
unpatched code, thus allowing more code sharing between the "patch" and
"release" builds resulting in much faster execution at runtime.

Most patches on iOS should now run at speeds indistinguishable from releases.
If the toolchain detects a case where the patch will run slower, it will
provide a warning. If you see any of these warnings, please let us know!

Note: `shorebird patch ios` now takes a little longer as it has to do
more work when building a patch.

This is probably our last iOS beta before we declare Shorebird Code Push 1.0.
We still have one more slowdown for unpatched builds we need to fix, but we
expect that to only take a couple days and be ready for a 1.0 next week.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.28.0

## 0.27.3 (March 26, 2024)

🪟 Updates the Azure app used for Microsoft login.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.27.3

## 0.27.2 (March 22, 2024)

🐦 Support for Flutter 3.19.4

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.27.2

## 0.27.1 (March 22, 2024)

🪟 Automatically detects a CI environment when running on an Azure pipeline.
👀 Fixes a bug in `shorebird preview` where the command could fail if Flutter
had not downloaded the necessary dependencies.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.27.1

## 0.27.0 (March 21, 2024)

🛑 Removes support for the `--force` flag for release and patch commands (see below)
🚢 Adds --export-options-plist option to `patch ios` command.
🤖 Fixes an issue where some Android builds were not able to find release
artifacts due to a change in the artifact output location (see
https://github.com/shorebirdtech/shorebird/issues/1798).

If you have previously used the `--force` flag for release or patch commands, now
is a good time to revisit whether this is necessary. `--force` is _not_ required
to run Shorebird on CI. If your patches include **known good** native code and/or
asset changes, you can use `--allow-native-diffs` and/or `--allow-asset-diffs`
as an argument to the patch command to bypass warnings. We caution against these,
however, as native code or asset changes can cause crashes or other issues in
your app.

If you have any questions about this change, please feel free to reach out!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.27.0

## 0.26.7 (March 18, 2024)

🐦 Support for Flutter 3.19.3
🩹 Fixes an issue where the wrong version of Flutter was being used for some patches

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.7

## 0.26.6 (March 14, 2024)

📝 Update iOS hybrid app workflow to use signed xcframeworks to comply with
Apple's privacy requirements. Note: this changes the workflow for iOS hybrid
apps that use Shorebird. If you have an iOS hybrid app, please see the updated
documentation at https://docs.shorebird.dev/guides/hybrid-app/ios.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.6

## 0.26.5 (March 13, 2024)

🩹 Fix issue where releases created with `--flutter-version` flag were reporting
incorrect Flutter version, causing `shorebird patch` to later fail. If you've
created a release using `--flutter-version`, you may not be able to patch.
To resolve this, create a new release after upgrading to this version.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.5

## 0.26.4 (March 11, 2024)

🪵 Clearer error messages for cases where shorebird is not properly set up in a project.
🍎 Fix incorrect native code change warning for iOS patches created in different
directory or machine than release.
🩹 Fix issue where patch commands would unnecessarily recompile the app when a
release version is specified.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.4

## 0.26.3 (March 5, 2024)

🧑‍🔬 Record more diagnostic information to help solve problems with patches.
🪵 Improved messaging for expiring CI tokens.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.3

## 0.26.2 (February 29, 2024)

⬇️ Lower required Dart version to 3.0

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.2

## 0.26.1 (February 28, 2024)

🆕 Updated to Flutter 3.19.2.
🪟 Fixed `shorebird patch` failing on some Windows installs (missing .dll).
☁️ Added Microsoft login to `shorebird login`, `shorebird login:ci`, and
console.shorebird.dev.

Microsoft login will show Shorebird as an "unverified" app for a few more
days until our Microsoft Partner Program application completes.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.1

## 0.26.0 (February 15, 2024)

🆕 Updated to Flutter 3.19.0.
🗑 Deprecated `flutter versions use` in favor of `shorebird release --flutter-version`.
💥 Fixed a crash on iOS involving package:dio.

The iOS crasher was caused by a subtle bug in the upstream Dart dill compiler,
triggered by code in `package:dio`, which only executed when parsing json blobs
larger than 50kb. The full fix required changes to upstream Dart which is why
we waited until Flutter 3.19.0 to release this fix.

We're now returning our focus to finishing 1.0. We believe this release to be
stable and safe to use on iOS and Android. Please let us know if you encounter
any issues!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.26.0

## 0.25.2 (February 7, 2024)

💥 Fixes a crash on iOS releases without a patch.
🚑 Now publishing .dSYM files for iOS builds to help with crash reporting, see
https://docs.shorebird.dev/guides/crash-reporting for usage instructions.
🪵 Fixed logs from Shorebird updater not appearing on iOS.

We have received multiple reports of iOS builds crashing at 0xfffffffffffffffe.
https://github.com/shorebirdtech/shorebird/issues/1700
We expect this is a bug in our new iOS engine relating to `async`/`await`, but
have not yet been able to reproduce this ourselves. We would _love_ to work
with you to debug this issue if you are seeing it.

If you see any issues, please let us know!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.25.2

## 0.25.1 (February 5, 2024)

- 🩹 Fixes an issue where our Flutter fork was reporting the incorrect version.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.25.1

## 0.25.0 (February 1, 2024)

🎉🎉🎉 **iOS IS NOW BETA!** 🎉🎉🎉

📰 See our blog post at https://shorebird.dev/blogs/ios-beta/.

This release includes:

- 🐦 Support for Flutter 3.16.9.
- 🦿 iOS hybrid app patches are now much faster (at parity with non-hybrid iOS patches).
- 🩹 Fixes issues where `shorebird patch ios` might not work if an export options plist is required.
- 🗑️ Dropped support for Flutter 3.16.4-3.16.7 on iOS due to crashes discovered in those versions.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.25.0

## 0.24.1 (January 31, 2024)

- iOS release builds now run at full speed. iOS patches remain slower than releases.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.24.1

## 0.24.0 (January 30, 2024)

This is our last planned release before iOS beta. We believe iOS is stable
enough for general use. We plan to release beta later this week once we hear
back from early adopters. iOS releases and patches are still slower than
Android, but they will continue to get faster in the coming weeks.

Please test and let us know if you encounter any issues!

- iOS patches now run ~2x faster.
- Fixed several crashers in the new iOS engine.
- `shorebird -v` now shows all output from underlying commands, not just errors.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.24.0

## 0.23.1 (January 25, 2024)

- 🩹 Fixes iOS patch for Flutter version 3.16.5

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.23.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.23.0 (January 24, 2024)

This release includes a new iOS "linker" which allows running much more code on
the CPU when patching on iOS. Some benchmarks improved 10-50x. We still have
work to do before we declare 1.0, but we're very close now.

This release contains fundamental changes as to how Dart executes and may
still have instabilities we failed to catch in our testing.

We recommend Shorebird users test apps and patches before distributing to users.
`shorebird preview` can be used to test patches before releasing to users:
https://docs.shorebird.dev/guides/staging-patches

If you encounter problems, you can release with an older (known stable) iOS
engine by running: `shorebird flutter versions use 3.16.4`

- 🚀 Enabled new linker on iOS, improving Dart execution after patching.

Known issues:

- Obfuscated iOS builds fail to patch:
  https://github.com/shorebirdtech/shorebird/issues/1619
- Unpatched iOS builds are sometimes _slower_ than patched builds:
  https://github.com/shorebirdtech/shorebird/issues/1661

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.23.0

## 0.22.1 (January 23, 2024)

- 🔍 Adds checks for `flavor` and `target` flags after the `--` separator.
- 🩹 Fixes iOS patch crash when patching with older Flutter versions.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.22.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.22.0 (January 18, 2024)

This release focused on stabilizing the new iOS engine released in 0.20.0.
We've squashed all known crashers. If you're seeing issues, please let us know!

- ⬆️ Updated to Flutter 3.16.7
- 💥 Fixed several crashers found in the new iOS engine.
- ⚖️ Reduced memory usage on iOS by over 30mb.
- 📉 Reduced iOS patch sizes by 10x -- now scale by amount changed rather than the size of the app.
- 🩹 Fixed `shorebird ios-alpha patch` to work with older Flutter versions.
- 🏃 Made `shorebird preview` faster on Android.
- 🔍 Fixed sometimes failing to find `adb` on Windows.
- 🧈 Fixed progress indicator hangs in `patch` command.
- 🍎 Fixed errors in CupertinoSwitch (caused by bad merge with Flutter).

If you encounter problems with the new iOS engine, you can use the older one by
running: `shorebird flutter versions use 3.16.4`

Known issues:

- Obfuscated iOS builds fail to patch:
  https://github.com/shorebirdtech/shorebird/issues/1619

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.22.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.21.1 (January 3, 2024)

- 🩹 Fixes an issue where releasing iOS apps would fail when zipping an archive (https://github.com/shorebirdtech/shorebird/pull/1612)

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.21.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.21.0 (January 2, 2024)

- ⬆️ Updated to Flutter 3.16.5
- 🩹 Fixed iOS patch support for x64 Macs.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.21.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.20.0 (December 20, 2023)

- New Dart VM "mixed-mode" is now enabled by default on iOS.
  - iOS patches now use the release's Dart code (on the CPU) for faster execution when possible.
  - No performance or user visible changes expected. Performance improvements will be coming in future releases.
  - This is a major change to how Dart code is executed on iOS. If you see anything surprising, please let us know!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.20.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.19.1 (December 20, 2023)

- ⬆️ Updated to Flutter 3.16.4
- 🩹 Improved `JDK` lookup and handle empty `JAVA_HOME`
- 👀 `shorebird preview` fixed to only use available platforms
- 🪟 Android Studio path fixes on Windows

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.19.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.19.0 (December 12, 2023)

- ⬆️ Updated to Flutter 3.16.3
- 🧑‍💻 Added support for `--local-engine-host`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.19.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.5 (December 11, 2023)

- 🍎 Additional changes for iOS mixed-mode (turned off by default)

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.5

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.4 (December 8, 2023)

- 🩹 Fixed `shorebird preview` bug when running with flavors (https://github.com/shorebirdtech/shorebird/issues/1542)
- 📲 A bunch of internal cleanup to prepare for iOS!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.4

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.3 (November 27, 2023)

- 🩹 Fixed `adb` not found when running `shorebird preview`
- 👀 `shorebird preview` defaults to current app
- 🩺 `shorebird doctor` improved `storage` reachability

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.2 (November 21, 2023)

- 🩺 `shorebird doctor`
  - Supports no system Flutter installation
  - Validates that `storage.googleapis.com` is reachable
- ✅ `shorebird --version` checks for updates
- 🚀 `shorebird release` lists the Flutter version

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.1 (November 14, 2023)

- 🚀 `shorebird release` outputs release version

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.18.0 (November 14, 2023)

- ❌ Remove `shorebird apps create` command
  - Use `shorebird init --force` instead
- 🪹 `shorebird` commands work within child directories
- 🪵 Only show current `adb` logs in `shorebird preview`
- 🍎 Tail logs in `shorebird preview` for iOS 17+
- 📦 `shorebird init` does not prompt when in CI or using `--force`
- 🛠️ `shorebird init` runs validators last
- 🚨 Improve various error messages

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.18.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.17.4 (November 10, 2023)

- 💿 Includes our new custom Dart Virtual Machine "mixed-mode" (not yet enabled)
  - We rewrote how Dart code is executed on iOS in this release. We haven't yet enabled the new faster "mixed-mode" execution so there should be no observable change, but the faster VM is now included and in partial use. Because this was such a large (multi-month!) change, there could be unanticipated changes on iOS devices. If you see anything surprising, please let us know!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.17.4

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.17.3 (November 8, 2023)

- 🗂️ Use multipart file uploads for release and patch artifacts
- 🩹 Only run `flutter pub get` if separate `flutter` installation exists

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.17.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.17.2 (November 3, 2023)

- 🧑‍⚕️ `shorebird doctor` now ignores non-main AndroidManifest.xml files.
- 📦 Added `export-method` option to `shorebird release ios-alpha` command.
- 🔎 Fixed a bug with `shorebird preview` platform selection.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.17.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.17.1 (October 26, 2023)

- ⬆️ Updated to Flutter 3.13.9
- 📝 Turn up verbosity of `-v` flag
- 👀 Print error message when trying to preview iOS on non MacOS host

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.17.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.17.0 (October 20, 2023)

- ⬆️ Updated to Flutter 3.13.8
- 🔨 Removed `shorebird collaborators` in favor of console.shorebird.dev

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.17.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.16.3 (October 17, 2023)

- 🧩 Added `release-version` option to `shorebird patch [android|ios-alpha]` to allow specifying a release version.
- 🩹 Better support for custom Android SDK/java locations.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.16.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.16.2 (October 13, 2023)

- 🍎 Support shorebird preview for iOS 17 devices
- 🧾 Additional pricing tiers for Team plan
- 🎮 https://console.shorebird.dev/account supports managing your subscription
- 🍨 shorebird init now lists flavors it detects

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.16.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.16.1 (October 5, 2023)

- 💥 fix rare crasher seen by large apps
- 🪟 "shorebird preview" fix on windows

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.16.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.16.0 (October 5, 2023)

- 🧯 Support staging and previewing patches before sending to production
  - `shorebird patch android --staging`
  - `shorebird preview --staging`
- 🧹 `shorebird preview` clears app data before installing
- ❗️ `shorebird account downgrade` moved to https://console.shorebird.dev/account

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.16.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.15.2 (October 2, 2023)

- 🐦 Flutter 3.13.6 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.15.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.15.1 (September 29, 2023)

- 🔗 Adds link to troubleshooting page when native changes are detected
- 🍎 Fixes issues with the `--no-codesign` flag for `shorebird release ios-alpha`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.15.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.15.0 (September 25, 2023)

**🚨 BREAKING CHANGE - Upgrade Required 🚨**

- 🍄 use upgraded backend to provide more additional metrics for console
- 🧹 internal refactoring of artifact management

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.15.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.11 (September 22, 2023)

- 🐦 Flutter 3.13.5 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.11

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.10 (September 20, 2023)

- 🔨 Support XCode projects with names other than "Runner"
- 🍎 Fixed iOS patches sometimes failing to install with download error.
- 🐦 Flutter 3.13.4 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.10

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.9 (September 19, 2023)

We've just released Shorebird v0.14.9 🎉

- 🍎 `shorebird release ios-alpha` supports `--no-codesign`
- 🍧 automatically add new flavors if detected by `shorebird init`
- 👀 only list preview-able releases when running `shorebird preview`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.9

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.8 (September 8, 2023)

We've just released Shorebird v0.14.8 🎉

- 🐦 Flutter 3.13.3 support!
- ✨ Automatically switch Flutter revisions on `shorebird patch`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.8

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.7 (September 8, 2023)

We've just released Shorebird v0.14.7 🎉

- 👀 Support `--device-id` for `shorebird preview`
- 🧩 Add patch number to `shorebird patch` output
- 🚨 Add error reporting to updater

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.7

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.6 (August 31, 2023)

We've just released Shorebird v0.14.6 🎉

- 🐦 Flutter 3.13.2 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.6

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.5 (August 30, 2023)

We've just released Shorebird v0.14.5 🎉

- 🩹 Hotfix for iOS crashes

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.5

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.4 (August 25, 2023)

We've just released Shorebird v0.14.4 🎉

- 🐦 Flutter 3.13.1 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.4

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.3 (August 24, 2023)

We've just released Shorebird v0.14.3 🎉

This is a hotfix for android build failures which was only partially addressed in 0.14.2

- 🐦 updates our Flutter revision to include an Android build fix

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.2 (August 23, 2023)

We've just released Shorebird v0.14.2 🎉

This is a small update to 0.14.0 that includes minor improvements:

- 🐦 updates our Flutter revision to include an Android build fix

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.1 (August 23, 2023)

We've just released Shorebird v0.14.1 🎉

This is a small update to 0.14.0 that includes minor improvements:

- 🔎 better logging for patch commands

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.14.0 (August 23, 2023)

We've just released Shorebird v0.14.0 🎉

- 🐦 Flutter 3.13.0 support!

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.14.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.13.2 (August 21, 2023)

We've just released Shorebird v0.13.2 🎉

- 👩‍⚕️ fix for `shorebird doctor` flutter version check
- 🐦 skipped flutter upgrade checks when completing builds

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.13.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.13.1 (August 18, 2023)

We've just released Shorebird v0.13.1 🎉

- 🩹 hotfix `shorebird.yaml` (de)serialization issue when using `auto_update`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.13.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.13.0 (August 17, 2023)

We've just released Shorebird v0.13.0 🎉

- 🍎 iOS crash fixes
- 🧩 `shorebird patch` no longer requires specifying a release version
- 🐦 `shorebird flutter versions use` supports passing a commit hash
- 🤖 no prompts when run in continuous integration
- 🩹 `.dart_tool/package_config.json` is reset after builds to resolve VSCode issues
- 🍎 improved iOS asset diffing (`.car` file fixes)
- 🧹 remove deprecated commands
  - `shorebird account upgrade`
  - `shorebird apps list`
  - `shorebird apps delete`
  - `shorebird releases add`
  - `shorebird releases list`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.13.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.12.3 (August 11, 2023)

We've just released Shorebird v0.12.3 🎉

- 🩹 fix script terminating errors on older versions of powershell
- 📝 `shorebird doctor --verbose` includes Android Toolchain information

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.12.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.12.2 (August 10, 2023)

We've just released Shorebird v0.12.2 🎉

- 🗒️ See available Flutter versions using `shorebird flutter versions list`
- 🕹️ Switch Flutter versions using `shorebird flutter versions use <version>`
- 🍎 iOS shows warning when patch includes changes to assets and native code
- 📝 `shorebird --version` includes Flutter version
- 🪟 Windows installer exits on error

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.12.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.12.1 (August 5, 2023)

We've just released Shorebird v0.12.1 🎉

- 🩹 fix for `shorebird release android --artifact apk` where `--split-per-abi` was incorrectly always enabled.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.12.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.12.0 (August 4, 2023)

We've just released Shorebird v0.12.0 🎉

- 📜 `shorebird patch` supports patching releases that used older Flutter versions
- ✅ `shorebird.yaml` exposes `auto_update` which can be used to disable automatic update checks
- 🗂️ `shorebird patch ios-alpha` warns users of asset changes
- 📦 `shorebird release android` supports `--split-per-abi` flag

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.12.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.11.2 (August 1, 2023)

We've just released Shorebird v0.11.2 🎉

- 🧩 Add-to-app support for iOS
  - `shorebird release ios-framework-alpha`
  - `shorebird patch ios-framework-alpha`
  - 📚 See our [new guides](https://docs.shorebird.dev/add-to-app)
- 🍧 Flavor support for iOS
  - `shorebird release ios-alpha --flavor <flavor>`
  - `shorebird patch ios-alpha --flavor <flavor>`
  - 📚 See our [new guides](https://docs.shorebird.dev/flavors)
- 🦀 Improve rust logging to reduce noise

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.11.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.11.1 (July 28, 2023)

We've just released Shorebird v0.11.1 🎉

- 🔄 Add retry logic to networking layer
- 🩹 Improve iOS flavors error until we add support for flavors
- 🧹 Deprecated `apps list`, `apps delete`, `releases list`, and `accounts upgrade` commands
  - This functionality has been moved to console.shorebird.dev

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.11.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.11.0 (July 26, 2023)

We've just released Shorebird v0.11.0 🎉

- 🍎 iOS is now in alpha (!!!)
  - New `shorebird release ios-alpha` and `shorebird patch ios-alpha` commands
  - `shorebird preview` support for iOS
- 🧑‍⚕️ `shorebird init` automatically runs `shorebird doctor` checks and fixes
- 🧹 Remove deprecated `shorebird account create` and `shorebird account usage` commands
  - This functionality has been moved to console.shorebird.dev

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.11.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.10.0 (July 20, 2023)

We've just released Shorebird v0.10.0 🎉

- ✨ `shorebird patch` warns users of incomplete releases
- 📈 New console.shorebird.dev accounts page to view plan and usage info
- 🧹 Remove deprecated `shorebird run` command

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.10.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.9.2 (July 14, 2023)

We've just released Shorebird v0.9.2 🎉

- 🐦 Upgrading to Flutter 3.10.6
- 👀 New `shorebird preview` command
- 🎮 New release of [package:shorebird_code_push](https://pub.dev/packages/shorebird_code_push)
- 🧩 `shorebird patch` allows user to proceed if java/kotlin changes are detected

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.9.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.9.1 (July 10, 2023)

We've just released Shorebird v0.9.1 🎉

- 💵 `shorebird account usage` price fix
- 🪟 `shorebird patch android` windows fix

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.9.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.9.0 (July 7, 2023)

We've just released Shorebird v0.9.0 🎉

- ✨ `shorebird account usage` includes month-to-date cost and tier
- 🔥 `shorebird run --dart-define` support
- 🚰 `shorebird run` forwards `stdin` to Flutter process
- 🖥️ console.shorebird.dev supports app deletion and releases list

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.9.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.8.0 (June 30, 2023)

We've just released Shorebird v0.8.0 🎉

- 🚀 introduce new hobby tier (FREE)
- 🪟 windows installer fixes/improvements
- ⬇️ rename `shorebird subscription cancel` to `shorebird account downgrade`
- 🐛 fix flavor detection issues when running `shorebird init`

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.8.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.7.0 (June 28, 2023)

We've just released Shorebird v0.7.0 🎉

- 🍄 rename `shorebird account subscribe` to `shorebird account upgrade`
- 🐛 don't prompt about asset changes when `--force` is used
- 🤝 `shorebird collaborators list` shows roles

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.7.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.6.0 (June 23, 2023)

We've just released Shorebird v0.6.0 🎉

- 🎮 Released [`package:shorebird_code_push`](https://pub.dev/packages/shorebird_code_push) to control code push from Dart
- 📈 `shorebird account usage` reports per-app update counts since the last billing cycle.
- 📦 `shorebird release android --artifacts apk` generates an `apk` instead of `aab`.
- 📝 `shorebird releases list` and `shorebird apps list` displays sorted by most recent.
- 🩹 Resolved Firebase Cloud Messaging background messages sometimes hanging on Android.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.6.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.5.1 (June 21, 2023)

We've just released Shorebird CLI v0.5.1 🎉

- ✅ release v0 of our [`setup-shorebird` GitHub action](https://github.com/shorebirdtech/setup-shorebird)
- 🔑 New `shorebird login:ci` command to get a `SHOREBIRD_TOKEN` for CI
- 🍎 Additional iOS preparation

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.5.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.5.0 (June 16, 2023)

We've just released Shorebird CLI v0.5.0 🎉

- 🐦 Upgrading to Flutter 3.10.5
- 📈 New Usage Command to show how many patches are installed (`shorebird account usage`)
  - In preparation for usage-based pricing
- 🍎 Additional iOS preparation
- 🧑‍⚕️ `shorebird doctor` supports being run outside of a shorebird project directory

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.5.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.5 (June 14, 2023)

We've just released Shorebird CLI v0.4.5 🎉

- Upgrading to Flutter 3.10.4
- Fixed iOS release version detection

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.5

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.4 (June 12, 2023)

We've just released Shorebird CLI v0.4.4 🎉

- 🩹 Temporarily reverting to Flutter 3.10.3

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.3 (June 10, 2023)

We've just released Shorebird CLI v0.4.3 🎉

✨ The most notable changes are:

- 🩹 Hotfix for issue where `shorebird android release` did not work with build flavors.

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.3

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.2 (June 9, 2023)

We've just released Shorebird CLI v0.4.2 🎉

✨ The most notable changes are:

- 🐦 Support for Flutter 3.10.4
- 🍎 Additional iOS preparation
- 📈 Codecov is enabled

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.2

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.1 (June 7, 2023)

We've just released Shorebird CLI v0.4.1 🎉

✨ The most notable changes are:

- 🐦 Support for Flutter 3.10.3
- 🍎 Additional iOS preparation
- 🧹 Refactors to improve consistency of CLI output

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.4.0 (June 2, 2023)

We've just released Shorebird CLI v0.4.0 🎉

✨ The most notable changes are:

- 🧩 Support for Android Archive Add-To-App workflows
  - `shorebird release aar` and `shorebird patch aar`
- 🐛 Fix uploads for large apps
- 🚨 Breaking Change: `shorebird patch` was renamed to `shorebird patch android` as continued preparation to support iOS

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.4.0

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.3.1 (May 30, 2023)

We've just released Shorebird CLI v0.3.1 🎉

✨ The most notable changes are:

- 📦 Allow resubmitting a release after a partial failure
- 📝 Additional verbose logging `shorebird --verbose`
- ⚠️ Improved error output if artifact uploads fail

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.3.1

As always, you can upgrade using `shorebird upgrade`

Please let us know if we can help!

## 0.3.0 (May 25, 2023)

We've just released Shorebird CLI v0.3.0 🎉

✨ The most notable changes are:

- 🐦 Support for Flutter 3.10.2 and Dart 3.0.2
- 🚨 Breaking Change: `shorebird release` was removed in favor of `shorebird release android` as part of the preparation to support iOS
- ⚠️ `shorebird patch` alerts users of non-patchable changes
- 🩹 Fixed a bug which caused crashes on Android API <28

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.3.0

As always, you can upgrade using shorebird upgrade

Please let us know if we can help!

## 0.2.2 (May 22, 2023)

We've just released Shorebird CLI v0.2.2 🎉

✨ The most notable changes are:

- 🐦 Support for Flutter 3.10.1 and Dart 3.0.1

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.2.2

As always, you can upgrade using shorebird upgrade

Please let us know if we can help!

## 0.2.1 (May 17, 2023)

We've just released Shorebird CLI v0.2.1 🎉

✨ The most notable changes are:

🤝 Added support for managing collaborators (see shorebird collaborators --help)
🍧 Fixed flavors case sensitivity
🧑‍🔧 Fixed rare crash when shorebird was misconfigured

📚 Release notes can be found at https://github.com/shorebirdtech/shorebird/releases/tag/v0.2.1

As always, you can upgrade using shorebird upgrade

Please let us know if we can help!

## 0.2.0 (May 12, 2023)

We've just released v0.2.0 of shorebird 🎉 :shorebird:

✨ Highlights:

- 🐦 Support for Flutter 3.10.0 and Dart 3.0.0
- 🤖 Fixed Android Studio paths on Linux
- 📦 `shorebird release` no longer accepts `--release-version`
  - release versions are derived from build artifacts
- ✅ `shorebird release --force` will skip confirmation prompts (thanks @rkishan516)!

Note: Moving to Dart 3 is breaking. Dart 3 is not able to build apps that run
in Dart 2.x (e.g. apps you released last week) and vice versa. Once you upgrade
to Shorebird 0.2.0, you will not be able to push patches to releases made with
Shorebird 0.1.0 or earlier. You will need to make a new release with Shorebird
0.2.0 to be able to push patches from Shorebird 0.2.0.

We can add support for multiple Flutter versions in the future:
https://github.com/shorebirdtech/shorebird/issues/472
Let us know if that's important to you.

📚 Changelog
https://github.com/shorebirdtech/shorebird/releases/tag/v0.2.0

## 0.1.0 (May 6, 2023)

We've just released v0.1.0 of shorebird 🎉 :shorebird:

✨ Highlights include:

- 🍧 Support for Flavors
- 🗑️ Support for deleting releases and their artifacts (shorebird releases delete)
- 📝 Support for listing releases (shorebird releases list)
- 🧑‍⚕️ Shorebird Doctor can now also apply fixes for some issues (shorebird doctor --fix)

📚 Changelog
https://github.com/shorebirdtech/shorebird/releases/tag/v0.1.0

## 0.0.10

We've just released Shorebird CLI v0.0.10.

We discovered a bug in 0.0.9 that caused releases made from 0.0.9 with
a version name including build number (e.g. `1.0.0+1`) to fail to update.

`shorebird release` would include the build number in the version name,
but the updater client would not include the build number in its request
to the server.

The fix was to make the updater client always also include the build number
which will make "1.0.0+1" and "1.0.0+2" correctly different versions.

What else is new:

- `shorebird run` now supports `-d` to specify a device ID.
- Fixed `shorebird run` on linux x64 when `web` was enabled for the project.
- Fixed Windows install script to work even when IE was not installed.
- Fixed Windows install to add the correct path to the PATH variable.

As always, you can upgrade with `shorebird upgrade`.

Please let us know if we can help!

Eric

## 0.0.9 - Open Beta

Welcome to 0.0.9, big changes ahead!

If you're already using Shorebird, you can upgrade to the latest version
with `shorebird upgrade`.

It no longer requires an invite to use Shorebird. You can create and account
and subscribe to the Open Beta directly from the command line. Instructions
are available at our new docs site: https://docs.shorebird.dev/

What's new:

- New site: https://shorebird.dev/ and docs site: https://docs.shorebird.dev/
- Windows support! https://docs.shorebird.dev now has instructions on how
  to install Shorebird on Windows.
- Updates no longer block launch. When available, updates are still applied
  during app launch, but now on a background thread. This means that your
  development flow to test your patches will involve launching your app
  letting it update in the background, and then re-launching to see the patch
  applied. This change was made to improve the experience for users
  (there is no longer a synchronous network request during app startup) and
  make apps resilient to unreliable networks during launch.

As always, please let us know if you see any issues.

## Announcement for 0.0.8

We've just released Shorebird CLI v0.0.8 🎉

What's new:

- Updated to Flutter 3.7.12.
- Updated Shorebird to use a specific revision of Flutter (rather than
  "latest stable in our fork", making it possible to check out a specific
  version of Shorebird from git and expect it to be able to build binaries
  even months in the future).
- Added (partial) support for Android build numbers.
- Added `shorebird account create` and `shorebird account subscribe` to
  automate our onboarding process for new trusted testers.
- Improved the way we proxy Flutter artifacts (via download.shorebird.dev) to
  greatly improve our speed of releasing new versions of Shorebird.

Let us know if you see any issues!

## Announcement for 0.0.7

We've just released Shorebird CLI v0.0.7 🎉

What's new:

- Fixed our backend to not error for large app releases.
- `shorebird build` is now split into two subcommands:
  - `shorebird build apk` (new)
  - `shorebird build appbundle` (previously `shorebird build`)

Changelog: https://github.com/shorebirdtech/shorebird/releases/tag/v0.0.7

## Announcement for 0.0.6

We're happy to announce Shorebird 0.0.6!

Shorebird should be ready for production apps < 10k users.

You should be able to get test latest via `shorebird upgrade`

What's new:

- Fixed updates to apply when app installed with apk splits (as the Play
  Store does by default). This was our last known production blocking issue.
- `shorebird subscription cancel` now is able to cancel your monthly
  Shorebird subscription. Your Shorebird account will keep working until
  the end of your billing period. After expiration, your apps will continue
  to function normally, just will no longer pull updates from Shorebird.
- `shorebird cache clean` (Thanks @TypicalEgg!) will now clear Shorebird
  caches.
- Install script now pulls down artifacts as part of install.
- Continued improvements to our account handling in preparation for supporting
  self-sign-up.

Known issues:

- Shorebird is still using Flutter 3.7.10. We will update to 3.7.11 right
  after this release:
  https://github.com/shorebirdtech/shorebird/issues/305
- Shorebird does not yet support Android versionCode, only versionName.
  https://github.com/shorebirdtech/shorebird/issues/291

Please try shorebird in production and let us know how we can help!

Eric

## Announcement for 0.0.5

We're happy to announce Shorebird 0.0.5!

TL;DR: Shorebird should be ready for use in production for apps < 10k users.

You should be able to get the latest via `shorebird upgrade`.

What's new:

- Updates should now apply consistently (previously sometimes failed).
  https://github.com/shorebirdtech/shorebird/issues/235. This was our
  last-known production-blocking issue.
- `shorebird doctor` and other commands now are a bit more robust in
  their checks.
- We did a ton of backend work (which shouldn't be visible), mostly
  in terms of testing to make sure we're ready for production. We also
  integrated our backend with Stripe (to make subscription management
  possible).

Known issues:

- Shorebird is still using Flutter 3.7.10. We will update to 3.7.11
  in the next couple days. We've done the previous Flutter updates
  manually, but we're working on automating updates so that Shorebird
  can track Flutter versions as soon as minutes after they are released.
  https://github.com/shorebirdtech/shorebird/issues/236

You can see what we're tracking for 0.0.6 here:
https://github.com/orgs/shorebirdtech/projects/6/views/1

We've also wired up Stripe integration on the backend and will have some
subscription management (including ability to cancel) in our next release.

We expect you all will have requests as you try Shorebird in production
please don't hesitate to let us know! We're standing by to fix/add what
you need to help you be successful.

Please try shorebird in production and let us know how we can help!

Eric

## Announcement for 0.0.4

I'm happy to announce shorebird 0.0.4!

This one's a big one. Unfortunately it's also breaking.

You will both need to re-install shorebird and re-login to shorebird:

```bash
rm -rf ~/.shorebird
curl --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | sh
```

Then you'll want to `shorebird login` and follow the prompts to authenticate
with a Google account.

We believe we've updated our database to mark all trusted testers as paid
accounts after the auth migration, but if you see any issues, please let us
know, and we'll be happy to fix your account right away.

What's new:

- `shorebird` supports Android 32-bit and 64-bit devices!
- `shorebird` works on Linux and Mac-Intel hosts!
- `shorebird login` uses Google OAuth instead of API keys.
- `shorebird doctor` does some basic validation.
- `shorebird account` shows your login status.
- Updated to Flutter 3.7.10.
- We also automated our builds of the Shorebird engine.
  While that won't affect your usage, it did make this release
  possible and will allow us to keep up to date with Flutter more easily as
  well as removing a source of human error in our processes.

As part of adding support for Android arm32 devices as well as Linux and
Mac-Intel hosts, we've changed how `shorebird` uses Flutter. Previously it used
the Flutter SDK already installed on your machine. Now it brings its own copy
of `flutter`. This is due to the fact that our previous method of replacing the
Flutter engine binaries on Android went in through a (hacky) development-only
path, which only supported only a single architecture at a time (hence us
previously limiting `shorebird` only 64-bit Android devices).

Now we use a fork of Flutter. The only change in our fork is the engine version
it tries to fetch. When `shorebird` runs our forked `flutter`, we also tell it
to fetch its engine artifacts from our server (download.shorebird.dev) instead
of Google's (download.flutter.io). download.shorebird.dev knows how to replace
a few Android artifacts with Shorebird enabled ones and proxy all other requests
to Google's servers. This is how we now support all platforms Flutter does
since it's using the same host binaries as an unmodified Flutter SDK.

https://github.com/shorebirdtech/shorebird/blob/main/FORKING_FLUTTER.md has more
information on how we forked Flutter if you're curious.

Known issues:

- We have had reports of patches sometimes failing to apply. We expect to have
  a fix for this early next week.
  https://github.com/shorebirdtech/shorebird/issues/235
- Shorebird itself should work on Windows, but we haven't updated our installer
  script to support it yet. https://github.com/shorebirdtech/install/issues/10

Please try out the new platforms and new auth flow and let us know what you
think.
