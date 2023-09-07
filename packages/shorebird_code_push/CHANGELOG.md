# 1.2.0
- break: `package:shorebird_code_push/shorebird_code_push_io.dart` and
  `package:shorebird_code_push/shorebird_code_push_web.dart` have moved into
  `src/` to discourage accidental direct import of these files.  Please import
  `package:shorebird_code_push/shorebird_code_push.dart` instead.

# 1.1.0

- feat: introduce `isShorebirdAvailable` to determine whether the Shorebird Engine is detected
- fix: crashes when running Flutter application on web
- docs: improvements to example app

# 1.0.0

- Change `downloadUpdate` to `downloadUpdateIfAvailable`, as the Updater performs
  this check internally anyway.

# 0.1.3

- Ignore some lints in generated files to make pub.dev happy

# 0.1.2

- Improves documentation
- Improves example, adds restart button to readme

# 0.1.1

- Add readiness warning to README

# 0.1.0

- Initial release 🎉
