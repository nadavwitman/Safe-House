# lib

The Flutter client's entire source tree — a phone app for the two roles who use Safe House: an installer (`admin`) provisioning houses, and a family member (`user`) watching over one. Talks to nothing but [Backend_Server](../../../Backend_Server/README.md)'s HTTP API and Firebase Cloud Messaging.

## [main.dart](main.dart)

The entry point. On startup: initializes Firebase (skipped on platforms FCM doesn't support, e.g. Linux desktop), loads any persisted session (`AuthState.instance.loadFromStorage()`), and — if a token was found — re-validates it by calling `UserService.getProfile()`, clearing the session entirely on failure rather than launching into a UI backed by a stale/invalid token. `SafeHouseApp` then picks the launch screen from `AuthState`'s role/onboarding state (see [screens/README.md](screens/README.md) for the exact branch) and defines the app's single `ThemeData` — the cream/sage palette from [theme/colors.dart](theme/README.md), Newsreader for display text and Manrope for body text (via `google_fonts`), and Cupertino-style page transitions on every platform except web.

## [firebase_options.dart](firebase_options.dart)

FlutterFire-CLI-generated, not hand-edited — per-platform `FirebaseOptions` (API keys, project id, app id) consumed by `main.dart`'s `Firebase.initializeApp()`.

## Subfolders

- **[screens/](screens/README.md)** — every screen, split into `auth/`, `customer/`, and `admin/`.
- **[services/](services/README.md)** — the backend/device boundary: the HTTP client, one wrapper per API area, session state (`AuthState`), and local-only persistence (alert acknowledgements, the weekly report cache).
- **[widgets/](widgets/README.md)** — shared UI primitives (buttons, inputs, cards, the bottom nav shell) used across every screen.
- **[theme/](theme/README.md)** — the color palette.
- **[config/](config/README.md)** — build-time configuration (the backend's base URL).
