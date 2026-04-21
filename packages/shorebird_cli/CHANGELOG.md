# 1.6.93

- 🐦 Support for Flutter 3.41.7 & Dart 3.11.5
- 🔧 Updater: resumable downloads with streaming to disk
- 🔧 Updater: replace serde_yaml with hand-rolled parser for smaller binary
- 🔧 Updater: return UpdateInProgress status instead of erroring on concurrent updates
- 🔧 Updater: do not throw UpdateException on SHOREBIRD_NO_UPDATE
- ✨ Capture build trace + privacy-safe summary on release
- ✨ Hint at --dart-define/--obfuscate mismatch on link failure
- ✨ Reject ExportOptions.plist with manageAppVersionAndBuildNumber
- ✨ Include snapshots in patch debug dump
- 🐛 Only pass --shorebird-trace to build commands that support it
- 🐛 Detect --obfuscate and --split-debug-info after --
- 🐛 Fetch latest refs before resolving --flutter-version

# 0.0.1

- feat: initial commit 🎉
