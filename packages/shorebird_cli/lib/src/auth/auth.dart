import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/session.dart';
import 'package:shorebird_cli/src/config/config.dart';

class Auth {
  Auth() {
    _loadSession();
  }

  static const _sessionFileName = 'shorebird-session.json';
  final sessionFilePath = p.join(shorebirdConfigDir, _sessionFileName);

  void login({required String apiKey}) {
    _session = Session(apiKey: apiKey);
    _flushSession(_session!);
  }

  void logout() => _clearSession();

  Session? _session;

  Session? get currentSession => _session;

  void _loadSession() {
    final sessionFile = File(sessionFilePath);

    if (sessionFile.existsSync()) {
      try {
        final contents = sessionFile.readAsStringSync();
        _session = Session.fromJson(
          json.decode(contents) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  void _flushSession(Session session) {
    File(sessionFilePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(json.encode(session.toJson()));
  }

  void _clearSession() {
    _session = null;

    final sessionFile = File(sessionFilePath);
    if (sessionFile.existsSync()) {
      sessionFile.deleteSync(recursive: true);
    }
  }
}
