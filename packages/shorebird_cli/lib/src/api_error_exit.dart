import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template api_error_exit}
/// A [ProcessExit] thrown when a Shorebird API call fails, carrying the
/// [error] the server returned so `--json` output can report its error code
/// and details instead of only the exit code.
/// {@endtemplate}
class ApiErrorExit extends ProcessExit {
  /// {@macro api_error_exit}
  ApiErrorExit(this.error, int exitCode) : super(exitCode);

  /// The error the Shorebird API returned.
  final CodePushException error;
}
