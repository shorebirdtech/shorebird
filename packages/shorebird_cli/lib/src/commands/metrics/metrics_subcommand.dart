import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/app_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The bucket sizes the metrics API accepts for `granularity`.
final metricsGranularityValues = GetUniqueUsersParameter2.values
    .map((g) => g.value)
    .toList();

/// {@template metrics_subcommand}
/// Base class for the `shorebird metrics` subcommands, each of which fetches
/// one metrics endpoint for an app and prints it.
///
/// Subclasses add their own options, implement [request], and describe how
/// to print the response in [printResult]. With `--json` the response is
/// emitted as returned by the API (via [toJson]).
/// {@endtemplate}
abstract class MetricsSubcommand<T> extends ShorebirdCommand
    with AppScopedCommand {
  /// {@macro metrics_subcommand}
  MetricsSubcommand() {
    addAppScopeOptions();
  }

  /// What this command fetches, for progress and error messages
  /// (e.g. "patch installs").
  String get metricName;

  /// Validates options before any network call, throwing a usage error (via
  /// [usageException]) on invalid input.
  ///
  /// Subclasses that override this must call `super.validateArgs()`.
  void validateArgs() {
    if (argParser.options.containsKey('start')) {
      _parseTime('start');
      _parseTime('end');
    }
  }

  /// Fetches the metric for [appId] from [client].
  ///
  /// When the command has a `--release-version` option and it was passed,
  /// [run] has already checked that the release exists, and [releaseId] is
  /// its id. Otherwise [releaseId] is null.
  Future<T> request(
    CodePushClient client, {
    required String appId,
    int? releaseId,
  });

  /// Serializes [response] as the API returned it.
  Map<String, dynamic> toJson(T response);

  /// Prints [response] for a human reader.
  void printResult(T response);

  /// Adds the `--start` and `--end` options for a time-windowed metric.
  void addWindowOptions() {
    argParser
      ..addOption(
        'start',
        help:
            'Window start (inclusive), as an ISO 8601 date or date-time '
            '(e.g. "2026-10-01" or "2026-10-01T12:00:00Z"). Interpreted as '
            'UTC when no offset is given. Defaults to --end minus 28 days.',
      )
      ..addOption(
        'end',
        help:
            'Window end (exclusive), in the same format as --start. '
            'Defaults to now.',
      );
  }

  /// Adds the `--granularity` option with [help].
  void addGranularityOption({required String help}) {
    argParser.addOption(
      'granularity',
      allowed: metricsGranularityValues,
      help: help,
    );
  }

  /// The `--start` value, or null when not passed.
  DateTime? get start => _parseTime('start');

  /// The `--end` value, or null when not passed.
  DateTime? get end => _parseTime('end');

  /// The `--release-version` value, or null when not passed or when this
  /// command has no such option.
  String? get releaseVersion {
    final name = CommonArguments.releaseVersionArg.name;
    if (!argParser.options.containsKey(name)) return null;
    return results[name] as String?;
  }

  DateTime? _parseTime(String name) {
    final value = results[name] as String?;
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      usageException(
        '--$name: "$value" is not an ISO 8601 date or date-time '
        '(e.g. "2026-10-01" or "2026-10-01T12:00:00Z").',
      );
    }
    if (parsed.isUtc) return parsed;
    // No offset was given: interpret the wall-clock fields as UTC, matching
    // the API, rather than as this machine's local time.
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
  }

  @override
  Future<int> run() async {
    final (:appId, :errorCode) = await resolveAppId();
    if (errorCode != null) return errorCode;

    validateArgs();

    // Every metric that takes --release-version checks it here, so an
    // unknown version is the same usage error on every subcommand rather
    // than whatever the endpoint happens to return.
    int? releaseId;
    final version = releaseVersion;
    if (version != null) {
      late final Release? release;
      final fetchError = await guardApiCall(
        () async => release = await codePushClientWrapper.maybeGetRelease(
          appId: appId,
          releaseVersion: version,
        ),
        code: JsonErrorCode.fetchFailed,
        message: 'Failed to fetch releases.',
      );
      if (fetchError != null) return fetchError;
      if (release == null) {
        return reportError(
          message: 'Release not found: "$version".',
          hint: 'Run "shorebird releases list" to see available releases.',
        );
      }
      releaseId = release!.id;
    }

    final progress = isJsonMode
        ? null
        : logger.progress('Fetching $metricName');
    final T response;
    try {
      response = await request(
        codePushClientWrapper.codePushClient,
        appId: appId,
        releaseId: releaseId,
      );
    } on CodePushException catch (error) {
      progress?.fail();
      return reportApiError(error, message: 'Failed to fetch $metricName.');
    } catch (_) {
      progress?.fail();
      rethrow;
    }
    progress?.complete();

    if (isJsonMode) {
      emitJsonSuccess(toJson(response));
    } else {
      printResult(response);
    }
    return ExitCode.success.code;
  }
}

/// Formats [time] as a UTC ISO 8601 timestamp to the second
/// (e.g. "2026-10-01T00:00:00Z").
String formatMetricsTime(DateTime time) =>
    '${time.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';

/// Formats [range] as "`start` to `end`".
String formatMetricsRange(MetricsRange range) =>
    '${formatMetricsTime(range.start)} to ${formatMetricsTime(range.end)}';

/// Formats [fraction] (0.0 to 1.0) as a percentage with one decimal place.
String formatPercent(double fraction) =>
    '${(fraction * 100).toStringAsFixed(1)}%';

/// Formats [hour] (0 to 23) as "HH:00".
String formatHour(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// Logs [rows] as left-aligned columns separated by two spaces, each line
/// indented by [indent].
void logTable(List<List<String>> rows, {String indent = '  '}) {
  if (rows.isEmpty) return;
  final widths = List<int>.filled(rows.first.length, 0);
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      if (row[i].length > widths[i]) widths[i] = row[i].length;
    }
  }
  for (final row in rows) {
    final cells = [
      for (var i = 0; i < row.length; i++) row[i].padRight(widths[i]),
    ];
    logger.info('$indent${cells.join('  ').trimRight()}');
  }
}
