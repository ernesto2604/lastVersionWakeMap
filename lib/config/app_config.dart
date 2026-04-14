class AppConfig {
  static const String _definedApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Non-secret backend URL used by the client to reach the guide proxy API.
  static String get apiBaseUrl => _definedApiBaseUrl.trim();
}
