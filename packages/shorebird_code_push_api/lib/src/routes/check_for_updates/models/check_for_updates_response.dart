class CheckForUpdatesResponse {
  const CheckForUpdatesResponse({
    this.updateAvailable = false,
    this.update,
  });

  final bool updateAvailable;
  final Update? update;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'update_available': updateAvailable,
      if (update != null) 'update': update!.toJson(),
    };
  }
}

class Update {
  const Update({required this.version, required this.hash});

  final String version;
  final String hash;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'hash': hash,
      'download_url': downloadUrlForVersion(version),
    };
  }

  String downloadUrlForVersion(String version) {
    return 'https://shorebird-code-push-api-cypqazu4da-uc.a.run.app/api/v1/releases/$version.txt';
  }
}
