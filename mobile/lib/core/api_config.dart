/// API configuration for LORE backend connectivity.
///
/// The base URL is a compile-time setting so an emulator, a physical device,
/// and a desktop debug build can point at different local backend hosts
/// without editing source code.
///
/// - Android emulator (default): `http://10.0.2.2:8000`
/// - Physical device on the same network:
///   `flutter run --dart-define=LORE_API_BASE_URL=http://<host-ip>:8000`
class ApiConfig {
  static const String defaultBaseUrl = String.fromEnvironment(
    'LORE_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final String baseUrl;
  final String apiPrefix;
  final Duration timeout;

  const ApiConfig({
    this.baseUrl = defaultBaseUrl,
    this.apiPrefix = '/api/v1',
    this.timeout = const Duration(seconds: 20),
  });

  String get _normalizedBaseUrl => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  String get _normalizedPrefix {
    if (apiPrefix.isEmpty) return '';
    return apiPrefix.startsWith('/') ? apiPrefix : '/$apiPrefix';
  }

  /// Constructs a URI for the given API endpoint path.
  Uri uri(String path, [Map<String, String>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse(
      '$_normalizedBaseUrl$_normalizedPrefix$normalizedPath',
    );
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: queryParameters);
  }

  /// Root URI (no API prefix).
  Uri rootUri([String path = '/']) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_normalizedBaseUrl$normalizedPath');
  }
}
