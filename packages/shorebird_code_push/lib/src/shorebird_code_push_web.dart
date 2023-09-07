import 'package:shorebird_code_push/src/shorebird_code_push_base.dart';
import 'package:shorebird_code_push/src/shorebird_code_push_noop.dart';

/// Applications should not import this file directly, but
/// import `package:shorebird_code_push/shorebird_code_push.dart` instead.

/// {@template shorebird_code_push}
/// Get info about your Shorebird code push app.
/// {@endtemplate}
class ShorebirdCodePush extends ShorebirdCodePushNoop
    implements ShorebirdCodePushBase {}
