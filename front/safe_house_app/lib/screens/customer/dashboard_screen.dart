import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/alert_ack_store.dart';
import '../../services/auth_state.dart';
import '../../services/house_service.dart';

// ── Data ───────────────────────────────────────────────────────
enum HouseStatus { clear, warning, emergency, vacation }

class SensorDef {
  final String id, name, tone;
  const SensorDef(this.id, this.name, this.tone);
}

// Order must match API sensor_mask: door=0, kitchen=1, bath=2, toilet=3, meds=4, bed=5, living=6
const _sensors = [
  SensorDef('door', 'Front Door', 'sage'),
  SensorDef('kitchen', 'Kitchen', 'warm'),
  SensorDef('bath', 'Bathroom', 'sky'),
  SensorDef('toilet', 'Toilet', 'cream'),
  SensorDef('meds', 'Medication Cabinet', 'plum'),
  SensorDef('bed', 'Bed', 'sage'),
  SensorDef('living', 'Living Room', 'cream'),
];

String _relTime(DateTime? t) {
  if (t == null) return 'No data yet';
  final diff = DateTime.now().difference(t);
  if (diff.isNegative || diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ── Dashboard Screen ───────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  // sensor index (0-6) → last time that sensor had value 1
  final Map<int, DateTime> _lastActivity = {};
  Timer? _timer;
  bool _refreshing = false;
  // Home-screen status derived from the latest AI decision (see _deriveStatus).
  HouseStatus _alertStatus = HouseStatus.clear;

  // ── Alert banner state ───────────────────────────────────────
  // `current_status_at` from the poll: the moment the house entered its current
  // status. It doubles as the alert's identity — the server rewrites it whenever a
  // *different* anomaly takes over, including one of the same severity, so a change
  // here means "a new alert is in effect" and nothing else does.
  String? _alertAt;
  // The alert's message, denormalized onto the house doc and delivered by the same
  // poll as the status. Null on a house whose current alert predates those fields,
  // which _bannerTitle/_bannerBody cover with generic per-severity text.
  String? _alertTitle;
  String? _alertNote;
  // The ai_decisions document id of the alert in effect — the same id the Alerts tab
  // acknowledges against, which is what lets the two screens agree.
  String? _alertId;
  // Whether _alertId has been acknowledged on this device. Device-local by design:
  // acknowledging hides the banner on this phone only, and never touches the house's
  // real status — the hero keeps showing (and pulsing) Warning/Emergency until the
  // AI itself recovers.
  bool _alertAcked = false;
  // Which _alertId the flag above was read for, so the store is consulted once per
  // alert rather than on every 30s poll.
  String? _ackCheckedFor;
  // Guards against a stale house's alert state bleeding into a newly selected one.
  String? _stateForHouse;

  // How often to poll the backend for new sensor activity. The screen lives
  // inside an IndexedStack, so this keeps ticking across tab switches but is
  // paused while the app is backgrounded.
  //
  // The ESP32 reports once a minute, so polling faster than that only re-reads
  // data that cannot have changed. 30s keeps the "Xm ago" labels feeling live
  // while costing one Firestore read per tick (see HouseService.getStatus).
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The Profile tab can turn vacation on or off while this screen sits alive
    // but unbuilt in the IndexedStack. Without this the hero kept its old state
    // until a poll happened to land, up to 30s later.
    AuthState.instance.vacationMode.addListener(_onVacationChanged);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthState.instance.vacationMode.removeListener(_onVacationChanged);
    _stopPolling();
    super.dispose();
  }

  void _onVacationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _refresh();
    _timer = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refresh() async {
    if (_refreshing) return; // skip overlapping polls on slow networks
    final houseId = AuthState.instance.activeHouseId;
    if (houseId == null) return;
    _refreshing = true;
    try {
      // Switching houses must not carry the previous house's alert (or the
      // acknowledgement of it) across — reset before the first poll lands.
      if (_stateForHouse != houseId) {
        _stateForHouse = houseId;
        _alertAt = null;
        _alertId = null;
        _alertTitle = null;
        _alertNote = null;
        _alertAcked = false;
        _ackCheckedFor = null;
        AuthState.instance.currentAlertId.value = null;
        // Stale until this poll returns the new house's value. Left set, the
        // Summary tab would compare the new house's cached report against the
        // previous house's timestamp and re-download for nothing.
        AuthState.instance.weeklyReportAt.value = null;
      }
      final data = await HouseService.getStatus(houseId);

      // Nothing on this screen uses it — the Summary tab does, as the cache key
      // that tells it whether its stored report is still the current one. It
      // rides along on this poll so the summary never has to poll for itself.
      AuthState.instance.weeklyReportAt.value =
          data['weekly_report_at'] as String?;

      final serverVacation = data['is_vacation'] as bool? ?? false;
      if (serverVacation != AuthState.instance.vacationMode.value) {
        await AuthState.instance.setVacationMode(serverVacation);
      }
      // last_activity is a server-maintained map {sensorIndex: isoTime} of the
      // last time each sensor fired — so a sensor's last-seen time is shown even
      // if it fired weeks ago, without scanning the full per-minute history.
      final rawActivity =
          (data['last_activity'] as Map<String, dynamic>?) ?? const {};
      final Map<int, DateTime> found = {};
      rawActivity.forEach((key, value) {
        final idx = int.tryParse(key);
        final timeStr = value as String?;
        if (idx == null || idx < 0 || idx > 6 || timeStr == null) return;
        final parsed = DateTime.tryParse(timeStr);
        if (parsed != null) found[idx] = parsed.toLocal();
      });
      if (!mounted) return;
      // Merge, never wipe: the server's last-activity map only ever grows, so a poll that
      // returns it empty or partial (a slow/incomplete response) must NOT clear a sensor's
      // last-seen time — that was causing the card to flicker to "No data yet". We only
      // add/update entries; the display stays stable and labels still age each tick.
      final changed = found.entries.any((e) => _lastActivity[e.key] != e.value);
      setState(() {
        if (changed) _lastActivity.addAll(found);
      });

      // Home status and the banner's whole content now arrive in this one payload —
      // the server keeps all of it on the house document, so drawing the banner
      // costs no extra round trip and no extra Firestore read. This used to be a
      // status field plus a follow-up query into the alert history.
      final s = _deriveStatus(data['current_status'] as String?);
      final statusAt = data['current_status_at'] as String?;
      final alertId = data['current_alert_id'] as String?;
      // The Alerts tab prunes acknowledgements against its 7-day window; this tells
      // it which id to spare, since a long-running alert is still on this banner
      // after it has aged out of that list.
      AuthState.instance.currentAlertId.value = alertId;
      if (s != _alertStatus ||
          statusAt != _alertAt ||
          alertId != _alertId) {
        setState(() {
          _alertStatus = s;
          _alertAt = statusAt;
          _alertId = alertId;
          _alertTitle = data['current_alert_title'] as String?;
          _alertNote = data['current_alert_note'] as String?;
        });
      }

      // A newly-seen alert may already have been acknowledged in the Alerts tab, so
      // the banner has to ask before it draws. Reading it here rather than per build
      // keeps SharedPreferences off the paint path.
      if (alertId != null && alertId != _ackCheckedFor) {
        _ackCheckedFor = alertId;
        final acked = await AlertAckStore.read(houseId);
        if (!mounted) return;
        setState(() => _alertAcked = acked.contains(alertId));
      }
    } catch (_) {
      // silently ignore — stale data stays on screen
    } finally {
      _refreshing = false;
    }
  }

  /// Maps the server's current AI status into a home-screen status. The server
  /// updates this on every state transition, so it is a live signal rather than
  /// something that needs to time out.
  HouseStatus _deriveStatus(String? currentStatus) {
    final decision = (currentStatus ?? '').toLowerCase();
    if (decision.contains('emergency')) return HouseStatus.emergency;
    if (decision.contains('warning')) return HouseStatus.warning;
    return HouseStatus.clear;
  }

  /// The banner's headline. The server composes a situation-specific title and
  /// sends it with the status; this generic wording only appears on a house whose
  /// current alert was recorded before that field existed, and only until the AI
  /// next writes a decision.
  String get _bannerTitle {
    final title = _alertTitle;
    if (title != null && title.isNotEmpty) return title;
    return _alertStatus == HouseStatus.emergency
        ? 'Emergency detected'
        : 'Unusual pattern detected';
  }

  String get _bannerBody {
    final note = _alertNote;
    if (note != null && note.isNotEmpty) return note;
    return _alertStatus == HouseStatus.emergency
        ? 'The system flagged something that needs attention now. Please check on '
            'things.'
        : 'The system noticed activity that falls outside the usual routine.';
  }

  /// Acknowledge — marks the alert read on this device, hiding the banner here and
  /// clearing it from Unread in the Alerts tab, which reads the same store. There is
  /// deliberately no server call: the alert stays in the Alerts tab as history, and
  /// the house's status is the AI's to change, not the reader's.
  Future<void> _acknowledge() async {
    final houseId = AuthState.instance.activeHouseId;
    final id = _alertId;
    if (houseId == null || id == null) return;
    setState(() => _alertAcked = true);
    await AlertAckStore.add(houseId, id);
    // The Alerts tab owns the badge count and may not be built yet, so decrement
    // here rather than waiting for it to notice. It recomputes from scratch on its
    // next load, which corrects any drift.
    final unread = AuthState.instance.unreadAlerts;
    if (unread.value > 0) unread.value -= 1;
  }

  Future<void> _callContact(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    final ok = await launchUrl(uri).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start a call to $phone')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final auth = AuthState.instance;
    final activeId = auth.activeHouseId;
    final houses = auth.currentUser?.houses ?? [];
    final activeHouse = houses.isEmpty
        ? null
        : houses.firstWhere(
            (h) => h['house_id'] == activeId,
            orElse: () => houses.first,
          );
    final residentName =
        activeHouse?['resident_name'] as String? ?? 'your house';
    final isVacation = auth.vacationMode.value;
    final status = isVacation ? HouseStatus.vacation : _alertStatus;
    final rawMask = activeHouse?['sensor_mask'] as List<dynamic>?;
    final mask = (rawMask != null && rawMask.length == 7)
        ? rawMask.map((v) => v == 1 || v == true).toList()
        : List.filled(7, true);
    final activeSensors = [
      for (int i = 0; i < _sensors.length; i++)
        if (mask[i]) (index: i, sensor: _sensors[i]),
    ];
    // Vacation silences alerts, so the banner follows the hero and stays hidden.
    // Acknowledging hides only this alert — a different anomaly taking over gets a
    // new id, so it reappears without the user having to un-acknowledge anything.
    //
    // Note this no longer waits on a fetched message: the text arrives with the
    // status, and a house with no stored message still draws the banner using the
    // generic wording. A Warning the family can't see is worse than one described
    // in plain terms.
    final showBanner = !isVacation &&
        (_alertStatus == HouseStatus.warning ||
            _alertStatus == HouseStatus.emergency) &&
        _alertAt != null &&
        !_alertAcked;
    final phone =
        (activeHouse?['emergency_contact_phone'] as String?)?.trim() ?? '';

    return Scaffold(
      backgroundColor: AppColors.bgCream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: Row(
                  children: [
                    const Wordmark(size: 'sm'),
                    const Spacer(),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        border: Border.all(color: AppColors.line),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          size: 18, color: AppColors.ink700),
                    ),
                  ],
                ),
              ),

              // House name
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WATCHING OVER',
                        style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppColors.ink500,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8)),
                    const SizedBox(height: 2),
                    Text("$residentName's House",
                        style: GoogleFonts.newsreader(
                            fontSize: 24,
                            color: AppColors.ink900,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _StatusHero(status: status, residentName: residentName),
                    if (showBanner) ...[
                      const SizedBox(height: 14),
                      _AlertBanner(
                        emergency: _alertStatus == HouseStatus.emergency,
                        title: _bannerTitle,
                        note: _bannerBody,
                        at: _alertAt,
                        onCall: phone.isEmpty ? null : () => _callContact(phone),
                        onAcknowledge: _acknowledge,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Sensors',
                            style: GoogleFonts.newsreader(
                                fontSize: 18,
                                color: AppColors.ink900,
                                fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text('${activeSensors.length} monitored',
                            style: GoogleFonts.manrope(
                                fontSize: 12, color: AppColors.ink500)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (int i = 0; i < activeSensors.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: 10),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                                child: _SensorCard(
                                    sensor: activeSensors[i].sensor,
                                    paused: isVacation,
                                    lastActivity: _lastActivity[activeSensors[i].index])),
                            const SizedBox(width: 10),
                            Expanded(
                              child: i + 1 < activeSensors.length
                                  ? _SensorCard(
                                      sensor: activeSensors[i + 1].sensor,
                                      paused: isVacation,
                                      lastActivity: _lastActivity[activeSensors[i + 1].index])
                                  : const SizedBox(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status Hero ────────────────────────────────────────────────
class _StatusHero extends StatefulWidget {
  final HouseStatus status;
  final String residentName;
  const _StatusHero({required this.status, required this.residentName});

  @override
  State<_StatusHero> createState() => _StatusHeroState();
}

class _StatusHeroState extends State<_StatusHero>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    // The outer ring expands past the card while fading out, so the alert reads as
    // a radiating pulse. Opacity finishes at 80% of the cycle, letting the ring
    // vanish before it reaches full size instead of popping out of existence.
    _scaleAnim = Tween<double>(begin: 1.0, end: 2.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.35, end: 0.0).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0.0, 0.8, curve: Curves.linear)),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_StatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncAnimation();
  }

  /// Only Warning/Emergency pulse. Stopping (rather than leaving it running behind
  /// an invisible ring) keeps a calm house off the vsync path entirely.
  void _syncAnimation() {
    final pulse = widget.status == HouseStatus.warning ||
        widget.status == HouseStatus.emergency;
    if (pulse) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVacation = widget.status == HouseStatus.vacation;
    final isAlerting = widget.status == HouseStatus.warning ||
        widget.status == HouseStatus.emergency;
    final (
      String label,
      Color accentColor,
      Color accentSoft,
      String body,
      IconData icon
    ) = switch (widget.status) {
      HouseStatus.emergency => (
          'Emergency',
          AppColors.alert,
          AppColors.alertSoft,
          'Unusual activity that may need immediate attention. Please check in now.',
          Icons.warning_amber_rounded,
        ),
      HouseStatus.warning => (
          'Heads Up',
          AppColors.warn,
          AppColors.warnSoft,
          'A small anomaly was detected. Nothing urgent — check the alert below.',
          Icons.notifications_active_outlined,
        ),
      HouseStatus.vacation => (
          'Vacation Mode',
          const Color(0xFF3F6868),
          const Color(0xFFE1ECEC),
          'Sensors are still recording, but alerts are off while ${widget.residentName} is away.',
          Icons.luggage_outlined,
        ),
      HouseStatus.clear => (
          'All Clear',
          AppColors.sage600,
          AppColors.sage100,
          'Monitoring is active. Alerts will be sent if anything unusual is detected.',
          Icons.home_outlined,
        ),
    };

    return AppCard(
      padding: const EdgeInsets.all(18),
      clip: true,
      child: Column(
        children: [
          Row(
            children: [
              Text('STATUS',
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink500,
                      letterSpacing: 1.0)),
              const Spacer(),
              AppTag(
                label: isVacation ? 'Live · alerts off' : 'Live',
                tone: isVacation
                    ? 'neutral'
                    : widget.status == HouseStatus.emergency
                        ? 'alert'
                        : widget.status == HouseStatus.warning
                            ? 'warn'
                            : 'sage',
                icon: StatusDot(
                  tone: widget.status == HouseStatus.emergency
                      ? 'alert'
                      : widget.status == HouseStatus.warning
                          ? 'warn'
                          : 'ok',
                  pulse: isAlerting,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 138,
            height: 138,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 138,
                  height: 138,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [accentSoft, accentSoft.withValues(alpha: 0)],
                      stops: const [0.0, 0.65],
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                // Outer ring — pulses for warning/emergency, dashed for vacation,
                // static otherwise.
                if (isAlerting)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, _) => Transform.scale(
                      scale: _scaleAnim.value,
                      child: Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                accentColor.withValues(alpha: _opacityAnim.value),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (isVacation)
                  CustomPaint(
                    size: const Size(118, 118),
                    painter: _DashedCirclePainter(
                        color: accentColor.withValues(alpha: 0.6),
                        strokeWidth: 1.5),
                  )
                else
                  Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: accentColor.withValues(alpha: 0.6),
                          width: 1.5),
                    ),
                  ),
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 1.0),
                  ),
                ),
                Container(
                  width: 63,
                  height: 63,
                  decoration: BoxDecoration(
                    color: AppColors.card2,
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color:
                              const Color(0xFF505A4B).withValues(alpha: 0.10),
                          blurRadius: 14,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Icon(icon, size: 30, color: accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Status:',
              style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.ink500)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.newsreader(
                  fontSize: 30,
                  color: accentColor,
                  fontWeight: FontWeight.w500,
                  height: 1.1)),
          const SizedBox(height: 8),
          Text(body,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 13.5, color: AppColors.ink600, height: 1.5)),
        ],
      ),
    );
  }
}

// ── Dashed Circle Painter ──────────────────────────────────────
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _DashedCirclePainter(
      {required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const dashCount = 20;
    final gapAngle = (math.pi / dashCount) * 0.6;
    final stepAngle = (2 * math.pi) / dashCount;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * stepAngle - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        stepAngle - gapAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      color != old.color || strokeWidth != old.strokeWidth;
}

// ── Alert Banner ───────────────────────────────────────────────
/// The alert in effect, shown directly under the status hero.
///
/// It carries the server-composed message verbatim — the same `title` and `note`
/// the Alerts tab renders — so there is nothing further to drill into and no
/// "View details" affordance. Only two actions are offered: reach the emergency
/// contact, and dismiss.
class _AlertBanner extends StatelessWidget {
  final bool emergency;
  final String? title;
  final String? note;
  final String? at;
  // Null when the house has no emergency contact on file — that alone hides the
  // Call button, so the number itself never needs to reach this widget.
  final VoidCallback? onCall;
  final VoidCallback onAcknowledge;

  const _AlertBanner({
    required this.emergency,
    required this.title,
    required this.note,
    required this.at,
    required this.onCall,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final bg = emergency ? AppColors.alertSoft : AppColors.warnSoft;
    final bd = emergency ? const Color(0xFFE6BFB1) : const Color(0xFFEAD7A4);
    final fg = emergency ? const Color(0xFF7A3727) : const Color(0xFF7A5419);
    final dotBg = emergency ? const Color(0xFFE89B86) : const Color(0xFFD9B36C);
    final timeFg =
        emergency ? const Color(0xFF9C5840) : const Color(0xFF9C7A2F);

    final parsedAt = DateTime.tryParse(at ?? '')?.toLocal();
    final heading = (title != null && title!.isNotEmpty)
        ? title!
        : (emergency ? 'Emergency' : 'Heads Up');
    final body = (note != null && note!.isNotEmpty)
        ? note!
        : (emergency
            ? 'Unusual activity that may need immediate attention.'
            : 'A small anomaly was detected.');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: bd),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle),
            child: Icon(
                emergency
                    ? Icons.warning_amber_rounded
                    : Icons.notifications_none,
                size: 20,
                color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(heading,
                          style: GoogleFonts.manrope(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: fg,
                              height: 1.3)),
                    ),
                    const SizedBox(width: 8),
                    // Blank rather than _relTime's "No data yet" fallback — an
                    // unparseable stamp should drop the time, not caption a live
                    // alert as having no data.
                    if (parsedAt != null)
                      Text(_relTime(parsedAt),
                          style: GoogleFonts.manrope(
                              fontSize: 12, color: timeFg)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body,
                    style: GoogleFonts.manrope(
                        fontSize: 13.5, color: fg, height: 1.5)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Offered on warnings too, not just emergencies: the warning
                    // copy itself ends with "worth checking in" / "worth making
                    // sure they're okay", and calling is how the reader does that.
                    //
                    // The severity distinction moves to the button's weight rather
                    // than its presence — solid red demands action now, outlined
                    // offers it. Labelled for who is actually dialled: the contact
                    // the installer registered, not the resident's own line.
                    if (onCall != null)
                      AppButton(
                        variant: emergency
                            ? AppButtonVariant.danger
                            : AppButtonVariant.outline,
                        buttonSize: AppButtonSize.sm,
                        leading: const Icon(Icons.phone, size: 16),
                        onPressed: onCall,
                        child: const Text('Call emergency contact'),
                      ),
                    AppButton(
                      variant: AppButtonVariant.ghost,
                      buttonSize: AppButtonSize.sm,
                      onPressed: onAcknowledge,
                      child: const Text('Acknowledge'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sensor Card ────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final SensorDef sensor;
  final bool paused;
  final DateTime? lastActivity;
  const _SensorCard({
    required this.sensor,
    required this.paused,
    this.lastActivity,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF3C4837).withValues(alpha: 0.04),
                  blurRadius: 2,
                  offset: const Offset(0, 1))
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconWell(
                      tone: paused ? 'cream' : sensor.tone,
                      size: 36,
                      child: _sensorIcon(sensor.id)),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sensor.name,
                            style: GoogleFonts.manrope(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink900,
                                height: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          paused ? 'Paused' : 'Active',
                          style: GoogleFonts.manrope(
                              fontSize: 11.5, color: AppColors.ink500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                paused
                    ? (lastActivity != null
                        ? 'Last seen ${_relTime(lastActivity)}'
                        : 'No data yet')
                    : _relTime(lastActivity),
                style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: paused
                        ? AppColors.ink400
                        : AppColors.ink700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: StatusDot(tone: paused ? 'off' : 'ok', size: 8),
        ),
      ],
    );
  }
}

Widget _sensorIcon(String id) {
  return switch (id) {
    'door' => const Icon(Icons.door_front_door_outlined),
    'kitchen' => const Icon(Icons.kitchen_outlined),
    'bath' => const Icon(Icons.bathtub_outlined),
    'toilet' => const Icon(Icons.water_drop_outlined),
    'meds' => const Icon(Icons.medication_outlined),
    'bed' => const Icon(Icons.bed_outlined),
    'living' => const Icon(Icons.weekend_outlined),
    _ => const Icon(Icons.sensors_outlined),
  };
}
