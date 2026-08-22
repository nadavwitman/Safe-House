# screens/admin

The installer-facing side of the app — the two screens shown to an `admin`-role user after sign-in, hosted in a shared bottom-nav shell. Talks to the backend exclusively through [AdminService](../../services/README.md) (see `services/README.md`).

## [admin_shell.dart](admin_shell.dart)

`AdminShell`: the bottom-nav container for the two admin tabs (House Search, Create House). Builds both screens once into an `IndexedStack` so switching tabs never re-runs `initState` — a screen isn't rebuilt from scratch just because the admin tapped away and back. Because of that, `AdminSearchScreen` can't rely on `initState` to notice a house created on the other tab; it's handed the shared `_activeTab` `ValueNotifier` instead and reloads itself when it becomes the visible tab (see below).

## [admin_create_screen.dart](admin_create_screen.dart)

`AdminCreateScreen`: a form (resident name required; address and emergency phone optional) that calls `AdminService.createHouse`. On success it swaps the form for `_SuccessView`, showing the newly generated **house ID**, **invite code**, and **device token** as copyable chips (`CopyChip`, from [shared_widgets.dart](../../widgets/README.md)) — these are what the installer pastes into the ESP32's `config.h` and hands to the family. `_SuccessView` offers "Create another" (resets the form in place) or "Done" (`onNavigateToSearch` — jumps to House Search, where the new house now shows up and its credentials can be looked up again later).

## [admin_search_screen.dart](admin_search_screen.dart)

`AdminSearchScreen`: list → detail flow over every house the admin manages, driven by an explicit `_Mode` enum (`loading`, `list`, `loadingDetail`, `detail`, `listError`) rather than separate booleans, so the UI can't represent an invalid combination (e.g. "loading" and "showing an error" at once).

- **List mode** — loads all houses via `AdminService.listHouses()`, with a client-side substring filter (name/ID/address) over the already-fetched list rather than re-querying per keystroke. Because the shell keeps this screen alive via `IndexedStack`, returning from Create House doesn't restart `initState` — the screen instead listens to the shared `activeTab` notifier and reloads the list whenever it becomes the active tab again, but only while sitting in `list`/`listError` mode (an open detail view is left alone, since the admin is mid-task there).
- **Detail mode** (`_FoundCard`) — one house's full management view: invite code / device token as `CopyChip`s, `ConfirmButton`-gated regenerate/rotate actions (rotating the device token is flagged `danger: true` since it invalidates the currently-configured ESP32 until reconfigured), the list of joined users with per-user removal, and a 7-sensor mask editor (`_sensorList`, indices matching the backend's `sensor_mask` array order) with a "Save sensor mask" button that only appears once a toggle has actually been changed (`_maskDirty`). Deleting a house is behind a confirmation `AlertDialog` (not the lighter `ConfirmButton`) since it is irreversible and destroys all of that house's data.
- Every mutating action (`_regenerate`, `_rotate`, `_removeUser`, `_deleteHouse`, `_saveMask`) reports failure via a snackbar rather than failing silently, so the admin never believes an action succeeded when the backend call actually threw.
