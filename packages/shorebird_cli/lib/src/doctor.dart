import 'dart:convert';

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// A reference to a [Doctor] instance.
final doctorRef = create(Doctor.new);

/// The [Doctor] instance available in the current zone.
Doctor get doctor => read(doctorRef);

/// {@template validator_result}
/// The issues one validator found.
/// {@endtemplate}
class ValidatorResult {
  /// {@macro validator_result}
  const ValidatorResult({required this.name, required this.issues});

  /// The validator's description.
  final String name;

  /// The issues the validator found.
  final List<ValidationIssue> issues;

  /// Whether the validator passed. Only errors fail a validator; warnings
  /// don't.
  bool get ok => !hasErrors(issues);

  /// Whether any of [issues] is an error.
  static bool hasErrors(Iterable<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.error);

  /// The JSON representation of this result.
  Map<String, Object> toJson() => {
    'name': name,
    'ok': ok,
    'issues': [
      for (final issue in issues)
        {'severity': issue.severity.name, 'message': issue.message},
    ],
  };
}

/// {@template doctor}
/// A class that provides a set of validators to check the current environment
/// for potential issues.
/// {@endtemplate}
class Doctor {
  /// Validators that verify shorebird will work on Android.
  final List<Validator> androidCommandValidators = [
    AndroidInternetPermissionValidator(),
    LegacyKeepDebugSymbolsValidator(),
  ];

  /// Validators that verify shorebird will work on iOS.
  final List<Validator> iosCommandValidators = [
    XcodeprojFlutterOverrideValidator(),
  ];

  /// Validators that verify shorebird will work on Linux.
  final List<Validator> linuxCommandValidators = [];

  /// Validators that verify shorebird will work on macOS.
  final List<Validator> macosCommandValidators = [MacosEntitlementsValidator()];

  /// Validators that verify shorebird will work on Windows.
  final List<Validator> windowsCommandValidators = [
    // Check whether powershell is installed?
  ];

  /// Validators that should run during `shorebird doctor` and `shorebird init`.
  List<Validator> initAndDoctorValidators = [
    ShorebirdVersionValidator(),
    AndroidInternetPermissionValidator(),
    LegacyKeepDebugSymbolsValidator(),
    XcodeprojFlutterOverrideValidator(),
    MacosEntitlementsValidator(),
    ShorebirdYamlAssetValidator(),
    TrackedLockFilesValidator(),
  ];

  /// Runs each of [validators] that can run in the current context and returns
  /// what each found, without logging or applying fixes.
  Future<List<ValidatorResult>> validate(List<Validator> validators) async {
    return [
      for (final validator in validators)
        if (validator.canRunInCurrentContext())
          ValidatorResult(
            name: validator.description,
            issues: await validator.validate(),
          ),
    ];
  }

  /// Run the provided [validators]. If [applyFixes] is `true`, any validation
  /// issues that can be automatically fixed will be.
  Future<void> runValidators(
    List<Validator> validators, {
    bool applyFixes = false,
  }) async {
    final allIssues = <ValidationIssue>[];
    final allFixableIssues = <ValidationIssue>[];

    var totalIssuesFixed = 0;
    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        continue;
      }

      final failedFixes = <ValidationIssue, dynamic>{};
      final validatorProgress = logger.progress(validator.description);
      final issues = await validator.validate();
      if (issues.isEmpty) {
        validatorProgress.complete();
        continue;
      }

      final fixableIssues = issues.where((issue) => issue.fix != null);
      var unresolvedIssues = issues;
      String? fixAppliedMessage;
      if (fixableIssues.isNotEmpty) {
        if (applyFixes) {
          validatorProgress.update('Fixing');
          for (final issue in fixableIssues) {
            try {
              await issue.fix!();
            } on Exception catch (error) {
              failedFixes[issue] = error;
            }
          }

          // Re-run the validator to see if there are any remaining issues that
          // we couldn't fix.
          unresolvedIssues = await validator.validate();
          final numIssuesFixed = issues.length - unresolvedIssues.length;
          if (numIssuesFixed > 0) {
            totalIssuesFixed += numIssuesFixed;
            fixAppliedMessage =
                '''${validator.description} ${green.wrap('($numIssuesFixed fix${numIssuesFixed == 1 ? '' : 'es'} applied)')}''';
            // Everything this validator found is fixed, so there is nothing
            // left to report for it.
            if (unresolvedIssues.isEmpty && failedFixes.isEmpty) {
              validatorProgress.complete(fixAppliedMessage);
              continue;
            }
          }
        } else {
          allFixableIssues.addAll(fixableIssues);
        }
      }

      // The validator should only fail if there are errors (warnings don't
      // cause failure).
      ValidatorResult.hasErrors(unresolvedIssues)
          ? validatorProgress.fail(fixAppliedMessage)
          : validatorProgress.complete(fixAppliedMessage);

      for (final issue in failedFixes.keys) {
        logger.err(
          '''  An error occurred while attempting to fix ${issue.message}: ${failedFixes[issue]}''',
        );
      }

      for (final issue in unresolvedIssues) {
        if (issue.displayMessage == null) {
          continue;
        }

        final lines = const LineSplitter().convert(issue.displayMessage!);
        for (final (i, line) in lines.indexed) {
          var leadingPaddingSpaceCount = 2;
          if (i > 0) {
            // Indent subsequent lines to align with the first line after the
            // leading string and the space following it.
            leadingPaddingSpaceCount += issue.severity.rawLeading.length + 1;
          }
          logger.info('${' ' * leadingPaddingSpaceCount}$line');
        }
      }

      allIssues.addAll(unresolvedIssues);
    }

    // Everything that was found got fixed; the per-validator "fixes applied"
    // lines already say so.
    if (allIssues.isEmpty && totalIssuesFixed > 0) {
      return;
    }

    if (allIssues.isEmpty) {
      logger.info('''

No issues detected!''');
    } else {
      final numIssues = allIssues.length;
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');

      if (allFixableIssues.isNotEmpty && !applyFixes) {
        final fixableIssueCount = allFixableIssues.length;
        logger.info(
          '''
$fixableIssueCount issue${fixableIssueCount == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
        );
      }
    }
  }
}
