/// A standard CLI exit code.
///
/// Constants follow the BSD `sysexits.h` convention.
// Class-with-static-constants form (rather than enum) preserves the
// `ExitCode.success.code` access pattern callers expect from `package:io`.
// ignore: use_enums
class ExitCode {
  /// Create an [ExitCode] with the given numeric [code] and human-readable
  /// [_name].
  const ExitCode._(this.code, this._name);

  /// The numeric exit code.
  final int code;

  final String _name;

  /// Successful termination.
  static const ExitCode success = ExitCode._(0, 'success');

  /// The command was used incorrectly (wrong arguments, bad flags, etc.).
  static const ExitCode usage = ExitCode._(64, 'usage');

  /// The input data was incorrect in some way.
  static const ExitCode data = ExitCode._(65, 'data');

  /// An input file did not exist or wasn't readable.
  static const ExitCode noInput = ExitCode._(66, 'noInput');

  /// The user specified did not exist.
  static const ExitCode noUser = ExitCode._(67, 'noUser');

  /// The host specified did not exist.
  static const ExitCode noHost = ExitCode._(68, 'noHost');

  /// A service is unavailable.
  static const ExitCode unavailable = ExitCode._(69, 'unavailable');

  /// An internal software error has been detected.
  static const ExitCode software = ExitCode._(70, 'software');

  /// An operating system error has been detected.
  static const ExitCode osError = ExitCode._(71, 'osError');

  /// A system file (e.g. `/etc/passwd`) does not exist or could not be opened.
  static const ExitCode osFile = ExitCode._(72, 'osFile');

  /// A user-specified output file cannot be created.
  static const ExitCode cantCreate = ExitCode._(73, 'cantCreate');

  /// An error occurred while doing I/O on some file.
  static const ExitCode ioError = ExitCode._(74, 'ioError');

  /// Temporary failure; the user is invited to retry.
  static const ExitCode tempFail = ExitCode._(75, 'tempFail');

  /// The user did not have sufficient permission to perform the operation.
  static const ExitCode noPerm = ExitCode._(77, 'noPerm');

  /// Something was found in a misconfigured or missing-config state.
  static const ExitCode config = ExitCode._(78, 'config');

  @override
  String toString() => '$_name: $code';
}
