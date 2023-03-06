class Session {
  const Session({required this.projectId, required this.apiKey});

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      projectId: json['project_id'] as String,
      apiKey: json['api_key'] as String,
    );
  }

  final String projectId;
  final String apiKey;

  Map<String, dynamic> toJson() => {'project_id': projectId, 'api_key': apiKey};
}
