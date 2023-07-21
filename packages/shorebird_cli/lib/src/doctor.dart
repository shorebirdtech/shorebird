import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// A reference to a [Doctor] instance.
final doctorRef = create(Doctor.new);

/// The [Doctor] instance available in the current zone.
Doctor get doctor => read(doctorRef);

/// {@template doctor}
/// A class that provides a set of validators to check the current environment
/// for potential issues.
/// {@endtemplate}
class Doctor {
  /// Validators that verify shorebird will work on Android.
  final List<Validator> androidCommandValidators = [
    AndroidInternetPermissionValidator(),
  ];

  /// Validators that verify shorebird will work on iOS.
  final List<Validator> iosCommandValidators = [];

  /// All available validators.
  List<Validator> allValidators = [
    ShorebirdVersionValidator(),
    ShorebirdFlutterValidator(),
    AndroidInternetPermissionValidator(),
  ];
}
