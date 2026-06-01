// Configure at build time: flutter build apk --dart-define=BASE_URL=https://your-server:5000
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://16.164.45.100:5000',
  );
}
