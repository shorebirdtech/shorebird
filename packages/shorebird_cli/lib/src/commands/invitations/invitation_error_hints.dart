import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/logging/logging.dart';

/// What to do next after the invitations API refused a request with
/// [apiCode], or null when the server's own message says enough.
String? invitationErrorHint(String? apiCode) => switch (apiCode) {
  'invitation_email_mismatch' =>
    'Run `shorebird account whoami` to see which account you are signed in '
        'as, and `shorebird login` to sign in as the invited one.',
  'invitation_not_found' =>
    'Run `shorebird invitations list` to see your pending invitations.',
  'invitation_gone' =>
    'Run `shorebird invitations list` to see your pending invitations, or ask '
        'the sender for a new one.',
  'service_account_forbidden' =>
    'Invitations belong to people. Unset SHOREBIRD_TOKEN and sign in with '
        '`shorebird login`.',
  _ => null,
};

/// Runs [body], and when it exits on an API error logs that error's
/// [invitationErrorHint] before letting the exit through.
Future<T> withInvitationErrorHints<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ApiErrorExit catch (exit) {
    if (invitationErrorHint(exit.error.code) case final hint?) {
      logger.info(hint);
    }
    rethrow;
  }
}
