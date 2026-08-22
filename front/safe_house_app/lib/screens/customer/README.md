# screens/customer

The family-facing side of the app: the four bottom-nav tabs shown to a signed-in `user`-role member of at least one house. All four talk to the backend through [services/](../../services/README.md) and build on [shared_widgets.dart](../../widgets/README.md); state that must survive tab switches (which house is active, vacation mode, unread alert count) lives in `AuthState.instance`, shared with [screens/auth](../auth/README.md).

## [customer_shell.dart](customer_shell.dart)

`CustomerShell`: the bottom-nav container for Dashboard / Summary / Alerts / Profile. Like `AdminShell`, it builds all four screens once into an `IndexedStack` so tab switches never re-run `initState` — screens that need to refresh on becoming visible are handed the shared `_activeTab` notifier and listen to it themselves. The shell's own job beyond hosting is the alert badge: it listens to `AuthState.instance.unreadAlerts` (owned by `AlertsScreen`, since that's the screen holding both the alerts and the acknowledgements the count is derived from) and rebuilds only the nav bar when it changes.

## [dashboard_screen.dart](dashboard_screen.dart)

`DashboardScreen`: the home tab — a status hero, an alert banner, and a grid of per-sensor cards. Polls `HouseService.getStatus(houseId)` every 30s (matching the ESP32's own once-a-minute report rate) while the app is foregrounded, pausing on backgrounding via `WidgetsBindingObserver`.

- **Status hero** (`_StatusHero`) — one of four states (`clear`/`warning`/`emergency`/`vacation`), driven by the server's `current_status` field. Warning/emergency pulse with a radiating ring animation; vacation gets a dashed ring instead; a calm house animates nothing, keeping it off the vsync path entirely.
- **Alert banner** (`_AlertBanner`) — shows the *same* server-composed `title`/`note` as the Alerts tab for the current alert, identified by `current_alert_id` (`current_status_at` changing means a genuinely new alert, including same-severity ones that displaced the old one). Acknowledging is device-local only (via `AlertAckStore`, see `services/README.md`) — it hides the banner on this phone and decrements the shared unread count, but never calls the server, since only the AI's own next decision can actually clear a house's status.
- **Sensor cards** — one per active sensor (filtered by the house's `sensor_mask`), each showing a relative "last seen" time from the server-maintained `last_activity` map. Merged into local state rather than replacing it wholesale on every poll, so a slow/partial response can't flicker a card back to "No data yet".
- Switching the active house (from the Profile tab) resets all locally-held alert/banner state before the next poll lands, guarded by `_stateForHouse`, so a previous house's alert can never bleed into a newly selected one.

## [alerts_screen.dart](alerts_screen.dart)

`AlertsScreen`: the last-7-days alert history, fetched via `InsightsService.getAlerts`. Normalizes three different alert shapes the backend can produce (AI anomaly, `device_offline`, `sensor_fault` — see [app/monitoring](../../../../../Backend_Server/app/monitoring/README.md) and [app/alerts](../../../../../Backend_Server/app/alerts/README.md) for where these originate) into one `_Alert` model, then:

- **Deduplicates** consecutive same-kind alerts within 5 minutes client-side, since the producers can fire in bursts (a periodic sensor-fault sweep, a decision flickering across a threshold).
- **Groups by calendar day** ("Today"/"Yesterday"/weekday) and offers filter chips (All/Unread/Emergency/Warning) plus a static "About" panel explaining what each alert type means.
- Tracks per-device acknowledgement via `AlertAckStore`, pruning stored acks against the current 7-day window on every successful full fetch — except the alert currently in effect on the dashboard, which is deliberately spared so the two screens never disagree about what's still "current."
- Publishes the unread count to `AuthState.instance.unreadAlerts` (the badge `CustomerShell` reads), making this screen the single owner of what "unread" means.
- Switching houses blanks the list and acknowledgement set before refetching, same pattern as the dashboard.

## [summary_screen.dart](summary_screen.dart)

`SummaryScreen`: the AI-generated weekly wellness report (see [Backend_Server/app/weekly_summary](../../../../../Backend_Server/app/weekly_summary/README.md)) — metric cards, two hand-painted `CustomPainter` charts (sleep, activity), and the AI's narrative insights/recommendations.

- **Caching scheme**: the report is cached on-device via `WeeklyReportCache`. `AuthState.instance.weeklyReportAt` — populated by the dashboard's poll, so this screen never has to poll for itself — is compared against the cached report's own `generated_at`; a fetch only happens when they disagree, or when nothing is cached yet. On a normal app open with an up-to-date cache, this costs zero network requests.
- The header's **Refresh** button (not "Generate") is deliberately named for what it does — one re-read of the stored report — since report generation is entirely server-side (the weekly Sunday job, or its catch-up path). A refresh that finds nothing new gets a toast saying so, since silence would be ambiguous.
- A first-load-only overlay (`_GeneratingOverlay`) is held up for a minimum 600ms even if the fetch resolves faster, so it never flashes.
- The report body computes six metric cards (sleep, mobility, nutrition, hygiene, medications, outside time) from the server's `weekly_averages`/`deltas`, each flagged `warn`/`alert` by a hardcoded threshold on its delta (e.g. sleep down more than 30min/night, outside time down more than 15min/day).

## [profile_screen.dart](profile_screen.dart)

`ProfileScreen`: account settings, house switching, and vacation mode — the most stateful of the four tabs.

- **Account** — username/email display, with dialogs (`_UsernameDialog`, `_PasswordDialog`) for changing either via `AuthService`.
- **House switcher** (`_HouseSwitcher`) — for a user belonging to multiple houses, an expandable list to change `AuthState.instance.activeHouseId`, which every other tab reads.
- **Vacation mode** (`_VacationCard`, the largest piece) — a toggle plus an optional scheduled trip, rendered as one of four states (`active`/`scheduled`/`paused`/`tripRunning`) via `_VacationState`. A trip already under way (`_tripInProgress`, comparing against the schedule's absolute UTC instants — see [app/scheduling](../../../../../Backend_Server/app/scheduling/README.md) for why UTC and not wall-clock) disables the manual toggle, since the pause belongs to the schedule and the server's own 5-minute sweep would just re-assert it; the only way out mid-trip is "End trip now" (`ConfigService.clearSchedule`). The schedule editor (`_ScheduleEditor`) submits both a device-local wall-clock pair (`startDate`/`startTime`/…, for display) and their UTC equivalents (`startUtc`/`endUtc`) so a trip spanning a timezone or DST boundary starts and ends exactly when the family meant it to.
- `_refreshProfile()` re-fetches the account from the server whenever this tab becomes visible, since another family member's changes (a new schedule, a trip the server's own scheduler already ended) would otherwise sit stale until the next cold start.
- Every mutating action reports failure via a snackbar — silently reverting a toggle would read as the app ignoring the tap.
