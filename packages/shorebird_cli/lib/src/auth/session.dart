class Session {
  const Session({required this.apiKey});

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      apiKey: json['api_key'] as String,
    );
  }

  final String apiKey;

  Map<String, dynamic> toJson() => {'api_key': apiKey};
}
