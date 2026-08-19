# screens

Every screen in the app, split by who sees them. All three subfolders build on [services/](../services/README.md) for backend/state access and [widgets/shared_widgets.dart](../widgets/README.md) for UI primitives.

- **[auth/](auth/README.md)** — sign in, sign up, and join-a-house-by-invite-code. Shown before login, and to a signed-in `user`-role account with no houses yet.
- **[customer/](customer/README.md)** — the four-tab bottom nav (Dashboard, Summary, Alerts, Profile) shown to a `user`-role family member once they belong to at least one house.
- **[admin/](admin/README.md)** — the two-tab bottom nav (House Search, Create House) shown to an `admin`-role installer account.

Which of these `main.dart` shows at launch is decided once, in `AuthState.instance`: not logged in → `auth/`'s sign-in screen; logged in and `isAdmin` → `admin/`; logged in, `user`-role, with houses → `customer/`; logged in, `user`-role, no houses → `auth/`'s join-house screen. The same three-way branch is repeated after a successful sign-in inside [auth/sign_in_screen.dart](auth/README.md), since that's the other moment the role/onboarding state needs to route somewhere.
