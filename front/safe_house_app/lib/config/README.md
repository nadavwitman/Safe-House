# config

## [app_config.dart](app_config.dart)

`AppConfig.baseUrl`: the single source of truth for the backend's address, read by [services/api_client.dart](../services/README.md). Set via `String.fromEnvironment('BASE_URL', ...)`, so it's fixed at build time rather than runtime — a release build points at the production server with `flutter build apk --dart-define=BASE_URL=https://...`, and local dev falls back to the hardcoded default IP if no `--dart-define` is passed.
