import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';

// ── Data ───────────────────────────────────────────────────────
enum HouseStatus { clear, warning, emergency, vacation }

class SensorDef {
  final String id, name, tone;
  const SensorDef(this.id, this.name, this.tone);
}

class SensorReading {
  final String ts, state, tone;
  const SensorReading(this.ts, this.state, this.tone);
}

const _sensors = [
  SensorDef('door',    'Front Door',         'sage'),
  SensorDef('kitchen', 'Kitchen',            'warm'),
  SensorDef('bath',    'Bathroom',           'sky'),
  SensorDef('toilet',  'Toilet',             'cream'),
  SensorDef('meds',    'Medication Cabinet', 'plum'),
  SensorDef('bed',     'Bed',                'sage'),
  SensorDef('living',  'Living Room',        'cream'),
];

const _readings = {
  HouseStatus.clear: {
    'door':    SensorReading('Today 09:42', 'Active', 'ok'),
    'kitchen': SensorReading('Today 08:15', 'Active', 'ok'),
    'bath':    SensorReading('Today 07:48', 'Recent activity', 'ok'),
    'toilet':  SensorReading('Today 10:02', 'Active', 'ok'),
    'meds':    SensorReading('Today 08:30', 'Opened on time', 'ok'),
    'bed':     SensorReading('Today 07:12', 'Unoccupied', 'off'),
    'living':  SensorReading('Today 10:15', 'Active', 'ok'),
  },
  HouseStatus.warning: {
    'door':    SensorReading('Today 14:32', 'Active', 'ok'),
    'kitchen': SensorReading('7h ago', 'No recent activity', 'warn'),
    'bath':    SensorReading('Today 07:48', 'Recent activity', 'ok'),
    'toilet':  SensorReading('Today 13:12', 'Active', 'ok'),
    'meds':    SensorReading('Yesterday 21:00', 'Missed evening dose', 'warn'),
    'bed':     SensorReading('Today 06:40', 'Unoccupied', 'off'),
    'living':  SensorReading('Today 14:18', 'Active', 'ok'),
  },
  HouseStatus.vacation: {
    'door':    SensorReading('Today 09:42', 'Active', 'ok'),
    'kitchen': SensorReading('Today 08:15', 'Active', 'ok'),
    'bath':    SensorReading('Today 07:48', 'Recent activity', 'ok'),
    'toilet':  SensorReading('Today 10:02', 'Active', 'ok'),
    'meds':    SensorReading('Today 08:30', 'Opened on time', 'ok'),
    'bed':     SensorReading('Today 07:12', 'Unoccupied', 'off'),
    'living':  SensorReading('Today 10:15', 'Active', 'ok'),
  },
  HouseStatus.emergency: {
    'door':    SensorReading('2h ago', 'Opened, no return', 'alert'),
    'kitchen': SensorReading('Today 06:50', 'Active', 'ok'),
    'bath':    SensorReading('Today 07:48', 'Recent activity', 'ok'),
    'toilet':  SensorReading('Today 06:55', 'Active', 'ok'),
    'meds':    SensorReading('Today 08:30', 'Opened on time', 'ok'),
    'bed':     SensorReading('Today 06:20', 'Unoccupied', 'off'),
    'living':  SensorReading('Today 07:15', 'No recent activity', 'warn'),
  },
};

// ── Dashboard Screen ───────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  HouseStatus _status = HouseStatus.clear;

  @override
  Widget build(BuildContext context) {
    final readings = _readings[_status];
    final showAlert = _status == HouseStatus.warning || _status == HouseStatus.emergency;
    final alertCount = showAlert ? 1 : 0;

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
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(color: AppColors.line),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.notifications_outlined, size: 18, color: AppColors.ink700),
                        ),
                        if (alertCount > 0)
                          Positioned(
                            top: -2, right: -2,
                            child: Container(
                              width: 16, height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.alert, shape: BoxShape.circle,
                                border: Border.all(color: AppColors.bgCream, width: 2),
                              ),
                              alignment: Alignment.center,
                            child: Text('$alertCount', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, height: 1.0)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // House name + status switcher (demo)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WATCHING OVER', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text("Eleanor's House", style: GoogleFonts.newsreader(fontSize: 24, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    _StatusSwitcher(current: _status, onChanged: (s) => setState(() => _status = s)),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _StatusHero(status: _status),
                    if (showAlert) ...[
                      const SizedBox(height: 14),
                      _AlertBanner(status: _status),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Sensors', style: GoogleFonts.newsreader(fontSize: 18, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text('${_sensors.length} active', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (int i = 0; i < _sensors.length; i += 2) ...[
                      if (i > 0) const SizedBox(height: 10),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _SensorCard(sensor: _sensors[i], reading: readings?[_sensors[i].id])),
                            const SizedBox(width: 10),
                            Expanded(
                              child: i + 1 < _sensors.length
                                  ? _SensorCard(sensor: _sensors[i + 1], reading: readings?[_sensors[i + 1].id])
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

// ── Status Switcher (demo only) ────────────────────────────────
class _StatusSwitcher extends StatelessWidget {
  final HouseStatus current;
  final ValueChanged<HouseStatus> onChanged;
  const _StatusSwitcher({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HouseStatus>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.line)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Switch', style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink700)),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 14, color: AppColors.ink700),
          ],
        ),
      ),
      itemBuilder: (_) => [
        for (final s in HouseStatus.values)
          PopupMenuItem(value: s, child: Text(s.name.capitalize(), style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink800))),
      ],
    );
  }
}

extension _Cap on String {
  String capitalize() => isEmpty ? this : this[0].toUpperCase() + substring(1);
}

// ── Status Hero ────────────────────────────────────────────────
class _StatusHero extends StatefulWidget {
  final HouseStatus status;
  const _StatusHero({required this.status});

  @override
  State<_StatusHero> createState() => _StatusHeroState();
}

class _StatusHeroState extends State<_StatusHero> with SingleTickerProviderStateMixin {
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
    _scaleAnim = Tween<double>(begin: 1.0, end: 2.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _opacityAnim = Tween<double>(begin: 0.35, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.linear)),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_StatusHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncAnimation();
  }

  void _syncAnimation() {
    final pulse = widget.status == HouseStatus.warning || widget.status == HouseStatus.emergency;
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
    final status = widget.status;
    final (label, accentColor, accentSoft, body, icon) = switch (status) {
      HouseStatus.clear     => ('All Clear',    AppColors.sage600,          AppColors.sage100,          'Everything looks normal. Eleanor is following her usual routine.',          Icons.home_outlined),
      HouseStatus.warning   => ('Heads Up',     AppColors.warn,             AppColors.warnSoft,         'A small anomaly was detected. Nothing urgent — check the alert below.',     Icons.notifications_none),
      HouseStatus.emergency => ('Emergency',    AppColors.alert,            AppColors.alertSoft,        'Unusual activity that may need immediate attention. Please check in now.',  Icons.warning_amber_rounded),
      HouseStatus.vacation  => ('Vacation Mode',const Color(0xFF3F6868),    const Color(0xFFE1ECEC),    'Sensors are still recording, but alerts are off while Eleanor is away.',    Icons.luggage_outlined),
    };
    final doPulse = status == HouseStatus.warning || status == HouseStatus.emergency;
    final isVacation = status == HouseStatus.vacation;

    return AppCard(
      padding: const EdgeInsets.all(18),
      clip: true,
      child: Column(
        children: [
          Row(
            children: [
              Text('STATUS', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 1.0)),
              const Spacer(),
              AppTag(
                label: isVacation ? 'Live · alerts off' : 'Live',
                tone: status == HouseStatus.warning ? 'warn' : status == HouseStatus.emergency ? 'alert' : isVacation ? 'neutral' : 'sage',
                icon: StatusDot(
                  tone: isVacation ? 'ok' : status == HouseStatus.emergency ? 'alert' : status == HouseStatus.warning ? 'warn' : 'ok',
                  pulse: doPulse,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 138, height: 138,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Radial gradient — fade to zero-alpha of accentSoft (not Colors.transparent)
                // so Flutter interpolates within the same hue instead of drifting to gray.
                Container(
                  width: 138, height: 138,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [accentSoft, accentSoft.withValues(alpha: 0)],
                      stops: const [0.0, 0.65],
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                // Outer ring — pulses for warning/emergency, dashed for vacation, static otherwise
                if (doPulse)
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, _) => Transform.scale(
                      scale: _scaleAnim.value,
                      child: Container(
                        width: 118, height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: _opacityAnim.value),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (isVacation)
                  CustomPaint(
                    size: const Size(118, 118),
                    painter: _DashedCirclePainter(color: accentColor.withValues(alpha: 0.6), strokeWidth: 1.5),
                  )
                else
                  Container(
                    width: 118, height: 118,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
                    ),
                  ),
                // Inner static ring
                Container(
                  width: 94, height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.0),
                  ),
                ),
                // Center icon circle
                Container(
                  width: 63, height: 63,
                  decoration: BoxDecoration(
                    color: AppColors.card2,
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor, width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF505A4B).withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Icon(icon, size: 30, color: accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Status:', style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink500)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.newsreader(fontSize: 30, color: accentColor, fontWeight: FontWeight.w500, height: 1.1)),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600, height: 1.5)),
        ],
      ),
    );
  }
}

// ── Dashed Circle Painter ──────────────────────────────────────
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _DashedCirclePainter({required this.color, required this.strokeWidth});

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
    final dashAngle = math.pi / dashCount;
    final gapAngle = dashAngle * 0.6;
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
  bool shouldRepaint(_DashedCirclePainter old) => color != old.color || strokeWidth != old.strokeWidth;
}

// ── Alert Banner ───────────────────────────────────────────────
class _AlertBanner extends StatelessWidget {
  final HouseStatus status;
  const _AlertBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final isEmergency = status == HouseStatus.emergency;
    final bg = isEmergency ? AppColors.alertSoft : AppColors.warnSoft;
    final bd = isEmergency ? const Color(0xFFE6BFB1) : const Color(0xFFEAD7A4);
    final fg = isEmergency ? const Color(0xFF7A3727) : const Color(0xFF7A5419);
    final dotBg = isEmergency ? const Color(0xFFE89B86) : const Color(0xFFD9B36C);
    final sensor = isEmergency ? 'Front Door' : 'Medication Cabinet';
    final msg = isEmergency
        ? 'Door opened at 02:14 AM and no return detected for 2 hours. This is outside Eleanor\'s usual pattern.'
        : 'Evening medication dose hasn\'t been taken yet. Usual time: 9:00 PM.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, border: Border.all(color: bd), borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle),
            child: Icon(isEmergency ? Icons.warning_amber_rounded : Icons.notifications_none, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${isEmergency ? 'Emergency' : 'Warning'} · $sensor',
                        style: GoogleFonts.manrope(fontSize: 14.5, fontWeight: FontWeight.w700, color: fg)),
                    const SizedBox(width: 8),
                    Text('just now',
                        style: GoogleFonts.manrope(fontSize: 12, color: isEmergency ? const Color(0xFF9C5840) : const Color(0xFF9C7A2F))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(msg, style: GoogleFonts.manrope(fontSize: 13.5, color: fg, height: 1.5)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    if (isEmergency)
                      AppButton(variant: AppButtonVariant.danger, buttonSize: AppButtonSize.sm,
                          leading: const Icon(Icons.phone, size: 16), child: const Text('Call Eleanor')),
                    AppButton(variant: isEmergency ? AppButtonVariant.outline : AppButtonVariant.soft,
                        buttonSize: AppButtonSize.sm, child: const Text('View details')),
                    AppButton(variant: AppButtonVariant.ghost, buttonSize: AppButtonSize.sm, child: const Text('Acknowledge')),
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
  final SensorReading? reading;
  const _SensorCard({required this.sensor, this.reading});

  @override
  Widget build(BuildContext context) {
    final empty = reading == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: const Color(0xFF3C4837).withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
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
                  IconWell(tone: sensor.tone, size: 36, child: _sensorIcon(sensor.id)),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sensor.name,
                            style: GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink900, height: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          empty ? 'No data yet' : reading!.ts,
                          style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.ink500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              empty
                  ? Row(
                      children: [
                        Container(width: 14, height: 1.5, decoration: BoxDecoration(color: AppColors.ink300, borderRadius: BorderRadius.circular(1))),
                        const SizedBox(width: 6),
                        Text('Waiting for first reading', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink400)),
                      ],
                    )
                  : Text(
                      reading!.state,
                      style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ink700),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
            ],
          ),
        ),
        if (!empty)
          Positioned(
            top: 12, right: 12,
            child: StatusDot(tone: reading!.tone, size: 8),
          ),
      ],
    );
  }
}

// ── Sensor icon helper ─────────────────────────────────────────
Widget _sensorIcon(String id) {
  return switch (id) {
    'door'    => const Icon(Icons.door_front_door_outlined),
    'kitchen' => const Icon(Icons.kitchen_outlined),
    'bath'    => const Icon(Icons.bathtub_outlined),
    'toilet'  => const Icon(Icons.water_drop_outlined),
    'meds'    => const Icon(Icons.medication_outlined),
    'bed'     => const Icon(Icons.bed_outlined),
    'living'  => const Icon(Icons.weekend_outlined),
    _         => const Icon(Icons.sensors_outlined),
  };
}
