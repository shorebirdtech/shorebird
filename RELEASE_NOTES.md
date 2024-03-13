# Release Notes

This section contains past updates we've sent to customers via Discord.

## 0.26.5 (March 13, 2024)

🩹 Fix issue where releases created with `--flutter-version` flag were reporting
   incorrect Flutter version, causing `shorebird patch` to later fail.

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
have not yet been able to reproduce this ourselves. We would *love* to work
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
- 👀 only list previewable releases when running `shorebird preview`

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
