class CheckForUpdatesRequest {
  const CheckForUpdatesRequest({
    required this.version,
    required this.platform,
    required this.arch,
    required this.clientId,
  });

  factory CheckForUpdatesRequest.fromJson(Map<String, dynamic> json) {
    return CheckForUpdatesRequest(
      version: (json['version'] ?? '') as String,
      platform: json['platform'] as String,
      arch: json['arch'] as String,
      clientId: json['client_id'] as String,
    );
  }

  final String version;
  final String platform;
  final String arch;
  final String clientId;
}
