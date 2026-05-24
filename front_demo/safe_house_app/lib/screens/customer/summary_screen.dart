import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../theme/colors.dart';
import '../../widgets/shared_widgets.dart';

// ── Mock Data ──────────────────────────────────────────────────
const _sleepData = [
  (day: 'Mon', hours: 7.2, interruptions: 1),
  (day: 'Tue', hours: 6.4, interruptions: 3),
  (day: 'Wed', hours: 7.6, interruptions: 0),
  (day: 'Thu', hours: 5.8, interruptions: 4),
  (day: 'Fri', hours: 6.9, interruptions: 2),
  (day: 'Sat', hours: 7.1, interruptions: 1),
  (day: 'Sun', hours: 7.4, interruptions: 1),
];

const _activityData = [
  (day: 'Mon', transitions: 22, kitchen: 6, outside: 45),
  (day: 'Tue', transitions: 18, kitchen: 4, outside: 20),
  (day: 'Wed', transitions: 24, kitchen: 7, outside: 60),
  (day: 'Thu', transitions: 16, kitchen: 3, outside: 0),
  (day: 'Fri', transitions: 20, kitchen: 5, outside: 35),
  (day: 'Sat', transitions: 26, kitchen: 8, outside: 75),
  (day: 'Sun', transitions: 23, kitchen: 6, outside: 50),
];

const _metrics = [
  (title: 'Sleep',       icon: Icons.nightlight_round,   tone: 'sage',  value: '6h 54m', sub: 'avg, 1.7 interruptions/night', deltaV: '−0.4h', dir: 'down', state: 'warn'),
  (title: 'Mobility',    icon: Icons.arrow_forward,       tone: 'sage',  value: '21.3',   sub: 'transitions / day',             deltaV: '+1.2',  dir: 'up',   state: 'ok'),
  (title: 'Nutrition',   icon: Icons.kitchen_outlined,    tone: 'warm',  value: '5.6',    sub: 'kitchen triggers / day',        deltaV: '−1.1',  dir: 'down', state: 'warn'),
  (title: 'Hygiene',     icon: Icons.bathtub_outlined,    tone: 'sky',   value: '14 min', sub: 'bath/toilet/prep · daily',      deltaV: '+2 min',dir: 'up',   state: 'ok'),
  (title: 'Medications', icon: Icons.medication_outlined, tone: 'plum',  value: '1.9',    sub: 'sessions / day',                deltaV: '−0.1',  dir: 'down', state: 'ok'),
  (title: 'Outside',     icon: Icons.luggage_outlined,    tone: 'cream', value: '40 min', sub: 'outside time / day',            deltaV: '−12 min',dir:'down', state: 'alert'),
];

const _insights = [
  (title: 'Sleep',       body: 'Eleanor slept slightly less than usual this week (−0.4h), with two restless nights on Tuesday and Thursday.'),
  (title: 'Mobility',    body: 'Movement around the home stayed strong — 21 transitions/day, a touch above her baseline.'),
  (title: 'Nutrition',   body: 'Kitchen activity dropped on Thursday and Friday, which may reflect lighter meals or skipped snacks.'),
  (title: 'Cognitive',   body: 'Routines stayed consistent. Wake and bedtime varied by less than 25 minutes from her usual.'),
  (title: 'Medications', body: 'All morning doses were taken. One evening dose was skipped on Thursday.'),
  (title: 'Social',      body: 'Outside time fell by 12 minutes/day. Consider a short walk or visit this weekend.'),
];

const _recommendations = [
  'Plan a check-in call Thursday evening — her sleep dipped both nights this week.',
  'Encourage a short walk Saturday morning to gently bring outside time back to baseline.',
  'Ask her pharmacist about pairing the evening dose with another nightly habit.',
];

// ── Summary Screen ─────────────────────────────────────────────
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> with SingleTickerProviderStateMixin {
  bool _loading = false;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.bgCream,
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LAST 7 DAYS', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500, letterSpacing: 0.8)),
                          const SizedBox(height: 2),
                          Text('Weekly Summary', style: GoogleFonts.newsreader(fontSize: 26, color: AppColors.ink900, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const Spacer(),
                      AppButton(
                        variant: AppButtonVariant.primary,
                        buttonSize: AppButtonSize.sm,
                        leading: const Icon(Icons.refresh, size: 14),
                        onPressed: _loading ? null : _onRefresh,
                        child: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    child: Column(
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.45),
                          itemCount: 4,
                          itemBuilder: (_, i) => _MetricCard(metric: _metrics[i]),
                        ),
                        const SizedBox(height: 12),
                        _ChartCard(
                          title: 'Sleep',
                          subtitle: 'Hours slept + overnight interruptions',
                          legend: [
                            (color: AppColors.sage800, label: 'Hours'),
                            (color: AppColors.warn, label: 'Interruptions'),
                          ],
                          child: SizedBox(height: 170, child: CustomPaint(
                            painter: _SleepChartPainter(),
                            size: const Size(double.infinity, 170),
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ChartCard(
                          title: 'Activity',
                          subtitle: 'Transitions, kitchen events, outside minutes',
                          legend: [
                            (color: AppColors.sage700, label: 'Transitions'),
                            (color: AppColors.warn, label: 'Kitchen'),
                            (color: const Color(0xFF704863), label: 'Outside (min)'),
                          ],
                          child: SizedBox(height: 170, child: CustomPaint(
                            painter: _ActivityChartPainter(),
                            size: const Size(double.infinity, 170),
                          )),
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.45),
                          itemCount: 2,
                          itemBuilder: (_, i) => _MetricCard(metric: _metrics[i + 4]),
                        ),
                        const SizedBox(height: 12),
                        _AIInsightsBlock(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_loading) _GeneratingOverlay(spinController: _spinController),
      ],
    );
  }
}

// ── Generating Overlay ─────────────────────────────────────────
class _GeneratingOverlay extends StatelessWidget {
  final AnimationController spinController;
  const _GeneratingOverlay({required this.spinController});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        color: const Color(0xDCF2EDDF),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72, height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    RotationTransition(
                      turns: spinController,
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.sage200, width: 3),
                        ),
                        // top arc drawn via CustomPaint
                        child: CustomPaint(painter: _SpinnerArcPainter()),
                      ),
                    ),
                    const Icon(Icons.auto_awesome, size: 28, color: AppColors.sage800),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Generating your report',
                  style: GoogleFonts.newsreader(fontSize: 22, color: AppColors.ink900, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Text(
                'This may take a moment. We\'re reviewing the last 7 days of activity and writing a fresh summary.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink600, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinnerArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.sage700
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(0, 0, size.width, size.height),
      -math.pi / 2,
      math.pi * 0.6,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Metric Card ────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final ({String title, IconData icon, String tone, String value, String sub, String deltaV, String dir, String state}) metric;
  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (metric.state) {
      'warn'  => (AppColors.warnSoft, const Color(0xFF7A5419), const Color(0xFFEAD7A4)),
      'alert' => (AppColors.alertSoft, const Color(0xFF7E3A28), const Color(0xFFE8C2B5)),
      _       => (AppColors.sage100, AppColors.sage800, AppColors.sage200),
    };
    final arrowIcon = metric.dir == 'up' ? Icons.arrow_upward : metric.dir == 'down' ? Icons.arrow_downward : Icons.remove;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(tone: metric.tone, size: 30, child: Icon(metric.icon)),
              const SizedBox(width: 8),
              Expanded(child: Text(metric.title,
                  style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.6),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(metric.value,
                    style: GoogleFonts.newsreader(fontSize: 22, color: AppColors.ink900, fontWeight: FontWeight.w500, height: 1.05)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: bg, border: Border.all(color: bd), borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(arrowIcon, size: 10, color: fg),
                    const SizedBox(width: 3),
                    Text(metric.deltaV, style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(metric.sub, style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.ink600, height: 1.4), maxLines: 2),
        ],
      ),
    );
  }
}

// ── Chart Card ─────────────────────────────────────────────────
class _ChartCard extends StatelessWidget {
  final String title, subtitle;
  final List<({Color color, String label})> legend;
  final Widget child;
  const _ChartCard({required this.title, required this.subtitle, required this.legend, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.newsreader(fontSize: 18, color: AppColors.ink900, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: AppColors.ink500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 6,
            children: legend.map((l) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(2.5))),
                const SizedBox(width: 5),
                Text(l.label, style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.ink700)),
              ],
            )).toList(),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (_, constraints) => child),
        ],
      ),
    );
  }
}

// ── Sleep Chart Painter ────────────────────────────────────────
class _SleepChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const padL = 32.0, padR = 12.0, padT = 10.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    const maxHrs = 10.0, maxInt = 5.0;
    final innerInset = w * 0.04;
    final stepX = (w - innerInset * 2) / (_sleepData.length - 1);

    double xAt(int i) => padL + innerInset + i * stepX;
    double yAt(double v) => padT + h - (v / maxHrs) * h;

    // Grid lines
    final gridPaint = Paint()..color = AppColors.line..strokeWidth = 1;
    for (final v in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]) {
      final y = yAt(v);
      final dashPath = Path()..moveTo(padL, y);
      double x = padL;
      while (x < padL + w) {
        dashPath.lineTo(x + 2, y);
        x += 6;
        dashPath.moveTo(x, y);
      }
      canvas.drawPath(dashPath, gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '${v.toInt()}h', style: const TextStyle(fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    // Interruption bars
    final barW = stepX * 0.38;
    final barMaxH = h * 0.78;
    final barPaint = Paint()..color = AppColors.warn;
    for (int i = 0; i < _sleepData.length; i++) {
      final d = _sleepData[i];
      final bh = d.interruptions == 0 ? 4.0 : math.max(8.0, (d.interruptions / maxInt) * barMaxH);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(xAt(i) - barW / 2, padT + h - bh, barW, bh),
        const Radius.circular(3),
      );
      barPaint.color = AppColors.warn.withValues(alpha: d.interruptions == 0 ? 0.18 : 0.7);
      canvas.drawRRect(rect, barPaint);
    }

    // Area fill
    final pts = List.generate(_sleepData.length, (i) => Offset(xAt(i), yAt(_sleepData[i].hours)));
    final areaPath = Path()..moveTo(pts.first.dx, padT + h);
    for (final p in pts) { areaPath.lineTo(p.dx, p.dy); }
    areaPath.lineTo(pts.last.dx, padT + h);
    areaPath.close();
    canvas.drawPath(areaPath, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [AppColors.sage600.withValues(alpha: 0.25), AppColors.sage600.withValues(alpha: 0.0)],
    ).createShader(Rect.fromLTWH(0, padT, size.width, h)));

    // Line
    final linePaint = Paint()..color = AppColors.sage800..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) { linePath.lineTo(pts[i].dx, pts[i].dy); }
    canvas.drawPath(linePath, linePaint);

    // Dots + x labels
    for (int i = 0; i < _sleepData.length; i++) {
      canvas.drawCircle(pts[i], 4.5, Paint()..color = const Color(0xFFFBF8F0));
      canvas.drawCircle(pts[i], 4.5, Paint()..color = AppColors.sage800..style = PaintingStyle.stroke..strokeWidth = 1.8);
      final tp = TextPainter(
        text: TextSpan(text: _sleepData[i].day, style: const TextStyle(fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xAt(i) - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Activity Chart Painter ─────────────────────────────────────
class _ActivityChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const padL = 32.0, padR = 12.0, padT = 10.0, padB = 24.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    const max = 80.0;
    final groupW = w / _activityData.length;
    final barW = (groupW - 8) / 3;
    final colors = [AppColors.sage700, AppColors.warn, const Color(0xFF704863)];

    // Grid
    final gridPaint = Paint()..color = AppColors.line..strokeWidth = 1;
    for (final v in [0.0, 20.0, 40.0, 60.0, 80.0]) {
      final y = padT + h - (v / max) * h;
      final dashPath = Path()..moveTo(padL, y);
      double x = padL;
      while (x < padL + w) { dashPath.lineTo(x + 2, y); x += 6; dashPath.moveTo(x, y); }
      canvas.drawPath(dashPath, gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '${v.toInt()}', style: const TextStyle(fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    for (int i = 0; i < _activityData.length; i++) {
      final d = _activityData[i];
      final groupX = padL + i * groupW + 4;
      final values = [d.transitions.toDouble(), d.kitchen.toDouble(), d.outside.toDouble()];
      for (int j = 0; j < 3; j++) {
        final bh = (values[j] / max) * h;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(groupX + j * barW, padT + h - bh, barW - 1.5, bh),
          const Radius.circular(3),
        );
        canvas.drawRRect(rect, Paint()..color = colors[j].withValues(alpha: values[j] == 0 ? 0.2 : 0.92));
      }
      final tp = TextPainter(
        text: TextSpan(text: d.day, style: const TextStyle(fontSize: 10, color: AppColors.ink500, fontFamily: 'Manrope')),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(groupX + (groupW - 8) / 2 - tp.width / 2, padT + h + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── AI Insights Block ──────────────────────────────────────────
class _AIInsightsBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconWell(tone: 'sage', size: 32, child: const Icon(Icons.auto_awesome, size: 16)),
              const SizedBox(width: 10),
              Text('AI Insights', style: GoogleFonts.newsreader(fontSize: 20, color: AppColors.ink900, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              const AppTag(label: 'Personalized', tone: 'sage'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Overall, Eleanor had a calm but slightly less active week. Sleep was a little shorter and outside time dipped on Thursday and Friday — nothing alarming, but a gentle check-in would be kind. Mobility and morning routines were rock-solid.',
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.ink800, height: 1.65),
          ),
          const SizedBox(height: 18),
          for (final s in _insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.bgSoft, border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.title.toUpperCase(), style: GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.sage800, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text(s.body, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.ink700, height: 1.55)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text('RECOMMENDED ACTIONS', style: GoogleFonts.manrope(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.ink500, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          for (int i = 0; i < _recommendations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: const BoxDecoration(color: AppColors.sage100, shape: BoxShape.circle),
                    child: Center(child: Text('${i + 1}', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.sage800))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_recommendations[i], style: GoogleFonts.manrope(fontSize: 13.5, color: AppColors.ink800, height: 1.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
