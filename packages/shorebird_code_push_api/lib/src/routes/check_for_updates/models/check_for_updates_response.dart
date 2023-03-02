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
      'update': update?.toJson(),
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
    return 'http://localhost:8080/releases/$version.txt';
  }
}
