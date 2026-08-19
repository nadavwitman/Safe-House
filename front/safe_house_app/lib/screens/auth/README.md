# screens/auth

The unauthenticated / not-yet-in-a-house flow: sign in, sign up, and (for a `user`-role family member with no houses) join a house by invite code. All three build on [AuthService, UserService, AuthState, and ApiException](../../services/README.md) (see `services/README.md`) and share form primitives from [shared_widgets.dart](../../widgets/README.md).

## [sign_in_screen.dart](sign_in_screen.dart)

`SignInScreen`: email/password form with inline validation that only appears after the first submit attempt (`_submitted` gates `_emailError`/`_passwordError`, so a blank form doesn't show red errors before the user has done anything). On success it calls `AuthService.signIn` then `UserService.getProfile()` to populate `AuthState`, and routes based on the resulting state — **not** on anything returned directly from sign-in:

- `AuthState.instance.isAdmin` → [AdminShell](../admin/README.md)
- `currentUser.houses.isEmpty` (a `user`-role account with no house yet) → `JoinHouseScreen`
- otherwise → [CustomerShell](../customer/README.md)

This three-way branch is the app's actual role/onboarding router; it's why `AuthState` has to be fully populated before it runs.

## [sign_up_screen.dart](sign_up_screen.dart)

`SignUpScreen`: username/email/password form (password requires 6+ characters, checked client-side before calling `AuthService.signUp`). New accounts are always the `user` role — there's no admin sign-up path in the app, since admin accounts are provisioned another way — so success unconditionally routes to `JoinHouseScreen` rather than re-running the sign-in role check. Includes a static privacy notice ("we never record video or audio") since this is the first screen where a new user commits to the product.

## [join_house_screen.dart](join_house_screen.dart)

`JoinHouseScreen`: a single invite-code field (uppercased as typed to match the backend's code format) calling `UserService.joinHouse`. On success, swaps the form for a confirmation view showing the resident's name and a "Take me to the dashboard" button into [CustomerShell](../customer/README.md). Reachable from both `SignInScreen` (existing user with zero houses) and `SignUpScreen` (every new account), so it has no "back" affordance in either form state — leaving it means either joining a house or signing out entirely.
