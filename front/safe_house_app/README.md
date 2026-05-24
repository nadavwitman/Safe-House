# Safe House — Flutter App

Mobile app for the Safe House elder-care monitoring system.
Connects to the Flask backend at `BASE_URL` (configured via `--dart-define=BASE_URL=http://...`).

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

```
lib/
  main.dart               — startup, auth routing
  config/app_config.dart  — reads BASE_URL from --dart-define
  theme/colors.dart       — AppColors palette
  widgets/shared_widgets.dart — reusable UI components
  services/               — all API communication
  screens/
    auth/                 — sign-in, sign-up, join-house
    customer/             — dashboard, alerts, summary, profile
    admin/                — search, create
```

---

## Startup Flow (`main.dart`)

1. Load saved tokens from SharedPreferences.
2. If a token exists, call `GET /api/users/me` to refresh user profile.
3. If the call fails (expired/revoked), clear auth state.
4. Route based on role:
   - `admin` → **AdminShell**
   - `user` with houses → **CustomerShell**
   - `user` with no houses → **JoinHouseScreen**
   - not logged in → **SignInScreen**

---

## Auth Screens

### SignInScreen
- Fields: Email, Password.
- **Sign in** button → `POST /api/auth/signin`, fetches profile, routes by role.
- Link to SignUpScreen.

### SignUpScreen
- Fields: Username, Email, Password (min 6 chars).
- **Create account** button → `POST /api/auth/signup`, navigates to JoinHouseScreen.
- Privacy note: "We never record video or audio."

### JoinHouseScreen
- Field: Invite code (auto-uppercased).
- **Join house** button → `POST /api/users/join-house` with the code.
- On success: shows resident name confirmation card + **Take me to the dashboard** button → CustomerShell.

---

## Customer Screens (CustomerShell — bottom nav)

### Dashboard
Bottom nav tab 1. **Polls every 60 seconds** — `GET /api/house/<id>/recent-events`.

- **"Watching Over" header** — shows resident name of the active house.
- **Status Hero card** — large visual showing either:
  - `All Clear` (green, solid ring) — normal monitoring active.
  - `Vacation Mode` (teal, dashed ring) — sensors still recording, alerts off.
- **Sensor grid** — 7 sensor cards (Front Door, Kitchen, Bathroom, Toilet, Medication Cabinet, Bed, Living Room). Each card shows **"X min ago / X hr ago"** last-activity time, derived from the most recent ESP32 reading where that sensor had value 1. Updates automatically every minute.

### Alerts
Bottom nav tab 2. Informational screen, no API calls.

Explains the push-notification system:
- **Warning** — non-critical anomalies (off routine, unusual timing).
- **Emergency** — critical situations (fall risk, prolonged inactivity).
- Tips checklist for enabling phone notifications.
> Alerts are delivered via FCM push notifications, not listed in-app.

### Summary
Bottom nav tab 3. Weekly AI-generated health report.

On load: `GET /api/insights/weekly/<house_id>`

Displays:
- **Overall score** (0–100) with color ring.
- **Key metrics** — sleep hours, active hours, bathroom visits, meal times, medication adherence, door activity — each with a delta vs prior week.
- **AI narrative** — generated text summary.
- **Generate new report** button → `POST /api/insights/weekly/<house_id>/generate`, then reloads.
- Shows spinner during load; error state with retry if API fails.
- Shows "No report yet" state with a generate button if no report exists (404).

### Profile
Bottom nav tab 4.

- **Avatar** with user initials + username/email display.
- **House switcher** — if user is a member of multiple houses, shows chips to switch active house (updates `AuthState.activeHouseId`).
- **Vacation Mode card** — combined toggle + scheduling UI:
  - **Toggle** → `POST /api/config` with `{house_id, mode: "Vacation"/"Normal"}`. Immediately pauses/resumes monitoring.
  - **Plan a trip** button → opens inline schedule editor with:
    - Date picker (Flutter `showDatePicker`, sage theme).
    - Custom scroll-wheel time picker (12h + AM/PM, 5-min intervals).
    - "This weekend" quick-fill preset.
    - Validation: end must be after start.
    - **Save schedule** → `POST /api/config/vacation-schedule` with `{house_id, schedule: {startDate, startTime, endDate, endTime}}`.
  - When a schedule is saved, card shows **STARTS / ENDS** block with formatted date and relative label ("in 3 days", "today").
  - **Edit** / **Cancel trip** buttons → edit reopens editor; cancel → `DELETE /api/config/vacation-schedule`.
  - Tag shows `Active` / `Scheduled` / `Paused` depending on state.
  - Backend auto-activates vacation at `startDate+startTime` and auto-deactivates + clears schedule at `endDate+endTime` (checked every 5 minutes by APScheduler).
- **Change username** button → opens dialog → `POST /api/auth/change-username`.
- **Change password** button → opens dialog (current password + new password + confirm) → `POST /api/auth/change-password`.
- **Sign out** button → `POST /api/auth/signout`, clears tokens, navigates to SignInScreen.

---

## Admin Screens (AdminShell — bottom nav)

### Search House (tab 1)
- Search field: enter a house ID.
- **Search** button → `GET /api/admin/house/<id>`.
- States: empty, searching (spinner), not found, error, found.
- **Found card** shows:
  - **Invite code** with **Regenerate** button → `POST /api/admin/house/<id>/regenerate-invite`. Two-tap confirmation before firing.
  - **Device token** with **Rotate** button → `POST /api/admin/house/<id>/rotate-device-token`. Two-tap confirmation.
  - **Members list** — username, email, role. Each row has **Remove** button → `DELETE /api/admin/house/<id>/user/<userId>`. Two-tap confirmation.
  - **Sensor mask** — 7 toggles (one per sensor). Changes are tracked locally; a **Save** button appears only when something changed → `POST /api/house/sensor-mask`.
- **Sign out** button in top bar.

### Create House (tab 2)
- Fields: Resident name (required), Address (optional), Emergency contact phone (optional).
- **Create house** button → `POST /api/admin/house/create`.
- On success: shows **House ID**, **Invite code**, **Device token** — all copyable.
  - Warning: "Device token is shown only once."
- **Done** / **Create another** buttons reset the form.

---

## Services Layer

| Service | Responsibility |
|---|---|
| `ApiClient` | All HTTP calls; injects Bearer token; auto-refreshes on 401 |
| `AuthState` | Singleton holding tokens, user profile, active house, vacation mode (persisted via SharedPreferences) |
| `AuthService` | sign-in, sign-up, sign-out, change-username, change-password |
| `UserService` | get profile, join house |
| `ConfigService` | set vacation/normal mode |
| `InsightsService` | get weekly report, generate weekly report |
| `AdminService` | list/get/create houses, regenerate invite, rotate token, remove user, set sensor mask |

### Token handling
- Access token: 30-minute expiry, stored in SharedPreferences.
- Refresh token: 30-day expiry, stored in SharedPreferences.
- `ApiClient` retries any 401 response once using `POST /api/auth/refresh`; if refresh also fails, clears auth state.

---

## Shared Widgets (`shared_widgets.dart`)

| Widget | Description |
|---|---|
| `AppButton` | Primary / outline / ghost / danger variants, sm/md/lg sizes, full-width option, leading/trailing icons |
| `AppInput` | Labeled text field with icon, error display, hint text, password toggle, controlled via `value:` + `onChanged:` |
| `AppCard` | Rounded card with border, optional gradient, optional clip |
| `AppTag` | Small label chip with color tones |
| `AppToggle` | On/off switch |
| `CopyChip` | Label + value row with clipboard copy button |
| `ConfirmButton` | Two-tap confirmation widget — first tap shows confirm state, second tap fires callback |
| `StatusDot` | Small colored dot (ok/warn/alert/off) |
| `IconWell` | Circular icon container with tone-based color |
| `Wordmark` | "Safe House" logo text, sm/md/lg size |
