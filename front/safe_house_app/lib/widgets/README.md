# widgets

## [shared_widgets.dart](shared_widgets.dart)

Every reusable UI primitive shared across [screens/](../screens/README.md), built on [theme/colors.dart](../theme/README.md). One file rather than one-per-widget since none of these are large enough on their own to justify a split, and they're almost always used together.

- **`SafeHouseLogo` / `Wordmark`** — the hand-painted shield-with-house-and-checkmark logo (`CustomPainter`) and the "Safe House" wordmark that pairs it with the brand name, in `'sm'`/`'md'`/`'lg'` sizes. Used on every auth screen and the dashboard header.
- **`AppButton`** — the one button used everywhere, parameterized by `AppButtonVariant` (`primary`/`soft`/`ghost`/`outline`/`danger`/`dangerSoft`) and `AppButtonSize` (`sm`/`md`/`lg`). Implemented on a raw `GestureDetector` + `AnimatedScale` rather than Flutter's built-in button widgets, for the press-down scale animation and full control over the pill shape/shadow per variant.
- **`AppInput`** — the labeled text field used on every form (sign in/up, admin create, username/password change), with inline error/hint text, an optional leading icon, and password visibility toggling built in.
- **`AppCard`** — the base surface (cream card, hairline border, tiered box-shadow via `elevation: 0|1|2`) that almost every other card-like widget in the app wraps.
- **`StatusDot`** — a small colored dot (`'ok'`/`'warn'`/`'alert'`/`'off'`) with an optional radiating pulse animation, reused by `AppTag`, the dashboard's status hero, and sensor cards to mean the same thing everywhere: is this thing currently fine.
- **`IconWell`** — a circular icon background whose color comes from `AppColors.iconWellBg/Fg(tone)`, the shared way every sensor icon (door, kitchen, meds, ...) gets colored consistently across the dashboard, alerts, and admin sensor-mask editor.
- **`AppTag`** — a small pill (label + optional leading icon) for status labels like "Active"/"Live"/"EMERGENCY".
- **`AppToggle`** — a custom on/off switch (not Flutter's `Switch`) in `'sm'`/`'md'`/`'lg'` sizes, used for the sensor mask and vacation mode.
- **`BottomNavShell` / `NavItem` / `customerNavItems` / `adminNavItems`** — the bottom tab bar shell both [AdminShell and CustomerShell](../screens/README.md) wrap their `IndexedStack` in, including the single-badge support the customer shell uses for the Alerts unread count.
- **`AppFilterChip`** — the toggleable, count-carrying filter pill used by the Alerts tab's All/Unread/Emergency/Warning/About row.
- **`DayHeader`** — the "Today ⎯⎯⎯ 3 alerts" divider row used to group the Alerts tab's list by calendar day.
- **`CopyChip`** — a labeled value with a tap-to-copy button (clipboard, with a 1.4s "Copied" confirmation state) — used for invite codes, device tokens, and house IDs in the admin flow.
- **`ConfirmButton`** — a button that turns into an inline "Are you sure? [Confirm] [Cancel]" on first tap rather than opening a dialog, used for the admin's lighter-weight destructive actions (regenerate invite code, rotate device token, remove user) where a full `AlertDialog` (used instead for deleting a house) would be excessive.
