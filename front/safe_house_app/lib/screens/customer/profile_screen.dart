import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/auth_state.dart';
import '../../services/auth_service.dart';
import '../../services/config_service.dart';
import '../../services/user_service.dart';
import '../../services/api_client.dart';
import '../auth/sign_in_screen.dart';

// ── Helpers ──────────────────────────────────────────────────────
/// A schedule's endpoint as a local DateTime, or null if either half is missing
/// or malformed. Every read of a stored schedule goes through here — the fields
/// come back from Firestore and are not guaranteed to be well-formed strings,
/// and an int.parse throwing inside build takes the whole screen down.
DateTime? _parseLocalDT(Object? date, Object? time) {
  if (date is! String || time is! String) return null;
  final d = date.split('-');
  final t = time.split(':');
  if (d.length < 3 || t.length < 2) return null;
  final y = int.tryParse(d[0]);
  final mo = int.tryParse(d[1]);
  final day = int.tryParse(d[2]);
  final h = int.tryParse(t[0]);
  final mi = int.tryParse(t[1]);
  if (y == null || mo == null || day == null || h == null || mi == null) {
    return null;
  }
  return DateTime(y, mo, day, h, mi);
}

String _formatDateTime(Object? date, Object? time) {
  final dt = _parseLocalDT(date, time);
  if (dt == null) return '—';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final ap = dt.hour >= 12 ? 'PM' : 'AM';
  final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}'
      ' · $h12:${dt.minute.toString().padLeft(2, '0')} $ap';
}

String _relDays(Object? date, Object? time) {
  final dt = _parseLocalDT(date, time);
  if (dt == null) return '';
  // Whole calendar days apart, not elapsed 24h periods: a trip starting at 08:00
  // tomorrow is "tomorrow" whether it is now 22:00 or 09:00.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = day.difference(today).inDays;
  if (diff < 0) return '${-diff} day${-diff == 1 ? '' : 's'} ago';
  if (diff == 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}

/// Whether the trip is under way right now. The server has already paused the
/// house in this case (its scheduler does it within 5 minutes, and saving a
/// schedule that covers now does it immediately), so the card presents it as
/// something running rather than something to switch off by hand.
bool _tripInProgress(Map<String, dynamic>? schedule) {
  if (schedule == null) return false;
  final start = _parseLocalDT(schedule['startDate'], schedule['startTime']);
  final end = _parseLocalDT(schedule['endDate'], schedule['endTime']);
  if (start == null || end == null) return false;
  final now = DateTime.now();
  return !now.isBefore(start) && !now.isAfter(end);
}

class ProfileScreen extends StatefulWidget {
  /// The shell's current tab, and this screen's index in it. The tabs live in an
  /// IndexedStack, so initState fires once and never again — this is how the
  /// screen learns it has become visible and should re-read the account.
  final ValueNotifier<int> activeTab;
  final int tabIndex;

  const ProfileScreen(
      {super.key, required this.activeTab, required this.tabIndex});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _vacationLoading = false;
  bool _scheduleLoading = false;
  bool _refreshingProfile = false;

  @override
  void initState() {
    super.initState();
    widget.activeTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.activeTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.activeTab.value != widget.tabIndex) return;
    // The shell mutates the notifier inside its own setState, so this fires
    // mid-build; defer or the refresh's setState lands during the parent's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshProfile();
    });
  }

  /// Re-reads the account from the server. The houses list — and with it each
  /// house's stored trip and pause state — otherwise stays exactly as it was at
  /// sign-in, so a trip the server's scheduler ended, or one a second family
  /// member planned, never showed up until the next cold start.
  Future<void> _refreshProfile() async {
    if (_refreshingProfile) return;
    _refreshingProfile = true;
    try {
      await UserService.refresh();
      if (mounted) setState(() {});
    } catch (_) {
      // Keep showing the cached account; this is a background freshening.
    } finally {
      _refreshingProfile = false;
    }
  }

  /// Vacation calls change state the user is watching, so a failure has to say
  /// so — silently reverting the toggle reads as the app ignoring the tap.
  void _reportFailure(Object error, String fallback) {
    if (!mounted) return;
    final message = error is ApiException ? error.message : fallback;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// First name only — the copy reads "while Eleanor is away", and a full legal
  /// name there sounds like a form field rather than a person.
  String _activeResidentName(List<Map<String, dynamic>> houses, String activeId) {
    if (houses.isEmpty) return 'the resident';
    final house = houses.firstWhere(
      (h) => h['house_id'] == activeId,
      orElse: () => houses.first,
    );
    final full = (house['resident_name'] as String? ?? '').trim();
    if (full.isEmpty) return 'the resident';
    return full.split(RegExp(r'\s+')).first;
  }

  String _initials(String username) {
    final parts = username.trim().split(RegExp(r'[\s_]+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (username.length >= 2) return username.substring(0, 2).toUpperCase();
    return username.toUpperCase();
  }

  Future<void> _toggleVacation(bool on) async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() => _vacationLoading = true);
    try {
      final result =
          await ConfigService.setMode(houseId, on ? 'Vacation' : 'Normal');
      await AuthState.instance.setVacationMode(result.isVacation);
      // Turning monitoring back on ends a trip already under way, and the server
      // deletes that schedule. Without mirroring it here the card went on
      // advertising a trip that no longer existed.
      if (result.scheduleCleared) {
        AuthState.instance.updateActiveHouseSchedule(null);
      }
    } catch (e) {
      _reportFailure(e, 'Could not change vacation mode.');
    }
    if (mounted) setState(() => _vacationLoading = false);
  }

  Future<void> _saveSchedule(Map<String, dynamic> schedule) async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() => _scheduleLoading = true);
    try {
      final result = await ConfigService.setSchedule(houseId, schedule);
      AuthState.instance.updateActiveHouseSchedule(schedule);
      // A trip whose window already covers now pauses the house on the spot, so
      // the toggle and the status strip have to move with it.
      await AuthState.instance.setVacationMode(result.isVacation);
    } catch (e) {
      _reportFailure(e, 'Could not save the schedule.');
    }
    if (mounted) setState(() => _scheduleLoading = false);
  }

  Future<void> _clearSchedule() async {
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    setState(() => _scheduleLoading = true);
    try {
      final result = await ConfigService.clearSchedule(houseId);
      AuthState.instance.updateActiveHouseSchedule(null);
      // Cancelling resumes monitoring server-side. Leaving the toggle On here
      // told the user alerts were suppressed while they were in fact firing.
      await AuthState.instance.setVacationMode(result.isVacation);
    } catch (e) {
      _reportFailure(e, 'Could not cancel the trip.');
    }
    if (mounted) setState(() => _scheduleLoading = false);
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  void _showUsernameDialog() {
    showDialog(
      context: context,
      builder: (_) => _UsernameDialog(
        current: AuthState.instance.currentUser?.username ?? '',
        onSaved: () => setState(() {}),
      ),
    );
  }

  void _showPasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthState.instance;
    final user = auth.currentUser;
    final houses = user?.houses ?? [];
    final activeId = auth.activeHouseId ?? '';

    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACCOUNT',
                      style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink500,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 2),
                  Text('Profile',
                      style: GoogleFonts.newsreader(
                          fontSize: 28,
                          color: AppColors.ink900,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User info card
                    AppCard(
                      padding: EdgeInsets.zero,
                      clip: true,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                            color: AppColors.card3,
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: const BoxDecoration(
                                      color: AppColors.sage200,
                                      shape: BoxShape.circle),
                                  child: Center(
                                    child: Text(
                                      user != null
                                          ? _initials(user.username)
                                          : '?',
                                      style: GoogleFonts.newsreader(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.sage800),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(user?.username ?? '—',
                                          style: GoogleFonts.newsreader(
                                              fontSize: 20,
                                              color: AppColors.ink900,
                                              fontWeight: FontWeight.w500)),
                                      Text(user?.email ?? '—',
                                          style: GoogleFonts.manrope(
                                              fontSize: 13,
                                              color: AppColors.ink600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _ProfileRow(
                            label: 'Username',
                            value: user?.username ?? '—',
                            action: AppButton(
                              variant: AppButtonVariant.ghost,
                              buttonSize: AppButtonSize.sm,
                              onPressed: _showUsernameDialog,
                              child: const Text('Edit'),
                            ),
                          ),
                          _ProfileRow(
                            label: 'Password',
                            value: '••••••••••',
                            action: AppButton(
                              variant: AppButtonVariant.ghost,
                              buttonSize: AppButtonSize.sm,
                              onPressed: _showPasswordDialog,
                              child: const Text('Change'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Houses
                    if (houses.isNotEmpty) ...[
                      Text('HOUSES',
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink500,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 8),
                      _HouseSwitcher(
                        houses: houses,
                        activeId: activeId,
                        onChange: (id) async {
                          await AuthState.instance.setActiveHouse(id);
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          'You belong to ${houses.length} house${houses.length == 1 ? '' : 's'}.',
                          style: GoogleFonts.manrope(
                              fontSize: 12, color: AppColors.ink500),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Vacation mode. Listened to rather than read once: the
                    // server's scheduler can start a trip while this screen is
                    // sitting alive but unbuilt in the shell's IndexedStack, and
                    // the dashboard's poll is what notices.
                    ValueListenableBuilder<bool>(
                      valueListenable: auth.vacationMode,
                      builder: (context, isVacation, _) => _VacationCard(
                        on: isVacation,
                        loading: _vacationLoading,
                        scheduleLoading: _scheduleLoading,
                        onChanged: _toggleVacation,
                        schedule: auth.vacationSchedule,
                        onScheduleSave: _saveSchedule,
                        onScheduleClear: _clearSchedule,
                        residentName: _activeResidentName(houses, activeId),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sign out
                    AppButton(
                      variant: AppButtonVariant.ghost,
                      full: true,
                      leading: const Icon(Icons.logout,
                          size: 18, color: AppColors.alert),
                      onPressed: _signOut,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 14),
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Profile Row ──────────────────────────────────────────────────
class _ProfileRow extends StatelessWidget {
  final String label, value;
  final Widget action;
  const _ProfileRow(
      {required this.label, required this.value, required this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: GoogleFonts.manrope(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink500,
                        letterSpacing: 0.7)),
                const SizedBox(height: 3),
                Text(value,
                    style:
                        GoogleFonts.manrope(fontSize: 15, color: AppColors.ink900)),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}

// ── House Switcher ───────────────────────────────────────────────
class _HouseSwitcher extends StatefulWidget {
  final List<Map<String, dynamic>> houses;
  final String activeId;
  final ValueChanged<String> onChange;
  const _HouseSwitcher(
      {required this.houses,
      required this.activeId,
      required this.onChange});

  @override
  State<_HouseSwitcher> createState() => _HouseSwitcherState();
}

class _HouseSwitcherState extends State<_HouseSwitcher> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cur = widget.houses.firstWhere(
      (h) => h['house_id'] == widget.activeId,
      orElse: () => widget.houses.first,
    );
    final residentName = cur['resident_name'] as String? ?? '—';

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const IconWell(
                    tone: 'sage',
                    size: 36,
                    child: Icon(Icons.home_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE HOUSE',
                          style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink500,
                              letterSpacing: 0.7)),
                      const SizedBox(height: 2),
                      Text("$residentName's House",
                          style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900)),
                    ],
                  ),
                ),
                Icon(
                    _open
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.ink500),
              ],
            ),
          ),
        ),
        if (_open)
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: widget.houses.map((h) {
                final houseId = h['house_id'] as String? ?? '';
                final name = h['resident_name'] as String? ?? '—';
                final address = h['address'] as String?;
                final isActive = houseId == widget.activeId;
                return GestureDetector(
                  onTap: () {
                    widget.onChange(houseId);
                    setState(() => _open = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.sage50 : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const IconWell(
                            tone: 'sage',
                            size: 30,
                            child: Icon(Icons.home_outlined)),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink900)),
                              // Tells two houses with similar resident names
                              // apart. Absent on houses the installer set up
                              // without one, so the row collapses to the name.
                              if (address != null && address.isNotEmpty)
                                Text(address,
                                    style: GoogleFonts.manrope(
                                        fontSize: 12, color: AppColors.ink500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (isActive)
                          const Icon(Icons.check,
                              size: 16, color: AppColors.sage700),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

// ── Vacation Card ────────────────────────────────────────────────
class _VacationCard extends StatefulWidget {
  final bool on;
  final bool loading;
  final bool scheduleLoading;
  final ValueChanged<bool> onChanged;
  final Map<String, dynamic>? schedule;
  final ValueChanged<Map<String, dynamic>> onScheduleSave;
  final VoidCallback onScheduleClear;

  /// Named in the copy, so the card reads "while Eleanor is away" rather than
  /// describing the resident in the abstract.
  final String residentName;

  const _VacationCard({
    required this.on,
    required this.loading,
    required this.scheduleLoading,
    required this.onChanged,
    required this.schedule,
    required this.onScheduleSave,
    required this.onScheduleClear,
    required this.residentName,
  });

  @override
  State<_VacationCard> createState() => _VacationCardState();
}

/// The four presentations of the card, in the order a trip moves through them.
enum _VacationState { active, scheduled, paused, tripRunning }

class _VacationCardState extends State<_VacationCard> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    // A trip that has begun is not something the user switches off by hand —
    // the server started it and will end it. Distinguishing it from a manual
    // pause is what lets the card say "trip ends Sunday" instead of implying
    // monitoring stays off until someone remembers to come back here.
    final running = _tripInProgress(widget.schedule);
    final paused = widget.on || running;
    final state = !paused
        ? (widget.schedule != null
            ? _VacationState.scheduled
            : _VacationState.active)
        : (running ? _VacationState.tripRunning : _VacationState.paused);

    final resident = widget.residentName;
    final (tagLabel, bodyText) = switch (state) {
      _VacationState.active => (
          'Active',
          'Pauses anomaly detection while $resident is away. Schedule a trip '
              'ahead, or toggle on instantly.'
        ),
      _VacationState.scheduled => (
          'Scheduled',
          'Monitoring will pause automatically when the trip starts.'
        ),
      _VacationState.paused => (
          'Paused',
          'No alerts will fire until you turn this back off.'
        ),
      _VacationState.tripRunning => (
          'Paused · scheduled',
          'Vacation mode is paused as part of a scheduled trip. It will resume '
              'automatically.'
        ),
    };

    final (strongIcon, strongText) = switch (state) {
      _VacationState.active => (Icons.shield_outlined, 'Monitoring active'),
      _VacationState.scheduled => (
          Icons.access_time,
          'Monitoring active · scheduled trip ahead'
        ),
      _VacationState.paused => (
          Icons.nightlight_round,
          'Monitoring paused — vacation mode is on'
        ),
      _VacationState.tripRunning => (
          Icons.nightlight_round,
          'Monitoring paused — trip ends '
              '${_formatDateTime(widget.schedule?['endDate'], widget.schedule?['endTime'])}'
        ),
    };

    final bg = paused
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3DDB8), Color(0xFFECCB8E)])
        : null;
    final bd = paused ? const Color(0xFFE2B664) : AppColors.line;
    final fg = paused ? const Color(0xFF5C3F12) : AppColors.ink900;
    final bodyFg = paused ? const Color(0xFF6E5119) : AppColors.ink700;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: bg,
        color: bg == null ? AppColors.card : null,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: paused ? const Color(0xFFF8E9C9) : AppColors.sage100,
                  border: Border.all(
                      color: paused
                          ? const Color(0xFFE2B664)
                          : AppColors.sage200),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.luggage_outlined,
                    size: 22,
                    color: paused
                        ? const Color(0xFF8C6420)
                        : AppColors.sage800),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vacation Mode',
                        style: GoogleFonts.newsreader(
                            fontSize: 22,
                            color: fg,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    AppTag(
                      label: tagLabel,
                      tone: paused ? 'warn' : 'sage',
                      icon: StatusDot(tone: paused ? 'warn' : 'ok'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bodyText,
                      style: GoogleFonts.manrope(
                          fontSize: 13.5, color: bodyFg, height: 1.5),
                    ),
                  ],
                ),
              ),
              widget.loading
                  ? const SizedBox(
                      width: 44,
                      height: 28,
                      child: Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  // Disabled mid-trip: the pause belongs to the schedule, and
                  // switching it off here would be undone by the server's next
                  // sweep five minutes later. Cancelling the trip is the way out.
                  : AppToggle(
                      value: paused,
                      disabled: state == _VacationState.tripRunning,
                      onChanged: widget.onChanged,
                      size: 'lg'),
            ],
          ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: paused
                  ? Colors.white.withValues(alpha: 0.5)
                  : AppColors.bgSoft,
              border: Border.all(
                  color: paused
                      ? const Color(0xFFE2B664).withValues(alpha: 0.6)
                      : AppColors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(strongIcon, size: 16, color: bodyFg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strongText,
                    style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: bodyFg),
                  ),
                ),
              ],
            ),
          ),

          // ── Schedule section ──────────────────────────────────
          const SizedBox(height: 14),
          Divider(
              color: paused
                  ? const Color(0xFFE2B664).withValues(alpha: 0.55)
                  : AppColors.line2,
              thickness: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: bodyFg),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.schedule == null
                      ? 'Schedule a trip ahead'
                      : state == _VacationState.tripRunning
                          ? 'Trip in progress'
                          : 'Trip scheduled',
                  style: GoogleFonts.manrope(
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: fg),
                ),
              ),
              if (!_editing)
                widget.scheduleLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : widget.schedule != null
                        ? Row(children: [
                            AppButton(
                                variant: AppButtonVariant.ghost,
                                buttonSize: AppButtonSize.sm,
                                onPressed: () =>
                                    setState(() => _editing = true),
                                child: const Text('Edit')),
                            // Mid-trip this is the only way back to monitoring,
                            // since the toggle is the schedule's to control —
                            // named for what it does rather than "Cancel trip",
                            // which sounds like undoing a plan that has not
                            // happened yet.
                            AppButton(
                                variant: AppButtonVariant.ghost,
                                buttonSize: AppButtonSize.sm,
                                onPressed: widget.onScheduleClear,
                                child: Text(
                                    state == _VacationState.tripRunning
                                        ? 'End trip now'
                                        : 'Cancel trip')),
                          ])
                        : AppButton(
                            variant: AppButtonVariant.soft,
                            buttonSize: AppButtonSize.sm,
                            leading: const Icon(Icons.add, size: 14),
                            onPressed: () => setState(() => _editing = true),
                            child: const Text('Plan a trip')),
            ],
          ),

          if (widget.schedule != null && !_editing) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: paused
                    ? Colors.white.withValues(alpha: 0.55)
                    : AppColors.bgSoft,
                border: Border.all(
                    color: paused
                        ? const Color(0xFFE2B664).withValues(alpha: 0.6)
                        : AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('STARTS',
                            style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: bodyFg,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateTime(widget.schedule!['startDate'],
                              widget.schedule!['startTime']),
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fg),
                        ),
                        Text(
                          _relDays(widget.schedule!['startDate'],
                              widget.schedule!['startTime']),
                          style:
                              GoogleFonts.manrope(fontSize: 11, color: bodyFg),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 16, color: bodyFg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('ENDS',
                            style: GoogleFonts.manrope(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: bodyFg,
                                letterSpacing: 0.6)),
                        const SizedBox(height: 2),
                        Text(
                          _formatDateTime(widget.schedule!['endDate'],
                              widget.schedule!['endTime']),
                          style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: fg),
                          textAlign: TextAlign.end,
                        ),
                        Text(
                          _relDays(widget.schedule!['endDate'],
                              widget.schedule!['endTime']),
                          style:
                              GoogleFonts.manrope(fontSize: 11, color: bodyFg),
                          textAlign: TextAlign.end,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_editing) ...[
            const SizedBox(height: 12),
            _ScheduleEditor(
              initial: widget.schedule,
              onCancel: () => setState(() => _editing = false),
              onSave: (s) {
                widget.onScheduleSave(s);
                setState(() => _editing = false);
              },
            ),
          ],

          // A manual pause has nothing that will ever switch it off — worth
          // saying, since the whole point of the card is that alerts are
          // suppressed. A running trip ends itself, so it doesn't get this.
          if (state == _VacationState.paused) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 13, color: Color(0xFF7A5419)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Toggle off as soon as $resident returns home, or schedule a '
                    'trip to handle this automatically.',
                    style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: const Color(0xFF7A5419),
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ],

          if (widget.schedule == null && !_editing) ...[
            const SizedBox(height: 8),
            Text(
              "Set start and end times — we'll pause and resume monitoring automatically.",
              style:
                  GoogleFonts.manrope(fontSize: 12, color: bodyFg, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Schedule Editor ──────────────────────────────────────────────
class _ScheduleEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final VoidCallback onCancel;
  final ValueChanged<Map<String, dynamic>> onSave;
  const _ScheduleEditor(
      {this.initial, required this.onCancel, required this.onSave});

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  DateTime? _startDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  DateTime? _endDate;
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init == null) return;
    // Shared parser rather than a bare int.parse per field: these come back from
    // Firestore, and one malformed value used to throw out of initState and take
    // the screen with it.
    final start = _parseLocalDT(init['startDate'], init['startTime']);
    if (start != null) {
      _startDate = DateTime(start.year, start.month, start.day);
      _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    }
    final end = _parseLocalDT(init['endDate'], init['endTime']);
    if (end != null) {
      _endDate = DateTime(end.year, end.month, end.day);
      _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
    }
  }

  String _fmtDate(DateTime? d) => d == null
      ? 'Pick a date'
      : () {
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          return '${months[d.month - 1]} ${d.day}, ${d.year}';
        }();

  String _fmtTime(TimeOfDay t) {
    final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h12:$m $ap';
  }

  String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _startDT() => _startDate == null
      ? null
      : DateTime(_startDate!.year, _startDate!.month, _startDate!.day,
          _startTime.hour, _startTime.minute);

  DateTime? _endDT() => _endDate == null
      ? null
      : DateTime(_endDate!.year, _endDate!.month, _endDate!.day,
          _endTime.hour, _endTime.minute);

  bool get _invalid {
    final s = _startDT();
    final e = _endDT();
    return s != null && e != null && !e.isAfter(s);
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = isStart ? _startDate : _endDate;

    // The end of a trip can't precede its start; the start of one can't precede
    // today — except when it already has. A trip under way keeps a start date in
    // the past for its whole duration (the server only deletes the schedule once
    // the trip is over), and showDatePicker asserts that initialDate is not
    // before firstDate. Editing a running trip therefore crashed outright, so
    // the floor gives way to whatever the schedule already holds.
    var firstDate = isStart ? today : (_startDate ?? today);
    if (current != null && current.isBefore(firstDate)) firstDate = current;

    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (isStart ? today : (_startDate ?? today)),
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppColors.sage700, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          // Moving the start past the end leaves an impossible range the user
          // then has to fix by hand; carry the end along instead.
          if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (ctx) => _CustomTimePickerDialog(
          initial: isStart ? _startTime : _endTime),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _presetWeekend() {
    final now = DateTime.now();
    final daysUntilSat = (6 - now.weekday + 7) % 7;
    final sat = now.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
    final sun = sat.add(const Duration(days: 1));
    setState(() {
      _startDate = DateTime(sat.year, sat.month, sat.day);
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endDate = DateTime(sun.year, sun.month, sun.day);
      _endTime = const TimeOfDay(hour: 18, minute: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.card2,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monitoring will pause automatically at the start time and resume at the end time.',
            style: GoogleFonts.manrope(
                fontSize: 13, color: AppColors.ink700, height: 1.5),
          ),
          const SizedBox(height: 12),
          _DateTimeField(
            label: 'Starts',
            dateValue: _fmtDate(_startDate),
            timeValue: _fmtTime(_startTime),
            onDateTap: () => _pickDate(true),
            onTimeTap: () => _pickTime(true),
          ),
          const SizedBox(height: 12),
          _DateTimeField(
            label: 'Ends',
            dateValue: _fmtDate(_endDate),
            timeValue: _fmtTime(_endTime),
            onDateTap: () => _pickDate(false),
            onTimeTap: () => _pickTime(false),
          ),
          if (_invalid) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: Color(0xFF9C4A38)),
              const SizedBox(width: 6),
              Text('End must be after start.',
                  style: GoogleFonts.manrope(
                      fontSize: 12.5, color: const Color(0xFF9C4A38))),
            ]),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Quick fill:',
                  style:
                      GoogleFonts.manrope(fontSize: 11.5, color: AppColors.ink500)),
              const SizedBox(width: 7),
              GestureDetector(
                onTap: _presetWeekend,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.line2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('This weekend',
                      style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.line),
          const SizedBox(height: 12),
          Row(
            children: [
              AppButton(
                variant: AppButtonVariant.primary,
                buttonSize: AppButtonSize.sm,
                disabled: _startDate == null || _endDate == null || _invalid,
                onPressed: () => widget.onSave({
                  // What the user picked, and what gets rendered back to them.
                  'startDate': _dateStr(_startDate!),
                  'startTime': _timeStr(_startTime),
                  'endDate': _dateStr(_endDate!),
                  'endTime': _timeStr(_endTime),
                  // The same two moments as absolute instants. The wall-clock
                  // fields above carry no timezone, so the server was left
                  // reading them against its own clock — a trip set for 09:00
                  // began at noon for a UTC+3 family on a UTC host. Converting
                  // here is what makes it exact: the device knows the zone, and
                  // toUtc() on a local DateTime applies the offset in force on
                  // that specific date, so a trip spanning a DST change still
                  // starts and ends when the user said it would.
                  'startUtc': _startDT()!.toUtc().toIso8601String(),
                  'endUtc': _endDT()!.toUtc().toIso8601String(),
                }),
                child: const Text('Save schedule'),
              ),
              const SizedBox(width: 8),
              AppButton(
                  variant: AppButtonVariant.ghost,
                  buttonSize: AppButtonSize.sm,
                  onPressed: widget.onCancel,
                  child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Date + Time field ────────────────────────────────────────────
class _DateTimeField extends StatelessWidget {
  final String label, dateValue, timeValue;
  final VoidCallback onDateTap, onTimeTap;
  const _DateTimeField({
    required this.label,
    required this.dateValue,
    required this.timeValue,
    required this.onDateTap,
    required this.onTimeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink700,
                letterSpacing: 0.2)),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
                child: _FieldTrigger(
                    icon: Icons.calendar_today_outlined,
                    value: dateValue,
                    onTap: onDateTap)),
            const SizedBox(width: 8),
            SizedBox(
                width: 112,
                child: _FieldTrigger(
                    icon: Icons.access_time,
                    value: timeValue,
                    onTap: onTimeTap)),
          ],
        ),
      ],
    );
  }
}

// ── Field Trigger ────────────────────────────────────────────────
class _FieldTrigger extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  const _FieldTrigger(
      {required this.icon, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isPlaceholder = value.startsWith('Pick');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.card2,
          border: Border.all(color: AppColors.line2, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.ink500),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    color: isPlaceholder
                        ? AppColors.ink500
                        : AppColors.ink900),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: AppColors.ink500),
          ],
        ),
      ),
    );
  }
}

// ── Custom Time Picker Dialog ────────────────────────────────────
class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay initial;
  const _CustomTimePickerDialog({required this.initial});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  late int _hour12;
  late int _minute;
  late bool _isAm;

  @override
  void initState() {
    super.initState();
    final h = widget.initial.hour;
    _isAm = h < 12;
    _hour12 = h % 12 == 0 ? 12 : h % 12;
    // The wheel only offers multiples of 5, so an off-grid minute has to snap to
    // one. Rounding 58 up would wrap to 60, and the old `% 60` turned that into
    // :00 of the *same* hour — silently moving the time an hour earlier. Floor
    // instead: the value stays inside the hour the user chose.
    _minute = (widget.initial.minute ~/ 5) * 5;
  }

  TimeOfDay get _result {
    final h24 = (_hour12 % 12) + (_isAm ? 0 : 12);
    return TimeOfDay(hour: h24, minute: _minute);
  }

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(12, (i) => i + 1);
    final mins = List.generate(12, (i) => i * 5);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.card2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sage50,
                border: Border.all(color: AppColors.sage200),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: RichText(
                    text: TextSpan(children: [
                  TextSpan(
                    text:
                        '$_hour12:${_minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.manrope(
                        fontSize: 22,
                        color: AppColors.sage800,
                        fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '  ${_isAm ? 'AM' : 'PM'}',
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppColors.sage800,
                        fontWeight: FontWeight.w600),
                  ),
                ])),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 168,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      child: _WheelColumn(
                          items: hours,
                          selected: _hour12,
                          onSelect: (v) => setState(() => _hour12 = v))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                        child: Text(':',
                            style: GoogleFonts.manrope(
                                fontSize: 14, color: AppColors.ink500))),
                  ),
                  Expanded(
                      child: _WheelColumn(
                          items: mins,
                          selected: _minute,
                          onSelect: (v) => setState(() => _minute = v))),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 56,
                    child: Column(
                      children: ['AM', 'PM'].map((p) {
                        final active = _isAm ? p == 'AM' : p == 'PM';
                        return Expanded(
                          child: Padding(
                            padding:
                                EdgeInsets.only(bottom: p == 'AM' ? 6 : 0),
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _isAm = p == 'AM'),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppColors.sage700
                                      : AppColors.card,
                                  border:
                                      Border.all(color: AppColors.line),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(p,
                                      style: GoogleFonts.manrope(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: active
                                            ? const Color(0xFFFBF8F0)
                                            : AppColors.ink800,
                                      )),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(_result),
                child: Text('Done',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.ink600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Wheel Column ─────────────────────────────────────────────────
class _WheelColumn extends StatefulWidget {
  final List<int> items;
  final int selected;
  final ValueChanged<int> onSelect;
  const _WheelColumn(
      {required this.items,
      required this.selected,
      required this.onSelect});

  @override
  State<_WheelColumn> createState() => _WheelColumnState();
}

class _WheelColumnState extends State<_WheelColumn> {
  late final ScrollController _ctrl;
  static const double _itemH = 34.0;

  @override
  void initState() {
    super.initState();
    final idx = widget.items.indexOf(widget.selected);
    final offset =
        (idx * _itemH - (168 / 2 - _itemH / 2)).clamp(0.0, double.infinity);
    _ctrl = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSoft,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        controller: _ctrl,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: widget.items.length,
        itemExtent: _itemH,
        itemBuilder: (ctx, i) {
          final v = widget.items[i];
          final active = v == widget.selected;
          return GestureDetector(
            onTap: () => widget.onSelect(v),
            child: Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: active ? AppColors.sage700 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  v.toString().padLeft(2, '0'),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? const Color(0xFFFBF8F0)
                        : AppColors.ink800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Change Username Dialog ────────────────────────────────────────
class _UsernameDialog extends StatefulWidget {
  final String current;
  final VoidCallback onSaved;
  const _UsernameDialog({required this.current, required this.onSaved});

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late String _value;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _value = widget.current;
  }

  Future<void> _save() async {
    final val = _value.trim();
    if (val.isEmpty || val == widget.current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.changeUsername(val);
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.card2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Username',
                style: GoogleFonts.newsreader(
                    fontSize: 20,
                    color: AppColors.ink900,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            AppInput(
              label: 'New username',
              placeholder: 'Enter new username',
              value: _value,
              error: _error,
              onChanged: (v) => setState(() {
                _value = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  variant: AppButtonVariant.ghost,
                  buttonSize: AppButtonSize.sm,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                AppButton(
                  variant: AppButtonVariant.primary,
                  buttonSize: AppButtonSize.sm,
                  onPressed: _loading ? null : _save,
                  trailing: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Change Password Dialog ────────────────────────────────────────
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  String _current = '';
  String _newPw = '';
  String _confirm = '';
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_current.isEmpty || _newPw.isEmpty) {
      setState(() => _error = 'All fields are required.');
      return;
    }
    if (_newPw != _confirm) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.changePassword(_current, _newPw);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.card2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Password',
                style: GoogleFonts.newsreader(
                    fontSize: 20,
                    color: AppColors.ink900,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            AppInput(
              label: 'Current password',
              placeholder: '••••••••',
              isPassword: true,
              value: _current,
              onChanged: (v) => setState(() {
                _current = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
            AppInput(
              label: 'New password',
              placeholder: '••••••••',
              isPassword: true,
              value: _newPw,
              onChanged: (v) => setState(() {
                _newPw = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 10),
            AppInput(
              label: 'Confirm new password',
              placeholder: '••••••••',
              isPassword: true,
              value: _confirm,
              error: _error,
              onChanged: (v) => setState(() {
                _confirm = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  variant: AppButtonVariant.ghost,
                  buttonSize: AppButtonSize.sm,
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                AppButton(
                  variant: AppButtonVariant.primary,
                  buttonSize: AppButtonSize.sm,
                  onPressed: _loading ? null : _save,
                  trailing: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
