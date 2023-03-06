import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth/session.dart';

class Auth {
  Auth() {
    _loadSession();
  }

  static const _applicationName = 'shorebird';
  static const _sessionFileName = 'shorebird-session.json';

  void login({required String projectId, required String apiKey}) {
    _session = Session(projectId: projectId, apiKey: apiKey);
    _flushSession(_session!);
  }

  void logout() => _clearSession();

  late final String? _shorebirdConfigDir = () {
    try {
      return applicationConfigHome(_applicationName);
    } catch (_) {
      return null;
    }
  }();

  Session? _session;

  Session? get currentSession => _session;

  void _loadSession() {
    final shorebirdConfigDir = _shorebirdConfigDir;
    if (shorebirdConfigDir == null) return;

    final sessionFile = File(p.join(shorebirdConfigDir, _sessionFileName));

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
    final shorebirdConfigDir = _shorebirdConfigDir;
    if (shorebirdConfigDir == null) return;

    final sessionFile = File(p.join(shorebirdConfigDir, _sessionFileName))
      ..createSync(recursive: true);

    if (!sessionFile.existsSync()) {
      sessionFile.createSync(recursive: true);
    }

    sessionFile.writeAsStringSync(json.encode(session.toJson()));
  }

  void _clearSession() {
    _session = null;

    final shorebirdConfigDir = _shorebirdConfigDir;
    if (shorebirdConfigDir == null) return;

    final sessionFile = File(p.join(shorebirdConfigDir, _sessionFileName));
    if (sessionFile.existsSync()) {
      sessionFile.deleteSync(recursive: true);
    }
  }
}
