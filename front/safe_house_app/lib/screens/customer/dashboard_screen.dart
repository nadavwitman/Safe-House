import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';
import '../../services/auth_state.dart';
import '../../services/house_service.dart';
import '../../services/insights_service.dart';

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
  DateTime? _lastStatusFetch;

  // How often to poll the backend for new sensor activity. The screen lives
  // inside an IndexedStack, so this keeps ticking across tab switches but is
  // paused while the app is backgrounded.
  static const _pollInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
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
      final data = await HouseService.getRecentEvents(houseId);
      final serverVacation = data['is_vacation'] as bool? ?? false;
      if (serverVacation != AuthState.instance.vacationMode) {
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

      // Home status reflects the latest AI decision (now logged every analysis
      // cycle, including Normal), so check it once a minute rather than on every
      // 5-second poll.
      final now = DateTime.now();
      if (_lastStatusFetch == null ||
          now.difference(_lastStatusFetch!) > const Duration(minutes: 1)) {
        _lastStatusFetch = now;
        try {
          final alerts = await InsightsService.getAlerts(houseId, limit: 1);
          final s = _deriveStatus(alerts);
          if (mounted && s != _alertStatus) setState(() => _alertStatus = s);
        } catch (_) {
          // keep last-known status on a failed status poll
        }
      }
    } catch (_) {
      // silently ignore — stale data stays on screen
    } finally {
      _refreshing = false;
    }
  }

  /// Maps the most recent AI decision directly into a home-screen status. Every
  /// analysis cycle now logs a decision (including Normal), so the latest entry
  /// is a live, current signal rather than something that needs to time out.
  HouseStatus _deriveStatus(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) return HouseStatus.clear;
    final latest = alerts.first; // endpoint returns newest first
    final decision = (latest['decision'] as String? ?? '').toLowerCase();
    if (decision.contains('emergency')) return HouseStatus.emergency;
    if (decision.contains('warning')) return HouseStatus.warning;
    return HouseStatus.clear;
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
    final isVacation = auth.vacationMode;
    final status = isVacation ? HouseStatus.vacation : _alertStatus;
    final rawMask = activeHouse?['sensor_mask'] as List<dynamic>?;
    final mask = (rawMask != null && rawMask.length == 7)
        ? rawMask.map((v) => v == 1 || v == true).toList()
        : List.filled(7, true);
    final activeSensors = [
      for (int i = 0; i < _sensors.length; i++)
        if (mask[i]) (index: i, sensor: _sensors[i]),
    ];

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
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
                if (isVacation)
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
