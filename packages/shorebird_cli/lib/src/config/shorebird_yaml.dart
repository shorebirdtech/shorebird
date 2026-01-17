import 'package:json_annotation/json_annotation.dart';

part 'shorebird_yaml.g.dart';

/// The patch verification mode for the app.
@JsonEnum(fieldRename: FieldRename.snake)
enum PatchVerification {
  /// Verify the patch signature and hash before installing and loading.
  strict,

  /// Verify the patch signature and hash before installing, but not when
  /// loading from cache.
  installOnly,
}

/// {@template shorebird_yaml}
/// A Shorebird configuration file which contains metadata about the app.
///
/// Example `shorebird.yaml`:
/// ```yaml
/// # Basic configuration
/// app_id: 8d3155a8-a048-4820-acca-824d26c29b71
///
/// # For self-hosted deployments, specify your API server URL:
/// # base_url: https://your-codepush-server.com
///
/// # Disable automatic updates (requires package:shorebird_code_push):
/// # auto_update: false
///
/// # Multiple flavors configuration:
/// # flavors:
/// #   development: dev-app-id
/// #   production: prod-app-id
/// ```
/// {@endtemplate}
@JsonSerializable(anyMap: true, disallowUnrecognizedKeys: true)
class ShorebirdYaml {
  /// {@macro shorebird_yaml}
  const ShorebirdYaml({
    required this.appId,
    this.flavors,
    this.baseUrl,
    this.autoUpdate,
    this.patchVerification,
  });

  /// Creates a [ShorebirdYaml] from a JSON map.
  factory ShorebirdYaml.fromJson(Map<dynamic, dynamic> json) =>
      _$ShorebirdYamlFromJson(json);

  /// Converts this [ShorebirdYaml] to a JSON map.
  Map<String, dynamic> toJson() => _$ShorebirdYamlToJson(this);

  /// The base app id.
  ///
  /// Example:
  /// `"8d3155a8-a048-4820-acca-824d26c29b71"`
  final String appId;

  /// A map of flavor names to app ids.
  ///
  /// Will be `null` for apps with no flavors.
  ///
  /// Example:
  /// ```json
  /// {
  ///   "development": "8d3155a8-a048-4820-acca-824d26c29b71",
  ///   "production": "d458e87a-7362-4386-9eeb-629db2af413a"
  /// }
  /// ```
  final Map<String, String>? flavors;

  /// The base URL of the Shorebird CodePush API server.
  ///
  /// For self-hosted deployments, set this to your server's URL.
  /// If not specified, defaults to `https://api.shorebird.dev`.
  ///
  /// Can also be set via the `SHOREBIRD_HOSTED_URL` environment variable,
  /// which takes precedence over this configuration.
  ///
  /// Example:
  /// ```yaml
  /// base_url: https://your-codepush-server.com
  /// ```
  final String? baseUrl;

  /// Whether or not to automatically update the app.
  ///
  /// When set to `false`, you must use `package:shorebird_code_push` to
  /// manually trigger updates in your app.
  ///
  /// Defaults to `true` if not specified.
  final bool? autoUpdate;

  /// The patch verification mode for the app.
  final PatchVerification? patchVerification;
}

/// Extension on [ShorebirdYaml] to get the app id for a specific flavor.
extension AppIdExtension on ShorebirdYaml {
  /// Returns the app id for the given flavor.
  String getAppId({String? flavor}) {
    if (flavor == null || flavors == null) return appId;
    return flavors![flavor] ?? appId;
  }
}
