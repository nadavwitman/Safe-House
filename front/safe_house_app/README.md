# Safe House — Flutter App

Mobile app for the Safe House elder-care monitoring system, for two roles: an installer (`admin`) provisioning houses, and a family member (`user`) watching over one. Connects to the [Backend_Server](../../Backend_Server/README.md) Flask API at `BASE_URL` (configured via `--dart-define=BASE_URL=http://...`) and to Firebase Cloud Messaging for push alerts.

---

## Build & Run

```bash
# development
flutter run --dart-define=BASE_URL=http://<server-ip>:5000

# release APK
flutter build apk --dart-define=BASE_URL=https://<server-host>:5000
```

---

## App Structure

Everything lives under **[lib/](lib/README.md)**, which has its own README tree:

- **[lib/main.dart](lib/README.md)** — entry point: Firebase init, session restore, role-based routing to the first screen.
- **[lib/screens/](lib/screens/README.md)** — every screen, split into [auth/](lib/screens/auth/README.md) (sign in, sign up, join house), [customer/](lib/screens/customer/README.md) (the family member's 4-tab dashboard/summary/alerts/profile), and [admin/](lib/screens/admin/README.md) (the installer's house search/create).
- **[lib/services/](lib/services/README.md)** — the entire backend/device boundary: the HTTP client, one wrapper per API area, session state (`AuthState`), and local-only persistence.
- **[lib/widgets/](lib/widgets/README.md)** — shared UI primitives (buttons, inputs, cards, the bottom nav shell).
- **[lib/theme/](lib/theme/README.md)** — the color palette.
- **[lib/config/](lib/config/README.md)** — build-time configuration (`BASE_URL`).

Other top-level entries: `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` (Flutter's generated per-platform runner projects), `assets/`, `test/`, `pubspec.yaml`/`pubspec.lock` (dependencies), `firebase.json` (FlutterFire CLI config), `analysis_options.yaml` (lints).

---

## Token handling

Access tokens (30-minute expiry) and refresh tokens (30-day expiry) are held in `AuthState` and persisted to `SharedPreferences`. `ApiClient` retries any 401 once via `POST /api/auth/refresh`; if that also fails, it clears the session — see [lib/services/README.md](lib/services/README.md) for the full mechanism.
