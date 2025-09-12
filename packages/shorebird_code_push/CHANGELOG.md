# 2.0.5

- docs: fix Discord badge in `README.md`

# 2.0.4

- feat: allow for custom UpdateTrack names in addition to stable, staging, and
  beta

# 2.0.3

- feat: override `toString` in `ReadPatchException` and `UpdateException`

# 2.0.2

- fix: un-break web platform
- chore: minor improvements to example

# 2.0.1

- Update the minimum Flutter version from 3.24.4 to 3.24.5 (3.24.4 does not
  include the updater changes required to support the new API).

# 2.0.0

- **BREAKING**: more updates to the Updater API. We now support Stable, Beta,
  and Staging tracks for patches, meaning you have more control over who gets
  your patches and when. Check out the example for a demo.

# 2.0.0-dev.2

- fix: tighten library exports

# 2.0.0-dev.1

- **BREAKING**: revamp the updater API
  - Remove `ShorebirdCodePush` in favor of `ShorebirdUpdater`

# 1.1.6

- Update log messages to explain what "using no-op implementation" means.

# 1.1.5

- Update example to use isNewPatchReadyToInstall.

# 1.1.4

- Run `dart format` over generated files to appease pub static analysis.

# 1.1.3

- Update README to improve example.
- Remove confusing log message printed when Shorebird is not available.

# 1.1.2

- update README

# 1.1.1

- break: `package:shorebird_code_push/shorebird_code_push_io.dart` and
  `package:shorebird_code_push/shorebird_code_push_web.dart` have moved into
  `src/` to discourage accidental direct import of these files. Please import
  `package:shorebird_code_push/shorebird_code_push.dart` instead.
- Fixes repository link in pubspec.yaml

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
